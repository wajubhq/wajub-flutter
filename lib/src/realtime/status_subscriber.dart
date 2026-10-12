import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../client/pay_client.dart';
import '../constants.dart';
import '../mapper/payment_mapper.dart';
import '../models/models.dart';
import '../models/payment_result.dart';
import 'status_poller.dart';

/// Pusher/Reverb for speed, with polling running next to it for the whole
/// watch: a socket only carries what happens after it subscribed, and a
/// connected one can still miss an event. Mirrors checkout `realtime.ts` and
/// the React Native and Kotlin SDKs' subscribers.
class StatusSubscriber {
  StatusSubscriber(this._client, this._token, {this.interval = const Duration(seconds: 5)});

  final PayClient _client;
  final String _token;
  final Duration interval;

  Stream<PaymentResult> subscribe(SessionData session) {
    final echo = session.echo;
    if (echo == null) {
      return StatusPoller(_client, _token, interval: interval).poll();
    }

    return Stream.multi((controller) {
      PusherChannelsFlutter? pusher;
      StreamSubscription<PaymentResult>? pollSub;
      var closed = false;

      Future<void> closeAll() async {
        if (closed) return;
        closed = true;
        await pollSub?.cancel();
        try {
          await pusher?.disconnect();
        } catch (_) {}
        await controller.close();
      }

      // Two sources for one status: a result goes out when it changes, and
      // nothing follows a final one, which ends the watch.
      Type? lastKind;
      void deliver(PaymentResult result) {
        if (closed || result.runtimeType == lastKind) return;
        lastKind = result.runtimeType;
        controller.add(result);
        if (result is PaymentComplete || result is PaymentFailed) {
          unawaited(closeAll());
        }
      }

      // Not stopped when the socket connects.
      pollSub = StatusPoller(_client, _token, interval: interval).poll().listen(
        deliver,
        onError: (Object error, StackTrace stack) {
          if (!closed) controller.addError(error, stack);
        },
        onDone: () => unawaited(closeAll()),
      );

      unawaited(() async {
        try {
          pusher = PusherChannelsFlutter.getInstance();
          final useTls = echo.wsHost.startsWith('wss://') || echo.wsPort == 443;

          await pusher!.init(
            apiKey: echo.key,
            cluster: 'default',
            useTLS: useTls,
            // `channel_prefix` is `private-payment.` — this status channel is
            // private, so it must be authorized by proving possession of this
            // session's own bearer token. The plugin's `authEndpoint`/`authParams`
            // params only wire through on Flutter Web (pusher-js); native
            // Android/iOS need this callback instead — mirrors checkout
            // `realtime.ts` and the Kotlin/React Native SDKs' subscribers.
            onAuthorizer: (channelName, socketId, options) async {
              final uri = Uri.parse(
                '${apiUrl.replaceAll(RegExp(r'/+$'), '')}/pay/broadcasting/auth',
              );
              final response = await http.post(
                uri,
                headers: {
                  'Accept': 'application/json',
                  'Authorization': 'Bearer $_token',
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: {'channel_name': channelName, 'socket_id': socketId},
              );
              return jsonDecode(response.body) as Map<String, dynamic>;
            },
            onEvent: (event) {
              if (event.eventName != 'PaymentStatusUpdated') return;
              final status = _statusOf(event.data);
              if (status != null) {
                deliver(PaymentMapper.mapStatusToResult(status, session.transaction));
              }
            },
            onError: (_, __, ___) {},
            // pusher_channels_flutter has no public API for a custom host/port
            // (self-hosted Reverb), unlike pusher-js — it always dials Pusher's
            // cloud. Self-hosted deployments fail to connect here, and the
            // polling carries the watch on its own.
          );
          if (closed) return;
          await pusher!.connect();
          // The API publishes on the payment's Wajub id, and its authorizer
          // signs that channel only. `reference` is the merchant's own:
          // nothing is published there.
          await pusher!.subscribe(
            channelName: '${echo.channelPrefix}${session.transaction.id}',
          );
          if (closed) {
            await pusher!.disconnect();
          }
        } catch (_) {
          // No socket: the polling above carries the watch on its own.
        }
      }());

      controller.onCancel = () => unawaited(closeAll());
    });
  }

  /// The status a `PaymentStatusUpdated` event carries. The Android and iOS
  /// plugins hand its data over as a JSON string, the web one as a map.
  static String? _statusOf(dynamic data) {
    var payload = data;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        return null;
      }
    }
    if (payload is Map && payload['status'] is String) {
      return payload['status'] as String;
    }
    return null;
  }
}
