import 'dart:convert';

import 'package:flutter/services.dart';

import '../checkout/digits.dart';
import '../models/json_read.dart';

/// The Mobile Money tables (`assets/wajub/mobile-money.json`):
/// per country its dial code, number length, placeholder and prefix rules,
/// per operator its name and brand badge, and the operator-independent
/// wallets. The file ships in `assets/wajub/` and is read at first use; no
/// copy of these tables lives in code.
class MobileMoneyData {
  const MobileMoneyData({
    required this.countries,
    required this.operators,
    required this.operatorIndependentWallets,
    required this.fallbackBrand,
    required this.looseMinLength,
    required this.looseMaxLength,
    this.sandboxPrefixes = const {},
    this.sandboxSuffixes = const [],
  });

  /// The only `schema_version` this SDK reads; any other is refused.
  static const supportedSchemaVersion = 2;

  /// Where the file is when this package is a dependency of the app.
  static const assetKey = 'packages/wajub_mobile/assets/wajub/mobile-money.json';

  /// Where it is when this package is the root package (its own tests).
  static const rootAssetKey = 'assets/wajub/mobile-money.json';

  static MobileMoneyData? _shared;

  /// Keyed by ISO-2, upper case.
  final Map<String, MobileMoneyCountry> countries;

  /// Keyed by operator id: `mtn`, `orange`, `wave`…
  final Map<String, MobileMoneyOperator> operators;

  /// Wallets that take any number (`wave`, `eu`, `djamo`…): never a mismatch.
  final Set<String> operatorIndependentWallets;

  /// The badge of an operator without a brand entry (its label is null:
  /// the channel's name stands in).
  final OperatorBrand fallbackBrand;

  /// The length a number must have when its country is not in the tables.
  final int looseMinLength;
  final int looseMaxLength;

  /// The sandbox's test number prefixes by country (ISO-2), digits without
  /// `+`, each with its operator.
  final Map<String, List<SandboxPrefix>> sandboxPrefixes;

  /// The endings of a sandbox test number: the outcome each one forces.
  final List<String> sandboxSuffixes;

  /// Reads the file from the app's assets. The first successful read of
  /// [rootBundle] is kept for the process; an explicit [bundle] is read
  /// every time.
  static Future<MobileMoneyData> load([AssetBundle? bundle]) async {
    if (bundle != null) return _read(bundle);
    // The parsed tables are kept, not the future that read them: a future
    // belongs to the zone it was made in.
    return _shared ??= await _read(rootBundle);
  }

  static Future<MobileMoneyData> _read(AssetBundle bundle) async {
    String source;
    try {
      source = await bundle.loadString(assetKey);
    } catch (_) {
      source = await bundle.loadString(rootAssetKey);
    }
    return MobileMoneyData.parse(source);
  }

  /// Throws a [FormatException] on an unknown `schema_version` or a
  /// malformed file.
  factory MobileMoneyData.parse(String source) {
    final json = readMap(jsonDecode(source));
    if (json == null) throw const FormatException('mobile-money.json is not an object');
    final version = json['schema_version'];
    if (version != supportedSchemaVersion) {
      throw FormatException(
        'mobile-money.json schema_version $version is not supported (this SDK reads $supportedSchemaVersion)',
      );
    }
    final loose = readMap(json['loose_length']);
    final looseMin = readInt(loose?['min']);
    final looseMax = readInt(loose?['max']);
    if (looseMin == null || looseMax == null) {
      throw const FormatException('mobile-money.json has no loose_length');
    }
    final fallback = readMap(json['fallback_brand']);
    if (fallback == null) throw const FormatException('mobile-money.json has no fallback_brand');
    final sandbox = readMap(json['sandbox_test_numbers']) ?? const {};
    return MobileMoneyData(
      countries: {
        for (final entry in (readMap(json['countries']) ?? const {}).entries)
          entry.key.toUpperCase(): MobileMoneyCountry._fromJson(entry.key.toUpperCase(), _object(entry.value)),
      },
      operators: {
        for (final entry in (readMap(json['operators']) ?? const {}).entries)
          entry.key.toLowerCase(): MobileMoneyOperator._fromJson(entry.key.toLowerCase(), _object(entry.value)),
      },
      operatorIndependentWallets:
          readStringList(json['operator_independent_wallets']).map((w) => w.toLowerCase()).toSet(),
      fallbackBrand: OperatorBrand(
        color: _color(fallback['color']),
        background: _color(fallback['background']),
      ),
      looseMinLength: looseMin,
      looseMaxLength: looseMax,
      sandboxPrefixes: {
        for (final country in (readMap(sandbox['prefixes']) ?? const {}).entries)
          country.key.toUpperCase(): [
            for (final operator in (readMap(country.value) ?? const {}).entries)
              for (final prefix in readStringList(operator.value))
                SandboxPrefix(digits: sanitize(prefix), operator: operator.key.toLowerCase()),
          ],
      },
      sandboxSuffixes: (readMap(sandbox['outcome_suffixes']) ?? const {}).keys.toList(),
    );
  }

  /// The country's entry, whatever the case of [code].
  MobileMoneyCountry? countryFor(String code) => countries[code.toUpperCase()];

  /// A wallet that takes any number, whatever the operator behind it.
  bool isOperatorIndependent(String operatorId) {
    final id = operatorId.toLowerCase();
    return operatorIndependentWallets.contains(id) || (operators[id]?.operatorIndependent ?? false);
  }

  /// `algorithms.sanitize`: the digits of [input], `+` and everything else
  /// dropped. The digits of other scripts (Arabic-Indic, Persian…) count as
  /// the digits they are.
  static String sanitize(String input) => asciiDigits(input).replaceAll(RegExp('[^0-9]'), '');

  /// `algorithms.typed_national_digits`: the digits as the payer wrote the
  /// number, without the country's dial code when it was written
  /// internationally (`+` or `00`) or the dial code is not part of a national
  /// number; another country's number keeps its own dial code.
  String typedNationalDigits(String input, String country) => _typed(input, country).digits;

  /// Whether [input] is another country's number: written with `+` or `00`
  /// and a dial code that is not [country]'s.
  bool isForeign(String input, String country) => _typed(input, country).foreign;

  /// How [input] is written for [country]. [national]: a leading `00` is
  /// read as typed digits rather than as the international prefix.
  _Typed _typed(String input, String country, {bool national = false}) {
    final digits = sanitize(input);
    final entry = countryFor(country);
    if (entry == null) return _Typed(digits);
    final dial = entry.dialDigits;
    final plus = !national && _writtenWithPlus(input);
    final zeros = !national && !plus && digits.startsWith('00');
    if (plus || zeros) {
      final international = zeros ? digits.substring(2) : digits;
      if (international.startsWith(dial)) return _Typed(international.substring(dial.length));
      return _Typed(international, foreign: true);
    }
    // Written nationally: the dial code goes only when the digits do not
    // already make a national number (a Ghanaian number may start like it).
    if (digits.startsWith(dial) && !_isNationalNumber(entry, digits)) return _Typed(digits.substring(dial.length));
    return _Typed(digits);
  }

  /// The first of [input]'s digits and `+` is a `+`.
  static bool _writtenWithPlus(String input) {
    for (final char in asciiDigits(input).split('')) {
      if (char == '+') return true;
      if (RegExp('[0-9]').hasMatch(char)) return false;
    }
    return false;
  }

  /// [digits] read by [entry]'s plan make a whole national number.
  static bool _isNationalNumber(MobileMoneyCountry entry, String digits) {
    final national = _planSteps(entry, digits);
    final prefix = entry.numberPrefix;
    return national.length == entry.nationalNumberLength && (prefix == null || national.startsWith(prefix));
  }

  /// `algorithms.national_digits` steps 1 and 2: an earlier plan's number in
  /// its current form, then the trunk 0 dropped, or the 0 that is part of the
  /// number kept (and given back to a mobile number typed without it).
  static String _planSteps(MobileMoneyCountry entry, String typed) {
    var digits = typed;
    final earlier = entry.earlier;
    if (earlier != null && digits.length == earlier.length) {
      final key = earlier.keyStarting(digits);
      if (key != null) digits = '${earlier.map[key]}${digits.substring(key.length)}';
    }
    if (!entry.leadingZeroSignificant) return digits.replaceFirst(RegExp('^0+'), '');
    if (!digits.startsWith('0')) {
      final withZero = '0$digits';
      if (withZero.length == entry.nationalNumberLength && entry.mobilePrefixes.any(withZero.startsWith)) {
        return withZero;
      }
    }
    return digits;
  }

  /// `algorithms.national_digits`: the national number as the country's plan
  /// reads it; another country's number as written.
  String nationalDigits(String input, String country) {
    final entry = countryFor(country);
    if (entry == null) return sanitize(input).replaceFirst(RegExp('^0+'), '');
    final typed = _typed(input, country);
    return typed.foreign ? typed.digits : _planSteps(entry, typed.digits);
  }

  /// `algorithms.validate`, and in a sandbox session the sandbox's test
  /// numbers. Another country's number is never valid.
  bool isValid(String input, String country, {bool sandbox = false}) {
    if (sandbox && sandboxTestNumber(input, country) != null) return true;
    final entry = countryFor(country);
    final length = entry?.nationalNumberLength;
    if (entry != null && length != null) {
      if (isForeign(input, country)) return false;
      final digits = nationalDigits(input, country);
      final prefix = entry.numberPrefix;
      return digits.length == length && (prefix == null || digits.startsWith(prefix));
    }
    final digits = sanitize(input).length;
    return digits >= looseMinLength && digits <= looseMaxLength;
  }

  /// `algorithms.detect_operator`: the operator whose range the number is
  /// in, read in its current form while it is still being typed; in a
  /// sandbox session, a test number's operator. None for another country's
  /// number. Never an operator-independent wallet.
  String? detectOperator(String input, String country, {bool sandbox = false}) {
    if (sandbox) {
      final test = sandboxTestNumber(input, country);
      if (test != null) return test.operator;
    }
    final entry = countryFor(country);
    if (entry == null || isForeign(input, country)) return null;
    var digits = nationalDigits(input, country);
    if (digits.isEmpty) return null;
    if (entry.numberPrefix != null && !digits.startsWith('0')) {
      final key = entry.earlier?.keyStarting(digits);
      digits = key != null ? '${entry.earlier!.map[key]}${digits.substring(key.length)}' : '0$digits';
    }
    for (final rule in entry.prefixRules) {
      if (isOperatorIndependent(rule.operator)) continue;
      if (rule.startsWith.any(digits.startsWith)) return rule.operator;
    }
    return null;
  }

  /// `algorithms.e164`: the dial code, then the national digits; another
  /// country's number as written; in a sandbox session, a test number as it
  /// was read. A country the file does not know gets the digits as typed.
  String e164(String input, String country, {bool sandbox = false}) {
    if (sandbox) {
      final test = sandboxTestNumber(input, country);
      if (test != null) return test.e164;
    }
    final entry = countryFor(country);
    if (entry == null) return '+${sanitize(input)}';
    final typed = _typed(input, country);
    if (typed.foreign) return '+${typed.digits}';
    return '${entry.dialCode}${_planSteps(entry, typed.digits)}';
  }

  /// `algorithms.sandbox_test_number`: [input] as a sandbox test number of
  /// [country] — its operator and what is sent — or null. Only for a
  /// sandbox session. Read by the plan, then as typed after the dial code
  /// (its 0s kept), then with a leading `00` read as typed digits; never as
  /// another country's number.
  SandboxTestNumber? sandboxTestNumber(String input, String country) {
    final entry = countryFor(country);
    final prefixes = sandboxPrefixes[country.toUpperCase()];
    if (entry == null || prefixes == null || prefixes.isEmpty) return null;
    final dial = entry.dialDigits;
    final typed = _typed(input, country);
    final readings = [
      if (!typed.foreign) '$dial${_planSteps(entry, typed.digits)}',
      if (!typed.foreign) '$dial${typed.digits}',
      '$dial${_typed(input, country, national: true).digits}',
    ];
    for (final reading in readings) {
      SandboxPrefix? found;
      for (final prefix in prefixes) {
        if (!reading.startsWith(prefix.digits)) continue;
        if (!_isOutcome(reading.substring(prefix.digits.length))) continue;
        if (found == null || prefix.digits.length > found.digits.length) found = prefix;
      }
      if (found != null) return SandboxTestNumber(operator: found.operator, e164: '+$reading');
    }
    return null;
  }

  /// Any `0`s, then one of the outcome endings.
  bool _isOutcome(String rest) => sandboxSuffixes.any(
        (suffix) => rest.endsWith(suffix) && RegExp(r'^0*$').hasMatch(rest.substring(0, rest.length - suffix.length)),
      );

  /// `algorithms.format_as_you_type`: at most 15 digits, by pairs.
  static String formatAsYouType(String input) {
    final digits = sanitize(input);
    final kept = digits.length > 15 ? digits.substring(0, 15) : digits;
    final pairs = <String>[
      for (var i = 0; i < kept.length; i += 2) kept.substring(i, i + 2 > kept.length ? kept.length : i + 2),
    ];
    return pairs.join(' ');
  }

  static Map<String, dynamic> _object(Object? value) =>
      readMap(value) ?? (throw FormatException('mobile-money.json entry is not an object', value));

  /// `#rgb` or `#rrggbb`.
  static Color _color(Object? value) {
    var hex = readString(value)?.trim() ?? '';
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    final rgb = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    if (rgb == null) throw FormatException('mobile-money.json colour is not #rgb or #rrggbb', value);
    return Color(0xFF000000 | rgb);
  }
}

/// One country of the tables.
class MobileMoneyCountry {
  const MobileMoneyCountry({
    required this.code,
    required this.name,
    required this.dialCode,
    this.nationalNumberLength,
    this.leadingZeroSignificant = false,
    this.numberPrefix,
    this.mobilePrefixes = const [],
    this.earlier,
    required this.placeholder,
    required this.placeholderFormatted,
    this.operators = const [],
    this.prefixRules = const [],
  });

  /// ISO-2, upper case.
  final String code;
  final String name;

  /// With its `+`: `+237`.
  final String dialCode;

  /// The exact number of national digits.
  final int? nationalNumberLength;

  /// The 0 is part of the number (`leading_zero: "significant"`: Côte
  /// d'Ivoire, Benin, Congo, Burkina Faso's 0X ranges); otherwise it is a
  /// trunk prefix.
  final bool leadingZeroSignificant;

  /// What every national number starts with, when the plan says.
  final String? numberPrefix;

  /// The mobile ranges a number typed without its 0 gets it back onto.
  final List<String> mobilePrefixes;

  /// The numbers of the country's earlier plan, still typed by payers.
  final EarlierPlan? earlier;
  final String placeholder;

  /// The placeholder as the phone field shows it: `67 12 34 56 7`.
  final String placeholderFormatted;

  /// The operators the web offers in this country.
  final List<String> operators;

  /// The operator ranges; they do not overlap.
  final List<PrefixRule> prefixRules;

  /// [dialCode] without its `+`.
  String get dialDigits => dialCode.replaceAll('+', '');

  factory MobileMoneyCountry._fromJson(String code, Map<String, dynamic> json) {
    final dialCode = readText(json['dial_code']);
    if (dialCode == null || !dialCode.startsWith('+')) {
      throw FormatException('mobile-money.json country $code has no dial_code', json['dial_code']);
    }
    return MobileMoneyCountry(
      code: code,
      name: readString(json['name']) ?? code,
      dialCode: dialCode,
      nationalNumberLength: readInt(json['national_number_length']),
      leadingZeroSignificant: readString(json['leading_zero']) == 'significant',
      numberPrefix: readText(json['number_prefix']),
      mobilePrefixes: readStringList(json['mobile_prefixes']),
      earlier: EarlierPlan._fromJson(readMap(json['earlier'])),
      placeholder: readString(json['placeholder']) ?? '',
      placeholderFormatted: readString(json['placeholder_formatted']) ?? readString(json['placeholder']) ?? '',
      operators: readStringList(json['operators']).map((o) => o.toLowerCase()).toList(),
      prefixRules: readMapList(json['prefix_rules']).map(PrefixRule._fromJson).toList(),
    );
  }
}

/// A country's earlier plan (`earlier`): a number of [length] digits that
/// starts with a key of [map] takes that key's value instead (Benin:
/// `96 12 34 56` is `01 96 12 34 56`; Gabon: `06 12 34 56` is `66 12 34 56`).
class EarlierPlan {
  const EarlierPlan({required this.length, required this.map});

  final int length;
  final Map<String, String> map;

  /// The longest key [digits] start with, or null.
  String? keyStarting(String digits) {
    String? found;
    for (final key in map.keys) {
      if (digits.startsWith(key) && (found == null || key.length > found.length)) found = key;
    }
    return found;
  }

  static EarlierPlan? _fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final length = readInt(json['length']);
    final map = readMap(json['map']);
    if (length == null || map == null) return null;
    return EarlierPlan(length: length, map: {
      for (final entry in map.entries)
        if (readText(entry.value) != null) entry.key: readText(entry.value)!,
    });
  }
}

/// A number's digits as written, and whether it is another country's.
class _Typed {
  const _Typed(this.digits, {this.foreign = false});

  final String digits;
  final bool foreign;
}

/// A sandbox test number prefix: its digits (dial code included, no `+`)
/// and the operator it tests.
class SandboxPrefix {
  const SandboxPrefix({required this.digits, required this.operator});

  final String digits;
  final String operator;
}

/// A sandbox test number: the operator it tests and what is sent.
class SandboxTestNumber {
  const SandboxTestNumber({required this.operator, required this.e164});

  final String operator;

  /// `+` and the number as it was read.
  final String e164;
}

/// A national prefix that names an operator.
class PrefixRule {
  const PrefixRule({required this.startsWith, required this.operator});

  /// Prefixes of the national digits (no regular expression to run).
  final List<String> startsWith;
  final String operator;

  factory PrefixRule._fromJson(Map<String, dynamic> json) => PrefixRule(
        startsWith: readStringList(json['starts_with']),
        operator: readString(json['operator'])?.toLowerCase() ?? '',
      );
}

/// One operator of the tables.
class MobileMoneyOperator {
  const MobileMoneyOperator({
    required this.id,
    required this.name,
    this.countries = const [],
    this.operatorIndependent = false,
    this.brand,
  });

  /// `mtn`, `orange`, `wave`…
  final String id;
  final String name;
  final List<String> countries;

  /// Takes any number, whatever the operator behind it (Wave, Express Union…).
  final bool operatorIndependent;

  /// The badge drawn when the operator's logo is missing or does not load.
  final OperatorBrand? brand;

  factory MobileMoneyOperator._fromJson(String id, Map<String, dynamic> json) {
    final brand = readMap(json['brand']);
    return MobileMoneyOperator(
      id: id,
      name: readString(json['name']) ?? id,
      countries: readStringList(json['countries']).map((c) => c.toUpperCase()).toList(),
      operatorIndependent: readBool(json['operator_independent']) ?? false,
      brand: brand == null
          ? null
          : OperatorBrand(
              label: readText(brand['label']),
              mark: readText(brand['mark']),
              color: MobileMoneyData._color(brand['color']),
              background: MobileMoneyData._color(brand['background']),
            ),
    );
  }
}

/// An operator's brand: the label the picker shows and the round badge that
/// stands in for its logo.
class OperatorBrand {
  const OperatorBrand({this.label, this.mark, required this.color, required this.background});

  final String? label;

  /// The badge's text, when the brand has a short one (`MoMo`).
  final String? mark;
  final Color color;
  final Color background;

  /// `algorithms.brand_fallback`: [mark], else the first 8 alphanumerics of
  /// [label] (or of [fallbackLabel] when the brand has none), upper-cased.
  String badgeText(String fallbackLabel) {
    if (mark != null) return mark!;
    final letters = (label ?? fallbackLabel).replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return (letters.length > 8 ? letters.substring(0, 8) : letters).toUpperCase();
  }
}
