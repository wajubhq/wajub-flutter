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
  wajub_mobile: ^1.1.0
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

## API URL

Production calls always go to `https://api.wajub.com`.

## Documentation & support

- Mobile SDK docs: [docs.wajub.com/libraries/sdks/mobile](https://docs.wajub.com/libraries/sdks/mobile)
- Server SDKs (create payments): [docs.wajub.com/libraries/sdks](https://docs.wajub.com/libraries/sdks)

## License

MIT — see [LICENSE](LICENSE).
