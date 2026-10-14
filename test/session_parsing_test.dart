import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/mapper/payment_mapper.dart';
import 'package:wajub_mobile/src/models/models.dart';

// The shape GET /pay/session really returns (ResolvesPublicSession), types
// included: `white_label` is a bool, `overlay_intensity` an int, and the
// French name sits under the literal key `name.fr`. 1.5.0 cast every
// branding value to String? and threw on each of these sessions.
const _session = '''
{
  "code": 200,
  "status": "OK",
  "message": "Payment session retrieved",
  "transaction": {
    "id": "trx.PVrU8x2kQ1",
    "reference": "CMD-4172",
    "trxref": "CMD-4172",
    "amount": 25000,
    "amount_total": 25000,
    "currency": "XAF",
    "status": "pending",
    "status_label": "Pending",
    "sandbox": true,
    "description": null
  },
  "tax": null,
  "altcha": null,
  "branding": {
    "primary_color": "#0F766E",
    "secondary_color": null,
    "logo_url": "https://cdn.wajub.com/logo.png",
    "business_name": "Boutique Ada",
    "layout": "classic",
    "border_radius": "8px",
    "font": "Inter",
    "appearance_mode": "system",
    "white_label": true,
    "overlay_intensity": 40,
    "font_weight_heading": 600,
    "card.background_color": null
  },
  "checkout_fields": [],
  "channels": [
    {
      "id": "cm.mobile",
      "slug": "cm.mobile",
      "name": "Mobile Money",
      "name.fr": "Mobile Money",
      "type": "mobile_money",
      "logo": null,
      "countries": ["CM"],
      "min_amount": "25.00",
      "max_amount": 500000.5,
      "currency": "XAF",
      "operators": [{"slug": "cm.mtn", "name": "MTN"}]
    },
    {
      "id": "card",
      "slug": "card",
      "name": "Card",
      "name.fr": "Carte bancaire",
      "type": "card",
      "logo": null,
      "countries": [],
      "min_amount": null,
      "max_amount": null,
      "currency": "XAF"
    }
  ],
  "locale": "fr",
  "echo": {
    "key": "app-key",
    "ws_host": "ws.wajub.com",
    "ws_port": "443",
    "channel_prefix": "private-payment.",
    "broadcaster": "pusher"
  },
  "callback": null
}
''';

void main() {
  test('parses a session whose branding holds booleans and integers', () {
    final session = SessionData.fromJson(jsonDecode(_session) as Map<String, dynamic>);

    expect(session.branding['primary_color'], '#0F766E');
    expect(session.branding['white_label'], 'true');
    expect(session.branding['overlay_intensity'], '40');
    expect(session.branding['font_weight_heading'], '600');
    expect(session.branding['secondary_color'], isNull);
  });

  test('reads the French name, numeric strings and a string port', () {
    final session = SessionData.fromJson(jsonDecode(_session) as Map<String, dynamic>);
    final mobile = session.channels.first;

    expect(session.transaction.amount, 25000);
    expect(mobile.nameFr, 'Mobile Money');
    expect(session.channels.last.nameFr, 'Carte bancaire');
    expect(mobile.minAmount, 25);
    expect(mobile.maxAmount, 500000.5);
    expect(session.channels.last.minAmount, isNull);
    expect(session.echo?.wsPort, 443);
  });

  test('ignores a session without echo or branding', () {
    final session = SessionData.fromJson({
      'transaction': {'id': 'trx.1', 'reference': 'R1', 'amount': 100, 'currency': 'XOF', 'status': 'pending'},
      'channels': [],
    });

    expect(session.branding, isEmpty);
    expect(session.echo, isNull);
  });

  test('reads a process response whose numbers come as strings', () {
    final raw = RawProcessResponse.fromJson({
      'code': '202',
      'status': 'Accepted',
      'message': 'Payment processing',
      'transaction': {'id': 'trx.1', 'reference': 'R1', 'amount': '100.00', 'currency': 'XOF', 'status': 'processing'},
    });

    expect(raw.code, 202);
    expect(raw.transaction?.amount, 100);
  });
}
