import 'package:flutter/widgets.dart';

import 'checkout/checkout_types.dart';
import 'checkout/present_options.dart';
import 'client/pay_client.dart';
import 'wajub_session.dart';
import 'widgets/present.dart';

/// Entry point for the Wajub Flutter SDK.
class Wajub {
  Wajub._();

  static String? _publicKey;

  /// Stores a merchant public key (`pk_*`); the payment sheet does not need one.
  static void initialize({required String publicKey}) {
    _publicKey = publicKey.trim();
  }

  static String? get publicKey => _publicKey;

  /// A [WajubSession] for the payment's `authorization_token`, from your
  /// server. [client] sends its calls through your own `http.Client`.
  static WajubSession createSession(String authorizationToken, {PayClient? client}) =>
      WajubSession(authorizationToken, client: client ?? PayClient());

  /// [presentWajubCheckout]: the payment sheet, resolved once it closes.
  static Future<CheckoutResult> present(BuildContext context, PresentOptions options) =>
      presentWajubCheckout(context, options);
}

/// @deprecated Use [Wajub] instead.
typedef WajubMobile = Wajub;
