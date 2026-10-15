import 'dart:math';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/realtime/payment_watcher.dart';
import 'package:wajub_mobile/src/realtime/pusher_socket.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

/// A watcher on [api]'s `/pay/status`, recording its decision.
class Watch {
  Watch(this.async, this.api, {RealtimeEndpoint? realtime, FakeRealtime? sockets, bool seenProcessing = true}) {
    watcher = PaymentWatcher(
      client: api.payClient(),
      token: 'tok_test',
      realtime: realtime,
      connector: (sockets ?? FakeRealtime(refuse: true)).connect,
      seenProcessing: seenProcessing,
      random: Random(1),
      onDecision: decisions.add,
    );
  }

  final FakeAsync async;
  final FakeApi api;
  late final PaymentWatcher watcher;
  final decisions = <WatchDecision>[];

  /// Seconds between the status reads so far.
  List<double> gaps() {
    final times = [fixtureTime, ...api.times];
    return [
      for (var i = 1; i < times.length; i++) times[i].difference(times[i - 1]).inMilliseconds / 1000,
    ];
  }
}

void main() {
  test('WT-01 polls on schedule', () {
    for (final jump in [const Duration(hours: 3), const Duration(days: -1)]) {
      // The slow-down counts the device's monotonic time: the wall clock
      // jumping forward or back changes nothing.
      virtual((async) {
        final api = FakeApi(routes: {'GET /pay/status': 'status-processing.json'});
        final client = api.payClient();
        final virtualClock = clock;
        var offset = Duration.zero;
        withClock(Clock(() => virtualClock.now().add(offset)), () {
          PaymentWatcher(client: client, token: 'tok_test', seenProcessing: true, onDecision: (_) {}).start();
        });
        async.elapse(const Duration(seconds: 6));
        offset = jump;
        async.elapse(const Duration(seconds: 60));
        expect(api.calls('/pay/status'), hasLength(13), reason: 'every 5 s still ($jump)');
        async.elapse(const Duration(minutes: 3));
        expect(api.calls('/pay/status').length, lessThan(13 + 36), reason: 'slower after 2 minutes ($jump)');
        async.elapse(const Duration(hours: 1));
      });
    }
    virtual((async) {
      final watch = Watch(async, FakeApi(routes: {'GET /pay/status': 'status-processing.json'}))..watcher.start();
      async.elapse(const Duration(minutes: 2));
      expect(watch.gaps(), everyElement(5.0), reason: 'every 5 s for two minutes');
      expect(watch.api.times, hasLength(24));
      async.elapse(const Duration(minutes: 1));
      final slower = watch.gaps().skip(24).toList();
      expect(slower.take(3), [7.5, 11.25, 15.0], reason: '×1.5 per poll after 2 minutes without a change');
      expect(slower.skip(3), everyElement(15.0), reason: 'up to 15 s');
      watch.watcher.stop();
    });

    virtual((async) {
      // Errors back off: min(5 s × 2^n, 60 s) ± 20 %, n the consecutive failures.
      final api = FakeApi(routes: {
        'GET /pay/status': [
          for (var i = 0; i < 5; i++) const FakeAnswer(501, {'code': 501, 'status': 'Not Implemented'}),
          FakeAnswer.fixture('status-processing.json'),
        ],
      });
      final watch = Watch(async, api)..watcher.start();
      async.elapse(const Duration(minutes: 4));
      final gaps = watch.gaps();
      expect(gaps.first, 5.0);
      for (final (i, base) in [10, 20, 40, 60, 60].indexed) {
        expect(gaps[i + 1], inInclusiveRange(base * 0.8, base * 1.2), reason: 'failure ${i + 1}');
      }
      // A success resets the backoff; three minutes without a status change
      // put the schedule on its slower pace (5 s × 1.5).
      expect(gaps[6], 7.5, reason: 'reset on success');
      watch.watcher.stop();
    });

    virtual((async) {
      // 15 s while the socket is joined.
      final sockets = FakeRealtime();
      final session = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
      final watch = Watch(
        async,
        FakeApi(routes: {
          'GET /pay/status': 'status-processing.json',
          'POST /pay/broadcasting/auth': 'broadcasting-auth-200.json'
        }),
        realtime: RealtimeEndpoint.resolve(session),
        sockets: sockets,
      )..watcher.start();
      async.flushMicrotasks();
      final socket = sockets.sockets.single;
      socket.receive('pusher:connection_established', {'socket_id': '123456.7890123', 'activity_timeout': 120});
      async.flushMicrotasks();
      socket.receive('pusher_internal:subscription_succeeded', {}, channel: 'private-payment.trx_PVrU8x2kQ1mNa7Lb3cDe');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 61));
      expect(watch.api.calls('/pay/status').length, 4);
      final reads = watch.gaps().where((gap) => gap > 1).toList();
      expect(reads.first, 5.0, reason: 'the read planned before the socket joined');
      expect(reads.skip(1), everyElement(15.0));
      watch.watcher.stop();
    });

    virtual((async) {
      // The cap is 15 minutes of the device's own time: an `expires_at` the
      // device clock reads as near, or past, never ends the watch early.
      final session = fixtureBody('session-processing-mobile-money.json');
      (session['transaction'] as Map)['expires_at'] = '2026-10-14T09:00:30+00:00';
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer(200, session),
        'GET /pay/sdk-config': 'sdk-config-sandbox.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      expect(checkout.controller.state, CheckoutState.approvalRequired);
      async.elapse(const Duration(minutes: 5));
      expect(checkout.controller.capped, isFalse);
      async.elapse(const Duration(minutes: 11));
      expect(checkout.controller.capped, isTrue);
      checkout.end();
    });

    virtual((async) {
      // Counted from the press of Pay, not from the answer.
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process':
            FakeAnswer.fixture('process-processing-mobile-money-live.json', delay: const Duration(seconds: 50)),
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      async.elapse(const Duration(seconds: 51));
      expect(checkout.controller.state, CheckoutState.approvalRequired);
      async.elapse(const Duration(minutes: 14, seconds: 8));
      expect(checkout.controller.capped, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(checkout.controller.capped, isTrue, reason: '15 minutes after Pay');
      checkout.end();
    });

    virtual((async) {
      // The 15-minute cap: still processing → "you will be notified".
      final watch = Watch(async, FakeApi(routes: {'GET /pay/status': 'status-processing.json'}))..watcher.start();
      async.elapse(const Duration(minutes: 15));
      expect(watch.decisions.single.verdict, WatchVerdict.capped);
      final reads = watch.api.times.length;
      async.elapse(const Duration(minutes: 1));
      expect(watch.api.times, hasLength(reads), reason: 'stopped');
    });
  });

  test('WT-02 decides on status', () {
    PaymentStatusUpdate status(String name) => PaymentStatusUpdate.fromJson(fixtureBody(name));

    expect(decideStatus(status('status-succeeded.json'), seenProcessing: false)?.verdict, WatchVerdict.success);
    expect(decideStatus(status('status-processing.json'), seenProcessing: true), isNull);
    for (final name in ['status-pending-attempt-refused.json', 'status-pending-attempt-refused-live.json']) {
      expect(decideStatus(status(name), seenProcessing: false), isNull, reason: 'a leftover of a previous attempt');
      final refused = decideStatus(status(name), seenProcessing: true)!;
      expect(refused.verdict, WatchVerdict.failed);
      expect(refused.error?.code, 'insufficient_funds');
      expect(refused.error?.declineCode, 'insufficient_funds');
      expect(refused.error?.retryable, isTrue);
    }
    final ended = decideStatus(const PaymentStatusUpdate(status: 'pending'), seenProcessing: true)!;
    expect(ended.error?.code, 'payment_attempt_ended');
    expect(ended.error?.retryable, isTrue);
    for (final (value, verdict, code, retryable) in [
      ('failed', WatchVerdict.failed, 'payment_failed', false),
      ('cancelled', WatchVerdict.cancelled, 'payment_cancelled', false),
      ('expired', WatchVerdict.expired, 'session_expired', false),
      ('refunded', WatchVerdict.success, null, null),
      ('partially_refunded', WatchVerdict.success, null, null),
    ]) {
      final decision = decideStatus(PaymentStatusUpdate(status: value), seenProcessing: true)!;
      expect(decision.verdict, verdict, reason: value);
      expect(decision.error?.code, code);
      expect(decision.error?.retryable, retryable);
    }
    expect(decideStatus(const PaymentStatusUpdate(status: 'partial'), seenProcessing: true), isNull);

    for (final (name, verdict, code) in [
      ('error-410-session-terminal-expired.json', WatchVerdict.expired, 'session_terminal_expired'),
      ('error-401-invalid-token.json', WatchVerdict.failed, 'session_not_found'),
      ('error-403-not-a-payment-session.json', WatchVerdict.failed, 'session_not_found'),
    ]) {
      virtual((async) {
        final watch = Watch(async, FakeApi(routes: {'GET /pay/status': name}))..watcher.start(pollNow: true);
        async.flushMicrotasks();
        expect(watch.decisions.single.verdict, verdict, reason: name);
        expect(watch.decisions.single.error?.code, code);
        expect(watch.api.times, hasLength(1), reason: 'not retried');
      });
    }

    virtual((async) {
      // A dead session decides on its HTTP status, whatever code it carries.
      final api = FakeApi(routes: {
        'GET /pay/status': const FakeAnswer(404, {'code': 404, 'error_code': 'transaction_not_found'}),
      });
      final watch = Watch(async, api)..watcher.start(pollNow: true);
      async.flushMicrotasks();
      expect(watch.decisions.single.error?.code, 'session_not_found');
    });

    virtual((async) {
      // Seen processing by a poll: a later pending is the attempt's end.
      final api = FakeApi(routes: {
        'GET /pay/status': ['status-processing.json', 'status-pending-attempt-refused.json'],
      });
      final watch = Watch(async, api, seenProcessing: false)..watcher.start();
      async.elapse(const Duration(seconds: 10));
      expect(watch.decisions.single.error?.code, 'insufficient_funds');
    });
  });

  test('WT-03 subscribes to the payment channel', () {
    final reverb = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
    final endpoint = RealtimeEndpoint.resolve(reverb)!;
    expect(endpoint.uri.toString(),
        'wss://ws.wajub.com:443/app/wajub-app-key?protocol=7&client=wajub-flutter&version=1.6.0&flash=false');
    expect(endpoint.channel, 'private-payment.trx_PVrU8x2kQ1mNa7Lb3cDe');

    final pusher = SessionData.fromJson(fixtureBody('session-ci-xof-wallets.json'));
    final hosted = RealtimeEndpoint.resolve(pusher)!;
    expect((hosted.host, hosted.port, hosted.tls, hosted.key), ('ws-eu.pusher.com', 443, true, 'pusher-app-key'));

    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/status': 'status-processing.json',
        'POST /pay/broadcasting/auth': 'broadcasting-auth-200.json',
      });
      final sockets = FakeRealtime();
      final watch = Watch(async, api, realtime: endpoint, sockets: sockets)..watcher.start();
      async.flushMicrotasks();
      expect(sockets.uris.single, endpoint.uri);
      final socket = sockets.sockets.single;

      socket.receive('pusher:connection_established', {'socket_id': '123456.7890123', 'activity_timeout': 120});
      async.flushMicrotasks();
      final auth = api.calls('/pay/broadcasting/auth').single;
      expect(auth.headers['Authorization'], 'Bearer tok_test');
      expect(api.bodies('/pay/broadcasting/auth').single, fixtureRequestBody('broadcasting-auth-200.json'));
      expect(socket.sent.last, {
        'event': 'pusher:subscribe',
        'data': {'channel': 'private-payment.trx_PVrU8x2kQ1mNa7Lb3cDe', 'auth': 'wajub-app-key:SIGNATURE'},
      });

      socket.receive('pusher:ping', {});
      async.flushMicrotasks();
      expect(socket.sent.last['event'], 'pusher:pong');

      final event = fixture('realtime-payment-status-updated-succeeded.json');
      socket.receive(event['event'] as String, Map<String, dynamic>.from(event['data'] as Map),
          channel: endpoint.channel);
      async.flushMicrotasks();
      expect(watch.decisions.single.verdict, WatchVerdict.success);
      expect(socket.closed, isTrue, reason: 'disconnected once the watch ends');
    });
  });

  test('WT-04 falls back to polling', () {
    // 2.1: no key, no `echo` at all.
    final sandbox = SessionData.fromJson(fixtureBody('session-sandbox-cm.json'));
    expect(sandbox.echoSettings, isNull);
    expect(RealtimeEndpoint.resolve(sandbox), isNull, reason: 'echo absent');
    // 2.0: `echo` with `key: null`.
    final keyless = SessionData.fromJson(fixtureBody('session-processing-mobile-money.json'));
    expect(keyless.echoSettings, isNotNull);
    expect(RealtimeEndpoint.resolve(keyless), isNull, reason: 'key: null');
    final reverb = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));

    virtual((async) {
      // An unreachable host: the polling carries the watch every 5 s.
      final api = FakeApi(routes: {'GET /pay/status': 'status-processing.json'});
      final watch = Watch(
        async,
        api,
        realtime: RealtimeEndpoint.resolve(reverb),
        sockets: FakeRealtime(refuse: true),
      )..watcher.start();
      async.elapse(const Duration(seconds: 30));
      expect(watch.gaps(), everyElement(5.0));
      expect(watch.api.times, hasLength(6));
      watch.watcher.stop();
    });
  });

  test('WT-05 decides on realtime events', () {
    final expected = {
      'realtime-payment-status-updated-succeeded.json': WatchVerdict.success,
      'realtime-payment-status-updated-failed.json': WatchVerdict.failed,
      'realtime-payment-status-updated-refused.json': WatchVerdict.failed,
      'realtime-payment-status-updated-processing.json': null,
    };
    final session = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
    final endpoint = RealtimeEndpoint.resolve(session)!;
    expected.forEach((name, verdict) {
      for (final rawData in [false, true]) {
        virtual((async) {
          final api = FakeApi(routes: {
            'GET /pay/status': 'status-processing.json',
            'POST /pay/broadcasting/auth': 'broadcasting-auth-200.json',
          });
          final sockets = FakeRealtime();
          final watch = Watch(async, api, realtime: endpoint, sockets: sockets)..watcher.start();
          async.flushMicrotasks();
          final socket = sockets.sockets.single;
          socket.receive('pusher:connection_established', {'socket_id': '1.2'});
          async.flushMicrotasks();
          final event = fixture(name);
          socket.receive(
            event['event'] as String,
            Map<String, dynamic>.from(event['data'] as Map),
            channel: endpoint.channel,
            rawData: rawData,
          );
          async.flushMicrotasks();
          expect(watch.decisions.firstOrNull?.verdict, verdict,
              reason: '$name, data as ${rawData ? 'object' : 'string'}');
          if (name.contains('refused')) expect(watch.decisions.single.error?.code, 'insufficient_funds');
          watch.watcher.stop();
        });
      }
    });
  });

  test('WT-06 stops watching on close', () {
    virtual((async) {
      final sockets = FakeRealtime();
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-processing-mobile-money-live.json',
        'GET /pay/status': 'status-processing.json',
        'POST /pay/broadcasting/auth': 'broadcasting-auth-200.json',
      });
      final checkout = Checkout(async, api, sockets: sockets);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.elapse(const Duration(seconds: 11));
      expect(api.calls('/pay/status'), hasLength(2));
      expect(sockets.sockets, hasLength(1));

      checkout.run(checkout.controller.dismiss);
      expect(checkout.result, isA<CheckoutProcessing>());
      checkout.elapse(const Duration(minutes: 1));
      expect(api.calls('/pay/status'), hasLength(2), reason: 'no read after the sheet closed');
      expect(sockets.sockets.single.closed, isTrue);
    });
  });
}
