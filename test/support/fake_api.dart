import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wajub_mobile/src/models/security_challenge.dart';
import 'package:wajub_mobile/src/checkout/checkout_controller.dart';
import 'package:wajub_mobile/src/checkout/present_options.dart';
import 'package:wajub_mobile/src/client/client_info.dart';
import 'package:wajub_mobile/src/client/pay_client.dart';
import 'package:wajub_mobile/src/mobile_money/mobile_money_data.dart';
import 'package:wajub_mobile/src/realtime/pusher_socket.dart';
import 'package:wajub_mobile/src/wajub_session.dart';

import 'fixtures.dart';

/// The device the tests run on.
const testClientInfo = ClientInfo(
  platform: 'android',
  osVersion: '15',
  timezone: 'Africa/Douala',
  locales: ['fr-CM', 'en-US'],
  screen: '1080x2400',
  fingerprint: '9f2c4e1a7b3d5f60a1b2c3d4e5f60718293a4b5c6d7e8f9011223344556677ab',
  platformUserAgent: 'Dart/3.9 (dart:io)',
);

final mobileMoneyData = MobileMoneyData.parse(File('assets/wajub/mobile-money.json').readAsStringSync());

/// One answer of the fake API.
class FakeAnswer {
  const FakeAnswer(this.status, this.body, {this.headers = const {}, this.delay, this.error, this.hang = false});

  /// A fixture's `http_status` and `body`.
  factory FakeAnswer.fixture(String name, {Map<String, String> headers = const {}, Duration? delay}) =>
      FakeAnswer(fixtureStatus(name), fixtureBody(name), headers: headers, delay: delay);

  /// A dropped connection.
  const FakeAnswer.network() : this(0, null, error: const SocketException('connection reset'));

  /// No answer at all (a timeout once the client gives up).
  const FakeAnswer.hang() : this(0, null, hang: true);

  final int status;

  /// A map (sent as JSON) or a string (sent as is).
  final Object? body;
  final Map<String, String> headers;
  final Duration? delay;
  final Object? error;
  final bool hang;
}

/// The API, faked at the HTTP layer: answers each `METHOD /path` from a
/// queue (the last answer repeats), and records every request.
class FakeApi {
  FakeApi({Map<String, Object> routes = const {}}) {
    routes.forEach(on);
  }

  final requests = <http.Request>[];

  /// When each request arrived, on the test's clock.
  final times = <DateTime>[];
  final _routes = <String, List<FakeAnswer>>{};

  /// [answer]: a fixture name, a [FakeAnswer], or a list of them (in order).
  void on(String route, Object answer) {
    final answers = answer is List ? answer : [answer];
    _routes[route] = [
      for (final a in answers) a is String ? FakeAnswer.fixture(a) : a as FakeAnswer,
    ];
  }

  /// The requests sent to [path] (`/pay/process`).
  List<http.Request> calls(String path) => requests.where((r) => r.url.path == path).toList();

  /// The JSON bodies sent to [path].
  List<Map<String, dynamic>> bodies(String path) =>
      calls(path).map((r) => jsonDecode(r.body) as Map<String, dynamic>).toList();

  late final http.Client httpClient = MockClient((request) async {
    requests.add(request);
    times.add(clock.now());
    final key = '${request.method} ${request.url.path}';
    final queue = _routes[key];
    if (queue == null || queue.isEmpty) {
      return http.Response(jsonEncode({'code': 404, 'status': 'Not Found', 'message': 'No route $key'}), 404);
    }
    final answer = queue.length > 1 ? queue.removeAt(0) : queue.first;
    if (answer.delay != null) await Future<void>.delayed(answer.delay!);
    if (answer.hang) await Completer<void>().future;
    if (answer.error != null) throw answer.error!;
    final body = answer.body;
    return http.Response(
      body is String ? body : jsonEncode(body ?? const {}),
      answer.status,
      headers: {'content-type': 'application/json', ...answer.headers},
    );
  });

  PayClient payClient({Random? random}) => PayClient(
        httpClient: httpClient,
        clientInfo: () async => testClientInfo,
        random: random ?? Random(7),
        stopwatch: clock.stopwatch,
      );

  WajubSession session([String token = 'tok_test']) => WajubSession(token, client: payClient());
}

/// A socket that records what the SDK sends and lets a test speak for the
/// server.
class FakeSocket implements RealtimeTransport {
  final sent = <Map<String, dynamic>>[];
  final _incoming = StreamController<String>();
  var closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) => sent.add(jsonDecode(message) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }

  /// A frame from the server; [data] is sent as a JSON string, as Pusher
  /// does, or as an object when [rawData].
  void receive(String event, Map<String, dynamic> data, {String? channel, bool rawData = false}) =>
      _incoming.add(jsonEncode({
        'event': event,
        'data': rawData ? data : jsonEncode(data),
        if (channel != null) 'channel': channel,
      }));
}

/// Connects every socket to a [FakeSocket], or fails when [refuse].
class FakeRealtime {
  FakeRealtime({this.refuse = false});

  final bool refuse;
  final uris = <Uri>[];
  final sockets = <FakeSocket>[];

  Future<RealtimeTransport> connect(Uri uri) async {
    uris.add(uri);
    if (refuse) throw const SocketException('unreachable');
    final socket = FakeSocket();
    sockets.add(socket);
    return socket;
  }
}

/// A controller on [api], recording the URLs it opens.
CheckoutController checkoutController(
  FakeApi api, {
  PresentOptions options = const PresentOptions(sessionToken: 'tok_test'),
  List<String>? opened,
  bool browserOpens = true,
  FakeRealtime? realtime,
  String deviceLanguage = 'en',
  Future<int?> Function(SecurityChallenge challenge)? altchaSolver,
  Future<String> Function(String publishableKey, String? cardholderName)? stripePaymentMethod,
  Future<void> Function(String appPublishableKey)? restoreStripeKey,
}) =>
    CheckoutController(
      session: api.session(options.sessionToken),
      options: options,
      openUrl: (url) async {
        opened?.add(url);
        return browserOpens;
      },
      mobileMoneyData: () async => mobileMoneyData,
      altchaSolver: altchaSolver ?? (challenge) async => null,
      stripePaymentMethod: stripePaymentMethod,
      restoreStripeKey: restoreStripeKey ?? (_) async {},
      realtimeConnector: (realtime ?? FakeRealtime(refuse: true)).connect,
      deviceLanguage: deviceLanguage,
      // The test's virtual clock.
      stopwatch: clock.stopwatch,
    );
