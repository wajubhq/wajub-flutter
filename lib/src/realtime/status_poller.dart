import 'dart:async';

import '../client/pay_client.dart';
import '../mapper/payment_mapper.dart';
import '../models/payment_result.dart';

class StatusPoller {
  StatusPoller(this._client, this._token, {this.interval = const Duration(seconds: 5)});

  final PayClient _client;
  final String _token;
  final Duration interval;

  Stream<PaymentResult> poll() async* {
    while (true) {
      final session = await _client.getSession(_token);
      final result = PaymentMapper.mapStatusToResult(session.transaction.status, session.transaction);
      yield result;
      if (result is PaymentComplete || result is PaymentFailed) {
        break;
      }
      await Future<void>.delayed(interval);
    }
  }
}
