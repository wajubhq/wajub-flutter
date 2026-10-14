import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wajub_mobile/src/client/pay_client.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/payment_result.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';
import 'package:wajub_mobile/src/realtime/status_subscriber.dart';

// The payment's Wajub id and the merchant's reference differ, as they do on
// every real session, so a test that mixes them up fails.
const paymentId = 'trx_9f3c';
const merchantReference = 'ORDER-1042';
const pusherChannel = 'pusher_channels_flutter';
const interval = Duration(milliseconds: 20);

/// The Pusher plugin's native side: records what the SDK asks of it, and
/// sends back what the socket would.
class FakePusher {
  final calls = <MethodCall>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(pusherChannel),
      (call) async {
        calls.add(call);
        return null;
      },
    );
  }

  List<String> get subscribedChannels => [
        for (final call in calls)
          if (call.method == 'subscribe') (call.arguments as Map)['channelName'] as String,
      ];

  bool get disconnected => calls.any((call) => call.method == 'disconnect');

  Future<void> says(String method, Map<String, dynamic> arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      pusherChannel,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  Future<void> connected() =>
      says('onConnectionStateChange', {'currentState': 'connected', 'previousState': 'connecting'});

  /// A `PaymentStatusUpdated` event, with its data as the Android and iOS plugins hand it over: a JSON string.
  Future<void> statusUpdated(String status) => says('onEvent', {
        'channelName': 'private-payment.$paymentId',
        'eventName': 'PaymentStatusUpdated',
        'data': jsonEncode({'status': status, 'reference': paymentId, 'uid': paymentId}),
      });
}

/// `/pay/session` answering [status], counting its reads. [failures] go
/// first: an HTTP status is answered with an error body, anything else is
/// thrown, as a dropped connection is.
class FakeApi {
  String status = 'processing';
  int reads = 0;
  final failures = <Object>[];

  PayClient client() => PayClient(
        httpClient: MockClient((request) async {
          reads++;
          if (failures.isNotEmpty) {
            final failure = failures.removeAt(0);
            if (failure is int) {
              return http.Response(jsonEncode({'message': 'Session ended'}), failure,
                  headers: {'content-type': 'application/json'});
            }
            throw failure;
          }
          final body = {
            'transaction': {
              'id': paymentId,
              'reference': merchantReference,
              'amount': 1000,
              'currency': 'XAF',
              'status': status
            },
            'channels': <dynamic>[],
          };
          return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
        }),
      );
}

const session = SessionData(
  transaction: SessionTransaction(
      id: paymentId, reference: merchantReference, amount: 1000, currency: 'XAF', status: 'processing'),
  channels: [],
  echo: EchoConfig(
    key: 'app_key',
    wsHost: 'wss://ws.wajub.test',
    wsPort: 443,
    channelPrefix: 'private-payment.',
    broadcaster: 'pusher',
  ),
);

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePusher pusher;
  late FakeApi api;

  setUp(() {
    pusher = FakePusher()..install();
    api = FakeApi();
  });

  test('subscribes on the channel the API publishes on: the prefix and the payment id', () async {
    final results = <PaymentResult>[];
    final sub = StatusSubscriber(api.client(), 'tok', interval: interval).subscribe(session).listen(results.add);

    await waitFor(() => pusher.subscribedChannels.isNotEmpty);
    expect(pusher.subscribedChannels, ['private-payment.$paymentId']);

    await sub.cancel();
  });

  test('keeps polling once the socket is connected, and ends on the final status it reads', () async {
    final results = <PaymentResult>[];
    final done = Completer<void>();
    StatusSubscriber(api.client(), 'tok', interval: interval)
        .subscribe(session)
        .listen(results.add, onDone: done.complete);

    await waitFor(() => pusher.subscribedChannels.isNotEmpty);
    await pusher.connected();
    final readsWhenConnected = api.reads;

    // The socket misses the event: the polling still finds the payment paid.
    await Future<void>.delayed(interval * 5);
    expect(api.reads, greaterThan(readsWhenConnected));
    api.status = 'succeeded';

    await done.future.timeout(const Duration(seconds: 3));
    expect(results.last, isA<PaymentComplete>());
    expect(pusher.disconnected, isTrue);
  });

  test('a result goes out when it changes, from either source, and nothing after a final one', () async {
    final results = <PaymentResult>[];
    final done = Completer<void>();
    StatusSubscriber(api.client(), 'tok', interval: interval)
        .subscribe(session)
        .listen(results.add, onDone: done.complete);

    await waitFor(() => pusher.subscribedChannels.isNotEmpty);
    await pusher.connected();
    await Future<void>.delayed(interval * 5);
    await pusher.statusUpdated('processing');
    expect(results, hasLength(1), reason: 'still processing: one result, however many reads and events');
    expect(results.single, isA<PaymentProcessing>());

    await pusher.statusUpdated('succeeded');
    await done.future.timeout(const Duration(seconds: 3));
    expect(results, hasLength(2));
    expect(results.last, isA<PaymentComplete>());

    api.status = 'failed';
    await pusher.statusUpdated('failed');
    await Future<void>.delayed(interval * 3);
    expect(results, hasLength(2));
  });

  group('without realtime settings, polling alone', () {
    const polledOnly = SessionData(
      transaction: SessionTransaction(
          id: paymentId, reference: merchantReference, amount: 1000, currency: 'XAF', status: 'processing'),
      channels: [],
    );

    test('delivers a result when the status changes, and stops reading once cancelled', () async {
      final results = <PaymentResult>[];
      final sub = StatusSubscriber(api.client(), 'tok', interval: interval).subscribe(polledOnly).listen(results.add);

      await waitFor(() => api.reads >= 5);
      expect(results, hasLength(1));
      expect(results.single, isA<PaymentProcessing>());

      await sub.cancel();
      final readsWhenCancelled = api.reads;
      await Future<void>.delayed(interval * 5);
      expect(api.reads, lessThanOrEqualTo(readsWhenCancelled + 1));
    });

    test('tries a failed read again, and ends on an error the API will always give', () async {
      api.failures.addAll([http.ClientException('connection reset'), 503]);
      final results = <PaymentResult>[];
      final errors = <Object>[];
      final done = Completer<void>();
      StatusSubscriber(api.client(), 'tok', interval: interval)
          .subscribe(polledOnly)
          .listen(results.add, onError: errors.add, onDone: done.complete);

      await waitFor(() => results.isNotEmpty);
      expect(errors, isEmpty, reason: 'a dropped connection and a 503 are tried again');
      expect(results.single, isA<PaymentProcessing>());

      api.failures.add(410);
      api.status = 'succeeded';
      await done.future.timeout(const Duration(seconds: 3));
      expect(errors.single, isA<WajubError>().having((e) => e.retryable, 'retryable', isFalse));
      expect(results, hasLength(1));
    });
  });
}
