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

const _terminalStatuses = {
  'success',
  'successful',
  'succeeded',
  'paid',
  'complete',
  'failed',
  'cancelled',
  'expired',
};

/// Pusher/Reverb with polling fallback — mirrors checkout `realtime.ts`.
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
      Timer? fallbackTimer;
      var closed = false;

      Future<void> closeAll() async {
        if (closed) return;
        closed = true;
        fallbackTimer?.cancel();
        await pollSub?.cancel();
        try {
          await pusher?.disconnect();
        } catch (_) {}
        await controller.close();
      }

      void emitStatus(String status) {
        final result = PaymentMapper.mapStatusToResult(status, session.transaction);
        controller.add(result);
        if (_terminalStatuses.contains(status.toLowerCase())) {
          unawaited(closeAll());
        }
      }

      Future<void> startPolling() async {
        pollSub ??= StatusPoller(_client, _token, interval: interval).poll().listen(
          controller.add,
          onError: controller.addError,
          onDone: () => unawaited(closeAll()),
        );
      }

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
            onConnectionStateChange: (current, previous) async {
              if (current == 'CONNECTED') {
                fallbackTimer?.cancel();
                await pollSub?.cancel();
                pollSub = null;
              }
            },
            onEvent: (event) {
              if (event.eventName != 'PaymentStatusUpdated') return;
              final raw = event.data;
              if (raw is Map && raw['status'] is String) {
                emitStatus(raw['status'] as String);
              }
            },
            onError: (_, __, ___) {},
            // pusher_channels_flutter has no public API for a custom host/port
            // (self-hosted Reverb), unlike pusher-js — it always dials Pusher's
            // cloud. Self-hosted deployments fail to connect here and fall
            // back to the HTTP polling below within `fallbackTimer`.
          );
          await pusher!.connect();
          await pusher!.subscribe(
            channelName: '${echo.channelPrefix}${session.transaction.reference}',
          );

          fallbackTimer = Timer(const Duration(seconds: 10), () async {
            if (pusher?.connectionState != 'CONNECTED') {
              await startPolling();
            }
          });
        } catch (_) {
          await startPolling();
        }
      }());

      controller.onCancel = () => unawaited(closeAll());
    });
  }
}
