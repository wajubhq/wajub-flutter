import 'models/payment_result.dart';
import 'wajub_session.dart';
import 'adapters/hosted_redirect.dart';

/// Opens the page a [PaymentRequiresAction] asks for in the system browser,
/// and returns [result].
Future<PaymentResult> handlePaymentAction(
  WajubSession session,
  PaymentResult result,
) async {
  if (result is PaymentRequiresAction) {
    if (result.action == ActionKind.redirect ||
        result.action == ActionKind.confirm ||
        result.action == ActionKind.confirm3ds ||
        result.action == ActionKind.clientSession) {
      await session.handleRedirectAction(result);
    }
  }
  return result;
}

/// Opens [url] in the system browser.
Future<bool> openHostedRedirectUrl(String url) => HostedRedirect.open(url);
