# wajub_mobile

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

The Flutter SDK for [Wajub](https://wajub.com) takes Mobile Money, card and wallet payments in your app, with a
ready-made native payment sheet.

## Requirements

| Requirement | Version |
|---|---|
| Flutter | 3.24 or later (Dart `^3.5.0`) |
| `flutter_stripe` | `^11.4.0`, a dependency of the package: its own requirements become yours |
| Android build | Java 17, `compileSdk` 35 or later, `minSdk` 24 |
| iOS | Deployment target 13.0 |

The package's other dependencies need no code of yours.

**Android needs `FlutterFragmentActivity`** for Stripe's card form, and the app's theme must descend from
`Theme.AppCompat`:

```kotlin
// android/app/src/main/kotlin/.../MainActivity.kt
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

**On Flutter 3.24 to 3.26, pin `flutter_stripe` 11.4**: version 11.5 needs Flutter 3.27 although it accepts any
Flutter 3, and pub picks it.

```yaml
# pubspec.yaml, on Flutter 3.24 to 3.26 only
dependency_overrides:
  flutter_stripe: 11.4.0
  stripe_android: 11.4.0
  stripe_ios: 11.4.0
  stripe_platform_interface: 11.4.0
```

## Installation

```bash
flutter pub add wajub_mobile
```

or in `pubspec.yaml`:

```yaml
dependencies:
  wajub_mobile: ^1.6.0
```

## Quick start

1. **Your server creates the payment** with your secret key
   ([create a payment](https://docs.wajub.com/api/payments/create)) and hands the app the `authorization_token` of
   the answer. The app never holds a secret key.
2. **The app presents the sheet** with that token and reads the result:

```dart
import 'package:wajub_mobile/wajub_mobile.dart';

final result = await presentWajubCheckout(
  context,
  PresentOptions(sessionToken: authorizationToken),
);

switch (result) {
  case CheckoutComplete(:final payment):
    // Paid: payment.id is Wajub's payment id. Confirm it on your server.
    break;
  case CheckoutProcessing():
    // Closed while a payment was running: money may still move. Your server
    // learns the outcome from the webhook.
    break;
  case CheckoutFailed(:final error):
    // A failure, an ended or expired payment, or a load error (error.code).
    break;
  case CheckoutCancelled(:final reason):
    // "Cancel payment", or closed before any payment (reason.wireName).
    break;
}
```

3. **Your server confirms.** The result is what the payer saw, not proof of payment. Deliver on the
   `payment.succeeded` [webhook](https://docs.wajub.com/developer-tools/webhooks/quickstart), or after
   `GET /payments/{id}` with `payment.id`.

`presentWajubCheckout` resolves exactly once, when the sheet closes; `Wajub.present(context, options)` is the same
call. Presenting a second sheet while one is open fails at once with the `sheet_already_presented` error and leaves
the open sheet alone. A new sheet can open as soon as the last one has closed, from its `onComplete` too.

## Options

```dart
PresentOptions(
  sessionToken: authorizationToken,
  locale: 'fr',                               // 'fr' | 'en'; else the payment's, else the device's
  appearance: const Appearance(theme: 'night'),// see Appearance below
  loader: WajubLoader.skeleton,               // or WajubLoader.spinner
  readyTimeout: const Duration(seconds: 15),  // Duration.zero waits forever
  returnUrl: 'https://shop.example.com/app/return', // an https universal/app link into your app
  mobileMoney: const MobileMoneyOptions(
    country: 'CI',                            // the country to start on
    countryLocked: true,                      // hide the country selector
    operatorMode: OperatorMode.detect,        // the operator comes from the number
  ),
  cancelOnDismiss: true,                      // closing before any payment cancels it
  autoCloseSuccess: const Duration(seconds: 3), // Duration.zero keeps the success screen
  stripe: const StripeOptions(appPublishableKey: 'pk_live_…'), // your app's own Stripe key, if it has one
  callbacks: CheckoutCallbacks(/* … */),
)
```

| Field | Default | What it does |
|---|---|---|
| `sessionToken` | required | The payment's `authorization_token` |
| `locale` | `null` | `'fr'` or `'en'`. Without it the payment's language, else the device's. Anything not French reads English |
| `appearance` | `null` | The sheet's look, see [Appearance](#appearance) |
| `loader` | `skeleton` | `WajubLoader.skeleton`, placeholder blocks in the sheet's colours, or `WajubLoader.spinner` |
| `readyTimeout` | 15 s | Past it, a sheet still loading shows "We couldn't load the payment" with Retry and reports `ready_timeout` to `onLoadError`. `Duration.zero` waits forever |
| `returnUrl` | `null` | An `https` universal link or App Link back into your app, for the pages that open in the browser. Without it the payer comes back to the app by hand |
| `mobileMoney` | | `country` (ISO-2, the country to start on), `countryLocked` (hides the country selector), `operatorMode` (`choose` lists the operators; `detect` takes the operator from the number) |
| `cancelOnDismiss` | `true` | Closing the sheet before any payment cancels the payment. `false` leaves it open so you can present it again |
| `autoCloseSuccess` | 3 s | How long the success screen stays. `Duration.zero` keeps it until the payer closes it |
| `stripe` | | `appPublishableKey`: your app's own Stripe key, when your app also takes Stripe payments with `flutter_stripe`. The sheet puts it back when it closes, so your own Stripe payments keep working |
| `callbacks` | | See [Callbacks](#callbacks) |

## Callbacks

All optional, called on the UI thread in this order for a payment: `onReady`, `onStateChange` on each change,
`onPaymentStarted` and `onRedirect`, then `onSuccess`, `onError` or `onCancel`, and `onComplete` exactly once. A
callback that throws does not break the sheet.

```dart
CheckoutCallbacks(
  onReady: (e) {},           // ReadyEvent: sessionId, environment, amount, currency, methods (slugs)
  onStateChange: (e) {},     // StateChangeEvent: state (CheckoutState), method
  onLoadError: (error) {},   // the sheet could not offer a payment
  onPaymentStarted: (e) {},  // the payment was accepted: from now on, closing resolves `processing`
  onRedirect: (e) {},        // e.url, right before the system browser opens
  onSuccess: (payment) {},   // PaymentSuccess: id, reference, amount, currency, method, timestamp, receiptUrl
  onError: (error) {},       // every failure the payer sees, retryable ones included
  onCancel: (e) {},          // CancelEvent: reason, redirectUrl
  onComplete: (result) {},   // the CheckoutResult presentWajubCheckout resolves with
)
```

### States

`state.wireName` is the state's name: `INITIATED` (method list), `COLLECTING_DETAILS` (a form), `PROCESSING` (Pay
pressed), `APPROVAL_REQUIRED` (approve on the phone), `USSD_REQUIRED`, `OTP_REQUIRED`, `PIN_REQUIRED`,
`PHONE_REQUIRED`, `BIRTHDAY_REQUIRED`, `ADDRESS_REQUIRED`, `3DS_REQUIRED`, `VERIFYING`, `PENDING` (waiting, or a
provider page is open), `SUCCESS`, `FAILED`, `EXPIRED`, `CANCELLED`.

### Results

| `CheckoutResult` | When | Carries |
|---|---|---|
| `CheckoutComplete` | The sheet closed after the success, also for a payment already paid as it opened | `payment` (`PaymentSuccess`), `transaction` |
| `CheckoutProcessing` | The sheet closed while a payment was under way: money may still move, confirm on your server | `transaction` |
| `CheckoutFailed` | Closed on a failure, an ended or expired payment, or a load error | `error` (`WajubError`), `transaction` |
| `CheckoutCancelled` | "Cancel payment", a close before any payment, or the page that presented it going away first | `reason` (`CancelReason`), `redirectUrl` |

The sheet never shows a failure when the outcome is unknown: it shows "Payment in progress", and closing it then
resolves `processing`. When the page that presented the sheet goes away, the sheet resolves `cancelled` with
`host_gone` before any payment, `processing` once one has started, and never cancels the payment. If the app's
process dies, read the outcome on your server at the next launch.

### Cancelling and closing

The payer closes the sheet with its close button, a swipe down, the back button or a tap outside it.

| Closing… | Result |
|---|---|
| While the payment still loads | `CheckoutCancelled`, `dismissed` |
| Before any payment | `CheckoutCancelled`, `dismissed`. The payment is cancelled, unless `cancelOnDismiss` is `false` |
| While the payer approves, dials a code, confirms a step or waits | `CheckoutProcessing`: the payment keeps running |
| On the failure screen | `CheckoutFailed`, with the error the payer saw. The payment is cancelled when it still can be, unless `cancelOnDismiss` is `false`. `onCancel` does not fire |
| After the success | `CheckoutComplete` |

"Cancel payment" in the sheet cancels the payment for good and resolves `CheckoutCancelled` with
`payer_cancelled`. It is not offered while a payment is under way.

## Errors

Every failure is a `WajubError`. The sheet hands it to `onLoadError` or `onError` and puts it in
`CheckoutFailed`.

| Field | What it is for |
|---|---|
| `type` | A `WajubErrorType`: `apiError`, `authenticationError`, `invalidRequestError`, `paymentError`, `rateLimitError` |
| `code` | The code to branch on |
| `message` | For the payer, in the sheet's language; `localized('fr')` gives the same error in another language |
| `declineCode` | On a decline, the reason's code |
| `retryable` | Whether another attempt can work |
| `param` | The field at fault, when there is one |
| `correlationId` | The request id to quote to Wajub support |
| `retryAfterSeconds` | On `rate_limited`, how long to wait |
| `blockReference` | On `shield_blocked`, the reference to quote to Wajub support |
| `attemptsRemaining` | On a confirmation step, the attempts left |

| Codes | When |
|---|---|
| `session_not_found`, `session_terminal_expired`, `session_terminal_cancelled`, `session_terminal_failed`, `load_error`, `ready_timeout`, `no_payment_method` | `onLoadError`: the payment cannot be offered |
| `network_error`, `timeout`, `server_error`, `rate_limited`, `request_failed` | the connection |
| `payment_declined`, `insufficient_funds`, a provider's own decline code, `merchant_not_verified`, `limit_exceeded`, `shield_blocked`, `merchant_restricted`, `payment_method_restricted`, `country_restricted`, `currency_restricted`, `channel_not_accepted`, `payment_failed`, `payment_attempt_ended`, `payment_cancelled`, `session_expired`, `not_processable`, `order_not_validated`, `security_check_failed`, `unsupported_action`, `redirect_unavailable` | the payment |
| `invalid_otp`, `otp_expired`, `invalid_pin`, `max_attempts_exceeded`, `invalid_code`, `3ds_failed`, … | confirmation steps |
| `client_session_unavailable`, `client_session_expired` | card payments on the provider's page |
| `sheet_already_presented` | a second `presentWajubCheckout` while a sheet is open |

## Appearance

The `appearance` option sets the sheet's look, with the keys, presets and variables of
[Appearance](https://docs.wajub.com/libraries/components/appearance):

```dart
const appearance = Appearance(
  theme: 'stripe',            // presets: stripe, night, flat, none — or light, dark, auto
  colorScheme: 'auto',        // light | dark | auto (follows the phone)
  inherit: true,              // read Theme.of(context) where you set nothing
  variables: AppearanceVariables(
    colorPrimary: '#0F766E',
    colorBackground: '#FFFFFF',
    colorText: '#171717',
    colorDanger: '#B91C1C',
    fontFamily: 'Inter',      // used when your app ships it
    borderRadius: '12px',
    spacingUnit: '4px',
  ),
  buttonTextColor: '#FFFFFF',
  disableAnimations: false,
);

// Or from a map, such as decoded JSON:
final shared = Appearance.fromMap(jsonDecode(appearanceJson) as Map<String, Object?>);
```

What you leave unset comes from the merchant's branding in the Dashboard, then Wajub's default light or dark
palette. With white label on, the sheet does not show "Secured by Wajub".

## Your own UI

The sheet is the simplest integration. An app that draws its own payment screens uses the lower-level
`WajubSession`, created with `Wajub.createSession(authorizationToken)` and described in the package's
[API reference](https://pub.dev/documentation/wajub_mobile/latest/).

## Privacy

To make the payment, the SDK sends Wajub what the payer types. For fraud prevention, it also sends basic device
information and a random install identifier, which is not the advertising identifier. When the payer uses Stripe's
card form, Stripe's SDK also collects what Stripe documents for its own fraud checks. Declare it next to what your
app collects on its own.

For the **App Store privacy labels**, declare it linked to the user, not used for tracking, for App Functionality,
which covers processing the payment and preventing fraud.

| App Store Connect | What the SDK sends |
|---|---|
| Contact Info, Name | First and last name, or the card holder, when the payment method asks for them |
| Contact Info, Email Address | When the card payment asks for it |
| Contact Info, Phone Number | The Mobile Money number, or a phone number a card payment asks for |
| Contact Info, Physical Address | Address, city, ZIP code and country, when the card payment asks for them |
| Financial Info, Payment Info | The Mobile Money account, the Stripe card token, a card PIN when one is asked, and test cards in sandbox |
| Identifiers, Device ID | The random install identifier, for fraud prevention |
| Other Data | A date of birth when one is asked, and basic device information, for fraud prevention |

For **Google Play data safety**, declare it collected for *App functionality* and *Fraud prevention, security, and
compliance*, shared with Wajub as your payment processor, encrypted in transit.

| Google Play data safety | What the SDK sends |
|---|---|
| Personal info, Name | First and last name, or the card holder, when the payment method asks for them |
| Personal info, Email address | When the card payment asks for it |
| Personal info, Phone number | The Mobile Money number, or a phone number a card payment asks for |
| Personal info, Address | Address, city, ZIP code and country, when the card payment asks for them |
| Personal info, Other info | A date of birth, when one is asked |
| Financial info, User payment info | The Mobile Money account, the Stripe card token, a card PIN when one is asked, and test cards in sandbox |
| Device or other IDs | The random install identifier and basic device information, for fraud prevention |

## Testing

Create the payment with a sandbox key: the whole flow runs in sandbox, sheet included, and the sheet shows a
"Test mode" badge. Test numbers and cards are on
[Test scenarios](https://docs.wajub.com/developer-tools/testing/test-scenarios).

## Documentation and support

- Flutter SDK: [docs.wajub.com/libraries/sdks/flutter](https://docs.wajub.com/libraries/sdks/flutter)
- Server SDKs (create payments): [docs.wajub.com/libraries/sdks](https://docs.wajub.com/libraries/sdks)

## License

MIT — see [LICENSE](LICENSE).
