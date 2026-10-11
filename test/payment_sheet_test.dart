import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wajub_mobile/src/client/pay_client.dart';
import 'package:wajub_mobile/src/models/payment_result.dart';
import 'package:wajub_mobile/src/wajub_session.dart';
import 'package:wajub_mobile/src/widgets/payment_sheet.dart';

/// A session whose API answers the sheet's two reads, and records every call.
WajubSession fakeSession(List<http.Request> calls, {String locale = 'en'}) {
  return WajubSession(
    'tok',
    client: PayClient(
      httpClient: MockClient((request) async {
        calls.add(request);
        final path = request.url.path;
        final body = switch (path) {
          '/pay/session' => {
              'transaction': {'id': 'trx_1', 'reference': 'order-1', 'amount': 5000, 'currency': 'XAF', 'status': 'pending'},
              'channels': [
                {'id': 'c1', 'slug': 'cm.mtn', 'name': 'MTN', 'type': 'mobile_money', 'countries': ['CM'], 'currency': 'XAF'},
              ],
              'locale': locale,
            },
          '/pay/sdk-config' => {'channels': <String, dynamic>{}},
          '/pay/cancel' => {'code': 200, 'status': 'OK', 'message': 'Cancelled'},
          _ => <String, dynamic>{},
        };
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      }),
    ),
  );
}

Future<void> openSheet(
  WidgetTester tester,
  WajubSession session, {
  String? locale,
  required List<PaymentResult> results,
  required List<String> cancels,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showWajubPaymentSheet(
          context: context,
          session: session,
          locale: locale,
          onResult: results.add,
          onCancel: () => cancels.add('cancelled'),
        ),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('closing the sheet before paying reports it cancelled and cancels the payment', (tester) async {
    final calls = <http.Request>[];
    final results = <PaymentResult>[];
    final cancels = <String>[];
    await openSheet(tester, fakeSession(calls), results: results, cancels: cancels);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(cancels, ['cancelled']);
    expect(results, isEmpty);
    expect(calls.map((r) => r.url.path), contains('/pay/cancel'));
  });

  testWidgets('a swipe or back press that closes the sheet is reported too', (tester) async {
    final calls = <http.Request>[];
    final cancels = <String>[];
    await openSheet(tester, fakeSession(calls), results: [], cancels: cancels);

    await tester.tapAt(const Offset(10, 10)); // the barrier above the sheet
    await tester.pumpAndSettle();

    expect(cancels, ['cancelled']);
    expect(calls.map((r) => r.url.path), contains('/pay/cancel'));
  });

  testWidgets('the sheet speaks the payment\'s language, and the one asked for first', (tester) async {
    await openSheet(tester, fakeSession([], locale: 'fr'), results: [], cancels: []);
    expect(find.text('Payer avec Wajub'), findsOneWidget);
    expect(find.text('Numéro de téléphone'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await openSheet(tester, fakeSession([], locale: 'fr'), locale: 'en', results: [], cancels: []);
    expect(find.text('Pay with Wajub'), findsOneWidget);
  });
}
