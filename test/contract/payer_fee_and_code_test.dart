import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/altcha.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/errors/error_catalogue.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/payer_otp.dart';
import 'package:wajub_mobile/src/models/payment_result.dart';
import 'package:wajub_mobile/src/realtime/payment_watcher.dart';
import 'package:wajub_mobile/src/widgets/sheet_strings.dart';
import 'package:wajub_mobile/wajub_mobile.dart' as public;

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

/// The Burkina Faso session as a body: its Orange channel's `payer_otp`
/// changed by [change], or removed when [change] returns null.
Map<String, dynamic> announcedSession(Map<String, dynamic>? Function(Map<String, dynamic> otp) change) {
  final session = fixtureBody('session-payer-otp-announced.json');
  final channel = (session['channels'] as List).first as Map;
  final otp = change(Map<String, dynamic>.from(channel['payer_otp'] as Map));
  otp == null ? channel.remove('payer_otp') : channel['payer_otp'] = otp;
  return session;
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

  test('MM-12 asks for the payer\'s code the charge asks for (processPayment)', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-payer-otp-announced.json',
        'POST /pay/process': [
          'process-payer-otp-required.json',
          'process-payer-otp-refused.json',
          'process-payer-otp-accepted-sandbox.json',
        ],
      });
      final session = api.session();
      final results = <PaymentResult>[];
      const data = {'phone': '+22670000000', 'country': 'BF'};
      session.processPayment('bf.orange', data, idempotencyKey: 'key-1').then(results.add);
      async.flushMicrotasks();

      final asked = results.single as PaymentRequiresAction;
      expect(asked.action, ActionKind.payerOtp);
      expect(asked.transaction.status, 'pending', reason: 'nothing was charged');
      final public.PayerOtpInstructions instructions = asked.payerOtp!;
      expect((instructions.channel, instructions.ussdCode, instructions.otpLength), ('bf.orange', '*144*4*6#', 6));
      expect((instructions.amount, instructions.currency), ('1000', 'XOF'));
      expect((instructions.reason, instructions.attemptsRemaining), ('required', 3));
      expect(instructions.stepsFor('fr').first.text, 'Sur le téléphone du compte Orange Money, composez *144*4*6#.');
      expect(instructions.dialUrl, 'tel:*144*4*6%23');

      session.processPayment('bf.orange', {...data, 'otp': '654321'}, idempotencyKey: 'key-2').then(results.add);
      async.flushMicrotasks();
      final refused = results.last as PaymentRequiresAction;
      expect((refused.action, refused.payerOtp?.reason, refused.payerOtp?.attemptsRemaining),
          (ActionKind.payerOtp, 'refused', 2));

      session.processPayment('bf.orange', {...data, 'otp': '123456'}, idempotencyKey: 'key-3').then(results.add);
      async.flushMicrotasks();
      expect((results.last as PaymentRequiresAction).action, ActionKind.pushApproval, reason: 'approve as usual');
      expect(api.bodies('/pay/process').map((b) => (b['data'] as Map)['otp']), [null, '654321', '123456']);

      // The channel that announces it says so too.
      final channel = SessionData.fromJson(fixtureBody('session-payer-otp-announced.json')).channels.first;
      final public.PayerOtpInstructions? announced = channel.payerOtp;
      expect((announced?.ussdCode, announced?.reason), ('*144*4*6#', null));
    });
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

  test('MM-13 handles refused payer codes (the refusal baseline)', () {
    // The refused answer's invalid_otp is the payment's last refusal: a code
    // sent next that gets no answer is not taken as refused by a status
    // still carrying it.
    virtual((async) {
      final api = payerOtpApi(
        announced: false,
        process: ['process-payer-otp-required.json', 'process-payer-otp-refused.json', const FakeAnswer.network()],
        status: 'status-pending-payer-otp-refused.json',
      );
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      checkout.run(controller.payMobileMoney);
      checkout.run(() => controller.submitPayerOtp('654321'));
      expect((controller.payerOtpNotice, controller.payerOtpAttemptsRemaining), (PayerOtpNotice.refused, 2));
      final opened = controller.payerOtpRound;

      checkout.run(() => controller.submitPayerOtp('123457'));
      checkout.elapse(const Duration(seconds: 30));
      expect(controller.state, CheckoutState.pending, reason: 'the old refusal is not news');
      expect(controller.payerOtpRound, opened);
      expect(api.calls('/pay/status'), isNotEmpty);
      checkout.elapse(const Duration(seconds: 60));
      expect(controller.state, CheckoutState.collectingDetails, reason: 'it never arrived');
      checkout.end();
    });
  });

  test('MM-13 handles refused payer codes (a refusal no code of this sheet led to)', () {
    virtual((async) {
      final api = payerOtpApi(
        announced: false,
        process: ['process-payer-otp-accepted-sandbox.json'],
        status: 'status-pending-payer-otp-refused.json',
      );
      final checkout = Checkout(async, api, locale: 'fr');
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      checkout.run(controller.payMobileMoney);
      expect(controller.state, CheckoutState.approvalRequired, reason: 'charged without a code');
      checkout.elapse(const Duration(seconds: 6));
      expect((controller.state, controller.screen), (CheckoutState.collectingDetails, CheckoutScreen.form));
      expect(controller.banner, "Votre opérateur n'a pas accepté ce code. Générez-en un nouveau et réessayez.");
      expect(checkout.recorder.errors, isEmpty, reason: 'not a failure');
      expect(controller.operatorBlock(controller.selectedChoice!), isNull, reason: 'still payable here');
      checkout.end();
    });

    // Read through the status alone: the same words, never a raw {n}.
    for (final language in ['en', 'fr']) {
      final error = attemptEndedError(const PaymentStatusUpdate(status: 'pending', errorCode: 'invalid_otp'), language);
      expect(error.message, ErrorCatalogue.text(ErrorCatalogue.payerOtpRefused, language));
      expect(error.message, isNot(contains('{')));
    }
  });

  test('MM-13 handles refused payer codes (the exhausted channel)', () {
    virtual((async) {
      final api = payerOtpApi(process: ['process-402-payer-otp-attempts-exceeded.json']);
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      checkout.run(controller.payMobileMoney);
      checkout.run(() => controller.submitPayerOtp('654323'));
      final text = ErrorCatalogue.text(ErrorCatalogue.lookup('otp_attempts_exceeded')!, 'en');
      expect((controller.state, controller.banner), (CheckoutState.collectingDetails, text));
      final orange = controller.choices.single;
      expect(controller.operatorBlock(orange)?.message, text, reason: 'shown disabled with that text');
      expect(controller.announcedPayerOtp, isNull);
      expect((controller.selectedChoice, controller.hasOfferedOperator), (null, false),
          reason: 'none left: no selection, no Pay');

      controller.pickOperator('orange');
      checkout.run(controller.payMobileMoney);
      expect((controller.state, controller.screen), (CheckoutState.collectingDetails, CheckoutScreen.form),
          reason: 'Pay never reopens the code screen there');
      expect(api.calls('/pay/process'), hasLength(1));
      checkout.end();
    });

    // Refused too many times while watching: the same.
    virtual((async) {
      final api = payerOtpApi(
          process: ['process-payer-otp-accepted-sandbox.json'], status: pendingWith('otp_attempts_exceeded'));
      final checkout = Checkout(async, api);
      checkout.mobileMoney('70000000');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.run(() => checkout.controller.submitPayerOtp('123456'));
      checkout.elapse(const Duration(seconds: 6));
      expect(checkout.controller.state, CheckoutState.collectingDetails);
      expect(checkout.controller.operatorBlock(checkout.controller.choices.single), isNotNull);
      expect(checkout.controller.hasOfferedOperator, isFalse);
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.state, CheckoutState.collectingDetails);
      expect(api.calls('/pay/process'), hasLength(1));
      checkout.end();
    });
  });

  test('MM-13 handles refused payer codes (instructions that leave things out)', () {
    // A code asked without how to get it: unsupported, and nothing started.
    virtual((async) {
      final asked = fixtureBody('process-payer-otp-required.json')..remove('payer_otp');
      final api = payerOtpApi(announced: false, process: [FakeAnswer(202, asked)]);
      final checkout = Checkout(async, api);
      checkout.mobileMoney('70000000');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.error?.code, 'unsupported_action');
      expect(checkout.recorder.started, isNull, reason: 'nothing was charged');
      checkout.run(checkout.controller.dismiss);
      expect(api.calls('/pay/cancel'), hasLength(1), reason: 'the payment is released');
    });

    // A missing amount is none; steps as plain strings; an empty list is none.
    final sparse = PayerOtpInstructions.fromJson({
      'channel': 'bf.orange',
      'ussd_code': ' *144*4*6# ',
      'otp_length': 0,
      'amount': '',
      'currency': 'XOF',
      'steps': {
        'fr': <Object>[],
        'en': ['Dial the code.', 42, null],
      },
      'reason': 'refused',
      'attempts_remaining': -2,
    })!;
    expect((sparse.amount, sparse.amountText), (null, null), reason: 'never " XOF"');
    expect(sparse.stepsFor('fr').map((s) => s.text), ['Dial the code.'], reason: 'an empty list counts as none');
    expect(sparse.stepsFor('fr').single.template, isNull);
    expect(sparse.otpLength, isNull);
    expect(sparse.attemptsRemaining, 0, reason: 'none left');
    expect((SheetStrings.en.payerOtpAttempts(0), SheetStrings.fr.payerOtpAttempts(0)),
        ('No tries left.', 'Plus aucun essai possible.'));
    expect((SheetStrings.en.payerOtpGenericSteps(null)[1], SheetStrings.fr.payerOtpGenericSteps(null)[1]),
        ('Generate a payment code for the exact amount.', 'Générez un code de paiement pour le montant exact.'));
    expect(PayerOtpInstructions.fromJson({'ussd_code': '*144 *4*6 #'})!.dialUrl, 'tel:*144*4*6%23');
    for (final (length, read) in [(-3, null), (0, null), (1, 1), (12, 12), (13, null), ('6', 6)]) {
      expect(PayerOtpInstructions.fromJson({'otp_length': length})!.otpLength, read, reason: '$length');
    }
  });

  test('MM-13 handles refused payer codes (the tries left stay)', () {
    virtual((async) {
      final api =
          payerOtpApi(announced: false, process: ['process-payer-otp-required.json', 'process-payer-otp-refused.json']);
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      checkout.run(controller.payMobileMoney);
      checkout.run(() => controller.submitPayerOtp('654321'));
      expect((controller.payerOtpNotice, controller.payerOtpAttemptsRemaining), (PayerOtpNotice.refused, 2));
      controller.payerOtpTyped();
      expect((controller.payerOtpNotice, controller.payerOtpAttemptsRemaining), (null, 2),
          reason: 'the refusal goes once the payer types again; the tries left stay');
      checkout.run(() => controller.submitPayerOtp('12'));
      expect((controller.payerOtpNotice, controller.payerOtpAttemptsRemaining), (PayerOtpNotice.invalidLength, 2));
      expect(api.calls('/pay/process'), hasLength(2));
      checkout.end();
    });
  });

  test('MM-13 handles refused payer codes (a security retry keeps the code)', () {
    String sha(String text) => sha256.convert(utf8.encode(text)).toString();
    Map<String, dynamic> withChallenge(String salt, int number) => fixtureBody('session-payer-otp-announced.json')
      ..['altcha'] = {
        'algorithm': 'SHA-256',
        'challenge': sha('$salt$number'),
        'salt': salt,
        'signature': 'sig',
        'maxnumber': 100,
      };
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': [FakeAnswer(200, withChallenge('s1', 7)), FakeAnswer(200, withChallenge('s2', 42))],
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': ['process-422-security-check-failed.json', 'process-payer-otp-accepted-sandbox.json'],
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api, altchaSolver: (c) async => solveAltcha(c));
      final controller = checkout.controller;
      checkout.mobileMoney('70000000');
      checkout.run(controller.payMobileMoney);
      checkout.run(() => controller.submitPayerOtp('123456'));
      final bodies = api.bodies('/pay/process');
      expect(bodies.map((b) => dataOf(b)['otp']), ['123456', '123456'], reason: 'the same code');
      expect(bodies.map((b) => (dataOf(b)['altcha'] as Map)['number']), [7, 42], reason: 'a new challenge');
      expect(controller.state, CheckoutState.approvalRequired);
      expect(controller.payerOtpSent, isTrue, reason: 'the same flow afterwards');
      expect(checkout.recorder.errors, isEmpty);
      checkout.end();
    });
  });

  test('CH-07 shows what the payer pays on the chosen channel (after a code step, and the limits)', () {
    // Back on the form after a code step: the selection's amount again.
    virtual((async) {
      final asked = fixtureBody('process-payer-otp-required.json')
        ..['transaction'] = fixtureBody('session-payer-fee-per-channel.json')['transaction'];
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-payer-fee-per-channel.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': [FakeAnswer(202, asked), 'process-payer-fee-on-channel-sandbox.json'],
        'GET /pay/status': 'status-pending-payer-otp-refused.json',
      });
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('690000000');
      checkout.run(controller.payMobileMoney);
      expect(controller.state, CheckoutState.payerOtpRequired);
      checkout.run(() => controller.submitPayerOtp('123456'));
      expect(controller.amountToPay, 10450, reason: 'what the charge took');
      checkout.elapse(const Duration(seconds: 6));
      expect(controller.state, CheckoutState.payerOtpRequired, reason: 'refused later');
      controller.leavePayerOtp();
      controller.pickOperator('mtn');
      expect(controller.amountToPay, 10200, reason: "the selection's, not the attempt's");
      controller.backToMethods();
      expect(controller.amountToPay, 10200);
      checkout.end();
    });
  });

  test('CH-05 disables channels out of their limits (what the chosen operator costs)', () {
    virtual((async) {
      final session = fixtureBody('session-payer-fee-per-channel.json');
      ((session['channels'] as List).first as Map)['max_amount'] = 10300;
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer(200, session),
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      });
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      expect(checkout.method(MethodFamily.mobileMoney).enabled, isTrue, reason: 'MTN is within it');
      checkout.mobileMoney('670000000');
      expect(controller.operatorBlock(controller.selectedChoice!), isNull);
      final orange = controller.choices.firstWhere((c) => c.id == 'orange');
      expect(controller.operatorBlock(orange)?.limit?.amount, 10300, reason: '10 450 is over 10 300');
      controller.pickOperator('orange');
      expect(controller.selectedOperatorId, 'mtn', reason: 'not offered');
      controller.setPhone('690000000');
      expect(controller.selectedOperatorId, 'mtn', reason: 'detection never selects a disabled operator');
      checkout.run(controller.payMobileMoney);
      expect(controller.fieldErrors['data.phone'], contains('Orange'), reason: 'the number is not MTN');
      expect(api.calls('/pay/process'), isEmpty);
      checkout.end();
    });
  });

  test('MM-13 handles refused payer codes (the form on a reopened sheet)', () {
    // A sheet reopened on an approval in progress never built its form: a
    // refusal brings it, the payment's country and its operators.
    for (final (status, exhausted) in [
      (FakeAnswer.fixture('status-pending-payer-otp-refused.json'), false),
      (pendingWith('otp_attempts_exceeded'), true),
    ]) {
      virtual((async) {
        // Reopened on MTN, with Orange offered too.
        final session = fixtureBody('session-processing-mobile-money.json');
        final aggregate = fixtureBody('session-cm-aggregate.json');
        final orange = (((aggregate['channels'] as List).firstWhere((c) => (c as Map)['slug'] == 'cm.mobile')
                as Map)['operators'] as List)
            .firstWhere((o) => (o as Map)['operator'] == 'orange');
        (((session['channels'] as List).first as Map)['operators'] as List).add(orange);
        final api = FakeApi(routes: {
          'GET /pay/session': FakeAnswer(200, session),
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'GET /pay/status': status,
        });
        final checkout = Checkout(async, api);
        final controller = checkout.controller;
        checkout.elapse(const Duration(seconds: 1));
        expect((controller.state, controller.screen), (CheckoutState.collectingDetails, CheckoutScreen.form),
            reason: '$exhausted');
        expect(controller.method?.family, MethodFamily.mobileMoney);
        expect(controller.country, 'CM');
        expect(controller.choices.map((c) => c.id), ['mtn', 'orange']);
        expect(controller.hasOfferedOperator, isTrue);
        if (exhausted) {
          expect(controller.operatorBlock(controller.choices.first), isNotNull, reason: 'cm.mtn was being paid');
          expect(controller.selectedOperatorId, 'orange', reason: 'the first choice still offered');
          expect(checkout.recorder.errors.map((e) => e.code), ['otp_attempts_exceeded']);
        } else {
          expect(controller.banner, ErrorCatalogue.text(ErrorCatalogue.payerOtpRefused, 'en'));
          expect(controller.selectedOperatorId, 'mtn');
          expect(checkout.recorder.errors, isEmpty);
        }
        checkout.end();
      });
    }
  });

  test('MM-03 never selects a disabled operator', () {
    // The selection becomes disabled: it moves to the first choice still
    // offered, and detection does not bring it back.
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-sandbox-cm.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': ['process-payer-otp-required.json', 'process-402-payer-otp-attempts-exceeded.json'],
      });
      final checkout = Checkout(async, api);
      final controller = checkout.controller;
      checkout.mobileMoney('670000000', pick: 'mtn');
      checkout.run(controller.payMobileMoney);
      checkout.run(() => controller.submitPayerOtp('654323'));
      expect(controller.state, CheckoutState.collectingDetails);
      final mtn = controller.choices.firstWhere((c) => c.id == 'mtn');
      expect(controller.operatorBlock(mtn), isNotNull);
      expect(controller.selectedOperatorId, 'orange', reason: "MM-03's first choice still offered");
      controller.setPhone('670000001');
      expect(controller.selectedOperatorId, 'orange', reason: 'an MTN number does not select it');
      checkout.end();
    });
  });
}
