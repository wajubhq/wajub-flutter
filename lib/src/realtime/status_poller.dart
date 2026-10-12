import 'dart:async';

import '../client/pay_client.dart';
import '../mapper/payment_mapper.dart';
import '../models/payment_result.dart';
import '../models/wajub_error.dart';

/// Reads the session every [interval] until its status is final, and yields a
/// result each time that status changes. A read that fails is tried again,
/// each time a little later (at most a minute apart); an error the API will
/// give every time, an ended session for instance, ends the stream. Cancelling
/// the subscription stops the reads.
class StatusPoller {
  StatusPoller(this._client, this._token, {this.interval = const Duration(seconds: 5)});

  final PayClient _client;
  final String _token;
  final Duration interval;

  Stream<PaymentResult> poll() {
    late final StreamController<PaymentResult> controller;
    var cancelled = false;

    Future<void> run() async {
      String? lastStatus;
      var failures = 0;
      while (!cancelled) {
        var wait = interval;
        try {
          final session = await _client.getSession(_token);
          if (cancelled) return;
          failures = 0;
          final status = session.transaction.status;
          if (status != lastStatus) {
            lastStatus = status;
            final result = PaymentMapper.mapStatusToResult(status, session.transaction);
            controller.add(result);
            if (result is PaymentComplete || result is PaymentFailed) break;
          }
        } on WajubError catch (error, stack) {
          if (cancelled) return;
          if (!error.retryable) {
            controller.addError(error, stack);
            break;
          }
          wait = _backoff(++failures);
        } catch (_) {
          wait = _backoff(++failures);
        }
        await Future<void>.delayed(wait);
      }
      if (!cancelled) unawaited(controller.close());
    }

    controller = StreamController<PaymentResult>(
      onListen: () => unawaited(run()),
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }

  Duration _backoff(int failures) {
    final wait = interval * failures;
    const cap = Duration(minutes: 1);
    return wait > cap ? cap : wait;
  }
}
