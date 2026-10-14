import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/client/client_info.dart';
import 'package:wajub_mobile/src/client/pay_client.dart';
import 'package:wajub_mobile/src/constants.dart';
import 'package:wajub_mobile/src/models/payment_result.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';
import 'package:wajub_mobile/src/version.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

FakeApi processing(Object answers) => FakeApi(routes: {
      'GET /pay/session': 'session-cm-aggregate.json',
      'POST /pay/process': answers,
      'POST /pay/otp/verify': 'otp-verify-invalid.json',
      'GET /pay/status': 'status-processing.json',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TR-01 sends the common headers', () async {
    final api =
        FakeApi(routes: {'GET /pay/session': 'session-cm-aggregate.json', 'POST /pay/cancel': 'cancel-200.json'});
    final client = api.payClient();
    await client.getSession('tok_test');
    await client.cancel('tok_test');

    final get = api.requests.first;
    expect(get.headers['Authorization'], 'Bearer tok_test');
    expect(get.headers['Accept'], 'application/json');
    expect(get.headers['Accept-Language'], 'fr-CM, fr;q=0.9, en-US;q=0.8, en;q=0.7');
    expect(get.headers['X-Request-Id'], matches(uuid));
    expect(get.headers['X-Wajub-Client'], 'wajub-flutter/1.6.0 (android 15)');
    expect(get.headers.containsKey('Content-Type'), isFalse);
    final post = api.requests.last;
    expect(post.headers['Content-Type'], startsWith('application/json'));
    expect(post.headers['X-Request-Id'], isNot(get.headers['X-Request-Id']), reason: 'a fresh id per call');
    expect(wajubSdkVersion, '1.6.0');
    final pubspec = File('pubspec.yaml').readAsLinesSync().firstWhere((line) => line.startsWith('version:'));
    expect(pubspec, 'version: $wajubSdkVersion', reason: 'X-Wajub-Client reports the published version');
  });

  test('TR-02 suffixes the user agent', () async {
    final api = FakeApi(routes: {'GET /pay/session': 'session-cm-aggregate.json'});
    await api.payClient().getSession('tok_test');
    final userAgent = api.requests.single.headers['User-Agent']!;
    expect(userAgent, endsWith(api.requests.single.headers['X-Wajub-Client']!));
    expect(userAgent, 'Dart/3.9 (dart:io) wajub-flutter/1.6.0 (android 15)');
  });

  test('TR-03 sends device signals', () async {
    final api = processing('process-processing-mobile-money-sandbox.json');
    await api.payClient().process('tok_test', 'cm.mobile', {'phone': '+237670000000', 'country': 'CM'});
    final client = (api.bodies('/pay/process').single['data'] as Map)['_client'] as Map;
    final reference =
        (fixtureRequestBody('process-processing-mobile-money-sandbox.json')!['data'] as Map)['_client'] as Map;
    expect(client.keys, containsAll(reference.keys));
    expect(client, {
      'timezone': 'Africa/Douala',
      'language': 'fr-CM',
      'screen': '1080x2400',
      'color_depth': 24,
      'fingerprint': testClientInfo.fingerprint,
      'client': 'wajub-flutter/1.6.0 (android 15)',
    });

    // The device's own signals: one fingerprint per install, shared by every client.
    SharedPreferences.setMockInitialValues({});
    ClientInfo.reset();
    final first = await ClientInfo.current();
    ClientInfo.reset();
    final second = await ClientInfo.current();
    expect(first.fingerprint, matches(RegExp(r'^[a-f0-9]{16,64}$')));
    expect(second.fingerprint, first.fingerprint);
    expect(first.screen, matches(RegExp(r'^\d+x\d+$')));
    final (width, height) = (int.parse(first.screen.split('x').first), int.parse(first.screen.split('x').last));
    expect(width, lessThanOrEqualTo(height), reason: 'portrait');
    expect(first.colorDepth, 24);
    expect(first.timezone, isNotEmpty);
  });

  test('TR-04 keeps a stable install fingerprint', () async {
    SharedPreferences.setMockInitialValues({});
    ClientInfo.reset();
    final fingerprint = await ClientInfo.installFingerprint();
    final stored = (await SharedPreferences.getInstance()).getString('wajub_mobile.install_id')!;
    expect(stored, matches(uuid), reason: 'a random id, not a hardware one');
    expect(fingerprint, sha256.convert(utf8.encode('device:$stored')).toString());

    // A restart of the SDK reads the same id from the app's storage.
    ClientInfo.reset();
    expect(await ClientInfo.installFingerprint(), fingerprint);
  });

  test('TR-05 applies per-call timeouts', () {
    expect(PayClient.connectTimeout, const Duration(seconds: 10));
    expect(PayClient.requestTimeout, const Duration(seconds: 30));
    expect(PayClient.paymentRequestTimeout, const Duration(seconds: 60));
    virtual((async) {
      final api = FakeApi(routes: {'GET /pay/status': const FakeAnswer.hang()});
      Object? error;
      api.payClient().getStatus('tok_test').then((_) {}, onError: (Object e) {
        error = e;
      });
      async.elapse(const Duration(milliseconds: 29999));
      expect(api.times, hasLength(1));
      async.elapse(const Duration(milliseconds: 1302));
      expect(api.times, hasLength(2), reason: 'the read timed out at 30 s and was tried again');
      async.elapse(const Duration(minutes: 5));
      expect((error! as WajubError).code, 'timeout');
    });
    virtual((async) {
      final api = processing(const FakeAnswer.hang());
      api.payClient().process('tok_test', 'cm.mobile', const {}).then((_) {}, onError: (Object _) {});
      async.elapse(const Duration(milliseconds: 59999));
      expect(api.calls('/pay/process'), hasLength(1), reason: 'a payment call gets 60 s');
      async.elapse(const Duration(milliseconds: 1302));
      expect(api.calls('/pay/process'), hasLength(2));
      async.elapse(const Duration(minutes: 5));
    });
    virtual((async) {
      final api = FakeApi(routes: {'POST /pay/otp/verify': const FakeAnswer.hang()});
      Object? error;
      api.payClient().verifyStep('tok_test', PaymentStepKind.otp, 'prc_1', const {'code': '1'}).then((_) {},
          onError: (Object e) {
        error = e;
      });
      async.elapse(const Duration(seconds: 60));
      expect((error! as WajubError).code, 'timeout');
      expect(api.times, hasLength(1));
    });
  });

  test('TR-06 retries process with the same idempotency key', () {
    virtual((async) {
      final api = processing([
        const FakeAnswer(503, {'code': 503, 'status': 'Service Unavailable'}),
        const FakeAnswer.network(),
        FakeAnswer.fixture('process-idempotent-replay.json'),
      ]);
      final client = api.payClient();
      RawProcessAnswer? answer;
      client.process('tok_test', 'cm.mobile', {'phone': '+237670000000', 'country': 'CM', 'operator': 'mtn'}).then(
          (r) => answer = RawProcessAnswer(r.httpStatus, r.transaction?.status));
      async.elapse(const Duration(seconds: 10));
      final calls = api.calls('/pay/process');
      expect(calls, hasLength(3));
      final keys = calls.map((r) => r.headers['Idempotency-Key']).toSet();
      expect(keys, hasLength(1));
      expect(keys.single, matches(uuid));
      expect(calls.map((r) => r.body).toSet(), hasLength(1), reason: 'the identical body');
      expect(answer?.status, 202);

      // A new press of Pay: a new key.
      client.process('tok_test', 'cm.mobile', const {});
      async.flushMicrotasks();
      expect(api.calls('/pay/process').last.headers['Idempotency-Key'], isNot(keys.single));
    });
  });

  test('TR-07 does not retry non-retryable posts', () {
    for (final answer in [
      'process-failed-402.json',
      'process-422-validation.json',
      'error-500-production.json',
      'process-409-payment-in-progress.json',
    ]) {
      virtual((async) {
        final api = processing(answer);
        api.payClient().process('tok_test', 'cm.mobile', const {}).then((_) {}, onError: (Object _) {});
        async.elapse(const Duration(seconds: 30));
        expect(api.calls('/pay/process'), hasLength(1), reason: answer);
      });
    }
    virtual((async) {
      final api = FakeApi(routes: {'POST /pay/otp/verify': const FakeAnswer.network()});
      api.payClient().verifyStep('tok_test', PaymentStepKind.otp, 'prc_1', const {'code': '1'}).then((_) {},
          onError: (Object _) {});
      async.elapse(const Duration(seconds: 30));
      expect(api.calls('/pay/otp/verify'), hasLength(1));
    });
    virtual((async) {
      final api = processing('process-processing-mobile-money-live.json')
        ..on('POST /pay/otp/verify', 'otp-verify-invalid.json');
      api.payClient().verifyStep('tok_test', PaymentStepKind.otp, 'prc_1', const {'code': '000000'});
      async.flushMicrotasks();
      expect(api.calls('/pay/otp/verify'), hasLength(1));
    });
  });

  test('TR-08 retries idempotent reads', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': [
          const FakeAnswer(503, {'code': 503}),
          const FakeAnswer(503, {'code': 503}),
          FakeAnswer.fixture('session-cm-aggregate.json'),
        ],
      });
      String? id;
      api.payClient().getSession('tok_test').then((s) => id = s.transaction.id);
      async.elapse(const Duration(seconds: 2));
      expect(api.times, hasLength(2));
      expect(api.times[1].difference(api.times[0]).inMilliseconds, inInclusiveRange(700, 1300), reason: '1 s ± 30 %');
      async.elapse(const Duration(seconds: 3));
      expect(api.times, hasLength(3));
      expect(api.times[2].difference(api.times[1]).inMilliseconds, inInclusiveRange(1400, 2600), reason: '2 s ± 30 %');
      expect(id, 'trx_PVrU8x2kQ1mNa7Lb3cDe');
    });
    for (final status in [408, 500, 502, 504]) {
      virtual((async) {
        final api = FakeApi(routes: {'GET /pay/status': FakeAnswer(status, const {})});
        Object? error;
        api.payClient().getStatus('tok_test').then((_) {}, onError: (Object e) {
          error = e;
        });
        async.elapse(const Duration(seconds: 30));
        expect(api.times, hasLength(4), reason: '$status: three retries');
        expect(error, isA<WajubError>());
      });
    }
    virtual((async) {
      // 429: Retry-After when it is at most 10 s; otherwise stop with rate_limited.
      final api = FakeApi(routes: {
        'GET /pay/status': [
          const FakeAnswer(429, {'code': 429}, headers: {'retry-after': '4'}),
          FakeAnswer.fixture('status-processing.json'),
        ],
      });
      api.payClient().getStatus('tok_test');
      async.elapse(const Duration(seconds: 3));
      expect(api.times, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(api.times, hasLength(2));
    });
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/status': FakeAnswer.fixture('error-429-rate-limited.json', headers: {'retry-after': '300'})
      });
      Object? error;
      api.payClient().getStatus('tok_test').then((_) {}, onError: (Object e) {
        error = e;
      });
      async.elapse(const Duration(seconds: 30));
      expect(api.times, hasLength(1));
      expect((error! as WajubError).code, 'rate_limited');
      expect((error! as WajubError).retryAfterSeconds, 300);
    });
  });

  test('TR-09 treats an unanswered process as pending', () {
    virtual((async) {
      final api = FakeApi(routes: {
        'GET /pay/session': 'session-cm-aggregate.json',
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': const FakeAnswer.hang(),
        'GET /pay/status': ['status-processing.json', 'status-succeeded.json'],
      });
      final checkout = Checkout(async, api);
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      checkout.elapse(const Duration(minutes: 4));
      expect(api.calls('/pay/process'), hasLength(3), reason: 'two retries, then the outcome is unknown');
      expect(checkout.recorder.states, isNot(contains(CheckoutState.failed)));
      expect(checkout.recorder.errors, isEmpty);
      expect(api.calls('/pay/status'), isNotEmpty);
      expect(checkout.controller.state, CheckoutState.success);
      checkout.end();
    });
  });

  test('TR-10 defaults to the production api', () async {
    expect(apiUrl, 'https://api.wajub.com');
    final api = FakeApi(routes: {'GET /pay/session': 'session-cm-aggregate.json'});
    await api.payClient().getSession('tok_test');
    expect(api.requests.single.url.toString(), 'https://api.wajub.com/pay/session');
  });
}

class RawProcessAnswer {
  RawProcessAnswer(this.status, this.transactionStatus);

  final int? status;
  final String? transactionStatus;
}
