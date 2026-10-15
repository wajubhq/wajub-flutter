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
| Flutter | 3.24 or later (Dart `^3.5.0`) |
| `flutter_stripe` | `^11.4.0` (Stripe cards) — sets its own requirements, see [pub.dev/packages/flutter_stripe](https://pub.dev/packages/flutter_stripe) (for example `FlutterFragmentActivity` on Android) |

The SDK also uses `url_launcher` (provider pages in the system browser), `web_socket_channel` (realtime updates),
`flutter_svg` (operator logos), and `shared_preferences`, `device_info_plus` and `flutter_timezone` (the device
signals of [Privacy](#privacy)). They need no code, but they set native minimums. With the versions pub resolves on
current Flutter (`device_info_plus` 13.3, `flutter_timezone` 5.1, `shared_preferences_android` 2.4,
`shared_preferences_foundation` 2.5, `url_launcher_android` 6.3, `url_launcher_ios` 6.4):

- **Android**: Java 17 for the build (`flutter_timezone`, `device_info_plus`, `shared_preferences_android`,
  `url_launcher_android` compile for it), `compileSdk` 35 or later (`flutter_timezone`), `minSdk` 24
  (`shared_preferences_android`, `url_launcher_android`).
- **iOS**: deployment target 13.0 (`shared_preferences_foundation`, `url_launcher_ios`; `device_info_plus` asks
  12.0, `flutter_timezone` 11.0).

On older Flutter versions pub resolves older plugin versions, whose minimums are lower. On Flutter 3.24 to 3.26,
pin `flutter_stripe` 11.4 (`dependency_overrides`: `flutter_stripe`, `stripe_android`, `stripe_ios` and
`stripe_platform_interface` at `11.4.0`): flutter_stripe 11.5 calls Flutter 3.27 APIs although it accepts any
Flutter 3, and pub picks it.

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
  ended" notice; one still processing (the app was killed during an approval) on the screen it was on — each at
  once, from the session alone, without waiting for the SDK configuration. When the configuration cannot be read,
  Mobile Money still shows; a payment with only cards or wallets shows "We couldn't load the payment" with Retry.
- **Never waits on the device's plugins**: the device signals are read in the background; until they are, the
  calls carry what the app knows without them.
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
  minutes from the press of Pay, timed on the phone's monotonic clock (a changed device time, or the payment's
  `expires_at`, never shortens it).
- **Never loses a payment**: a payment without an answer (a network error, a timeout, a `5xx`) is followed as
  pending, never shown as failed. If the status still reads a plain `pending` 60 s later, the request never
  arrived: the form comes back with a connection error, and Pay sends the same `Idempotency-Key`, so a request that
  did arrive is replayed, not charged twice.
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
  stripe: const StripeOptions(appPublishableKey: 'pk_live_…'), // your app's own Stripe key, if it has one
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
- **`stripe`**: the sheet's Stripe card form sets `flutter_stripe`'s global `Stripe.publishableKey` to the
  merchant's key from Wajub. If your app also takes Stripe payments with its own key, give it as
  `appPublishableKey`: the sheet puts it back (and applies Stripe's settings again) when it closes after using its
  card form. Without it, set your key again yourself before your next Stripe call.

## Callbacks

All optional, called on the UI thread in this order for a payment:
`onReady` → `onStateChange`… → `onPaymentStarted`, `onRedirect` → `onSuccess` / `onError` / `onCancel` →
`onComplete` (exactly once). A callback that throws does not break the sheet. The sheet is released before the
callbacks run: `onComplete` may present the next one.

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
the payment then; a `presentWajubCheckout` whose `context` is no longer mounted resolves `host_gone` at once. If the
app's process dies, read the outcome on your server (or `WajubSession.status()`) at the next launch.

### Cancelling and closing

The sheet calls `POST /pay/cancel` only while the payment's last known status is `pending` and no attempt is
undecided — from the press of Pay to a definitive answer (a decline, a refusal the status reports, a confirmation
step failed for good, an ended payment). The API would also cancel a payment the payer is still approving on the
phone, so:

- "Cancel payment" is offered on the method list, a form, and a failure the payer can retry; never while the payer
  approves, dials a USSD code, confirms a step or waits. Closing the sheet there resolves `processing`, without a
  call.
- After a refusal the payment is `pending` again: "Cancel payment" is back, and closing the sheet from the form
  cancels it as before any attempt (with `cancelOnDismiss`). Closing it on the failure screen — its Close button,
  the close icon, a swipe or back — resolves `failed` with the error the payer saw, and also cancels the payment
  (with `cancelOnDismiss`) so the order is released; `onCancel` does not fire.
- An attempt the API accepted stays undecided until such an answer: a failure the sheet cannot follow after it
  (`unsupported_action`, `redirect_unavailable`, `3ds_timeout`) never cancels the payment.
- Closing the sheet while the payment loads resolves `cancelled` (`dismissed`) without a call; once the session has
  answered, its status decides (`processing` resolves `processing`).
- While a cancel runs, Pay, Close, back and a swipe down wait for it. A cancel the API refuses reads the status and
  shows what it says (a success, a failure, an expired payment), or resolves `processing` when the status cannot be
  read; if the sheet went away meanwhile, it resolves with that at once.

## Errors

Every failure is a `WajubError` with Wajub.js's fields — `type` (`WajubErrorType`, `type.wireName` is
`payment_error`…), `code`, `message` (for the payer, in the sheet's language), `declineCode`, `retryable`,
`param` — and the mobile ones: `httpStatus`, `correlationId` (the response's `X-Request-Id`, quote it to Wajub's
support), `retryAfterSeconds`, `details`, `blockReference`, `apiMessage` (the API's own English text),
`attemptsRemaining` (a confirmation step's tries left). `toMap()` gives Wajub.js's JSON shape, `localized('fr')`
the same error with its message in another language, and `WajubError.fromStep(answer)` the error of a
confirmation step `verifyStep()` refused.

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
// `sdk` is a string: compare it with the SdkFlavor constants (not an enum).
final stripeCard = config.channels['card']?.sdk == SdkFlavor.stripeElements; // keyed by channel slug

// One Idempotency-Key per press of Pay; pass the same one again only to resend
// a payment that got no answer.
final key = newIdempotencyKey(); // yours: a UUID per press of Pay
final result = await session.processPayment(
  'cm.mobile',
  {'phone': '+237677123456', 'country': 'CM', 'operator': 'mtn'},
  idempotencyKey: key,
);
switch (result) {
  case PaymentComplete():
    // Paid.
    break;
  case PaymentProcessing(kind: ProcessingKind.approval, :final instruction):
    // Approve the push on the phone; follow the status.
    print(instruction); // the provider's words, when it gives some
  case PaymentProcessing(kind: ProcessingKind.ussd, :final instruction):
    // Dial the USSD code it gives; follow the status.
    print(instruction);
  case PaymentProcessing():
    // Pending, or no answer at all (network, timeout, 5xx): the charge may be
    // running. Follow the status; if it still reads a plain `pending` 60 s
    // later, call processPayment again with the same `key`.
    break;
  case PaymentRequiresAction(:final step?, :final stepId?):
    // confirm_otp, confirm_pin, confirm_phone, confirm_birthday, confirm_address
    final answer = await session.verifyStep(step, stepId, {'code': '123456'});
    if (!answer.success) print(WajubError.fromStep(answer).message);
  case PaymentRequiresAction(:final actionUrl?):
    // A provider page (3-D Secure, a wallet): open it, then follow the status.
    await session.handleRedirectAction(result);
    print(actionUrl);
  case PaymentRequiresAction():
    break;
  case PaymentFailed(:final error):
    // A refusal (error.code, error.message for the payer, error.retryable).
    print(error.message);
}

await for (final update in session.watchStatus()) {
  // PaymentProcessing on each change, then PaymentComplete or PaymentFailed.
  print(update);
}
```

`processPayment()` reads the answer as the sheet does, and returns every answer as an outcome: a refusal is
`PaymentFailed`, a payment without an answer or already running is `PaymentProcessing`; only a session that cannot
load throws. `Wajub.createSession(token, client: PayClient(httpClient: myClient))` sends the calls through your own
`http.Client`. The 1.5 calls — `process()`, `payMobileMoney()`,
`payWallet()`, `payCardHostedRedirect()`, `payCard()` / `payCardWithStripeElements()`,
`startClientSession()` / `completeClientSession()` — keep their 1.5 reading, where a confirmation step is
`unsupported_action`. Also: `status()` (`GET /pay/status`), `resendStep()`, `verifyThreeDs()` / `sendThreeDs()`
(sandbox), `handleRedirectAction()`, `cancel()`.

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

Code written for 1.5 keeps compiling — no type lost or gained a value, the deprecated entry points keep their
signatures — and the 1.5 calls keep their meaning, with the differences listed here.

- **`showWajubPaymentSheet` and `PaymentSheet` are deprecated** in favour of `presentWajubCheckout`. They keep
  working and now draw the new sheet, which follows redirects, approvals and confirmation steps itself:
  - `onResult` comes once, when the sheet closes, with `PaymentComplete`, `PaymentFailed`, or
    `PaymentProcessing` when it closed while a payment was running — no `PaymentRequiresAction` any more;
  - `onCancel` (and `PaymentSheet.onDismiss`) as before: the payer closed the sheet or cancelled, or the payment
    could not load;
  - `PaymentSheet.onPaymentStarted` as before: when the payer submits, before any answer;
  - an already paid payment now reports `PaymentComplete` instead of offering a form.

  ```dart
  // 1.5
  await showWajubPaymentSheet(context: context, session: session, onResult: handle, onCancel: cancelled);
  // 1.6
  final result = await presentWajubCheckout(context, PresentOptions(sessionToken: token));
  ```

- **Confirmation steps** (`confirm_otp`, `confirm_pin`, `confirm_phone`, `confirm_birthday`, `confirm_address`):
  the 1.5 calls still return `PaymentFailed` with `unsupported_action` for them. The new
  `WajubSession.processPayment()` returns `PaymentRequiresAction` with `action: ActionKind.confirm`, no
  `actionUrl`, and the new `step`, `stepId` and `hint`; `verifyStep()` sends the payer's answer.
- **`WajubError`**: the errors the SDK builds from API answers follow Wajub.js's catalogue — messages in the
  sheet's (or the device's) language, the API's own text in `apiMessage`, a `410` as an `invalidRequestError` (it
  was `authenticationError`), a decline code the catalogue does not know read as "This payment could not be
  completed…". `WajubError.fromHttp` keeps its 1.5 mapping.
- **`SessionTransaction.status`** reads `unknown` when an answer carries no status (1.5 read it as `pending`).
- **`MobileMoneyInput.phone`** is sent as you give it: give it in E.164 (`+237677123456`). The sheet builds it from
  what the payer types.
- **`watchStatus()`** keeps its results — `PaymentProcessing` on each change, `PaymentComplete`, `PaymentFailed`
  with the status as its code (`failed`, `cancelled`, `expired`) — and still watches until one. It now reads
  `GET /pay/status` instead of the whole session, follows a self-hosted Reverb as well as Pusher, ends with the
  `WajubError` on `401`, `403`, `404` and `410`, and reports an attempt that went back to `pending` without
  charging as `PaymentFailed` with the refusal's code (`insufficient_funds`…) instead of waiting forever.
- **Native minimums**: the new plugins need Java 17, `compileSdk` 35, Android `minSdk` 24 and iOS 13 with the
  versions current Flutter resolves (see [Requirements](#requirements)); declare the device signals in your store
  listings (see [Privacy](#privacy)).

## Privacy

To score fraud the way the web checkout does, every payment sends Wajub a few device signals
(`data._client` of `POST /pay/process`), and every call names the SDK:

- the device's time zone (`Africa/Douala`), its preferred language (`fr-CM`) and its languages
  (`Accept-Language`), the main screen's size in pixels and its colour depth;
- the SDK's name and version and the OS name and version (`X-Wajub-Client`, and the `User-Agent` suffix);
- an **install fingerprint**: the SHA-256 of a random identifier the SDK creates on first use and keeps in the
  app's private storage (`shared_preferences`, key `wajub_mobile.install_id`). It is not derived from any hardware
  or advertising identifier, and it is gone when the app is uninstalled or its data cleared.

The Mobile Money number, the email and the other fields the payer types go to Wajub only to make the payment.
The device signals and the install fingerprint go to Wajub (`api.wajub.com`) only. Besides Wajub, the sheet
connects to:

- **Stripe**, with the Stripe card form: the card goes from Stripe's own field to Stripe, which returns a token
  the sheet sends to Wajub; Stripe's SDK collects what Stripe documents for its fraud checks;
- the **realtime host** the session names (Pusher, or the merchant's own Reverb or Soketi): it receives the
  connection (the device's IP address) and the channel name, and sends the payment's status;
- the hosts of the **operators' logos** (the URLs the session gives): plain image requests;
- the **payment pages** of the providers, opened in the system browser when the payment needs one.

What to declare:

- **App Store privacy labels**: *Identifiers → Device ID* (the install fingerprint) and, for the payment itself,
  *Contact Info* (phone number, email) and *Financial Info* (payment info) — all *Used for: App Functionality*
  (Apple's purpose that covers fraud prevention), linked to the user when the payment is, not used for tracking.
- **Google Play data safety**: *Device or other IDs* (the install fingerprint), *Personal info* (phone number,
  email) and *Financial info* (purchase history), collected for *Fraud prevention, security, and compliance* and
  *App functionality*, shared with Wajub as your payment processor, encrypted in transit.

Your own app may collect more; this lists what this package adds.

## API URL

Production calls always go to `https://api.wajub.com`.

## Documentation & support

- Mobile SDK docs: [docs.wajub.com/libraries/sdks/mobile](https://docs.wajub.com/libraries/sdks/mobile)
- Server SDKs (create payments): [docs.wajub.com/libraries/sdks](https://docs.wajub.com/libraries/sdks)

## License

MIT — see [LICENSE](LICENSE).
