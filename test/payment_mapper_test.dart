import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/adapters/stripe_adapter.dart';
import 'package:wajub_mobile/src/mapper/payment_mapper.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/payment_result.dart';

void main() {
  group('PaymentMapper', () {
    test('maps mobile money process to push approval', () {
      final raw = RawProcessResponse(
        code: 202,
        status: 'Accepted',
        message: 'Processing',
        transaction: SessionTransaction.fromJson({
          'id': 'trx.test',
          'reference': 'trx.test',
          'amount': 1000,
          'currency': 'XAF',
          'status': 'processing',
          'processing_context': {
            'is_mobile_money': true,
            'payer_instruction': 'Confirm on your phone',
          },
        }),
      );

      final result = PaymentMapper.mapProcessResponse(raw, 'mobile_money');
      expect(result, isA<PaymentRequiresAction>());
      final action = result as PaymentRequiresAction;
      expect(action.action, ActionKind.pushApproval);
    });

    test('builds mobile money payload', () {
      final data = PaymentMapper.buildMobileMoneyRequest(
        const MobileMoneyInput(channelSlug: 'cm.mtn', phone: '699887766', country: 'cm'),
      );
      expect(data['phone'], '699887766');
      expect(data['country'], 'CM');
    });

    test('maps redirect action', () {
      final raw = RawProcessResponse(
        code: 202,
        status: 'Accepted',
        message: 'Redirect',
        action: 'redirect',
        confirmUrl: 'https://psp.example/confirm',
        transaction: SessionTransaction.fromJson({
          'id': 'trx.test',
          'reference': 'trx.test',
          'amount': 1000,
          'currency': 'XAF',
          'status': 'processing',
        }),
      );
      final result = PaymentMapper.mapProcessResponse(raw, 'card');
      expect(result, isA<PaymentRequiresAction>());
      final action = result as PaymentRequiresAction;
      expect(action.action, ActionKind.redirect);
      expect(action.actionUrl, 'https://psp.example/confirm');
    });
  });

  group('StripeAdapter', () {
    test('builds stripe card payload', () {
      final data = buildStripeCardRequest(paymentMethodId: 'pm_test', cardholderName: 'Jane');
      expect(data['payment_method_id'], 'pm_test');
      expect(data['card_holder'], 'Jane');
    });
  });
}
