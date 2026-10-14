import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../checkout/present_options.dart';
import '../models/json_read.dart';
import '../models/models.dart';
import '../version.dart';

/// One message pipe to a Pusher-protocol server (Pusher, Reverb, Soketi).
abstract interface class RealtimeTransport {
  Stream<String> get messages;
  void send(String message);
  Future<void> close();
}

/// Opens a [RealtimeTransport] to [uri]; throws when it cannot.
typedef RealtimeConnector = Future<RealtimeTransport> Function(Uri uri);

/// Where the payment's realtime updates are published: the session's `echo`,
/// overridden by [RealtimeOptions].
class RealtimeEndpoint {
  const RealtimeEndpoint({
    required this.key,
    required this.host,
    required this.port,
    required this.tls,
    required this.channel,
  });

  final String key;
  final String host;
  final int port;
  final bool tls;

  /// `private-payment.trx_…`: the prefix and the payment's Wajub id.
  final String channel;

  /// The Pusher protocol's socket URL.
  Uri get uri => Uri(
        scheme: tls ? 'wss' : 'ws',
        host: host,
        port: port,
        path: '/app/$key',
        queryParameters: {'protocol': '7', 'client': 'wajub-flutter', 'version': wajubSdkVersion, 'flash': 'false'},
      );

  /// Null when the session names no usable socket (no `echo`, no key) or the
  /// app turned realtime off: the payment is then followed by polling only.
  static RealtimeEndpoint? resolve(SessionData session, RealtimeOptions options) {
    final echo = session.echoSettings ?? session.echo;
    if (!options.enabled || echo == null || echo.key.trim().isEmpty) return null;
    // `ws_host` carries the scheme: `wss://` is TLS, `ws://` plain.
    final configured = Uri.tryParse(echo.wsHost.contains('://') ? echo.wsHost : '//${echo.wsHost}');
    final override =
        options.host == null ? null : Uri.tryParse(options.host!.contains('://') ? options.host! : '//${options.host}');
    final source = override ?? configured;
    final host = source?.host ?? '';
    if (host.isEmpty) return null;
    final port = options.port ?? (override != null && override.hasPort ? override.port : echo.wsPort);
    final scheme = source!.scheme;
    final tls = options.tls ?? (scheme.isEmpty ? port == 443 : scheme == 'wss' || scheme == 'https');
    return RealtimeEndpoint(
      key: echo.key,
      host: host,
      port: port,
      tls: tls,
      channel: '${echo.channelPrefix}${session.transaction.id}',
    );
  }
}

/// A Pusher-protocol client for one private channel, over a plain WebSocket:
/// it reaches the host and port the session names (a self-hosted Reverb as
/// well as Pusher's cloud), authorizes the channel with the session's token,
/// answers pings, and reconnects with a growing delay until [stop].
class PusherSocket {
  PusherSocket({
    required this.endpoint,
    required this.authorize,
    required this.onEvent,
    this.onSubscribed,
    RealtimeConnector? connector,
  }) : _connect = connector ?? connectWebSocket;

  final RealtimeEndpoint endpoint;

  /// `POST /pay/broadcasting/auth`: the `auth` value for (socket id, channel).
  final Future<String> Function(String socketId, String channel) authorize;

  /// An event's name and its data (a map) on the channel.
  final void Function(String event, Map<String, dynamic> data) onEvent;

  /// The channel is joined (`true`) or the connection is lost (`false`).
  final void Function(bool subscribed)? onSubscribed;
  final RealtimeConnector _connect;

  RealtimeTransport? _transport;
  StreamSubscription<String>? _messages;
  Timer? _reconnect;
  Timer? _inactivity;
  var _activityTimeout = const Duration(seconds: 120);
  var _failures = 0;
  var _stopped = false;
  var _subscribed = false;

  bool get subscribed => _subscribed;

  void start() {
    _stopped = false;
    unawaited(_open());
  }

  Future<void> stop() async {
    _stopped = true;
    _reconnect?.cancel();
    _inactivity?.cancel();
    _setSubscribed(false);
    await _drop();
  }

  Future<void> _open() async {
    if (_stopped) return;
    try {
      final transport = await _connect(endpoint.uri);
      if (_stopped) {
        await transport.close();
        return;
      }
      _transport = transport;
      _messages = transport.messages.listen(_receive, onDone: _lost, onError: (Object _) => _lost());
      _touch();
    } catch (_) {
      _lost();
    }
  }

  void _receive(String raw) {
    _touch();
    final frame = readMap(_json(raw));
    if (frame == null) return;
    final event = readString(frame['event']) ?? '';
    final data = readMap(_json(frame['data'])) ?? const <String, dynamic>{};
    switch (event) {
      case 'pusher:connection_established':
        final timeout = readInt(data['activity_timeout']);
        if (timeout != null && timeout > 0) _activityTimeout = Duration(seconds: timeout);
        final socketId = readString(data['socket_id']);
        if (socketId != null) unawaited(_subscribe(socketId));
      case 'pusher_internal:subscription_succeeded':
        _failures = 0;
        _setSubscribed(true);
      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': <String, dynamic>{}});
      case 'pusher:error':
        // 4000–4099: the server will refuse every reconnection as well.
        final code = readInt(data['code']);
        if (code != null && code >= 4000 && code < 4100) unawaited(stop());
      default:
        if (readString(frame['channel']) == endpoint.channel && !event.startsWith('pusher')) {
          // Laravel's broadcastAs name; Echo clients prefix it with a dot.
          onEvent(event.startsWith('.') ? event.substring(1) : event, data);
        }
    }
  }

  Future<void> _subscribe(String socketId) async {
    try {
      final auth = await authorize(socketId, endpoint.channel);
      _send({
        'event': 'pusher:subscribe',
        'data': {'channel': endpoint.channel, 'auth': auth},
      });
    } catch (_) {
      // Not authorized (another channel, an ended session): polling carries on.
      await _drop();
      _lost();
    }
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _transport?.send(jsonEncode(frame));
    } catch (_) {
      _lost();
    }
  }

  /// A connection quiet for the server's activity timeout gets a ping; one
  /// still quiet 30 s later is dropped and reopened.
  void _touch() {
    _inactivity?.cancel();
    _inactivity = Timer(_activityTimeout, () {
      _send({'event': 'pusher:ping', 'data': <String, dynamic>{}});
      _inactivity = Timer(const Duration(seconds: 30), () => unawaited(_drop().then((_) => _lost())));
    });
  }

  void _lost() {
    _setSubscribed(false);
    _inactivity?.cancel();
    if (_stopped || (_reconnect?.isActive ?? false)) return;
    unawaited(_drop());
    final delay = Duration(seconds: [1, 2, 4, 8, 16, 30][_failures.clamp(0, 5)]);
    _failures++;
    _reconnect = Timer(delay, () => unawaited(_open()));
  }

  Future<void> _drop() async {
    final messages = _messages;
    final transport = _transport;
    _messages = null;
    _transport = null;
    unawaited(messages?.cancel());
    try {
      await transport?.close();
    } catch (_) {}
  }

  void _setSubscribed(bool value) {
    if (_subscribed == value) return;
    _subscribed = value;
    onSubscribed?.call(value);
  }

  /// Pusher frames carry `data` as a JSON string; some servers send an object.
  static Object? _json(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
}

/// A WebSocket, given up after 10 s without a connection.
Future<RealtimeTransport> connectWebSocket(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  try {
    await channel.ready.timeout(const Duration(seconds: 10));
  } catch (_) {
    // A connection that comes up later must not stay open.
    unawaited(channel.sink.close());
    rethrow;
  }
  return _WebSocketTransport(channel);
}

class _WebSocketTransport implements RealtimeTransport {
  _WebSocketTransport(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages => _channel.stream.map((message) => message is String ? message : '$message');

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  Future<void> close() async => _channel.sink.close();
}
