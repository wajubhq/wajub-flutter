import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/json_read.dart';

/// The Mobile Money tables of the shared spec (`data/mobile-money.json`):
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
  });

  /// The only `schema_version` this SDK reads; any other is refused.
  static const supportedSchemaVersion = 1;

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

  /// The length a number must have when its country sets none.
  final int looseMinLength;
  final int looseMaxLength;

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
  /// dropped.
  static String sanitize(String input) => input.replaceAll(RegExp('[^0-9]'), '');

  /// `algorithms.national_digits`: the digits without the country's dial
  /// code and without leading zeros.
  String nationalDigits(String input, String country) {
    var digits = sanitize(input);
    final dial = countryFor(country)?.dialDigits;
    if (dial != null && dial.isNotEmpty && digits.startsWith(dial)) digits = digits.substring(dial.length);
    return digits.replaceFirst(RegExp('^0+'), '');
  }

  /// `algorithms.validate`: the country's exact national length when it has
  /// one, else 7 to 15 digits.
  bool isValid(String input, String country) {
    final length = countryFor(country)?.nationalNumberLength;
    if (length != null) return nationalDigits(input, country).length == length;
    final digits = sanitize(input).length;
    return digits >= looseMinLength && digits <= looseMaxLength;
  }

  /// `algorithms.detect_operator`: the operator of the first prefix rule the
  /// national digits start with. Never an operator-independent wallet.
  String? detectOperator(String input, String country) {
    final rules = countryFor(country)?.prefixRules ?? const <PrefixRule>[];
    final digits = nationalDigits(input, country);
    if (digits.isEmpty) return null;
    for (final rule in rules) {
      if (isOperatorIndependent(rule.operator)) continue;
      if (rule.startsWith.any(digits.startsWith)) return rule.operator;
    }
    return null;
  }

  /// `algorithms.e164`: the dial code, the trunk 0 where the country keeps
  /// it (Côte d'Ivoire, see the file's `errata`), then the national digits.
  /// A country the file does not know gets the digits as typed.
  String e164(String input, String country) {
    final entry = countryFor(country);
    if (entry == null) return '+${sanitize(input)}';
    return '${entry.dialCode}${entry.keepTrunkZero ? '0' : ''}${nationalDigits(input, country)}';
  }

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
    this.keepTrunkZero = false,
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

  /// The exact number of national digits, when the country has one.
  final int? nationalNumberLength;

  /// The E.164 sent keeps the national trunk 0 (Côte d'Ivoire).
  final bool keepTrunkZero;
  final String placeholder;

  /// The placeholder as the phone field shows it: `67 12 34 56 7`.
  final String placeholderFormatted;

  /// The operators the web offers in this country.
  final List<String> operators;

  /// In order: the first that matches wins.
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
      keepTrunkZero: readString(json['e164_trunk_zero']) == 'keep',
      placeholder: readString(json['placeholder']) ?? '',
      placeholderFormatted: readString(json['placeholder_formatted']) ?? readString(json['placeholder']) ?? '',
      operators: readStringList(json['operators']).map((o) => o.toLowerCase()).toList(),
      prefixRules: readMapList(json['prefix_rules']).map(PrefixRule._fromJson).toList(),
    );
  }
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
