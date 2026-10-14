# wajub_mobile

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Native Flutter checkout SDK for [Wajub](https://wajub.com). Presents Mobile Money, card and wallet payments in a
native sheet — **no WebView** — that looks and behaves like Wajub's hosted checkout and Wajub.js. It calls
`https://api.wajub.com/pay/*` with a payment session `authorization_token` from your
[server SDK](https://docs.wajub.com/libraries/sdks).

## How it works

```
Your backend (server SDK, sk_)        POST /payments → authorization_token
        ↓
Flutter app: presentWajubCheckout()   GET /pay/session + GET /pay/sdk-config (in parallel)
        ↓
Native sheet                          methods → form → POST /pay/process
        ↓                             approval / confirmation steps / system browser
Status                                realtime socket + GET /pay/status until the outcome
        ↓
CheckoutResult                        complete · processing · failed · cancelled
```

Always confirm a payment server-side (`GET /payments/{id}` or the `payment.succeeded` webhook) before you deliver.

## Requirements

| Requirement | Version |
|-------------|---------|
| Dart SDK | `^3.5.0` |
| `flutter_stripe` | `^11.4.0` (Stripe cards) — sets its own minimum iOS/Android versions, see [pub.dev/packages/flutter_stripe](https://pub.dev/packages/flutter_stripe) |

The SDK also uses `url_launcher` (provider pages in the system browser), `web_socket_channel` (realtime updates),
`shared_preferences`, `device_info_plus` and `flutter_timezone` (the device signals the API's risk scoring reads).
None needs any setup.

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

Create the payment on your server, send its `authorization_token` to the app, then present the sheet:

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

`presentWajubCheckout` resolves exactly once, when the sheet closes. `Wajub.present(context, options)` is the same
call. Presenting a second sheet while one is open fails at once with the `sheet_already_presented` error and leaves
the open sheet alone.

### What the sheet does

- **Loads** the session and the SDK configuration in parallel, behind a skeleton in the merchant's colours. An
  already paid payment opens on the success screen; a failed, cancelled or expired one on a "this payment has
  ended" notice; one still processing (the app was killed during an approval) on the screen it was on.
- **Offers** the payment's methods in the API's order: Mobile Money (one form for every operator), the card when
  its provider can be paid on mobile, and one-tap wallets (Djamo). Methods outside their amount limits show
  disabled with the limit.
- **Mobile Money**: country, operator list with the operators' logos (a brand badge when a logo is missing), the
  number formatted as it is typed and sent in E.164. The number's prefix preselects its operator until the payer
  picks one; a number of another operator is refused before any call ("This number belongs to MTN MoMo…"), except in
  sandbox where test numbers do not follow the real prefixes. Then "Approve the payment on your phone", with the
  provider's instruction (and its USSD fallback).
- **Cards**: Stripe's native card field; the PSP's hosted checkout for Paystack, Flutterwave and Adyen (client
  sessions); a PSP page for CinetPay, Kkiapay, Mollie… after the contact fields the provider needs; the test-card
  form in sandbox. Card numbers are never sent to Wajub in live.
- **Confirmation steps** a provider asks for — OTP, card PIN, phone, date of birth, billing address, and the
  sandbox 3-D Secure email code — each on its own screen, with "Resend" after 60 seconds.
- **Provider pages** open in the system browser, never a WebView; coming back to the app reads the status at once,
  and "Continue payment" reopens the page.
- **Follows** the payment over the session's realtime socket (Pusher or a self-hosted Reverb/Soketi) and by polling
  `GET /pay/status` — every 5 s, slower after 2 minutes without a change, backing off on errors — for at most 15
  minutes.
- **Ends** on a success screen (it closes itself after 3 s), a failure screen with "Try again" when the payer can,
  or "Payment in progress — you will be notified".
- Speaks **French and English**: the language you ask for, else the payment's, else the device's.

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
  realtime: const RealtimeOptions(host: 'ws.shop.example', port: 443, tls: true), // or enabled: false
  cancelOnDismiss: true,                      // a dismiss before any payment cancels it on Wajub
  autoCloseSuccess: const Duration(seconds: 3), // Duration.zero keeps the success screen
  callbacks: CheckoutCallbacks(/* … */),
)
```

- **`readyTimeout`**: when the payment has not loaded in time the sheet shows "We couldn't load the payment" with
  Retry and reports `ready_timeout` to `onLoadError`. If the data arrives later, the sheet shows it.
- **`returnUrl`** is sent to the provider pages that open in the browser (`return_url`). Without it the provider
  returns the payer to the merchant's page and the payer comes back to the app by hand; either way the sheet reads
  the status as soon as the app is in the foreground again.
- **`realtime`** overrides the session's socket settings: another host, port or TLS for a self-hosted Reverb or
  Soketi, or `enabled: false` for polling only. By default the sheet connects where the session says (`echo`), with
  no Pusher cluster setting.
- **`cancelOnDismiss: false`** leaves the payment open when the payer closes the sheet before paying, so you can
  present it again.

## Callbacks

All optional, called on the UI thread in this order for a payment:
`onReady` → `onStateChange`… → `onPaymentStarted`, `onRedirect` → `onSuccess` / `onError` / `onCancel` →
`onComplete` (exactly once). A callback that throws does not break the sheet.

```dart
CheckoutCallbacks(
  onReady: (e) {},           // ReadyEvent: sessionId, environment, amount, currency, methods (slugs)
  onStateChange: (e) {},     // StateChangeEvent: state (CheckoutState), method
  onLoadError: (error) {},   // the sheet could not offer a payment
  onPaymentStarted: (e) {},  // first accepted request: from now on a dismiss resolves `processing`
  onRedirect: (e) {},        // e.url, right before the system browser opens
  onSuccess: (payment) {},   // PaymentSuccess: id, reference, amount, currency, method, timestamp, receiptUrl
  onError: (error) {},       // every failure the payer sees, retryable ones included
  onCancel: (e) {},          // CancelEvent: reason, redirectUrl
  onComplete: (result) {},   // the CheckoutResult presentWajubCheckout resolves with
)
```

### States

`CheckoutState` uses Wajub.js's names (`state.wireName`): `INITIATED` (method list), `COLLECTING_DETAILS` (a
form), `PROCESSING` (Pay pressed), `APPROVAL_REQUIRED` (approve on the phone), `USSD_REQUIRED`, `OTP_REQUIRED`,
`PIN_REQUIRED`, `PHONE_REQUIRED`, `BIRTHDAY_REQUIRED`, `ADDRESS_REQUIRED`, `3DS_REQUIRED`, `VERIFYING`, `PENDING`
(waiting, or a provider page is open), `SUCCESS`, `FAILED`, `EXPIRED`, `CANCELLED`.

### Results

| `CheckoutResult` | When | Carries |
|---|---|---|
| `CheckoutComplete` | the sheet closed after the success | `payment` (`PaymentSuccess`), `transaction` |
| `CheckoutProcessing` | closed while a payment was running, or after 15 minutes without an outcome | `transaction` |
| `CheckoutFailed` | closed on a failure, an ended or expired payment, a load error | `error` (`WajubError`), `transaction` |
| `CheckoutCancelled` | "Cancel payment", a dismiss before any payment, the screen that presented it went away | `reason` (`CancelReason`), `redirectUrl` |

When the page that presented the sheet goes away (its route is removed, the app's navigator is disposed), the sheet
settles: `cancelled` with reason `host_gone` before any payment, `processing` after one started. It never cancels
the payment then. If the app's process dies, read the outcome on your server (or `WajubSession.status()`) at the
next launch.

## Errors

Every failure is a `WajubError` with Wajub.js's fields — `type` (`WajubErrorType`, `type.wireName` is
`payment_error`…), `code`, `message` (for the payer, in the sheet's language), `declineCode`, `retryable`,
`param` — and the mobile ones: `httpStatus`, `correlationId` (the response's `X-Request-Id`, quote it to Wajub's
support), `retryAfterSeconds`, `details`, `blockReference`, `apiMessage` (the API's own English text). `toMap()`
gives Wajub.js's JSON shape.

| Codes | When |
|---|---|
| `session_not_found`, `session_terminal_expired`, `session_terminal_cancelled`, `session_terminal_failed`, `load_error`, `ready_timeout`, `no_payment_method` | `onLoadError`: the payment cannot be offered |
| `network_error`, `timeout`, `server_error`, `rate_limited`, `request_failed` | transport |
| `payment_declined`, `insufficient_funds`, a provider's own decline code, `merchant_not_verified`, `limit_exceeded`, `shield_blocked`, `merchant_restricted`, `payment_method_restricted`, `country_restricted`, `currency_restricted`, `channel_not_accepted`, `payment_failed`, `payment_attempt_ended`, `payment_cancelled`, `session_expired`, `not_processable`, `order_not_validated`, `security_check_failed`, `unsupported_action`, `redirect_unavailable` | payment |
| `invalid_otp`, `otp_expired`, `invalid_pin`, `max_attempts_exceeded`, `invalid_code`, `3ds_failed`, … | confirmation steps |
| `client_session_unavailable`, `client_session_expired` | PSP-hosted cards |
| `sheet_already_presented` | a second `presentWajubCheckout` while a sheet is open |

## Appearance

`Appearance` takes Wajub.js's appearance object, key for key, so the web Components and the native sheet share
one style:

```dart
const appearance = Appearance(
  theme: 'stripe',            // presets: stripe, night, flat, none — or light, dark, auto
  colorScheme: 'auto',        // light | dark | auto (follows the phone, live)
  variables: AppearanceVariables(
    colorPrimary: '#0F766E',
    colorBackground: '#FFFFFF',
    colorText: '#171717',
    colorDanger: '#B91C1C',
    fontFamily: 'Inter',      // used when your app ships it
    borderRadius: '12px',
    spacingUnit: '4px',
  ),
  buttonTextColor: '#FFFFFF', // Wajub.js's top-level keys work too
  disableAnimations: false,
);

// Or the very object your web checkout uses:
final shared = Appearance.fromMap(jsonDecode(appearanceJson) as Map<String, Object?>);
```

For each colour, size and font the sheet takes the first value set: your `variables`, your top-level keys, your
preset, your app's theme (`inherit: true` reads `Theme.of(context)`, keeping only legible colours), the merchant's
branding from the dashboard, then Wajub's default light or dark palette. The colour scheme is your `colorScheme`
(or `theme`), else your app's with `inherit`, else the merchant's choice, else the phone's — and follows the phone
live. A merchant primary colour too pale to read on the background falls back to the default one, and
`white_label` hides "Secured by Wajub". Values that do not parse are ignored. The loader's pulse and the
cross-fades stop when `disableAnimations` is set or the phone asks for reduced motion.

## Headless integration

`WajubSession` gives the `/pay/*` calls to apps that draw their own UI. It sends the same headers, device signals,
timeouts and retries as the sheet.

```dart
final session = Wajub.createSession(authorizationToken);
final data = await session.loadSession();
final config = await session.getSdkConfig();

final result = await session.payMobileMoney(
  const MobileMoneyInput(channelSlug: 'cm.mobile', phone: '+237677123456', country: 'CM', operator: 'mtn'),
);
switch (result) {
  case PaymentRequiresAction(:final step?, :final stepId?):
    // confirm_otp, confirm_pin, confirm_phone, confirm_birthday, confirm_address
    final answer = await session.verifyStep(step, stepId, {'code': '123456'});
    if (!answer.success) print(WajubError.fromStep(answer).message);
  case PaymentRequiresAction(action: ActionKind.pushApproval):
    // Approve on the phone: follow the status.
  default:
    break;
}

await for (final update in session.watchStatus()) {
  // PaymentProcessing on each change, then PaymentComplete or PaymentFailed.
}
```

Also: `status()` (`GET /pay/status`), `process()`, `payWallet()`, `payCardHostedRedirect()`, `payCard()` /
`payCardWithStripeElements()`, `startClientSession()` / `completeClientSession()`, `resendStep()`,
`verifyThreeDs()` / `sendThreeDs()` (sandbox), `handleRedirectAction()`, `cancel()`.

### Cards via Paystack / Flutterwave (client sessions)

When sdk-config flags the card with `client_session: true`, the PSP's own checkout collects the card and runs
PIN / OTP / AVS. The sheet does all of it; headless:

```dart
final started = await session.startClientSession(channelSlug: 'card', email: 'payer@example.com');
if (started is PaymentRequiresAction && started.action == ActionKind.clientSession) {
  final cs = started.clientSession!;
  await session.handleRedirectAction(started); // opens cs.hostedUrl in the system browser
  // …when the app is back in the foreground:
  final result = await session.completeClientSession(cs.id);
}
```

You may instead launch the PSP's native SDK with the `ClientSession` fields — Paystack: `publicKey` +
`accessCode`; Flutterwave: `publicKey`, `encryptionKey`, `reference` as `tx_ref`, `amount`, `currency` — then call
`completeClientSession(cs.id)` the same way. These PSP SDKs are not bundled.

## Migrating from 1.5

Everything you use keeps compiling: no type lost or gained a value, and the deprecated entry points keep their
signatures.

- **`showWajubPaymentSheet` and `PaymentSheet` are deprecated** in favour of `presentWajubCheckout`. They keep
  working and now draw the new sheet: `onResult` receives `PaymentComplete`, `PaymentFailed`, or
  `PaymentProcessing` when the sheet closed while a payment was running, once the sheet closes (no more
  `PaymentRequiresAction` — the sheet now follows redirects, approvals and confirmation steps itself); `onCancel`
  as before.

  ```dart
  // 1.5
  await showWajubPaymentSheet(context: context, session: session, onResult: handle, onCancel: cancelled);
  // 1.6
  final result = await presentWajubCheckout(context, PresentOptions(sessionToken: token));
  ```

- **`confirm_otp`, `confirm_pin`, `confirm_phone`, `confirm_birthday`, `confirm_address`** are no longer
  `unsupported_action`: the low-level calls return `PaymentRequiresAction` with `action: ActionKind.confirm`, no
  `actionUrl`, and the new `step`, `stepId` and `hint`; `WajubSession.verifyStep()` sends the payer's answer.
- **`WajubError`**: the errors the SDK builds from API answers follow Wajub.js's catalogue — messages in the
  sheet's (or the device's) language, the API's own text in `apiMessage`, a `410` as an `invalidRequestError` (it
  was `authenticationError`), a decline code the catalogue does not know read as "This payment could not be
  completed…". `WajubError.fromHttp` keeps its 1.5 mapping.
- **`MobileMoneyInput.phone`** is sent as you give it: give it in E.164 (`+237677123456`). The sheet builds it from
  what the payer types.
- **`watchStatus()`** reads `GET /pay/status` instead of the whole session, follows a self-hosted Reverb as well as
  Pusher, and stops on `401`, `403`, `404` and `410`.

## API URL

Production calls always go to `https://api.wajub.com`.

## Documentation & support

- Mobile SDK docs: [docs.wajub.com/libraries/sdks/mobile](https://docs.wajub.com/libraries/sdks/mobile)
- Server SDKs (create payments): [docs.wajub.com/libraries/sdks](https://docs.wajub.com/libraries/sdks)

## License

MIT — see [LICENSE](LICENSE).
