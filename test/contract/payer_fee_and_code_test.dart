import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/errors/error_catalogue.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/payer_otp.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

/// The Burkina Faso session, its Orange channel announcing the code, or not
/// when [announced] is false (the charge then asks for it).
FakeApi payerOtpApi({bool announced = true, required List<Object> process, Object status = 'status-processing.json'}) {
  final session = fixtureBody('session-payer-otp-announced.json');
  if (!announced) {
    for (final channel in session['channels'] as List) {
      (channel as Map).remove('payer_otp');
    }
  }
  return FakeApi(routes: {
    'GET /pay/session': FakeAnswer(200, session),
    'GET /pay/sdk-config': 'sdk-config-sandbox.json',
    'POST /pay/process': process,
    'GET /pay/status': status,
    'POST /pay/cancel': 'cancel-200.json',
  });
}

/// A status read saying the payment is `pending` again, refused with [code].
FakeAnswer pendingWith(String code) {
  final body = fixtureBody('status-pending-payer-otp-refused.json');
  (body['transaction'] as Map)['error_code'] = code;
  return FakeAnswer(200, body);
}

Map<String, dynamic> dataOf(Map<String, dynamic> body) => Map<String, dynamic>.from(body['data'] as Map);

void main() {
  test('CH-07 shows what the payer pays on the chosen channel', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-payer-fee-per-channel.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': 'process-payer-fee-on-channel-sandbox.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      expect(controller.screen, CheckoutScreen.methods);
      expect(controller.amountToPay, 10200, reason: 'no method chosen: the payment total');

      checkout.mobileMoney('');
      expect(controller.selectedOperatorId, 'mtn', reason: 'the initial selection');
      expect(controller.amountToPay, 10200, reason: "MTN's own total");
      controller.setPhone('690000000');
      expect(controller.selectedOperatorId, 'orange', reason: 'detected');
      expect(controller.amountToPay, 10450, reason: "the detected operator's total, live");
      controller.setPhone('670000000');
      expect(controller.amountToPay, 10200);
      controller.pickOperator('orange');
      expect(controller.amountToPay, 10450, reason: 'chosen by hand');

      controller.backToMethods();
      expect(controller.amountToPay, 10200);
      controller.selectMethod(checkout.method(MethodFamily.card));
      expect(controller.amountToPay, 10200, reason: "the card channel's total");

      controller.backToMethods();
      checkout.mobileMoney('690000000');
      checkout.run(controller.payMobileMoney);
      final data = dataOf(api.bodies('/pay/process').single);
      expect(data.keys, isNot(anyElement(anyOf('amount', 'fee_amount', 'amount_total'))), reason: 'the API prices it');
      expect(controller.state, CheckoutState.approvalRequired);
      expect(controller.amountToPay, 10450, reason: 'what the charge took');
      checkout.end();
    });

    // Without the fields, the payment's total, as in 2.1.
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
      });
      final checkout = Checkout(async, api);
      for (final phone in ['670000000', '690000000']) {
        checkout.mobileMoney(phone);
        expect(checkout.controller.amountToPay, 25000, reason: phone);
      }
      checkout.end();
    });

    // CH-05 compares the limits with the channel's own total.
    final body = fixtureBody('session-payer-fee-per-channel.json');
    final card = (body['channels'] as List).firstWhere((c) => (c as Map)['slug'] == 'card') as Map;
    card['max_amount'] = 10300;
    card['amount_total'] = 10500;
    final methods =
        buildMethods(SessionData.fromJson(body), SdkConfig.fromJson(fixtureBody('sdk-config-sandbox.json')));
    final limited = methods.firstWhere((m) => m.family == MethodFamily.card);
    expect(limited.enabled, isFalse, reason: '10 500 on the card is over 10 300, though the payment is 10 200');
    expect(limited.limit?.amount, 10300);
    expect(methods.firstWhere((m) => m.family == MethodFamily.mobileMoney).enabled, isTrue);
  });

  test('MM-11 asks for the payer\'s code before the charge', () {
    virtual((async) {
      final api = payerOtpApi(process: ['process-payer-otp-accepted-sandbox.json']);
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      expect((controller.country, controller.selectedOperatorId), ('BF', 'orange'));
      expect(controller.announcedPayerOtp?.ussdCode, '*144*4*6#', reason: 'the form says a code comes next');

      checkout.run(controller.payMobileMoney);
      expect(api.calls('/pay/process'), isEmpty, reason: 'no call before the code');
      expect((controller.state, controller.screen), (CheckoutState.payerOtpRequired, CheckoutScreen.payerOtp));
      expect((controller.payerOtp?.amount, controller.payerOtp?.currency), ('1000', 'XOF'));
      expect(controller.payerOtp?.otpLength, 6);
      expect(checkout.recorder.started, isNull);

      checkout.run(() => controller.submitPayerOtp('123456'));
      final body = api.bodies('/pay/process').single;
      final expected = dataOf(fixtureRequestBody('process-payer-otp-accepted-sandbox.json')!)..remove('_client');
      expect(body['channel'], 'bf.orange');
      expect(dataOf(body)..remove('_client'), expected, reason: 'the code goes with the first charge');
      expect(controller.state, CheckoutState.approvalRequired);
      expect(checkout.recorder.started?.channel, 'bf.orange');
      checkout.end();
    });

    // An aggregate's operator is never announced, even if it says so.
    virtual((async) {
      final session = fixtureBody('session-cm-aggregate.json');
      final mobile = (session['channels'] as List).firstWhere((c) => (c as Map)['slug'] == 'cm.mobile') as Map;
      mobile['payer_otp'] = fixtureBody('process-payer-otp-required.json')['payer_otp'];
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer(200, session),
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-processing-mobile-money-sandbox.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('670000000');
      expect(checkout.controller.announcedPayerOtp, isNull);
      checkout.run(checkout.controller.payMobileMoney);
      expect(api.calls('/pay/process'), hasLength(1));
      expect(checkout.controller.state, CheckoutState.approvalRequired);
      checkout.end();
    });
  });

  test('MM-12 asks for the payer\'s code the charge asks for', () {
    virtual((async) {
      final api = payerOtpApi(
        announced: false,
        process: ['process-payer-otp-required.json', 'process-payer-otp-accepted-sandbox.json'],
      );
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      expect(controller.announcedPayerOtp, isNull);
      checkout.run(controller.payMobileMoney);
      expect(checkout.recorder.states.skip(2), [CheckoutState.processing, CheckoutState.payerOtpRequired]);
      expect(checkout.recorder.started, isNull, reason: 'nothing was charged');
      expect(checkout.recorder.errors, isEmpty);
      final instructions = controller.payerOtp!;
      expect((instructions.reason, instructions.attemptsRemaining), ('required', 3));
      expect(controller.payerOtpNotice, isNull);

      // The steps of the sheet's language, from their template.
      expect(instructions.stepsFor('en').first.text, 'On the phone of the Orange Money account, dial *144*4*6#.');
      expect(instructions.parts(instructions.stepsFor('en').first), [
        (PayerOtpPart.text, 'On the phone of the Orange Money account, dial '),
        (PayerOtpPart.ussdCode, '*144*4*6#'),
        (PayerOtpPart.text, '.'),
      ]);
      expect(instructions.parts(instructions.stepsFor('fr')[1]), [
        (PayerOtpPart.text, 'Saisissez le montant exact : '),
        (PayerOtpPart.amount, '1000'),
        (PayerOtpPart.text, ' '),
        (PayerOtpPart.text, 'XOF'),
        (PayerOtpPart.text, '.'),
      ]);

      // Checked before sending: 6 digits, nothing sent otherwise.
      for (final code in ['12345', '1234567', '12a456', '']) {
        checkout.run(() => controller.submitPayerOtp(code));
        expect(controller.payerOtpNotice, PayerOtpNotice.invalidLength, reason: code);
      }
      expect(api.calls('/pay/process'), hasLength(1));

      checkout.run(() => controller.submitPayerOtp('١٢٣٤٥٦'));
      final [first, second] = api.bodies('/pay/process');
      expect(dataOf(second), {...dataOf(first), 'otp': '123456'}, reason: 'the same request, with the code');
      expect(second['channel'], first['channel']);
      final keys = api.calls('/pay/process').map((r) => r.headers['Idempotency-Key']).toSet();
      expect(keys, hasLength(2), reason: 'a new Idempotency-Key');
      expect(checkout.recorder.states.skip(4), [CheckoutState.processing, CheckoutState.approvalRequired]);
      expect(controller.payerOtpSent, isTrue, reason: 'the approval screen says the code was received');
      checkout.end();
    });

    // "Use another payment method": the Mobile Money form; a dismiss there
    // is a dismiss before any attempt.
    virtual((async) {
      final api = payerOtpApi(announced: false, process: ['process-payer-otp-required.json']);
      final checkout = Checkout(async, api);
      checkout.mobileMoney('70000000');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.controller.leavePayerOtp();
      expect((checkout.controller.state, checkout.controller.screen),
          (CheckoutState.collectingDetails, CheckoutScreen.form));
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.state, CheckoutState.payerOtpRequired);
      checkout.run(checkout.controller.dismiss);
      expect(checkout.result, isA<CheckoutCancelled>());
      expect(api.calls('/pay/cancel'), hasLength(1), reason: 'nothing was charged: the payment is released');
    });

    // Steps: the sheet's language, else English, else French; a template
    // naming anything else, or a value missing, is shown as its text.
    final only = PayerOtpInstructions.fromJson({
      'channel': 'bf.orange',
      'ussd_code': null,
      'otp_length': null,
      'amount': '20.5',
      'currency': 'XOF',
      'steps': {
        'fr': [
          {'text': 'Composez le code.', 'template': 'Composez {ussd_code}.'},
          {'text': 'Montant : 20.5 XOF.', 'template': 'Montant : {amount} {currency} ({fee}).'},
        ],
      },
    })!;
    expect(only.stepsFor('en').map((s) => s.text), ['Composez le code.', 'Montant : 20.5 XOF.']);
    expect(only.stepsFor('en').map(only.parts), [
      [(PayerOtpPart.text, 'Composez le code.')],
      [(PayerOtpPart.text, 'Montant : 20.5 XOF.')],
    ]);
    expect((only.amount, only.dialUrl), ('20.5', null), reason: 'the amount as sent');
    expect([
      for (final code in ['123', '1234', '12345678', '123456789']) only.accepts(code)
    ], [
      false,
      true,
      true,
      false
    ], reason: 'no length: 4 to 8 digits');
  });

  test('MM-13 handles refused payer codes', () {
    virtual((async) {
      final api = payerOtpApi(announced: false, process: [
        'process-payer-otp-required.json',
        'process-payer-otp-invalid.json',
        'process-payer-otp-refused.json',
        'process-402-payer-otp-attempts-exceeded.json',
      ]);
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      checkout.run(controller.payMobileMoney);
      final opened = controller.payerOtpRound;

      checkout.run(() => controller.submitPayerOtp('123456'));
      expect(controller.state, CheckoutState.payerOtpRequired);
      expect(controller.payerOtpRound, opened + 1, reason: 'the field emptied');
      expect((controller.payerOtpNotice, controller.payerOtpAttemptsRemaining), (PayerOtpNotice.invalidLength, null));

      checkout.run(() => controller.submitPayerOtp('654321'));
      expect(controller.state, CheckoutState.payerOtpRequired);
      expect(controller.payerOtpRound, opened + 2);
      expect((controller.payerOtpNotice, controller.payerOtpAttemptsRemaining), (PayerOtpNotice.refused, 2));
      expect(checkout.recorder.errors, isEmpty, reason: 'inline refusals are not onError');
      expect(checkout.recorder.started, isNull);

      checkout.run(() => controller.submitPayerOtp('654323'));
      expect((controller.state, controller.screen), (CheckoutState.collectingDetails, CheckoutScreen.form));
      expect(controller.method?.family, MethodFamily.mobileMoney);
      expect(
          controller.banner, 'Your operator refused too many codes for this payment. Choose another payment method.');
      expect(checkout.recorder.errors.map((e) => (e.code, e.retryable)), [('otp_attempts_exceeded', true)]);
      expect(controller.canCancel, isTrue, reason: 'still payable on another channel');
      checkout.end();
    });

    // While watching after a code: refused later, then too many refusals.
    virtual((async) {
      final api = payerOtpApi(
        process: ['process-payer-otp-accepted-sandbox.json'],
        status: [
          'status-pending-payer-otp-refused.json',
          'status-processing.json',
          pendingWith('otp_attempts_exceeded'),
        ],
      );
      final checkout = Checkout(async, api, locale: 'fr');
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      checkout.run(controller.payMobileMoney);
      checkout.run(() => controller.submitPayerOtp('123456'));
      expect(controller.state, CheckoutState.approvalRequired);
      final opened = controller.payerOtpRound;
      checkout.elapse(const Duration(seconds: 6));
      expect((controller.state, controller.screen), (CheckoutState.payerOtpRequired, CheckoutScreen.payerOtp));
      expect(controller.payerOtpRound, opened + 1);
      expect((controller.payerOtpNotice, controller.payerOtpAttemptsRemaining), (PayerOtpNotice.refused, null),
          reason: 'the count is unknown there');
      expect(checkout.recorder.errors, isEmpty);

      checkout.run(() => controller.submitPayerOtp('123457'));
      expect(dataOf(api.bodies('/pay/process').last)['otp'], '123457');
      expect(controller.state, CheckoutState.approvalRequired);
      checkout.elapse(const Duration(seconds: 12));
      expect((controller.state, controller.screen), (CheckoutState.collectingDetails, CheckoutScreen.form));
      expect(controller.banner, ErrorCatalogue.text(ErrorCatalogue.lookup('otp_attempts_exceeded')!, 'fr'));
      expect(checkout.recorder.errors.map((e) => e.code), ['otp_attempts_exceeded']);
      expect(checkout.recorder.events.where((e) => e.startsWith('started')), hasLength(2),
          reason: 'each code the operator took started an attempt');
      checkout.end();
    });
  });
}
