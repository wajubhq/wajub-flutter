import 'client/pay_client.dart';
import 'wajub_session.dart';

/// Entry point for the Wajub Flutter SDK.
class Wajub {
  Wajub._();

  static String? _publicKey;

  /// Optional merchant public key (`pk_*`) — stored for Stripe initialization helpers.
  static void initialize({required String publicKey}) {
    _publicKey = publicKey.trim();
  }

  static String? get publicKey => _publicKey;

  /// Creates a session client from the backend `authorization_token`.
  static WajubSession createSession(String authorizationToken, {PayClient? client}) =>
      WajubSession(authorizationToken, client: client ?? PayClient());
}

/// @deprecated Use [Wajub] instead.
typedef WajubMobile = Wajub;
