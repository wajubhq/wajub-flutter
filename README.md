# wajub_mobile

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Native Flutter checkout SDK for [Wajub](https://wajub.com). Presents mobile-money and card payments in-app — **no WebView**. Calls `https://api.wajub.com/pay/*` with a session `authorization_token` from your [server SDK](https://docs.wajub.com/libraries/sdks).

## Architecture

```
Your backend (server SDK, sk_)
        ↓ authorization_token
Flutter app
        ↓
Wajub.createSession(token) → GET /pay/session, GET /pay/sdk-config
        ↓
showWajubPaymentSheet()
        ↓
POST /pay/process → system browser for redirect/3DS
        ↓
watchStatus() → Pusher or polling until terminal
```

## Requirements

| Requirement | Version |
|-------------|---------|
| Dart SDK | `^3.5.0` (see `pubspec.yaml`) |
| `flutter_stripe` | `^11.4.0` (for `stripe_elements` card flavor) |

`flutter_stripe` sets its own minimum iOS/Android platform versions — see [pub.dev/packages/flutter_stripe](https://pub.dev/packages/flutter_stripe).

## Installation

```bash
flutter pub add wajub_mobile
```

or add it to `pubspec.yaml` directly:

```yaml
dependencies:
  wajub_mobile: ^1.2.0
```

## Quick start

Initialize with your publishable key, create a payment on your backend, then present the sheet:

```dart
import 'package:wajub_mobile/wajub_mobile.dart';

void main() {
  Wajub.initialize(publicKey: 'pk_test_...');
  runApp(const MyApp());
}
```

```dart
final session = Wajub.createSession(authorizationToken);

await showWajubPaymentSheet(
  context: context,
  session: session,
  onResult: (result) {
    switch (result) {
      case PaymentComplete():
        break;
      case PaymentRequiresAction():
        break;
      case PaymentFailed():
        break;
      default:
        break;
    }
  },
);
```

## Features

| Flavor | Support |
|--------|---------|
| Mobile Money (`form`) | Native sheet |
| Card (`stripe_elements`) | Native Stripe `CardField` |
| Card via Paystack / Flutterwave / Adyen Pay by Link (`client_session: true`) | PSP-hosted checkout in the system browser |
| Card (`hosted_redirect` — PayPal, Mollie, Paddle, Kkiapay, FedaPay, PayDunya, CinetPay) | System browser via `url_launcher`, after collecting the sdk-config `requiredFields` (e.g. email, CinetPay billing) — `payCardHostedRedirect(channelSlug:, billing:)` |
| Card (`adyen_custom_card`) | Web only — Adyen cards use `client_session` on mobile |
| Redirect / hosted | System browser via `url_launcher` |
| Realtime | Pusher/Reverb + polling fallback |

## Headless integration

```dart
final result = await session.payCardWithStripeElements(
  channelSlug: 'card',
  publishableKey: 'pk_test_...',
);
await for (final update in session.watchStatus()) { /* ... */ }
```

## Card via Paystack / Flutterwave (client sessions)

When `sdk-config` flags the card channel with `client_session: true`, the
PSP's own checkout collects the card and runs PIN / OTP / AVS — the SDK never
touches card data. `PaymentSheet` handles this automatically; headless:

```dart
final config = await session.getSdkConfig();
final card = config.channels['card'];

if (card != null && card.clientSession) {
  // Pins the provider — `card.provider` is only a prediction. Idempotent:
  // calling it again returns the same open session. Paystack/Flutterwave
  // need an email when the transaction has none.
  final started = await session.startClientSession(channelSlug: 'card', email: 'payer@example.com');

  if (started is PaymentRequiresAction && started.action == ActionKind.clientSession) {
    final cs = started.clientSession!;
    await session.handleRedirectAction(started); // opens cs.hostedUrl in the system browser

    // …when the app comes back to the foreground:
    final result = await session.completeClientSession(cs.id);
    // PaymentComplete → paid; PaymentProcessing → not confirmed yet, keep
    // watchStatus() running (the PSP webhook settles it). A decline throws
    // WajubError (402).
  }
}
```

The backend verifies with the PSP by its own reference and checks amount and
currency; the app never sends a PSP reference.

### Using the PSP's native SDK instead

Instead of `hostedUrl`, you may launch the PSP's native SDK yourself with the
`ClientSession` fields, then call `completeClientSession(cs.id)` exactly as
above once it returns (whatever it reports — only the backend's verification
counts):

- **Paystack** (`cs.provider == 'paystack'`): `cs.publicKey` + `cs.accessCode`.
- **Flutterwave** (`cs.provider == 'flutterwave'`): `cs.publicKey`,
  `cs.encryptionKey`, `cs.reference` as `tx_ref`, `cs.amount`, `cs.currency`.

`cs.amount` is in the PSP's own units (Paystack: subunit; Flutterwave: major).
These PSP SDKs are not bundled with `wajub_mobile`.

If the PSP-side session died (e.g. abandoned), call
`startClientSession(channelSlug: 'card', restart: true)` — the old one is
re-verified first.

### Unsupported actions

A payment step this SDK can't perform natively (`confirm_otp`, `confirm_pin`,
`card_reauth`, …) returns `PaymentFailed` with `error.code ==
'unsupported_action'` — never `PaymentProcessing`.

## API URL

Production calls always go to `https://api.wajub.com`.

## Documentation & support

- Mobile SDK docs: [docs.wajub.com/libraries/sdks/mobile](https://docs.wajub.com/libraries/sdks/mobile)
- Server SDKs (create payments): [docs.wajub.com/libraries/sdks](https://docs.wajub.com/libraries/sdks)

## License

MIT — see [LICENSE](LICENSE).
