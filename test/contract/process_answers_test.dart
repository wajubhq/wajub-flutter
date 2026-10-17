import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

/// A live Cameroonian session (cm.mobile aggregate, Stripe card).
FakeApi cameroon({Object process = 'process-processing-mobile-money-live.json', Object? status}) => FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
      'POST /pay/process': process,
      'GET /pay/status': status ?? 'status-processing.json',
    });

void main() {
  test('PA-01 ignores message when deciding', () {
    virtual((async) {
      // A 200 succeeded whose message still says to confirm on the phone.
      expect(fixtureBody('process-succeeded-200.json')['message'], contains('Confirm'));
      final checkout = Checkout(async, cameroon(process: 'process-succeeded-200.json'));
      checkout.mobileMoney('677123457');
      checkout.run(checkout.controller.payMobileMoney);

      expect(checkout.controller.state, CheckoutState.success);
      expect(checkout.recorder.success?.id, 'trx_Succeeded0000000000000');
      expect(checkout.recorder.states, isNot(contains(CheckoutState.approvalRequired)));
      checkout.end();
    });
  });

  test('PA-02 follows redirects', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-card-cinetpay.json',
        'POST /pay/process': 'process-redirect-card-hosted.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      checkout.controller.selectMethod(checkout.method(MethodFamily.card));
      for (final field in checkout.controller.cardRequiredFields) {
        checkout.controller.setCardField(
            field,
            field == 'email'
                ? 'awa@example.com'
                : field == 'country'
                    ? 'CM'
                    : 'x');
      }
      checkout.run(checkout.controller.payCard);

      const url = 'https://checkout.psp.example/pay/abc123';
      expect(checkout.recorder.redirects, [url]);
      expect(checkout.opened, [url]);
      expect(checkout.recorder.events.indexOf('redirect'), lessThan(checkout.recorder.events.length));
      expect(checkout.controller.state, CheckoutState.pending);
      expect(checkout.controller.continueUrl, url);
      checkout.elapse(const Duration(seconds: 6));
      expect(api.calls('/pay/status'), isNotEmpty, reason: 'watching while the browser is away');
      checkout.end();
    });

    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-ci-xof-wallets.json',
        'GET /pay/sdk-config': 'sdk-config-ci-wallets.json',
        'POST /pay/process': 'process-redirect-wallet-djamo.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      checkout.controller.selectMethod(checkout.method(MethodFamily.wallet));
      checkout.run(checkout.controller.payWallet);
      expect(checkout.opened, ['https://djamo.ci/?type=payment_confirmation&id=abc']);
      expect(checkout.controller.state, CheckoutState.pending);
      checkout.end();
    });
  });

  test('PA-03 maps unknown actions to unsupported_action', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (body) => body['action'] = 'confirm_magic',
      (body) => body.remove('otp_id'),
    ]) {
      virtual((async) {
        final body = fixtureBody('process-requires-otp.json');
        mutate(body);
        final api = cameroon(process: FakeAnswer(202, body));
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456');
        checkout.run(checkout.controller.payMobileMoney);

        expect(checkout.controller.state, CheckoutState.failed);
        expect(checkout.controller.error?.code, 'unsupported_action');
        expect(checkout.controller.error?.retryable, isFalse);
        checkout.end();
      });
    }
  });

  test('PA-04 maps declines', () {
    for (final (name, code, retryable) in [
      ('process-failed-402.json', 'insufficient_funds', true),
      ('process-402-insufficient-funds-sandbox.json', 'insufficient_funds', true),
      ('process-402-merchant-not-verified.json', 'merchant_not_verified', false),
    ]) {
      virtual((async) {
        final checkout = Checkout(async, cameroon(process: name), locale: 'en');
        checkout.mobileMoney('677123458');
        checkout.run(checkout.controller.payMobileMoney);

        final error = checkout.controller.error!;
        expect(checkout.controller.state, CheckoutState.failed, reason: name);
        expect(error.code, code);
        expect(error.declineCode, code);
        expect(error.retryable, retryable);
        expect(checkout.recorder.errors.single.code, code);
        checkout.controller.tryAgain();
        expect(checkout.controller.state, retryable ? CheckoutState.collectingDetails : CheckoutState.failed);
        checkout.end();
      });
    }
  });

  test('PA-05 waits on a charge in progress', () {
    virtual((async) {
      final api = cameroon(process: 'process-409-payment-in-progress.json', status: [
        FakeAnswer.fixture('status-processing.json'),
        FakeAnswer.fixture('status-succeeded.json'),
      ]);
      final checkout = Checkout(async, api);
      checkout.mobileMoney('690000000');
      checkout.run(checkout.controller.payMobileMoney);

      expect(checkout.controller.state, CheckoutState.pending);
      expect(checkout.recorder.errors, isEmpty);
      checkout.elapse(const Duration(seconds: 6));
      expect(checkout.controller.state, CheckoutState.success);
      checkout.end();
    });
  });

  test('PA-06 maps validation errors to fields', () {
    final cases = {
      'process-422-validation.json': ('data.phone', 'Invalid phone number'),
      'process-422-operator-mismatch.json': (
        'data.phone',
        'This number belongs to Orange Money. Pick Orange Money in the list, or enter a MTN MoMo number.'
      ),
      'process-422-sandbox-invalid-test-number.json': ('data.phone', 'Invalid phone number'),
      'process-422-over-mobile-money-limit-sandbox.json': (
        null,
        'This amount is above the limit for this payment method. Use a smaller amount or another method.'
      ),
    };
    cases.forEach((name, expected) {
      virtual((async) {
        final checkout = Checkout(async, cameroon(process: name), locale: 'en');
        checkout.mobileMoney('677123456');
        checkout.run(checkout.controller.payMobileMoney);

        expect(checkout.controller.screen, CheckoutScreen.form, reason: name);
        expect(checkout.controller.state, CheckoutState.collectingDetails);
        final (field, message) = expected;
        if (field != null) {
          expect(checkout.controller.fieldErrors[field], message, reason: name);
        } else {
          expect(checkout.controller.banner, message, reason: name);
        }
        expect(checkout.recorder.errors, isEmpty, reason: 'field validation is not an onError failure');
        checkout.end();
      });
    });
  });

  test('PA-07 surfaces rate limits', () {
    virtual((async) {
      final api = cameroon(process: FakeAnswer.fixture('error-429-rate-limited.json', headers: {'retry-after': '300'}));
      final checkout = Checkout(async, api, locale: 'en');
      checkout.mobileMoney('677123456');
      checkout.run(checkout.controller.payMobileMoney);

      final error = checkout.controller.error!;
      expect(error.code, 'rate_limited');
      expect(error.retryAfterSeconds, 300);
      expect(error.message, 'Too many attempts. Please wait 300 s before trying again.');
      expect(api.calls('/pay/process'), hasLength(1), reason: 'no automatic retry');
      checkout.controller.tryAgain();
      expect(checkout.controller.state, CheckoutState.failed, reason: 'the countdown is running');
      checkout.elapse(const Duration(seconds: 301));
      checkout.controller.tryAgain();
      expect(checkout.controller.state, CheckoutState.collectingDetails);
      checkout.end();
    });
  });

  test('PA-08 maps refusals', () {
    for (final (name, code, reference) in [
      ('process-403-shield-blocked.json', 'shield_blocked', 'BLK-PLACEHOLDER'),
      ('process-403-restricted.json', 'payment_method_restricted', null),
    ]) {
      virtual((async) {
        final checkout = Checkout(async, cameroon(process: name), locale: 'en');
        checkout.mobileMoney('677123456');
        checkout.run(checkout.controller.payMobileMoney);

        final error = checkout.controller.error!;
        expect(error.code, code);
        expect(error.blockReference, reference);
        if (reference != null) expect(error.message, 'Payment blocked for security. Reference: BLK-PLACEHOLDER.');
        checkout.end();
      });
    }
  });

  test('PA-09 handles ended sessions during payment', () {
    virtual((async) {
      final api = cameroon(process: 'process-400-not-processable.json', status: 'status-succeeded.json');
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456');
      checkout.run(checkout.controller.payMobileMoney);
      expect(api.calls('/pay/status'), hasLength(1));
      expect(checkout.controller.state, CheckoutState.success);
      checkout.end();
    });

    for (final (status, state) in [
      (
        const FakeAnswer(200, {
          'transaction': {'reference': 'trx_PVrU8x2kQ1mNa7Lb3cDe', 'status': 'pending'}
        }),
        CheckoutState.failed
      ),
      (FakeAnswer.fixture('status-processing.json'), CheckoutState.pending),
      (const FakeAnswer(200, <String, dynamic>{}), CheckoutState.pending),
      (const FakeAnswer(503, <String, dynamic>{}), CheckoutState.pending),
    ]) {
      virtual((async) {
        // pending: not_processable; processing, or unreadable: follow it.
        final api = cameroon(process: 'process-400-not-processable.json', status: status);
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        checkout.elapse(const Duration(seconds: 10));
        expect(checkout.controller.state, state, reason: '${status.status} ${status.body}');
        if (state == CheckoutState.failed) expect(checkout.controller.error?.code, 'not_processable');
        checkout.end();
      });
    }

    virtual((async) {
      final checkout = Checkout(async, cameroon(process: 'error-410-process-session-ended.json'));
      checkout.mobileMoney('677123456');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.state, CheckoutState.expired);
      expect(checkout.controller.error?.code, 'session_terminal_expired');
      checkout.end();
    });
  });

  test('PA-10 fires payment started on the first 2xx', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-sandbox-cm.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': [
          'process-422-sandbox-invalid-test-number.json',
          'process-processing-mobile-money-sandbox.json'
        ],
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.recorder.started, isNull, reason: 'a 422 starts nothing');

      checkout.controller.setPhone('670000000');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.recorder.started?.method, 'mobile_money');
      expect(checkout.recorder.started?.channel, 'cm.mobile');
      checkout.elapse(const Duration(seconds: 12));
      expect(checkout.recorder.events.where((e) => e.startsWith('started')), hasLength(1));
      checkout.end();
    });

    // Asked for the payer's code: nothing charged yet; the 2xx that answers
    // the code starts the payment.
    virtual((async) {
      final session = fixtureBody('session-payer-otp-announced.json');
      (((session['channels'] as List).first) as Map).remove('payer_otp');
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer(200, session),
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': ['process-payer-otp-required.json', 'process-payer-otp-accepted-sandbox.json'],
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('70000000');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.state, CheckoutState.payerOtpRequired);
      expect(checkout.recorder.started, isNull, reason: 'a payer_otp answer charged nothing');
      checkout.run(() => checkout.controller.submitPayerOtp('123456'));
      expect(checkout.recorder.events.where((e) => e.startsWith('started')), ['started:mobile_money:bf.orange']);
      checkout.elapse(const Duration(seconds: 12));
      expect(checkout.recorder.events.where((e) => e.startsWith('started')), hasLength(1));
      checkout.end();
    });
  });
}
