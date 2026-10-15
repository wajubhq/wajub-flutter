// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/altcha.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/checkout/present_options.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/payment_result.dart';
import 'package:wajub_mobile/src/realtime/payment_watcher.dart';
import 'package:wajub_mobile/src/realtime/pusher_socket.dart';
import 'package:wajub_mobile/src/widgets/payment_sheet.dart';
import 'package:wajub_mobile/src/widgets/present.dart';

import 'support/fake_api.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';

FakeApi stripeApi() => FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
      'POST /pay/process': 'process-redirect-card-hosted.json',
      'GET /pay/status': 'status-processing.json',
      'POST /pay/cancel': 'cancel-200.json',
    });

FakeApi sandbox(Map<String, Object> more) => FakeApi(routes: {
      'GET /pay/session': 'session-sandbox-cm.json',
      'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      'POST /pay/cancel': 'cancel-200.json',
      ...more,
    });

String sha(String text) => sha256.convert(utf8.encode(text)).toString();

Map<String, dynamic> sessionWithAltcha(String salt, int number) => fixtureBody('session-cm-aggregate.json')
  ..['altcha'] = {
    'algorithm': 'SHA-256',
    'challenge': sha('$salt$number'),
    'salt': salt,
    'signature': 'sig',
    'maxnumber': 100,
  };

/// Presents [controller] over a bare app; returns the host's context.
Future<BuildContext> present(WidgetTester tester, CheckoutController controller) async {
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
    context = c;
    return const Scaffold(body: Text('host'));
  })));
  unawaited(presentCheckout(context, controller));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return context;
}

void main() {
  group('Stripe card (review M2)', () {
    test('a dismiss while Stripe tokenizes resolves processing and sends nothing', () {
      virtual((async) {
        final api = stripeApi();
        final checkout = Checkout(
          async,
          api,
          stripePaymentMethod: (key, holder) => Future<String>.delayed(const Duration(seconds: 2), () => 'pm_test_123'),
        );
        checkout.controller.selectMethod(checkout.method(MethodFamily.card));
        checkout.run(checkout.controller.payCard);
        expect(checkout.controller.state, CheckoutState.processing);
        checkout.elapse(const Duration(seconds: 1));
        checkout.run(checkout.controller.dismiss);
        expect(checkout.result, isA<CheckoutProcessing>());
        checkout.elapse(const Duration(seconds: 5));
        expect(api.calls('/pay/cancel'), isEmpty);
        expect(api.calls('/pay/process'), isEmpty, reason: 'nothing is charged after the sheet closed');
        expect(checkout.recorder.events.where((e) => e.startsWith('success')), isEmpty);
      });
    });

    test('the payment method goes to /pay/process; a plugin failure gives the form back', () {
      virtual((async) {
        final api = stripeApi();
        final checkout = Checkout(async, api, stripePaymentMethod: (key, holder) async {
          expect(key, 'pk_live_51Hx4mPLACEHOLDER');
          return 'pm_test_123';
        });
        checkout.controller.selectMethod(checkout.method(MethodFamily.card));
        checkout.run(checkout.controller.payCard);
        expect((api.bodies('/pay/process').single['data'] as Map)['payment_method_id'], 'pm_test_123');
        checkout.end();
      });
      virtual((async) {
        final checkout = Checkout(
          async,
          stripeApi(),
          locale: 'en',
          stripePaymentMethod: (key, holder) async => throw PlatformException(code: 'not_fragment_activity'),
        );
        checkout.controller.selectMethod(checkout.method(MethodFamily.card));
        checkout.run(checkout.controller.payCard);
        expect(checkout.controller.state, CheckoutState.collectingDetails);
        expect(checkout.controller.busy, isFalse);
        expect(checkout.controller.banner, 'An error occurred. Please try again.');
        checkout.end();
      });
    });
  });

  group('outcomes are read fail-safe (review M3)', () {
    test('a status answer without a status keeps the watch going', () {
      for (final empty in [const FakeAnswer(200, <String, dynamic>{}), const FakeAnswer(200, '')]) {
        virtual((async) {
          final api = FakeApi(routes: {
            'GET /pay/status': [empty, empty, FakeAnswer.fixture('status-succeeded.json')],
          });
          final decisions = <WatchDecision>[];
          PaymentWatcher(client: api.payClient(), token: 'tok_test', seenProcessing: true, onDecision: decisions.add)
              .start(pollNow: true);
          async.elapse(const Duration(seconds: 6));
          expect(decisions, isEmpty, reason: 'no status, no refusal');
          async.elapse(const Duration(seconds: 5));
          expect(decisions.single.verdict, WatchVerdict.success);
        });
      }
      expect(PaymentStatusUpdate.fromJson(const {}).status, isNull);
      expect(decideStatus(PaymentStatusUpdate.fromJson(const {}), seenProcessing: true), isNull);
    });

    test('a realtime frame without a status decides nothing', () {
      virtual((async) {
        final session = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
        final endpoint = RealtimeEndpoint.resolve(session, const RealtimeOptions())!;
        final sockets = FakeRealtime();
        final decisions = <WatchDecision>[];
        final watcher = PaymentWatcher(
          client: FakeApi(routes: {
            'GET /pay/status': 'status-processing.json',
            'POST /pay/broadcasting/auth': 'broadcasting-auth-200.json',
          }).payClient(),
          token: 'tok_test',
          realtime: endpoint,
          connector: sockets.connect,
          seenProcessing: true,
          onDecision: decisions.add,
        )..start();
        async.flushMicrotasks();
        sockets.sockets.single.receive('PaymentStatusUpdated', {'reference': 'trx_x'}, channel: endpoint.channel);
        async.flushMicrotasks();
        expect(decisions, isEmpty);
        watcher.stop();
      });
    });

    test('a 2xx /pay/process without its transaction is followed as pending', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': const FakeAnswer(202, {'code': 202, 'status': 'Accepted', 'message': 'ok'}),
          'GET /pay/status': ['status-processing.json', 'status-succeeded.json'],
        });
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.state, CheckoutState.pending);
        expect(checkout.recorder.errors, isEmpty);
        expect(api.calls('/pay/status'), hasLength(1), reason: 'read at once');
        checkout.elapse(const Duration(seconds: 6));
        expect(checkout.controller.state, CheckoutState.success);
        checkout.end();
      });
    });
  });

  group('1.5 behaviour kept for the legacy entry points (review M4)', () {
    testWidgets('PaymentSheet.onPaymentStarted fires when the payer submits', (tester) async {
      final api = sandbox({'POST /pay/process': const FakeAnswer.hang()});
      var started = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaymentSheet(
              session: api.session(),
              onDismiss: () {},
              onResult: (_) {},
              locale: 'en',
              onPaymentStarted: () => started++,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('wajub-method-mobile_money')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const ValueKey('wajub-phone-field')), '670000000');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wajub-pay-button')));
      await tester.pump();
      expect(started, 1, reason: 'before any answer');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
    });

    test('watchStatus keeps the 1.5 codes and watches without a cap', () {
      for (final status in ['failed', 'cancelled', 'expired']) {
        virtual((async) {
          final api = FakeApi(routes: {
            'GET /pay/session': 'session-processing-mobile-money.json',
            'GET /pay/status': FakeAnswer(200, {
              'transaction': {'reference': 'trx_test_PVrU8x2kQ1mNa7Lb3cDe', 'status': status},
            }),
          });
          final results = <PaymentResult>[];
          api.session().watchStatus().listen(results.add);
          async.elapse(const Duration(seconds: 1));
          final failed = results.last as PaymentFailed;
          expect(failed.error.code, status);
          expect(failed.error.message, status);
        });
      }
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-processing-mobile-money.json',
          'GET /pay/status': 'status-processing.json',
        });
        final sub = api.session().watchStatus().listen((_) {});
        async.elapse(const Duration(minutes: 20));
        final reads = api.calls('/pay/status').length;
        async.elapse(const Duration(minutes: 1));
        expect(api.calls('/pay/status').length, greaterThan(reads), reason: 'still watching after 15 minutes');
        sub.cancel();
      });
    });

    test('WajubSession.process keeps confirm_* as unsupported_action; processPayment reads the step', () async {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'POST /pay/process': 'process-requires-otp.json',
      });
      final session = api.session();
      final legacy = await session.process('card', const {});
      expect((legacy as PaymentFailed).error.code, 'unsupported_action');
      final step = await session.processPayment('card', const {}) as PaymentRequiresAction;
      expect(
          (step.action, step.step, step.stepId), (ActionKind.confirm, PaymentStepKind.otp, 'prc_7hQm2LxV9pR4sT1wYb3N'));
    });

    testWidgets('showWajubPaymentSheet reports a payment that cannot load with onCancel, as 1.5 did', (tester) async {
      final api = FakeApi(routes: {
        'GET /pay/session': 'error-401-invalid-token.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
      });
      final results = <PaymentResult>[];
      var cancelled = 0;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showWajubPaymentSheet(
            context: context,
            session: api.session(),
            onResult: results.add,
            onCancel: () => cancelled++,
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('wajub-dismiss')));
      await tester.pump(const Duration(seconds: 1));
      expect(results, isEmpty);
      expect(cancelled, 1);
    });
  });

  group('closing the sheet (review m1, m4, m5)', () {
    testWidgets('a host pop never cancels; the payer\'s swipe and back do', (tester) async {
      final api = sandbox({});
      final controller = checkoutController(api);
      CheckoutResult? result;
      unawaited(controller.result.then((r) => result = r));
      final host = await present(tester, controller);
      Navigator.of(host).popUntil((route) => route.isFirst);
      await tester.pump(const Duration(seconds: 1));
      expect((result! as CheckoutCancelled).reason, CancelReason.hostGone);
      expect(api.calls('/pay/cancel'), isEmpty);

      for (final gesture in ['swipe', 'back']) {
        final calls = sandbox({});
        final next = checkoutController(calls);
        CheckoutResult? closed;
        unawaited(next.result.then((r) => closed = r));
        await present(tester, next);
        if (gesture == 'swipe') {
          await tester.flingFrom(
            tester.getCenter(find.byKey(const ValueKey('wajub-drag-handle'))),
            const Offset(0, 600),
            2000,
          );
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pump(const Duration(seconds: 1));
        expect((closed! as CheckoutCancelled).reason, CancelReason.dismissed, reason: gesture);
        expect(calls.calls('/pay/cancel'), hasLength(1), reason: gesture);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a new sheet can open while the last one\'s cancel still runs', (tester) async {
      final slow =
          sandbox({'POST /pay/cancel': FakeAnswer.fixture('cancel-200.json', delay: const Duration(seconds: 5))});
      final first = checkoutController(slow);
      final host = await present(tester, first);
      await tester.tap(find.byKey(const ValueKey('wajub-dismiss')));
      await tester.pump(const Duration(milliseconds: 500));
      final second = checkoutController(sandbox({}));
      CheckoutResult? result;
      Object? error;
      presentCheckout(host, second).then((r) => result = r, onError: (Object e) {
        error = e;
        return const CheckoutCancelled(reason: CancelReason.hostGone);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(error, isNull);
      expect(find.byKey(const ValueKey('wajub-method-mobile_money')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(result, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the success screen closes even under a page the host pushed', (tester) async {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-succeeded-200.json',
      });
      late BuildContext host;
      final controller = checkoutController(
        api,
        options: PresentOptions(
          sessionToken: 'tok_test',
          callbacks: CheckoutCallbacks(
            onSuccess: (_) => Navigator.of(host).push(MaterialPageRoute<void>(builder: (_) => const Text('receipt'))),
          ),
        ),
      );
      CheckoutResult? result;
      unawaited(controller.result.then((r) => result = r));
      host = await present(tester, controller);
      controller.selectMethod(controller.methods.firstWhere((m) => m.family == MethodFamily.mobileMoney));
      controller.setPhone('677123457');
      controller.pickOperator('mtn');
      unawaited(controller.payMobileMoney());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('receipt'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(result, isA<CheckoutComplete>());
      Navigator.of(host).pop();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BottomSheet), findsNothing, reason: 'the sheet route was removed');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('payments under way (review m2, m3, m6, m7, m8, m9)', () {
    test('no charge leaves after the sheet closed while Altcha was solving', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': FakeAnswer(200, sessionWithAltcha('s1', 7)),
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': 'process-processing-mobile-money-live.json',
        });
        final checkout = Checkout(
          async,
          api,
          altchaSolver: (c) => Future<int?>.delayed(const Duration(seconds: 3), () => solveAltcha(c)),
        );
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        checkout.run(checkout.controller.dismiss);
        checkout.elapse(const Duration(seconds: 5));
        expect(api.calls('/pay/process'), isEmpty);
        expect(api.calls('/pay/cancel'), isEmpty);
      });
    });

    test('each attempt sends the solution of a new challenge', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': [
            FakeAnswer(200, sessionWithAltcha('s1', 7)),
            FakeAnswer(200, sessionWithAltcha('s2', 42))
          ],
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': ['process-failed-402.json', 'process-processing-mobile-money-live.json'],
          'GET /pay/status': 'status-processing.json',
        });
        final checkout = Checkout(async, api, altchaSolver: (c) async => solveAltcha(c));
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        checkout.controller.tryAgain();
        checkout.run(checkout.controller.payMobileMoney);
        final numbers = [
          for (final body in api.bodies('/pay/process')) ((body['data'] as Map)['altcha'] as Map)['number'],
        ];
        expect(numbers, [7, 42]);
        checkout.end();
      });
    });

    test('no payment leaves without a solution: a new challenge that cannot be fetched is a connection error', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': [FakeAnswer(200, sessionWithAltcha('s1', 7)), const FakeAnswer.network()],
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': 'process-failed-402.json',
        });
        final checkout = Checkout(async, api, altchaSolver: (c) async => solveAltcha(c));
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        checkout.controller.tryAgain();
        checkout.run(checkout.controller.payMobileMoney);
        checkout.elapse(const Duration(seconds: 30));
        expect(api.calls('/pay/process'), hasLength(1), reason: 'the used solution is never sent again');
        expect(checkout.controller.error?.code, 'network_error');
        expect(checkout.controller.error?.retryable, isTrue);
        checkout.end();
      });
    });

    test('a 400 re-read: processing is watched, and a dismiss meanwhile never cancels', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': 'process-400-not-processable.json',
          'GET /pay/status': 'status-processing.json',
        });
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.state, CheckoutState.pending);
        checkout.end();
      });
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': 'process-400-not-processable.json',
          'GET /pay/status': FakeAnswer.fixture('status-succeeded.json', delay: const Duration(seconds: 2)),
          'POST /pay/cancel': 'cancel-200.json',
        });
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        checkout.elapse(const Duration(seconds: 1));
        checkout.run(checkout.controller.dismiss);
        checkout.elapse(const Duration(seconds: 3));
        expect(checkout.result, isA<CheckoutProcessing>());
        expect(api.calls('/pay/cancel'), isEmpty);
      });
    });

    test('a failure forgets the page "Continue payment" reopened', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-card-mollie.json',
          'POST /pay/process': 'process-redirect-card-hosted.json',
          'GET /pay/status': FakeAnswer(200, {
            'transaction': {'reference': 'trx_HostedCard0000000000', 'status': 'failed'},
          }),
        });
        final checkout = Checkout(async, api);
        checkout.controller.selectMethod(checkout.method(MethodFamily.card));
        checkout.run(checkout.controller.payCard);
        expect(checkout.controller.continueUrl, isNotNull);
        checkout.elapse(const Duration(seconds: 6));
        expect(checkout.controller.state, CheckoutState.failed);
        expect(checkout.controller.continueUrl, isNull);
        checkout.end();
      });
    });

    test('every return from the browser completes an open client session', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-card-paystack.json',
          'POST /pay/client-session': 'client-session-start-202.json',
          'POST /pay/client-session/complete': 'client-session-complete-202.json',
          'GET /pay/status': 'status-processing.json',
        });
        final checkout = Checkout(async, api);
        checkout.controller.selectMethod(checkout.method(MethodFamily.card));
        checkout.run(checkout.controller.payCard);
        for (var i = 1; i <= 2; i++) {
          checkout.controller.onAppPaused();
          checkout.run(checkout.controller.onAppResumed);
          expect(api.calls('/pay/client-session/complete'), hasLength(i));
        }
        checkout.run(checkout.controller.onAppResumed);
        expect(api.calls('/pay/client-session/complete'), hasLength(2), reason: 'not without leaving the app');
        checkout.end();
      });
    });

    test('onLoadError fires once per load', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': FakeAnswer.fixture('error-401-invalid-token.json', delay: const Duration(seconds: 20)),
          'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        });
        final checkout = Checkout(async, api);
        checkout.elapse(const Duration(seconds: 25));
        expect(checkout.recorder.events.where((e) => e.startsWith('loadError')), ['loadError:ready_timeout']);
        expect(checkout.controller.error?.code, 'session_not_found', reason: 'the view shows what the load found');
        checkout.end();
      });
    });
  });

  group('re-validation of 1.6.0 (N1-N5)', () {
    FakeAnswer statusOf(String status) => FakeAnswer(200, {
          'transaction': {'reference': 'trx_PVrU8x2kQ1mNa7Lb3cDe', 'status': status},
        });

    test('N1 a refused cancel settles even when the sheet went away while it ran', () {
      for (final (status, expected) in [
        ('expired', CheckoutFailed),
        ('failed', CheckoutFailed),
        ('pending', CheckoutFailed),
        ('succeeded', CheckoutComplete),
        ('processing', CheckoutProcessing),
      ]) {
        for (final away in ['host', 'payer']) {
          virtual((async) {
            final api = FakeApi(routes: {
              'GET /pay/session': 'session-cm-aggregate.json',
              'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
              'POST /pay/cancel':
                  FakeAnswer.fixture('cancel-400-not-cancellable.json', delay: const Duration(seconds: 3)),
              'GET /pay/status': statusOf(status),
            });
            final checkout = Checkout(async, api, autoCloseSuccess: Duration.zero);
            checkout.run(checkout.controller.cancelPayment);
            if (away == 'host') {
              checkout.controller.hostGone();
            } else {
              checkout.run(checkout.controller.dismiss);
            }
            expect(checkout.result, isNull, reason: 'the cancel decides');
            checkout.elapse(const Duration(seconds: 5));
            expect(checkout.result.runtimeType, expected, reason: '$status, $away');
            expect(checkout.recorder.completions, 1);
            expect(api.calls('/pay/cancel'), hasLength(1));
          });
        }
      }
    });

    testWidgets('N1 a swipe waits for a running cancel, as Close and back do', (tester) async {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-sandbox-cm.json',
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'POST /pay/cancel': FakeAnswer.fixture('cancel-400-not-cancellable.json', delay: const Duration(seconds: 3)),
        'GET /pay/status': statusOf('expired'),
      });
      final controller = checkoutController(api);
      CheckoutResult? result;
      unawaited(controller.result.then((r) => result = r));
      await present(tester, controller);
      expect(controller.canCancel, isTrue);
      unawaited(controller.cancelPayment());
      await tester.pump();
      await tester.flingFrom(
          tester.getCenter(find.byKey(const ValueKey('wajub-drag-handle'))), const Offset(0, 600), 2000);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'the swipe waits for the cancel');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state, CheckoutState.expired);
      expect(result, isNull, reason: 'the payer reads the outcome');
      final close = find.byKey(const ValueKey('wajub-close'));
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(result, isA<CheckoutFailed>());
      expect(find.byType(BottomSheet), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test('N3 the failure screen\'s Close releases a refused payment, as a dismiss does', () {
      for (final cancelOnDismiss in [true, false]) {
        virtual((async) {
          final api = FakeApi(routes: {
            'GET /pay/session': 'session-cm-aggregate.json',
            'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
            'POST /pay/process': 'process-failed-402.json',
            'POST /pay/cancel': 'cancel-200.json',
          });
          final checkout = Checkout(async, api, cancelOnDismiss: cancelOnDismiss);
          checkout.mobileMoney('677123456', pick: 'mtn');
          checkout.run(checkout.controller.payMobileMoney);
          expect(checkout.controller.state, CheckoutState.failed);
          checkout.controller.close();
          checkout.elapse(const Duration(seconds: 1));
          expect(api.calls('/pay/cancel'), hasLength(cancelOnDismiss ? 1 : 0));
          expect((checkout.result as CheckoutFailed).error.code, 'insufficient_funds');
          expect(checkout.recorder.cancel, isNull);
        });
      }
    });

    test('N4 an accepted attempt is never cancelled before a definitive answer', () {
      virtual((async) {
        // A 202 with an action the SDK cannot follow and no transaction.
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': const FakeAnswer(202, {'code': 202, 'status': 'Accepted', 'action': 'card_reauth'}),
          'POST /pay/cancel': 'cancel-200.json',
        });
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.state, CheckoutState.failed);
        expect(checkout.controller.error?.code, 'unsupported_action');
        expect(checkout.recorder.started, isNotNull);
        expect(checkout.controller.canCancel, isFalse);
        checkout.run(checkout.controller.dismiss);
        expect(api.calls('/pay/cancel'), isEmpty);
        expect(checkout.result, isA<CheckoutFailed>());
      });
      // A transaction without a status is not a pending one.
      final transaction = SessionTransaction.fromJson({'id': 'trx_1', 'amount': 5000, 'currency': 'XAF'});
      expect(transaction.status, 'unknown');
    });

    test('N5 a refusal code the payment carried when the sheet opened is not this attempt\'s', () {
      virtual((async) {
        final session = fixtureBody('session-cm-aggregate.json');
        (session['transaction'] as Map)['error_code'] = 'insufficient_funds';
        final api = FakeApi(routes: {
          'GET /pay/session': FakeAnswer(200, session),
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': const FakeAnswer.network(),
          'GET /pay/status': 'status-pending-attempt-refused-live.json',
        });
        final checkout = Checkout(async, api);
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        checkout.elapse(const Duration(seconds: 30));
        expect(checkout.controller.state, CheckoutState.pending, reason: 'not read as a refusal of this Pay');
        checkout.elapse(const Duration(seconds: 40));
        expect(checkout.controller.state, CheckoutState.collectingDetails, reason: 'it never arrived');
        checkout.end();
      });
    });

    test('an unanswered client session counts its 60 s from its own send', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': 'session-cm-aggregate.json',
          'GET /pay/sdk-config': 'sdk-config-card-paystack.json',
          'POST /pay/process': 'process-failed-402.json',
          'POST /pay/client-session': const FakeAnswer.network(),
          'GET /pay/status': statusOf('pending'),
        });
        final checkout = Checkout(async, api, locale: 'en');
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.error?.code, 'insufficient_funds');
        checkout.controller.tryAgain();
        checkout.elapse(const Duration(minutes: 5));
        checkout.controller.selectMethod(checkout.method(MethodFamily.card));
        checkout.run(checkout.controller.payCard);
        checkout.elapse(const Duration(seconds: 20));
        expect(checkout.controller.state, CheckoutState.pending,
            reason: 'the /pay/process of 5 minutes ago says nothing');
        checkout.elapse(const Duration(seconds: 50));
        expect(checkout.controller.state, CheckoutState.collectingDetails);
        checkout.end();
      });
    });

    test('an unsolved challenge makes the next Pay fetch a new one', () {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': [
            FakeAnswer(200, sessionWithAltcha('s1', 7)),
            FakeAnswer(200, sessionWithAltcha('s2', 42)),
          ],
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': 'process-processing-mobile-money-live.json',
          'GET /pay/status': 'status-processing.json',
        });
        var tries = 0;
        final checkout = Checkout(async, api, altchaSolver: (c) async => tries++ == 0 ? null : solveAltcha(c));
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(checkout.controller.error?.code, 'security_check_failed');
        expect(api.calls('/pay/process'), isEmpty);
        checkout.controller.tryAgain();
        checkout.run(checkout.controller.payMobileMoney);
        expect(api.calls('/pay/session'), hasLength(2));
        expect(((api.bodies('/pay/process').single['data'] as Map)['altcha'] as Map)['number'], 42);
        checkout.end();
      });
    });

    test('the app\'s own Stripe key comes back when the sheet closes after its card form', () {
      for (final (appKey, paid, restored) in [
        ('pk_live_app', true, ['pk_live_app']),
        (null, true, <String>[]),
        ('pk_live_app', false, <String>[]),
      ]) {
        virtual((async) {
          final calls = <String>[];
          final checkout = Checkout(
            async,
            stripeApi(),
            stripe: StripeOptions(appPublishableKey: appKey),
            stripePaymentMethod: (key, holder) async => 'pm_test_123',
            restoreStripeKey: (key) async => calls.add(key),
          );
          if (paid) {
            checkout.controller.selectMethod(checkout.method(MethodFamily.card));
            checkout.run(checkout.controller.payCard);
          }
          checkout.run(checkout.controller.dismiss);
          expect(checkout.result, isNotNull);
          expect(calls, restored, reason: '$appKey $paid');
        });
      }
    });

    test('processPayment returns every answer as an outcome', () {
      for (final (answer, expected) in [
        (const FakeAnswer.network(), PaymentProcessing),
        (FakeAnswer.fixture('error-500-production.json'), PaymentProcessing),
        (FakeAnswer.fixture('process-409-payment-in-progress.json'), PaymentProcessing),
        (FakeAnswer.fixture('process-failed-402.json'), PaymentFailed),
      ]) {
        virtual((async) {
          final api = FakeApi(routes: {'GET /pay/session': 'session-cm-aggregate.json', 'POST /pay/process': answer});
          PaymentResult? result;
          api.session().processPayment('cm.mobile', {'phone': '+237677123456'}).then((r) => result = r);
          async.elapse(const Duration(minutes: 5));
          expect(result.runtimeType, expected, reason: '${answer.status}');
          if (result case PaymentProcessing(:final transaction, :final kind)) {
            expect(kind, ProcessingKind.pending);
            expect(transaction.reference, isNotEmpty);
          }
          if (result case PaymentFailed(:final error)) expect(error.code, 'insufficient_funds');
        });
      }
    });

    test('the 1.x sheet reports a payment still running with the last transaction known', () {
      virtual((async) {
        final checkout = Checkout(
            async,
            FakeApi(routes: {
              'GET /pay/session': 'session-cm-aggregate.json',
              'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
            }));
        final legacy = legacyResult(const CheckoutProcessing(), checkout.controller);
        expect((legacy! as PaymentProcessing).transaction.reference,
            checkout.controller.sessionData!.transaction.reference);
        checkout.end();
      });
    });

    testWidgets('the 1.x entry point stacks over an open sheet instead of throwing', (tester) async {
      final first = checkoutController(sandbox(const {}));
      final context = await present(tester, first);
      var cancelled = 0;
      Object? thrown;
      unawaited(showWajubPaymentSheet(
        context: context,
        session: sandbox(const {}).session(),
        onResult: (_) {},
        onCancel: () => cancelled++,
      ).catchError((Object e) => thrown = e));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(thrown, isNull);
      expect(find.byType(BottomSheet), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(cancelled, 1, reason: 'reported through its callbacks');
    });
  });
}
