import 'package:flutter_stripe/flutter_stripe.dart';

import '../models/wajub_error.dart';

/// Stripe `stripe_elements` adapter — tokenizes card data natively (no WebView).
class StripeAdapter {
  StripeAdapter._();

  static bool _initialized = false;

  static Future<void> ensureInitialized(String publishableKey) async {
    if (_initialized && Stripe.publishableKey == publishableKey) return;
    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();
    _initialized = true;
  }

  /// Creates a Stripe PaymentMethod and returns `pm_*` for `POST /pay/process`.
  static Future<String> createPaymentMethod({String? cardholderName}) async {
    try {
      final result = await Stripe.instance.createPaymentMethod(
        params: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails: cardholderName != null && cardholderName.isNotEmpty
                ? BillingDetails(name: cardholderName)
                : null,
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

/// Builds the `/pay/process` body for a tokenized card payment.
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
