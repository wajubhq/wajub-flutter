import 'package:flutter_stripe/flutter_stripe.dart';

import '../models/wajub_error.dart';

/// Stripe's card form, for apps that draw their own card screen.
class StripeAdapter {
  StripeAdapter._();

  static bool _initialized = false;

  static Future<void> ensureInitialized(String publishableKey) async {
    if (_initialized && Stripe.publishableKey == publishableKey) return;
    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();
    _initialized = true;
  }

  /// Puts the app's own [publishableKey] back after the payment sheet used
  /// the merchant's.
  static Future<void> restore(String publishableKey) async {
    if (_initialized && Stripe.publishableKey == publishableKey) return;
    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();
  }

  /// Creates a Stripe PaymentMethod from Stripe's card field and returns its
  /// id (`pm_…`) for `WajubSession.payCard`.
  static Future<String> createPaymentMethod({String? cardholderName}) async {
    try {
      final result = await Stripe.instance.createPaymentMethod(
        params: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails:
                cardholderName != null && cardholderName.isNotEmpty ? BillingDetails(name: cardholderName) : null,
          ),
        ),
      );
      return result.id;
    } on StripeException catch (e) {
      throw WajubError(
        type: WajubErrorType.paymentError,
        message: e.error.localizedMessage ?? e.error.message ?? 'Stripe error',
        code: e.error.code.name,
      );
    }
  }
}

/// The payment data of a card Stripe tokenized, for
/// `WajubSession.processPayment`.
Map<String, dynamic> buildStripeCardRequest({
  required String paymentMethodId,
  String? cardholderName,
}) {
  final data = <String, dynamic>{'payment_method_id': paymentMethodId};
  if (cardholderName != null && cardholderName.isNotEmpty) {
    data['card_holder'] = cardholderName;
  }
  return data;
}
