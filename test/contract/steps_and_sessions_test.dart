import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

/// A card paid on a hosted page with nothing to collect (Mollie), whose
/// `/pay/process` answers [process].
FakeApi hostedCard({required Object process, Object status = 'status-processing.json', Map<String, Object>? more}) =>
    FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'GET /pay/sdk-config': 'sdk-config-card-mollie.json',
      'POST /pay/process': process,
      'GET /pay/status': status,
      ...?more,
    });

Checkout payByCard(dynamic async, FakeApi api, {String? returnUrl}) {
  final checkout = Checkout(async, api, locale: 'en', returnUrl: returnUrl);
  checkout.controller.selectMethod(checkout.method(MethodFamily.card));
  checkout.run(checkout.controller.payCard);
  return checkout;
}

void main() {
  test('CF-01 opens each confirmation step', () {
    final steps = {
      'otp': (CheckoutState.otpRequired, {'code': '123456'}),
      'pin': (CheckoutState.pinRequired, {'pin': '1234'}),
      'phone': (CheckoutState.phoneRequired, {'phone': '08012345678'}),
      'birthday': (CheckoutState.birthdayRequired, {'birthday': '1990-04-21'}),
      'address': (
        CheckoutState.addressRequired,
        {'address': '12 Admiralty Way', 'city': 'Lagos', 'state': 'Lagos', 'zip_code': '101233'},
      ),
    };
    steps.forEach((kind, expected) {
      virtual((async) {
        final api = hostedCard(
          process: 'process-requires-$kind.json',
          more: {'POST /pay/$kind/verify': '$kind-verify-success.json'},
        );
        final checkout = payByCard(async, api);
        final (state, fields) = expected;
        expect(checkout.controller.screen, CheckoutScreen.step, reason: kind);
        expect(checkout.controller.state, state);
        expect(checkout.controller.stepHint,
            fixtureBody('process-requires-$kind.json')[kind == 'otp' ? 'otp_masked_contact' : '${kind}_instruction']);

        checkout.run(() => checkout.controller.submitStep(fields));
        expect(api.bodies('/pay/$kind/verify').single, {'${kind}_id': 'prc_7hQm2LxV9pR4sT1wYb3N', ...fields});
        checkout.end();
      });
    });
  });

  test('CF-02 reads the transaction after a step', () {
    for (final kind in ['otp', 'pin', 'phone', 'birthday', 'address']) {
      virtual((async) {
        final api = hostedCard(
          process: 'process-requires-$kind.json',
          status: ['status-processing.json', 'status-succeeded.json'],
          more: {'POST /pay/$kind/verify': '$kind-verify-success.json'},
        );
        final checkout = payByCard(async, api);
        checkout.run(() => checkout.controller.submitStep({'value': '1'}));
        // Still processing after the step: wait on the status.
        expect(checkout.controller.state, CheckoutState.pending, reason: kind);
        checkout.elapse(const Duration(seconds: 6));
        expect(checkout.controller.state, CheckoutState.success, reason: kind);
        checkout.end();
      });
    }
    virtual((async) {
      final paid = fixtureBody('otp-verify-success.json');
      (paid['transaction'] as Map)['status'] = 'succeeded';
      final api =
          hostedCard(process: 'process-requires-otp.json', more: {'POST /pay/otp/verify': FakeAnswer(200, paid)});
      final checkout = payByCard(async, api);
      checkout.run(() => checkout.controller.submitStep({'code': '123456'}));
      expect(checkout.controller.state, CheckoutState.success);
      checkout.end();
    });
  });

  test('CF-03 handles step refusals', () {
    virtual((async) {
      final api =
          hostedCard(process: 'process-requires-otp.json', more: {'POST /pay/otp/verify': 'otp-verify-invalid.json'});
      final checkout = payByCard(async, api);
      checkout.run(() => checkout.controller.submitStep({'code': '000000'}));
      expect(checkout.controller.screen, CheckoutScreen.step);
      expect(checkout.controller.state, CheckoutState.otpRequired);
      expect(checkout.controller.attemptsRemaining, 2);
      expect(checkout.controller.banner, 'Incorrect code. 2 attempts left.');
      checkout.end();
    });
    virtual((async) {
      final api =
          hostedCard(process: 'process-requires-pin.json', more: {'POST /pay/pin/verify': 'pin-verify-invalid.json'});
      final checkout = payByCard(async, api);
      checkout.run(() => checkout.controller.submitStep({'pin': '0000'}));
      expect(checkout.controller.state, CheckoutState.pinRequired);
      expect(checkout.controller.banner, 'Incorrect PIN. 2 attempts left.');
      checkout.end();
    });
    for (final (name, code) in [
      ('otp-verify-max-attempts.json', 'max_attempts_exceeded'),
      ('otp-verify-expired.json', 'otp_expired'),
    ]) {
      virtual((async) {
        final api = hostedCard(process: 'process-requires-otp.json', more: {'POST /pay/otp/verify': name});
        final checkout = payByCard(async, api);
        checkout.run(() => checkout.controller.submitStep({'code': '000000'}));
        expect(checkout.controller.state, CheckoutState.failed);
        expect(checkout.controller.error?.code, code);
        expect(checkout.controller.error?.retryable, isTrue);
        checkout.end();
      });
    }
  });

  test('CF-04 shows step validation errors', () {
    virtual((async) {
      final api = hostedCard(
        process: 'process-requires-address.json',
        more: {'POST /pay/address/verify': 'address-verify-422-missing-fields.json'},
      );
      final checkout = payByCard(async, api);
      checkout.run(() =>
          checkout.controller.submitStep({'address': '12 Admiralty Way', 'city': ' ', 'state': 'x', 'zip_code': 'y'}));
      // A missing field is caught before the call.
      expect(api.calls('/pay/address/verify'), isEmpty);
      expect(checkout.controller.fieldErrors.keys, ['city']);

      checkout.run(() =>
          checkout.controller.submitStep({'address': '12 Admiralty Way', 'city': 'c', 'state': 's', 'zip_code': 'z'}));
      expect(checkout.controller.screen, CheckoutScreen.step);
      expect(checkout.controller.state, CheckoutState.addressRequired);
      expect(checkout.controller.fieldErrors, {
        'city': 'The city field is required.',
        'state': 'The state field is required.',
        'zip_code': 'The zip code field is required.',
      });
      checkout.end();
    });
    virtual((async) {
      final api = hostedCard(
        process: 'process-requires-birthday.json',
        more: {'POST /pay/birthday/verify': 'birthday-verify-422-format.json'},
      );
      final checkout = payByCard(async, api);
      checkout.run(() => checkout.controller.submitStep({'birthday': '21/04/1990'}));
      expect(checkout.controller.state, CheckoutState.birthdayRequired);
      expect(checkout.controller.fieldErrors['birthday'], 'The birthday field must match the format Y-m-d.');
      checkout.end();
    });
  });

  test('CF-05 resends after the countdown', () {
    virtual((async) {
      final api =
          hostedCard(process: 'process-requires-otp.json', more: {'POST /pay/otp/resend': 'otp-resend-200.json'});
      final checkout = payByCard(async, api);
      checkout.run(checkout.controller.resend);
      expect(api.calls('/pay/otp/resend'), isEmpty, reason: 'not before 60 s');

      checkout.elapse(const Duration(seconds: 60));
      checkout.run(checkout.controller.resend);
      expect(api.bodies('/pay/otp/resend').single, {'otp_id': 'prc_7hQm2LxV9pR4sT1wYb3N'});
      checkout.run(checkout.controller.resend);
      expect(api.calls('/pay/otp/resend'), hasLength(1), reason: 'the countdown starts again');
      checkout.end();
    });
  });

  test('CF-06 handles the sandbox 3ds code', () {
    FakeApi threeDs(Object verify) => FakeApi(routes: {
          'GET /pay/session': 'session-sandbox-cm.json',
          'GET /pay/sdk-config': 'sdk-config-sandbox.json',
          'POST /pay/process': 'process-requires-3ds-sandbox.json',
          'POST /pay/3ds/verify': verify,
          'POST /pay/3ds/send': '3ds-send-200.json',
          'GET /pay/status': ['status-processing.json', 'status-succeeded.json'],
        });
    Checkout sandboxCard(dynamic async, FakeApi api) {
      final checkout = Checkout(async, api, locale: 'en');
      checkout.controller.selectMethod(checkout.method(MethodFamily.card));
      for (final entry in {
        'card.number': '4000056655665556',
        'card_holder': 'Awa Ngono',
        'expiry_month': '12',
        'expiry_year': '30',
        'cvv': '123',
      }.entries) {
        checkout.controller.setCardField(entry.key, entry.value);
      }
      checkout.run(checkout.controller.payCard);
      return checkout;
    }

    virtual((async) {
      final api = threeDs('3ds-verify-202.json');
      final checkout = sandboxCard(async, api);
      expect(checkout.controller.screen, CheckoutScreen.threeDs);
      expect(checkout.controller.state, CheckoutState.threeDsRequired);
      expect(checkout.controller.stepHint, 'aw*******@example.com');

      checkout.run(() => checkout.controller.submitThreeDsCode('123456'));
      expect(api.bodies('/pay/3ds/verify').single,
          {'three_ds_id': '5f0c2b1e-8d4a-4c3b-9e7f-1a2b3c4d5e6f', 'code': '123456'});
      expect(checkout.controller.state, CheckoutState.verifying);
      expect(checkout.recorder.states, containsAllInOrder([CheckoutState.threeDsRequired, CheckoutState.verifying]));
      // Read at once (still processing), then on the next interval (paid).
      expect(api.calls('/pay/status'), hasLength(1));
      checkout.elapse(const Duration(seconds: 6));
      expect(checkout.controller.state, CheckoutState.success);
      checkout.end();
    });

    for (final wrong in ['3ds-verify-422-invalid-code.json', '3ds-verify-500-invalid-code-api-bug.json']) {
      virtual((async) {
        final api = threeDs(wrong);
        final checkout = sandboxCard(async, api);
        checkout.run(() => checkout.controller.submitThreeDsCode('000000'));
        expect(checkout.controller.screen, CheckoutScreen.threeDs, reason: wrong);
        expect(checkout.controller.state, CheckoutState.threeDsRequired);
        expect(checkout.controller.fieldErrors['code'], startsWith('Invalid verification code.'));
        expect(api.calls('/pay/3ds/verify'), hasLength(1), reason: 'never retried');
        checkout.end();
      });
    }

    virtual((async) {
      final failed = fixtureBody('3ds-verify-422-invalid-code.json');
      failed['error'] = {'code': '3ds_rejected', 'message': 'Rejected', 'retryable': false};
      final checkout = sandboxCard(async, threeDs(FakeAnswer(422, failed)));
      checkout.run(() => checkout.controller.submitThreeDsCode('000000'));
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.error?.code, '3ds_rejected');
      checkout.end();
    });

    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-sandbox-cm.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': 'process-requires-3ds-sandbox.json',
        'POST /pay/3ds/send': '3ds-send-200.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = sandboxCard(async, api);
      checkout.elapse(const Duration(seconds: 61));
      checkout.run(checkout.controller.resend);
      expect(api.bodies('/pay/3ds/send').single, {'three_ds_id': '5f0c2b1e-8d4a-4c3b-9e7f-1a2b3c4d5e6f'});
      checkout.elapse(const Duration(seconds: 540));
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.error?.code, '3ds_timeout');
      checkout.end();
    });
  });

  FakeApi paystack({Object start = 'client-session-start-202.json', Object? complete}) => FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-card-paystack.json',
        'POST /pay/client-session': start,
        if (complete != null) 'POST /pay/client-session/complete': complete,
        'GET /pay/status': 'status-processing.json',
      });

  Checkout startClientSession(dynamic async, FakeApi api) {
    final checkout = Checkout(async, api, locale: 'en', returnUrl: 'https://shop.example.com/app-return');
    checkout.controller.selectMethod(checkout.method(MethodFamily.card));
    expect(checkout.controller.cardRequiredFields, ['email']);
    expect(checkout.controller.cardFields['email'], 'awa.ngono@example.com', reason: 'the customer email is prefilled');
    checkout.run(checkout.controller.payCard);
    return checkout;
  }

  test('CS-01 opens a client session', () {
    for (final start in [
      'client-session-start-202.json',
      'client-session-start-202-flutterwave.json',
      'client-session-start-reserved.json',
    ]) {
      virtual((async) {
        final api = paystack(start: start);
        final checkout = startClientSession(async, api);
        final body = api.bodies('/pay/client-session').single;
        expect(body, {
          'channel': 'card',
          'email': 'awa.ngono@example.com',
          'return_url': 'https://shop.example.com/app-return',
        });
        expect(body.containsKey('inline'), isFalse);
        final hosted = (fixtureBody(start)['client_session'] as Map)['hosted_url'];
        expect(checkout.recorder.redirects, [hosted]);
        expect(checkout.opened, [hosted]);
        expect(checkout.controller.state, CheckoutState.pending);
        expect(checkout.recorder.started?.method, 'card');
        checkout.elapse(const Duration(seconds: 6));
        expect(api.calls('/pay/status'), isNotEmpty);
        checkout.end();
      });
    }
  });

  test('CS-02 completes a client session', () {
    final cases = {
      'client-session-complete-200.json': CheckoutState.success,
      'client-session-complete-202.json': CheckoutState.pending,
      'client-session-complete-402.json': CheckoutState.failed,
      'client-session-complete-422-expired.json': CheckoutState.failed,
    };
    cases.forEach((complete, state) {
      virtual((async) {
        final api = paystack(complete: complete);
        final checkout = startClientSession(async, api);
        checkout.controller.onAppPaused();
        checkout.run(checkout.controller.onAppResumed);
        expect(api.bodies('/pay/client-session/complete').single, {'client_session_id': 'prc_7hQm2LxV9pR4sT1wYb3N'});
        expect(checkout.controller.state, state, reason: complete);
        if (state == CheckoutState.failed) {
          expect(checkout.controller.error?.retryable, isTrue);
          expect(
            checkout.controller.error?.code,
            complete.contains('402') ? 'failed' : 'client_session_expired',
          );
        }
        checkout.end();
      });
    });
  });

  test('CS-03 reports client sessions unavailable in sandbox', () {
    virtual((async) {
      final api = paystack(start: 'client-session-422-sandbox.json');
      final checkout = startClientSession(async, api);
      expect(api.calls('/pay/client-session'), hasLength(1));
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.error?.code, 'client_session_unavailable');
      expect(checkout.controller.error?.retryable, isFalse);
      expect(checkout.recorder.started, isNull);
      checkout.end();
    });
  });

  test('RD-02 sends the return url only when given', () {
    for (final returnUrl in [null, 'https://shop.example.com/app-return']) {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-ci-xof-wallets.json',
          'GET /pay/sdk-config': 'sdk-config-ci-wallets.json',
          'POST /pay/process': 'process-redirect-wallet-djamo.json',
          'GET /pay/status': 'status-processing.json',
        });
        final checkout = Checkout(async, api, returnUrl: returnUrl);
        checkout.controller.selectMethod(checkout.method(MethodFamily.wallet));
        checkout.run(checkout.controller.payWallet);
        final data = api.bodies('/pay/process').single['data'] as Map;
        expect(data['return_url'], returnUrl);
        expect(data.containsKey('return_url'), returnUrl != null);
        checkout.end();
      });
    }
  });

  test('RD-03 polls on return', () {
    virtual((async) {
      final api = hostedCard(process: 'process-redirect-card-hosted.json', status: 'status-succeeded.json');
      final checkout = payByCard(async, api);
      expect(api.calls('/pay/status'), isEmpty);
      checkout.controller.onAppPaused();
      checkout.run(checkout.controller.onAppResumed);
      expect(api.calls('/pay/status'), hasLength(1), reason: 'at once, not after the interval');
      expect(checkout.controller.state, CheckoutState.success);
      checkout.end();
    });
  });

  test('CN-01 cancels on request', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api);
      expect(checkout.controller.canCancel, isTrue);
      checkout.run(checkout.controller.cancelPayment);
      final result = checkout.result as CheckoutCancelled;
      expect(result.reason, CancelReason.payerCancelled);
      expect(result.redirectUrl, fixtureBody('cancel-200.json')['redirect_url']);
      expect(checkout.recorder.cancel?.reason, CancelReason.payerCancelled);
      expect(checkout.recorder.states.last, CheckoutState.cancelled);
    });
  });

  test('CN-02 cancels on dismiss before any attempt', () {
    for (final cancelOnDismiss in [true, false]) {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/cancel': 'cancel-200.json',
        });
        final checkout = Checkout(async, api, cancelOnDismiss: cancelOnDismiss);
        checkout.run(checkout.controller.dismiss);
        final result = checkout.result as CheckoutCancelled;
        expect(result.reason, CancelReason.dismissed);
        expect(api.calls('/pay/cancel'), hasLength(cancelOnDismiss ? 1 : 0));
        expect(result.redirectUrl, cancelOnDismiss ? fixtureBody('cancel-200.json')['redirect_url'] : null);
      });
    }
    virtual((async) {
      // A cancel that fails changes nothing for the payer.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/cancel': const FakeAnswer.network(),
      });
      final checkout = Checkout(async, api);
      checkout.run(checkout.controller.dismiss);
      checkout.elapse(const Duration(seconds: 30));
      expect((checkout.result as CheckoutCancelled).reason, CancelReason.dismissed);
    });
  });

  test('CN-03 dismiss after start resolves processing', () {
    virtual((async) {
      // Pay pressed, no answer yet: the charge may be running.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-sandbox-cm.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': const FakeAnswer.hang(),
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('670000000', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.recorder.started, isNull);
      checkout.run(checkout.controller.dismiss);
      expect(checkout.result, isA<CheckoutProcessing>());
      expect(api.calls('/pay/cancel'), isEmpty);
      checkout.async.flushTimers(flushPeriodicTimers: false);
    });
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-sandbox-cm.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/process': 'process-processing-mobile-money-sandbox.json',
        'GET /pay/status': 'status-processing.json',
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('670000000', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.canCancel, isFalse);
      checkout.run(checkout.controller.dismiss);
      expect(checkout.result, isA<CheckoutProcessing>());
      expect(checkout.result?.transaction?.id, 'trx_test_PVrU8x2kQ1mNa7Lb3cDe');
      expect(api.calls('/pay/cancel'), isEmpty);
    });
  });

  test('CN-04 handles a refused cancel', () {
    // Never sent while loading, on a processing session, or while an attempt
    // is undecided; offered again after a definitive refusal (README §14).
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer.fixture('session-cm-aggregate.json', delay: const Duration(seconds: 5)),
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api);
      checkout.run(checkout.controller.dismiss);
      expect((checkout.result as CheckoutCancelled).reason, CancelReason.dismissed);
      expect(api.calls('/pay/cancel'), isEmpty, reason: 'the session had not answered');
    });
    for (final (session, expected, cancels) in [
      ('session-processing-mobile-money.json', CheckoutProcessing, 0),
      ('session-cm-aggregate.json', CheckoutCancelled, 1),
    ]) {
      virtual((async) {
        // The session answered, sdk-config not yet: its status decides at once.
        final api = FakeApi(routes: {
          'GET /pay/session': session,
          'GET /pay/sdk-config': FakeAnswer.fixture('sdk-config-cm-stripe.json', delay: const Duration(seconds: 5)),
          'POST /pay/cancel': 'cancel-200.json',
        });
        final checkout = Checkout(async, api);
        expect(checkout.controller.screen, CheckoutScreen.loading);
        checkout.run(checkout.controller.dismiss);
        expect(checkout.result.runtimeType, expected, reason: session);
        expect(api.calls('/pay/cancel'), hasLength(cancels), reason: session);
        checkout.elapse(const Duration(seconds: 6));
      });
    }
    for (final process in ['process-processing-mobile-money-live.json', 'process-requires-otp.json']) {
      virtual((async) {
        // Approval and step screens: no "Cancel payment", a dismiss calls nothing.
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': process,
          'GET /pay/status': 'status-processing.json',
          'POST /pay/cancel': 'cancel-200.json',
        });
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.canCancel, isFalse, reason: process);
        checkout.run(checkout.controller.cancelPayment);
        checkout.run(checkout.controller.dismiss);
        expect(checkout.result, isA<CheckoutProcessing>());
        expect(api.calls('/pay/cancel'), isEmpty);
      });
    }
    virtual((async) {
      // Undecided from the press of Pay until a definitive answer: here a
      // `pending` with a new error_code after it was seen processing. The
      // payment is `pending` again: "Cancel payment" is back, and a dismiss
      // cancels as before any attempt.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-processing-mobile-money-live.json',
        'GET /pay/status': ['status-processing.json', 'status-pending-attempt-refused-live.json'],
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.state, CheckoutState.approvalRequired);
      expect(checkout.controller.canCancel, isFalse);
      checkout.elapse(const Duration(seconds: 6));
      expect(checkout.controller.state, CheckoutState.approvalRequired, reason: 'seen processing');
      checkout.elapse(const Duration(seconds: 5));
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.canCancel, isTrue);
      checkout.controller.tryAgain();
      expect(checkout.controller.canCancel, isTrue);
      checkout.run(checkout.controller.dismiss);
      final result = checkout.result as CheckoutCancelled;
      expect(result.reason, CancelReason.dismissed);
      expect(result.redirectUrl, fixtureBody('cancel-200.json')['redirect_url']);
      expect(api.calls('/pay/cancel'), hasLength(1));
    });
    for (final (name, answer) in [
      ('a 402', FakeAnswer.fixture('process-failed-402.json')),
      ('a step failed for good', FakeAnswer.fixture('process-requires-otp.json')),
    ]) {
      virtual((async) {
        final api = hostedCard(
          process: answer,
          more: {'POST /pay/otp/verify': 'otp-verify-max-attempts.json', 'POST /pay/cancel': 'cancel-200.json'},
        );
        final checkout = payByCard(async, api);
        if (checkout.controller.state == CheckoutState.otpRequired) {
          checkout.elapse(const Duration(seconds: 6));
          expect(checkout.controller.canCancel, isFalse, reason: 'the watch read processing');
          checkout.run(() => checkout.controller.submitStep({'code': '000000'}));
        }
        expect(checkout.controller.state, CheckoutState.failed, reason: name);
        expect(checkout.controller.canCancel, isTrue, reason: name);
        checkout.run(checkout.controller.cancelPayment);
        expect((checkout.result as CheckoutCancelled).reason, CancelReason.payerCancelled, reason: name);
        expect(api.calls('/pay/cancel'), hasLength(1), reason: name);
      });
    }
    virtual((async) {
      // Closing the failure screen of a refused payment also releases the
      // order: the result stays the failure the payer saw, without onCancel.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-failed-402.json',
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      expect(checkout.controller.state, CheckoutState.failed);
      final seen = checkout.controller.error!;
      checkout.run(checkout.controller.dismiss);
      expect(api.calls('/pay/cancel'), hasLength(1));
      final result = checkout.result as CheckoutFailed;
      expect(result.error.code, seen.code);
      expect(checkout.recorder.cancel, isNull);
      expect(checkout.recorder.events, isNot(contains(startsWith('cancel'))));
    });
    virtual((async) {
      // With cancelOnDismiss off, the failure screen closes without a call.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-failed-402.json',
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api, cancelOnDismiss: false);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.run(checkout.controller.dismiss);
      expect(checkout.result, isA<CheckoutFailed>());
      expect(api.calls('/pay/cancel'), isEmpty);
    });
    virtual((async) {
      // A failed payment is not pending any more: nothing to cancel.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-processing-mobile-money-live.json',
        'GET /pay/status': FakeAnswer(200, {
          'transaction': {'reference': 'trx_PVrU8x2kQ1mNa7Lb3cDe', 'status': 'failed'},
        }),
        'POST /pay/cancel': 'cancel-200.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.elapse(const Duration(seconds: 6));
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.canCancel, isFalse);
      checkout.run(checkout.controller.dismiss);
      expect(api.calls('/pay/cancel'), isEmpty);
    });
    virtual((async) {
      // A refused cancel whose status cannot be read: money may move.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/cancel': 'cancel-400-not-cancellable.json',
        'GET /pay/status': const FakeAnswer(200, <String, dynamic>{}),
      });
      final checkout = Checkout(async, api);
      checkout.run(checkout.controller.cancelPayment);
      expect(checkout.result, isA<CheckoutProcessing>());
    });
    virtual((async) {
      // While the cancel runs, nothing else is sent and Close waits for it.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/cancel': FakeAnswer.fixture('cancel-200.json', delay: const Duration(seconds: 3)),
        'POST /pay/process': 'process-processing-mobile-money-live.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.cancelPayment);
      expect(checkout.controller.cancelling, isTrue);
      checkout.run(checkout.controller.payMobileMoney);
      checkout.controller.close();
      checkout.run(checkout.controller.dismiss);
      expect(checkout.result, isNull);
      checkout.elapse(const Duration(seconds: 4));
      expect(api.calls('/pay/process'), isEmpty);
      expect((checkout.result as CheckoutCancelled).reason, CancelReason.payerCancelled);
    });
    virtual((async) {
      // A retried cancel refused because the first try went through.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/cancel': [const FakeAnswer.network(), FakeAnswer.fixture('cancel-400-not-cancellable.json')],
        'GET /pay/status': const FakeAnswer(200, {
          'transaction': {'reference': 'trx_PVrU8x2kQ1mNa7Lb3cDe', 'status': 'cancelled'},
        }),
      });
      final checkout = Checkout(async, api);
      checkout.run(checkout.controller.cancelPayment);
      checkout.elapse(const Duration(seconds: 5));
      expect((checkout.result as CheckoutCancelled).reason, CancelReason.payerCancelled);
      expect(checkout.recorder.errors, isEmpty);
    });
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/cancel': 'cancel-400-not-cancellable.json',
        'GET /pay/status': 'status-succeeded.json',
      });
      final checkout = Checkout(async, api);
      checkout.run(checkout.controller.cancelPayment);
      expect(api.calls('/pay/status'), hasLength(1));
      expect(checkout.controller.state, CheckoutState.success);
      checkout.elapse(const Duration(seconds: 3));
      expect(checkout.result, isA<CheckoutComplete>());
    });
  });

  test('a refusal read while the client session completes waits for /complete, and its success wins', () {
    virtual((async) {
      final api = paystack(
        complete: FakeAnswer.fixture('client-session-complete-200.json', delay: const Duration(seconds: 8)),
      )..on('GET /pay/status', 'status-pending-attempt-refused-live.json');
      final checkout = startClientSession(async, api);
      checkout.controller.onAppPaused();
      checkout.run(checkout.controller.onAppResumed);
      checkout.elapse(const Duration(seconds: 6));
      expect(checkout.controller.state, isNot(CheckoutState.failed), reason: '/complete decides');
      checkout.elapse(const Duration(seconds: 3));
      expect(checkout.controller.state, CheckoutState.success);
      expect(checkout.recorder.errors, isEmpty);
      checkout.end();
    });
  });

  test('two returns while /complete is slow: a refusal read meanwhile waits for the last completion', () {
    virtual((async) {
      final api = paystack(complete: [
        FakeAnswer.fixture('client-session-complete-202.json', delay: const Duration(seconds: 2)),
        FakeAnswer.fixture('client-session-complete-200.json', delay: const Duration(seconds: 20)),
      ])
        ..on('GET /pay/status', ['status-processing.json', 'status-pending-attempt-refused-live.json']);
      final checkout = startClientSession(async, api);
      checkout.controller.onAppPaused();
      checkout.run(checkout.controller.onAppResumed);
      checkout.elapse(const Duration(seconds: 1));
      checkout.controller.onAppPaused();
      checkout.run(checkout.controller.onAppResumed);
      checkout.elapse(const Duration(seconds: 10));
      expect(checkout.controller.state, isNot(CheckoutState.failed), reason: 'the second /complete decides');
      expect(checkout.recorder.errors, isEmpty);
      checkout.elapse(const Duration(seconds: 15));
      expect(checkout.controller.state, CheckoutState.success);
      checkout.end();
    });
  });

  test('a 5xx on a step verify keeps the step and reads the status', () {
    virtual((async) {
      final api = hostedCard(
        process: 'process-requires-otp.json',
        more: {'POST /pay/otp/verify': 'error-500-production.json'},
      );
      final checkout = payByCard(async, api);
      final reads = api.calls('/pay/status').length;
      checkout.run(() => checkout.controller.submitStep({'code': '123456'}));
      expect(checkout.controller.state, CheckoutState.otpRequired);
      expect(checkout.controller.banner, 'Service temporarily unavailable.');
      expect(api.calls('/pay/status').length, greaterThan(reads), reason: 'polled at once');
      checkout.end();
    });
  });

  test('an answer that comes back after the watch decided changes nothing', () {
    virtual((async) {
      // The payer is back from the PSP while the status already says paid.
      final api = paystack(
        complete: FakeAnswer.fixture('client-session-complete-200.json', delay: const Duration(seconds: 3)),
      )..on('GET /pay/status', 'status-succeeded.json');
      final checkout = startClientSession(async, api);
      checkout.elapse(const Duration(seconds: 4));
      checkout.controller.onAppPaused();
      checkout.run(checkout.controller.onAppResumed);
      checkout.elapse(const Duration(seconds: 4));
      expect(checkout.controller.state, CheckoutState.success);
      expect(checkout.recorder.events.where((e) => e.startsWith('success')), hasLength(1));
      checkout.elapse(const Duration(seconds: 3));
      expect(checkout.result, isA<CheckoutComplete>());
    });
    virtual((async) {
      // A step accepted while still processing, after the watch saw it paid.
      final api = hostedCard(
        process: 'process-requires-otp.json',
        status: 'status-succeeded.json',
        more: {
          'POST /pay/otp/verify': FakeAnswer.fixture('otp-verify-success.json', delay: const Duration(seconds: 6)),
        },
      );
      final checkout = payByCard(async, api);
      checkout.run(() => checkout.controller.submitStep({'code': '123456'}));
      checkout.elapse(const Duration(seconds: 7));
      expect(checkout.controller.state, CheckoutState.success);
      expect(checkout.recorder.states.last, CheckoutState.success);
      checkout.elapse(const Duration(seconds: 3));
      expect(checkout.result, isA<CheckoutComplete>());
    });
  });

  test('the step answers are read with their literal JSON shapes', () {
    // A guard for CF-*: the verify bodies the API answered parse as sent.
    expect(jsonEncode(fixtureBody('otp-verify-invalid.json')['error']), contains('invalid_otp'));
  });
}
