import '../appearance/appearance.dart';
import 'checkout_types.dart';

/// The loader drawn while the payment loads.
enum WajubLoader {
  /// Placeholder blocks in the sheet's colours, pulsing.
  skeleton,

  /// A centred activity indicator.
  spinner,
}

/// How the Mobile Money form starts.
class MobileMoneyOptions {
  const MobileMoneyOptions({this.country, this.countryLocked = false, this.operatorMode = OperatorMode.choose});

  /// ISO-2 country to start on, when a Mobile Money channel covers it.
  final String? country;

  /// Hide the country selector when [country] is covered.
  final bool countryLocked;
  final OperatorMode operatorMode;
}

enum OperatorMode {
  /// The payer picks the operator in a list; the number preselects it.
  choose,

  /// The operator comes from the number; the list shows only when the number
  /// does not tell it.
  detect,
}

/// Your app's own use of `flutter_stripe`, next to the sheet's.
///
/// When your app also takes Stripe payments with its own key, give it here:
/// the sheet puts it back when it closes, so your own Stripe payments keep
/// working.
class StripeOptions {
  const StripeOptions({this.appPublishableKey});

  /// Your app's own `pk_…`, restored once the sheet closes.
  final String? appPublishableKey;
}

/// Everything `presentWajubCheckout` takes.
class PresentOptions {
  const PresentOptions({
    required this.sessionToken,
    this.locale,
    this.appearance,
    this.loader = WajubLoader.skeleton,
    this.readyTimeout = const Duration(milliseconds: 15000),
    this.returnUrl,
    this.mobileMoney = const MobileMoneyOptions(),
    this.cancelOnDismiss = true,
    this.autoCloseSuccess = const Duration(seconds: 3),
    this.stripe = const StripeOptions(),
    this.callbacks = const CheckoutCallbacks(),
  });

  /// The payment's `authorization_token`, from your server.
  final String sessionToken;

  /// `fr` or `en`; else the payment's language, else the device's.
  final String? locale;

  /// The sheet's look; the merchant's branding fills the rest.
  final Appearance? appearance;
  final WajubLoader loader;

  /// How long the sheet may take to load before it reports `ready_timeout`
  /// and offers Retry. [Duration.zero] waits forever.
  final Duration readyTimeout;

  /// An `https` universal link or App Link back into your app, for the pages
  /// that open in the browser. Without it the payer comes back by hand.
  final String? returnUrl;
  final MobileMoneyOptions mobileMoney;

  /// Closing the sheet before any payment cancels the payment. `false`
  /// leaves it open, so you can present it again.
  final bool cancelOnDismiss;

  /// How long the success screen stays before the sheet closes itself.
  /// [Duration.zero] keeps it until the payer closes it.
  final Duration autoCloseSuccess;

  /// Your app's own Stripe key, put back after the sheet's card form.
  final StripeOptions stripe;
  final CheckoutCallbacks callbacks;
}
