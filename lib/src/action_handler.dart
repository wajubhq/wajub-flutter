import 'models/payment_result.dart';
import 'wajub_session.dart';
import 'adapters/hosted_redirect.dart';

/// Opens redirect / 3DS / confirm URLs in the system browser — never WebView.
Future<PaymentResult> handlePaymentAction(
  WajubSession session,
  PaymentResult result,
) async {
  if (result is PaymentRequiresAction) {
    if (result.action == ActionKind.redirect ||
        result.action == ActionKind.confirm ||
        result.action == ActionKind.confirm3ds) {
      await session.handleRedirectAction(result);
    }
  }
  return result;
}

/// Direct open for sdk-config `hosted_redirect` URLs.
Future<bool> openHostedRedirectUrl(String url) => HostedRedirect.open(url);
