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

    test('maps client_session action with the hosted url', () {
      final raw = RawProcessResponse.fromJson({
        'code': 202,
        'status': 'Accepted',
        'message': 'Client session ready',
        'action': 'client_session',
        'client_session': {
          'id': 'cs_123',
          'provider': 'paystack',
          'reference': 'wjb_ref_1',
          'amount': 500000,
          'currency': 'NGN',
          'hosted_url': 'https://checkout.paystack.com/abc',
          'access_code': 'abc',
          'public_key': 'pk_test_1',
        },
        'transaction': _transactionJson,
      });

      final result = PaymentMapper.mapProcessResponse(raw, 'card');
      expect(result, isA<PaymentRequiresAction>());
      final action = result as PaymentRequiresAction;
      expect(action.action, ActionKind.clientSession);
      expect(action.actionUrl, 'https://checkout.paystack.com/abc');
      expect(action.clientSession?.id, 'cs_123');
      expect(action.clientSession?.provider, 'paystack');
      expect(action.clientSession?.accessCode, 'abc');
      expect(action.clientSession?.publicKey, 'pk_test_1');
      expect(action.clientSession?.encryptionKey, isNull);
    });

    for (final unsupported in ['confirm_otp', 'card_reauth']) {
      test('fails $unsupported with unsupported_action, never processing', () {
        final raw = RawProcessResponse.fromJson({
          'code': 202,
          'status': 'Accepted',
          'message': 'Action required',
          'action': unsupported,
          'transaction': {
            ..._transactionJson,
            'processing_context': {'is_mobile_money': true},
          },
        });

        final result = PaymentMapper.mapProcessResponse(raw, 'mobile_money');
        expect(result, isA<PaymentFailed>());
        expect((result as PaymentFailed).error.code, PaymentMapper.unsupportedActionCode);
      });
    }

    test('fails client_session action without a client_session object', () {
      final raw = RawProcessResponse.fromJson({
        'code': 202,
        'status': 'Accepted',
        'message': 'Client session ready',
        'action': 'client_session',
        'transaction': _transactionJson,
      });

      final result = PaymentMapper.mapProcessResponse(raw, 'card');
      expect(result, isA<PaymentFailed>());
      expect((result as PaymentFailed).error.code, PaymentMapper.unsupportedActionCode);
    });

    test('parses client_session flag from sdk-config', () {
      final config = SdkConfig.fromJson({
        'channels': {
          'card': {'available': true, 'provider': 'paystack', 'sdk': 'form', 'client_session': true},
          'visa': {'available': true, 'sdk': 'adyen_custom_card'},
        },
      });
      expect(config.channels['card']!.clientSession, isTrue);
      expect(config.channels['visa']!.clientSession, isFalse);
      expect(config.channels['visa']!.sdk, SdkFlavor.adyenCustomCard);
    });
  });

  group('hosted-redirect billing fields (sdk-config required_fields)', () {
    test('validates required, email and 2-letter country values', () {
      expect(PaymentMapper.hostedCardFieldError('city', '  '), 'Required');
      expect(PaymentMapper.hostedCardFieldError('email', 'nope'), 'Invalid email');
      expect(PaymentMapper.hostedCardFieldError('email', 'payer@example.test'), isNull);
      expect(PaymentMapper.hostedCardFieldError('country', 'CIV'), 'Use the 2-letter country code');
      expect(PaymentMapper.hostedCardFieldError('country', 'ci'), isNull);
    });

    test('builds flat data, trimming, upper-casing the country and dropping blanks and unknown keys', () {
      expect(
        PaymentMapper.buildHostedCardRequest(
          {'email': ' payer@example.test ', 'country': 'ci', 'city': '', 'card.number': '4242'},
        ),
        {'email': 'payer@example.test', 'country': 'CI'},
      );
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

const _transactionJson = <String, dynamic>{
  'id': 'trx.test',
  'reference': 'trx.test',
  'amount': 1000,
  'currency': 'NGN',
  'status': 'processing',
};
