import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/mobile_money/mobile_money_data.dart';
import 'package:wajub_mobile/src/mobile_money/mobile_money_rules.dart';
import 'package:wajub_mobile/src/mobile_money/operator_choice.dart';
import 'package:wajub_mobile/src/mobile_money/operator_logo.dart';
import 'package:wajub_mobile/src/models/models.dart';

import 'support/fixtures.dart';

const dataFile = 'assets/wajub/mobile-money.json';

final data = MobileMoneyData.parse(File(dataFile).readAsStringSync());

List<SessionChannel> channelsOf(String fixtureName) => SessionData.fromJson(fixtureBody(fixtureName)).channels;

/// Answers every key with [source], as an app's asset bundle would the data file.
class _StringBundle extends CachingAssetBundle {
  _StringBundle(this.source);

  final String source;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MM-01 matches the number vectors', () {
    for (final vector in (vectors()['numbers'] as List).cast<Map<String, dynamic>>()) {
      final input = vector['input'] as String;
      final country = vector['country'] as String;
      final reason = '$input in $country';
      expect(data.nationalDigits(input, country), vector['national_digits'], reason: reason);
      expect(data.isValid(input, country), vector['valid'], reason: reason);
      expect(data.detectOperator(input, country), vector['detected_operator'], reason: reason);
      expect(data.e164(input, country), vector['e164'], reason: reason);
      expect(MobileMoneyData.formatAsYouType(input), vector['formatted'], reason: reason);
    }
  });

  test('MM-10 takes the sandbox test numbers', () {
    final sandboxNumbers = (vectors()['sandbox_numbers'] as List).cast<Map<String, dynamic>>();
    expect(sandboxNumbers, isNotEmpty);
    for (final vector in sandboxNumbers) {
      final input = vector['input'] as String;
      final country = vector['country'] as String;
      final reason = '$input in $country';
      final test = data.sandboxTestNumber(input, country);
      expect(test?.operator, vector['operator'], reason: reason);
      expect(test?.e164, vector['e164'], reason: reason);
      if (test != null) {
        // In a sandbox session: valid, the prefix's operator, sent as read.
        expect(data.isValid(input, country, sandbox: true), isTrue, reason: reason);
        expect(data.detectOperator(input, country, sandbox: true), vector['operator'], reason: reason);
        expect(data.e164(input, country, sandbox: true), vector['e164'], reason: reason);
      } else {
        expect(data.detectOperator(input, country, sandbox: true), data.detectOperator(input, country), reason: reason);
        expect(data.e164(input, country, sandbox: true), data.e164(input, country), reason: reason);
      }
    }
    // Outside a sandbox session the prefixes mean nothing.
    expect(data.isValid('+225070000000', 'CI'), isFalse, reason: 'one digit short of an Ivorian number');
    expect(data.e164('90 00 00 00', 'BJ'), '+2290190000000');
    expect(data.detectOperator('680000000', 'CM'), 'mtn', reason: 'Express Union only in sandbox');
    expect(data.detectOperator('680000000', 'CM', sandbox: true), 'eu');
    expect(
      MobileMoneyRules.validate(
          data: data, phone: '+225070000000', country: 'CI', choiceIds: const ['orange'], selectedId: 'orange'),
      'invalid_phone',
    );
    expect(
      MobileMoneyRules.validate(
          data: data,
          phone: '+225070000000',
          country: 'CI',
          choiceIds: const ['orange'],
          selectedId: 'orange',
          sandbox: true),
      isNull,
    );
  });

  test('reads Arabic-Indic and Persian digits as the digits they are', () {
    const arabic = '٦٧٧١٢٣٤٥٦'; // 677123456
    const persian = '۰۷۰۱۰۲۰۳۰۴'; // 0701020304
    expect(MobileMoneyData.sanitize(arabic), '677123456');
    expect(MobileMoneyData.formatAsYouType(arabic), '67 71 23 45 6');
    expect(data.isValid(arabic, 'CM'), isTrue);
    expect(data.detectOperator(arabic, 'CM'), 'mtn');
    expect(data.e164(arabic, 'CM'), '+237677123456');
    expect(data.e164('+٢٣٧ ٦٩١٢٣٤٥٦٧', 'CM'), '+237691234567');
    expect(data.isValid(persian, 'CI'), isTrue);
    expect(data.detectOperator(persian, 'CI'), 'orange');
    expect(data.e164(persian, 'CI'), '+2250701020304');
    expect(
      MobileMoneyRules.validate(data: data, phone: arabic, country: 'CM', choiceIds: const ['mtn'], selectedId: 'mtn'),
      isNull,
    );
  });

  test('MM-02 matches the mismatch vectors', () {
    for (final vector in (vectors()['validation_and_mismatch'] as List).cast<Map<String, dynamic>>()) {
      final phone = vector['phone'] as String;
      final country = vector['country'] as String;
      final choices = (vector['choices'] as List).cast<String>();
      final selected = vector['selected'] as String?;
      final reason = '$phone in $country, $selected selected';
      expect(data.detectOperator(phone, country), vector['detected'], reason: reason);
      expect(
        MobileMoneyRules.validate(data: data, phone: phone, country: country, choiceIds: choices, selectedId: selected),
        vector['expected'],
        reason: reason,
      );
      if (vector['expected'] == 'operator_mismatch') {
        expect(
          MobileMoneyRules.mismatch(
              data: data, phone: phone, country: country, choiceIds: choices, selectedId: selected),
          vector['detected'],
          reason: reason,
        );
      }
    }
    expect(
      MobileMoneyRules.validate(data: data, phone: '677123456', country: 'CM', choiceIds: ['mtn'], selectedId: null),
      'operator_required',
    );
  });

  test('MM-03 matches the preselection vectors', () {
    for (final vector in (vectors()['preselection'] as List).cast<Map<String, dynamic>>()) {
      final choices = (vector['choices'] as List).cast<String>();
      final picked = vector['picked_by_hand'] as String?;
      final phone = vector['phone'] as String;
      final country = vector['country'] as String;
      expect(
        MobileMoneyRules.preselect(
          choiceIds: choices,
          currentId: picked ?? choices.first,
          pickedByHand: picked != null,
          detectedId: data.detectOperator(phone, country),
        ),
        vector['expected_selection'],
        reason: '$phone in $country, picked ${picked ?? 'nothing'}',
      );
    }
  });

  group('MM-04 lists aggregate operators', () {
    test('an aggregate gives one choice per member, paid through the aggregate', () {
      final channels = channelsOf('session-cm-aggregate.json');
      expect(mobileMoneyCountries(channels), ['CM']);

      final choices = operatorChoices(channels, 'CM', data, language: 'fr');
      expect(choices.map((c) => c.id), ['mtn', 'orange']);
      expect(choices.map((c) => c.name), ['MTN Mobile Money', 'Orange Money']);
      expect(choices.map((c) => c.label), ['MTN MoMo', 'Orange Money'], reason: 'the brand label wins (README §6.1)');
      expect(choices.map((c) => c.logo), [
        'https://assets.wajub.com/img/channels/momo.svg',
        'https://assets.wajub.com/img/channels/om.svg',
      ]);
      expect(choices.map((c) => c.channelSlug), ['cm.mobile', 'cm.mobile']);
      expect(choices.map((c) => c.configSlug), ['cm.mtn', 'cm.orange']);
      expect(choices.every((c) => c.viaAggregate && !c.operatorIndependent), isTrue);
    });

    test('other channels give one choice each, wallets excluded', () {
      final channels = channelsOf('session-ci-xof-wallets.json');
      final choices = operatorChoices(channels, 'CI', data, language: 'en');

      expect(choices.map((c) => c.id), ['mtn', 'moov', 'orange', 'wave'], reason: 'ci.djamo is a wallet');
      expect(choices.map((c) => c.channelSlug), ['ci.mtn', 'ci.moov', 'ci.orange', 'ci.wave']);
      expect(choices.map((c) => c.configSlug), ['ci.mtn', 'ci.moov', 'ci.orange', 'ci.wave']);
      expect(choices.firstWhere((c) => c.id == 'moov').logo, isNull);
      expect(choices.firstWhere((c) => c.id == 'wave').operatorIndependent, isTrue);
      expect(choices.any((c) => c.viaAggregate), isFalse);
      expect(choices.firstWhere((c) => c.id == 'moov').badge.mark, 'Moov');
    });

    test('a separate channel and an aggregate of one country mix in API order', () {
      final channels = channelsOf('session-sandbox-cm.json');
      final choices = operatorChoices(channels, 'CM', data, language: 'fr');

      expect(choices.map((c) => c.id), ['eu', 'mtn', 'orange']);
      final eu = choices.first;
      expect(eu.label, 'Express Union Mobile', reason: 'no brand entry: the channel name');
      expect(eu.channelSlug, 'cm.eu');
      expect(eu.operatorIndependent, isTrue);
      expect(eu.badge, same(data.fallbackBrand));
      expect(operatorChoices(channels, 'CI', data, language: 'fr'), isEmpty);
    });

    test('the default country follows the request, then the payer\'s IP, then the first channel', () {
      final channels = channelsOf('session-cm-aggregate.json');
      expect(defaultMobileMoneyCountry(channels, requested: 'cm', geoCountry: 'CI'), 'CM');
      expect(defaultMobileMoneyCountry(channels, requested: 'SN', geoCountry: 'CM'), 'CM');
      expect(defaultMobileMoneyCountry(channels, geoCountry: 'CI'), 'CM');
      expect(defaultMobileMoneyCountry(channelsOf('session-ci-xof-wallets.json')), 'CI');
      expect(defaultMobileMoneyCountry(const []), isNull);
    });
  });

  test('MM-05 builds the mobile money request', () {
    final sessions = [
      ...channelsOf('session-cm-aggregate.json'),
      ...channelsOf('session-ci-xof-wallets.json'),
    ];
    for (final vector in (vectors()['operator_hint'] as List).cast<Map<String, dynamic>>()) {
      final channel = sessions.firstWhere((c) => c.slug == vector['channel']);
      expect(
        MobileMoneyRules.operatorHint(
          viaAggregate: channel.isAggregate,
          selectedId: vector['selected'] as String,
          pickedByHand: vector['picked_by_hand'] as bool,
          detectedId: vector['detected'] as String?,
        ),
        vector['send_operator'],
        reason: '${vector['channel']}, ${vector['selected']} selected',
      );
    }

    final mtn = operatorChoices(channelsOf('session-sandbox-cm.json'), 'CM', data, language: 'en')
        .firstWhere((c) => c.id == 'mtn');
    final sent = fixtureRequestBody('process-processing-mobile-money-sandbox.json')!;
    expect(mtn.channelSlug, sent['channel']);
    expect(
      MobileMoneyRules.requestData(data: data, phone: '670000000', country: 'CM', choice: mtn, pickedByHand: false),
      Map<String, Object?>.from(sent['data'] as Map)..remove('_client'),
    );

    final undetected = MobileMoneyRules.requestData(
      data: data,
      phone: '+237 62 00 00 00 0',
      country: 'cm',
      choice: mtn,
      pickedByHand: false,
    );
    expect(undetected, {'phone': '+237620000000', 'country': 'CM'}, reason: 'an untouched default is not sent');
  });

  testWidgets('MM-07 falls back to brand badges', (tester) async {
    final ci = operatorChoices(channelsOf('session-ci-xof-wallets.json'), 'CI', data, language: 'en');
    final moov = ci.firstWhere((c) => c.id == 'moov');
    final orange = ci.firstWhere((c) => c.id == 'orange');
    final eu = operatorChoices(channelsOf('session-sandbox-cm.json'), 'CM', data, language: 'en').first;

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        OperatorLogo(choice: moov),
        OperatorLogo(choice: orange),
        OperatorLogo(choice: eu),
      ]),
    ));

    // No logo at all: the badge at once, in Moov's colours with its mark.
    final moovBadge = find.byKey(const ValueKey('wajub-operator-badge-moov'));
    expect(moovBadge, findsOneWidget);
    expect(find.byKey(const ValueKey('wajub-operator-logo-moov')), findsNothing);
    final decoration = tester.widget<Container>(moovBadge).decoration! as BoxDecoration;
    expect(decoration.color, data.operators['moov']!.brand!.background);
    final mark = tester.widget<Text>(find.descendant(of: moovBadge, matching: find.byType(Text)));
    expect(mark.data, 'Moov');
    expect(mark.style!.color, data.operators['moov']!.brand!.color);

    // A logo that does not load (every request fails under test): the badge.
    expect(find.byKey(const ValueKey('wajub-operator-logo-orange')), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.byKey(const ValueKey('wajub-operator-badge-orange')), findsOneWidget);
    expect(find.text('Orange'), findsOneWidget);

    // No brand entry: the fallback colours and the channel name's letters.
    final euBadge = find.byKey(const ValueKey('wajub-operator-badge-eu'));
    expect((tester.widget<Container>(euBadge).decoration! as BoxDecoration).color, data.fallbackBrand.background);
    expect(find.text('EXPRESSU'), findsOneWidget);

    expect(find.bySemanticsLabel('Moov Money'), findsOneWidget);
  });

  test('MM-08 does not block mismatches in sandbox', () {
    final channels = channelsOf('session-sandbox-cm.json');
    final ids = operatorChoices(channels, 'CM', data, language: 'en').map((c) => c.id).toList();
    // A sandbox MTN test number, with Orange picked by hand.
    const phone = '670000000';

    expect(
      MobileMoneyRules.mismatch(data: data, phone: phone, country: 'CM', choiceIds: ids, selectedId: 'orange'),
      'mtn',
    );
    expect(
      MobileMoneyRules.validate(
          data: data, phone: phone, country: 'CM', choiceIds: ids, selectedId: 'orange', sandbox: true),
      isNull,
    );
    expect(
      MobileMoneyRules.validate(data: data, phone: phone, country: 'CM', choiceIds: ids, selectedId: 'orange'),
      'operator_mismatch',
    );
  });

  group('MM-09 loads the shared data file', () {
    test('from the app bundle, with every country and operator of the file', () async {
      final loaded = await MobileMoneyData.load();
      final file = jsonDecode(File(dataFile).readAsStringSync()) as Map<String, dynamic>;
      final countries = file['countries'] as Map<String, dynamic>;

      expect(loaded.countries.keys, unorderedEquals(countries.keys));
      for (final entry in countries.entries) {
        final country = loaded.countries[entry.key]!;
        expect(country.dialCode, (entry.value as Map)['dial_code']);
        expect(country.prefixRules.length, ((entry.value as Map)['prefix_rules'] as List).length);
      }
      expect(loaded.operators.keys, unorderedEquals((file['operators'] as Map).keys));
      expect(loaded.operatorIndependentWallets, (file['operator_independent_wallets'] as List).toSet());
      expect(await MobileMoneyData.load(), same(loaded), reason: 'read once per process');
    });

    test('rejects an unknown schema_version', () async {
      final file = jsonDecode(File(dataFile).readAsStringSync()) as Map<String, dynamic>;
      final future = jsonEncode({...file, 'schema_version': 3});
      final past = jsonEncode({...file, 'schema_version': 1});

      expect(file['schema_version'], 2);
      expect(() => MobileMoneyData.parse(future), throwsFormatException);
      expect(() => MobileMoneyData.parse(past), throwsFormatException);
      await expectLater(MobileMoneyData.load(_StringBundle(future)), throwsFormatException);
      expect(() => MobileMoneyData.parse('[]'), throwsFormatException);
    });

    test('ships the tables without the spec\'s notes', () {
      final shipped = jsonDecode(File(dataFile).readAsStringSync()) as Map<String, dynamic>;
      for (final note in ['source', 'errata', 'algorithms']) {
        expect(shipped.containsKey(note), isFalse, reason: note);
      }
    });

    test('keeps no copy of the tables in code', () {
      final copies = <String>[];
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        for (final entry in const ["'express_union'", '"express_union"', "'+226'", '"+226"']) {
          if (source.contains(entry)) copies.add('${file.path}: $entry');
        }
      }
      expect(copies, isEmpty, reason: 'the Mobile Money tables live in $dataFile only');
    });
  });

  test('the operator list waits for the number in detect mode', () {
    final ci = operatorChoices(channelsOf('session-ci-xof-wallets.json'), 'CI', data, language: 'en');
    final cm = operatorChoices(channelsOf('session-cm-aggregate.json'), 'CM', data, language: 'en');
    final ciIds = ci.map((c) => c.id).toList();
    final cmIds = cm.map((c) => c.id).toList();
    bool shows(String phone, String country, List<String> ids, {String mode = 'detect'}) =>
        MobileMoneyRules.showOperatorList(
            data: data, operatorMode: mode, phone: phone, country: country, choiceIds: ids);

    expect(shows('67', 'CM', cmIds, mode: 'choose'), isTrue);
    expect(shows('6771', 'CM', cmIds), isFalse, reason: 'fewer than 6 digits');
    expect(shows('677123456', 'CM', cmIds), isFalse, reason: 'names an offered operator');
    expect(shows('621234567', 'CM', cmIds), isTrue, reason: 'names no offered operator');
    expect(shows('0701020304', 'CI', ciIds), isTrue, reason: 'Wave takes any number');
    expect(
      MobileMoneyRules.showOperatorList(
          data: data, operatorMode: 'detect', phone: '', country: 'CM', choiceIds: cmIds, openedByPayer: true),
      isTrue,
    );
    expect(MobileMoneyRules.fieldBadge(data: data, phone: '691234567', country: 'CM', choiceIds: cmIds), 'orange');
    expect(MobileMoneyRules.fieldBadge(data: data, phone: '', country: 'CM', choiceIds: ['mtn']), 'mtn');
  });
}
