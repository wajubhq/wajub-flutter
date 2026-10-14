import '../appearance/appearance.dart';
import 'checkout_types.dart';

/// The loader drawn while the payment loads.
enum WajubLoader {
  /// Placeholder blocks in the sheet's colours, pulsing.
  skeleton,

  /// A centred activity indicator.
  spinner,
}

/// How the Mobile Money form starts (Wajub.js `fields.country` and
/// `fields.operator`).
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

/// Overrides the session's realtime settings: a self-hosted Reverb or Soketi
/// behind another hostname, or no realtime at all.
class RealtimeOptions {
  const RealtimeOptions({this.enabled = true, this.host, this.port, this.tls});

  /// `false`: follow the payment by polling only.
  final bool enabled;
  final String? host;
  final int? port;
  final bool? tls;
}

/// Everything `presentWajubCheckout` takes (spec types.ts `PresentOptions`).
class PresentOptions {
  const PresentOptions({
    required this.sessionToken,
    this.locale,
    this.appearance,
    this.loader = WajubLoader.skeleton,
    this.readyTimeout = const Duration(milliseconds: 15000),
    this.returnUrl,
    this.mobileMoney = const MobileMoneyOptions(),
    this.realtime = const RealtimeOptions(),
    this.cancelOnDismiss = true,
    this.autoCloseSuccess = const Duration(seconds: 3),
    this.callbacks = const CheckoutCallbacks(),
  });

  /// The payment's `authorization_token`, from your server.
  final String sessionToken;

  /// `fr` or `en`; else the payment's language, else the device's.
  final String? locale;

  /// Wajub.js's appearance object; the merchant's branding fills the rest.
  final Appearance? appearance;
  final WajubLoader loader;

  /// How long the sheet may take to load before it reports `ready_timeout`
  /// and offers Retry. [Duration.zero] waits forever.
  final Duration readyTimeout;

  /// An `https` universal or app link back into your app, sent to the
  /// payment pages that open in the browser. Without it the payer comes back
  /// by hand.
  final String? returnUrl;
  final MobileMoneyOptions mobileMoney;
  final RealtimeOptions realtime;

  /// A dismiss before any payment cancels it on Wajub (`POST /pay/cancel`).
  /// `false` leaves it open, so you can present it again.
  final bool cancelOnDismiss;

  /// How long the success screen stays before the sheet closes itself.
  /// [Duration.zero] keeps it until the payer closes it.
  final Duration autoCloseSuccess;
  final CheckoutCallbacks callbacks;
}
