import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wajub_mobile/src/client/pay_client.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';

void main() {
  group('PayClient client sessions', () {
    late List<http.Request> requests;

    PayClient clientReturning(int status, Map<String, dynamic> body) {
      requests = [];
      return PayClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
        }),
      );
    }

    const sessionBody = {
      'code': 202,
      'status': 'Accepted',
      'message': 'Client session ready',
      'action': 'client_session',
      'client_session': {'id': 'cs_1', 'provider': 'flutterwave', 'hosted_url': 'https://checkout.flutterwave.com/x'},
    };

    test('startClientSession posts only non-null fields', () async {
      final client = clientReturning(202, sessionBody);

      final raw = await client.startClientSession('tok', 'card', email: 'payer@example.com');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.wajub.com/pay/client-session');
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(request.body), {'channel': 'card', 'email': 'payer@example.com'});
      expect(raw.clientSession?.id, 'cs_1');
    });

    test('startClientSession sends name, return_url and restart when set', () async {
      final client = clientReturning(202, sessionBody);

      await client.startClientSession(
        'tok',
        'card',
        name: 'Ada',
        returnUrl: 'https://merchant.example/done',
        restart: true,
      );

      expect(jsonDecode(requests.single.body), {
        'channel': 'card',
        'name': 'Ada',
        'return_url': 'https://merchant.example/done',
        'restart': true,
      });
    });

    test('completeClientSession posts the client_session_id', () async {
      final client = clientReturning(200, {'code': 200, 'status': 'OK', 'message': 'Paid'});

      await client.completeClientSession('tok', 'cs_1');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.wajub.com/pay/client-session/complete');
      expect(jsonDecode(request.body), {'client_session_id': 'cs_1'});
    });

    test('surfaces the API error when the PSP needs an email', () async {
      final client = clientReturning(402, {
        'code': 402,
        'status': 'Payment Required',
        'message': 'Paystack requires an email on every charge.',
        'error_code': 'missing_fields',
      });

      await expectLater(
        client.startClientSession('tok', 'card'),
        throwsA(isA<WajubError>()
            .having((e) => e.code, 'code', 'missing_fields')
            .having((e) => e.message, 'message', 'Paystack requires an email on every charge.')),
      );
    });
  });
}
