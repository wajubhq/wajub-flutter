# Changelog

## 1.6.0

- `presentWajubCheckout(context, PresentOptions(sessionToken: …))` (also `Wajub.present`) presents a new native
  sheet that follows the web checkout and Wajub.js 1.8, and resolves exactly once, when it closes, with a
  `CheckoutResult`: `CheckoutComplete` (with a `PaymentSuccess`), `CheckoutProcessing`, `CheckoutFailed` or
  `CheckoutCancelled` (with its reason: `payer_cancelled`, `dismissed`, `host_gone`). Presenting a second sheet
  while one is open fails with `sheet_already_presented`.
- `PresentOptions.callbacks` reports Wajub.js's events in order: `onReady`, `onStateChange` (with Wajub.js's 17
  `CheckoutState` names), `onLoadError`, `onPaymentStarted`, `onRedirect`, `onSuccess`, `onError`, `onCancel`,
  `onComplete`. A callback that throws no longer breaks the sheet.
- The sheet loads the session and the SDK configuration in parallel behind a skeleton (or a spinner,
  `loader`), and reports `ready_timeout` with a Retry button when the payment has not loaded after `readyTimeout`
  (15 s). A load that fails on the network offers Retry too. An already paid payment opens on the success screen
  instead of a form, a failed, cancelled or expired one on a "this payment has ended" notice
  (`session_terminal_failed`, `session_terminal_cancelled`, `session_terminal_expired`), and one still processing
  on the approval or waiting screen it was on. Both expired-session `410`s read `session_terminal_expired`.
- Mobile Money follows the web checkout: a country selector, the operators of the `cm.mobile` aggregate listed one
  by one with their logos (a brand badge when a logo is missing or does not load), operator detection from the
  number's prefix that preselects until the payer picks by hand, a refusal of a number of another operator before
  any call (a warning only in sandbox), the number formatted as typed and sent in E.164 (Côte d'Ivoire keeps its
  0), and the `operator` hint on aggregates. `PresentOptions.mobileMoney` sets the starting country, locks it, or
  lets the number pick the operator (`OperatorMode.detect`). The tables come from the shared
  `assets/wajub/mobile-money.json`.
- After the payment is sent, "Approve the payment on your phone" shows the number and the provider's instruction
  (under "Instructions" in French), and a USSD code when the provider asks to dial one.
- The confirmation steps a provider asks for — OTP, card PIN, phone, date of birth, billing address — have their
  own screens and endpoints, with the attempts left and "Resend" after 60 seconds, instead of failing with
  `unsupported_action`. The sandbox 3-D Secure email code has a screen too, including the wrong-code answer the
  API sends as a 500 today. For apps with their own UI, the new `WajubSession.processPayment()` returns them as
  `PaymentRequiresAction` with `ActionKind.confirm`, no URL, and the new `step`, `stepId` and `hint`;
  `verifyStep()`, `resendStep()`, `verifyThreeDs()` and `sendThreeDs()` answer them. `processPayment()` returns
  every answer as an outcome: a refusal as `PaymentFailed`, a payment without an answer or already running as
  `PaymentProcessing`. The 1.5 calls (`process()`, `payMobileMoney()`…) keep reading the steps as
  `unsupported_action`.
- Cards: the test-card form in sandbox, the contact fields a client session needs (the customer's email filled
  in), and a "Continue payment" button that reopens a provider's page. No card number is ever sent in live. The
  payer coming back to the app reads the status at once, and completes an open client session on every return.
  A Stripe card counts as a payment under way from the press of Pay: closing the sheet while Stripe tokenizes
  resolves `processing` and sends nothing.
- `PresentOptions.appearance` takes Wajub.js's appearance object (`Appearance`, or `Appearance.fromMap` of the
  same JSON): `variables`, the top-level keys, the `stripe`, `night`, `flat` and `none` presets, `colorScheme`
  light, dark or auto (following the phone live), `inherit` to read your app's theme, and `disableAnimations`. The
  merchant's dashboard branding fills what you do not set, with the web checkout's default palettes in light and
  dark, a fallback for a primary colour too pale to read, and `white_label` hiding "Secured by Wajub".
- Realtime updates connect where the session says, a self-hosted Reverb or Soketi as well as Pusher, over a
  plain WebSocket; `PresentOptions.realtime` overrides the host, port and TLS, or turns realtime off. The status
  is also polled every 5 s (15 s while the socket is joined), slower after 2 minutes without a change, backing off
  on errors, for at most 15 minutes from the press of Pay timed on the phone's monotonic clock (never against
  `expires_at` or the device's time), and stops on `401`, `403`, `404` and `410`. `pusher_channels_flutter` is no
  longer a dependency.
- Every call has a 10 s connect timeout and a 30 s (60 s for payments) request timeout. Reads are retried on
  network errors, timeouts, `408`, `429` (when `Retry-After` is at most 10 s) and `5xx`; `POST /pay/process` is
  retried on network errors, timeouts, `502`, `503` and `504` with the same body and `Idempotency-Key` (a UUID per
  press of Pay). A payment whose answer never came (a network error, a timeout, a `5xx`) is followed as pending,
  never shown as failed; if the status still reads a plain `pending` 60 s after its last try, the request never
  arrived: the form comes back with a connection error, and the next Pay sends the same `Idempotency-Key`, so a
  request that did arrive is replayed, not charged twice. The 60 s count from the call's own last try (a payment or
  a client session) on the phone's monotonic clock. A refusal the status reports meanwhile is shown as that
  refusal; one an earlier try left, or that the payment carried when the sheet opened, is not. An answer without a status, or a `2xx` without its transaction, is
  never read as a refusal. A `400` reads the status: an outcome is shown, a `pending` fails with
  `not_processable`, and a `processing` or unreadable status is followed. A step verify without an answer keeps
  the step and reads the status. While a client session completes (once per return to the app), a refusal the
  status reads meanwhile waits for the last completion, whose success always wins.
- Every call sends `X-Wajub-Client` (`wajub-flutter/1.6.0 (android 15)`), a fresh `X-Request-Id`, the device's
  languages in `Accept-Language`, and a `User-Agent` ending with `X-Wajub-Client`; payments send the device
  signals the API's risk scoring reads (`data._client`: time zone, language, screen, colour depth, and a
  fingerprint derived from a random id kept for the install; a failed read of that id never replaces it).
- `WajubError` gains Wajub.js's catalogue: `message` is the payer's text in the sheet's language, the API's own in
  `apiMessage`, with `httpStatus`, `correlationId` (the response's `X-Request-Id`), `blockReference`,
  `attemptsRemaining`, `toMap()` and `WajubError.fromStep()`. The errors built from API answers type a `410` as an
  `invalidRequestError`, and read an unknown decline code as "This payment could not be completed…";
  `WajubError.fromHttp` keeps its 1.5 mapping.
- The Altcha proof of work is solved in the background and sent with the payment when the API asks for one; each
  attempt sends the solution of a new challenge, and no payment leaves without one (a challenge that cannot be
  fetched is a connection error the payer can retry; one that could not be solved is replaced on the next Pay).
- `POST /pay/cancel` is sent only while the payment's last known status is `pending` and no attempt is undecided,
  from the press of Pay to a definitive answer: "Cancel payment" is not offered while the payer approves, dials a
  USSD code, confirms a step or waits, and closing the sheet there resolves `processing` without a call. After a
  refusal the payment is pending again and can be cancelled; closing its failure screen (its Close button too)
  resolves `failed` and also cancels it, so the order is released. An attempt the API accepted is never cancelled
  before a definitive answer, even on a failure screen such as `unsupported_action`. Closing the sheet while the payment loads resolves
  `cancelled` without a call; once the session answered, its status decides. While a cancel runs, Pay, Close, back
  and a swipe down wait for it; a refused cancel shows what the status says, resolves `processing` when the status
  cannot be read, and settles at once if the sheet went away meanwhile.
- Only the payer's own ways out — the close button, a swipe down, back, the barrier — cancel an unpaid payment on a
  dismiss. A page of your app popping or replacing the sheet settles it as `host_gone` and never cancels, and a
  sheet presented from a context no longer mounted resolves `host_gone` at once. A new sheet may open as soon as
  the last one is gone, and a success screen closes even under a page your app pushed.
- `showWajubPaymentSheet` and `PaymentSheet` are deprecated. They keep their callbacks and their 1.5 meaning —
  `PaymentSheet.onPaymentStarted` when the payer submits, `onCancel`/`onDismiss` when the payment could not load,
  `PaymentProcessing` with the last transaction known for a payment still running, a sheet stacked over an open
  one rather than refused — and now draw the new sheet, reporting the outcome once the sheet closes (see the
  README's migration notes).
- `PresentOptions.stripe` (`StripeOptions(appPublishableKey:)`) puts your app's own Stripe key back when the sheet
  closes after its card form, which sets the merchant's.
- `PayClient` is exported, so `Wajub.createSession(token, client: PayClient(httpClient: …))` can send the calls
  through your own `http.Client`.
- `WajubSession.watchStatus()` keeps 1.5's results (the status as the code of a `PaymentFailed`) and watches
  until an outcome; an attempt that goes back to `pending` without charging now ends it with the refusal's code.
- The README lists the native minimums the new plugins bring (Java 17, `compileSdk` 35, Android `minSdk` 24, iOS
  13 with current versions) and what the device signals mean for the App Store and Google Play privacy forms.
  Flutter 3.24 stays the oldest supported (`environment: flutter: '>=3.24.0'`), now tested in CI: `flutter_timezone`
  4 and 5 are both accepted (Flutter 3.24 can only resolve 4), and an app on Flutter 3.24 to 3.26 pins
  `flutter_stripe` 11.4, whose 11.5 calls Flutter 3.27 APIs although it claims any Flutter 3.
- New public models: `PaymentStatusUpdate` (`WajubSession.status()`), `StepVerifyResult`, `Branding`
  (`SessionData.merchantBranding`), `ChannelOperator` (`SessionChannel.operators`), `TransactionFee`,
  `TransactionCustomer`, `AltchaChallenge`; `SessionTransaction` reads `fee`, `customer`, `receiptUrl`,
  `errorCode` and its timestamps, reads a missing status as `unknown` (1.5 read `pending`), and refuses a session
  whose `amount` is not a number.

## 1.5.1

- `WajubSession.loadSession` no longer throws on every session. The merchant branding the API
  sends holds booleans and integers (`white_label`, `overlay_intensity`), and each value was cast to
  a string. `SessionData.branding` keeps its type, with those values in their text form (`"true"`,
  `"40"`).
- Amounts, ports and flags are read whatever their JSON type (number or numeric string), the
  French channel name is read from `name.fr`, where the API puts it, and an error page that is not
  JSON (a proxy's `502`) comes back as a `WajubError` rather than a `FormatException`.

## 1.5.0

- `showWajubPaymentSheet` reports a sheet the payer closes (the close button, a swipe down, the
  back button) through a new `onCancel` callback. Closing used to say nothing. When nothing had been
  submitted yet, the payment is also cancelled on Wajub (`POST /pay/cancel`); when an attempt was
  under way it is left alone, since a Mobile Money approval can still land.
- The payment sheet speaks French: `showWajubPaymentSheet(locale: 'fr')` asks for it, and without
  `locale` the sheet follows the payment's own language. English otherwise. `PaymentSheet` takes the
  same `locale`, and an `onPaymentStarted` callback.
- An ended session (`410`) is an `authenticationError` with `retryable: false`, and a server error
  (`5xx`) an `apiError`. Both used to come back as a retryable `paymentError`. `WajubError.param`
  names the refused field when a refusal is about exactly one. A token that is not a session
  (`401`, `404`) is not retryable either: no retry of the same token can succeed.
- `watchStatus()` hears the payment's realtime updates. It subscribed with your `reference`, a
  channel the API never publishes on; it now subscribes with the payment's Wajub id
  (`transaction.id`), as the API, the React Native SDK and the Android SDK do. The status events
  are also read as the Android and iOS plugins deliver them, a JSON string, where only a map was
  read.
- `watchStatus()` keeps polling for the whole watch, next to the socket, so a missed event costs at
  most one interval; it used to stop polling once the socket connected. A result is delivered when
  it changes, not at every read, and nothing follows a final one. A read that fails is tried again,
  later each time (at most a minute apart), where it ended the stream; an error the API will always
  give, an ended session (`410`) for instance, still ends it. Cancelling the subscription stops the
  reads.

## 1.4.0

- One-tap wallet channels (channel `type: wallet`, sdk-config `form` with no `requiredFields` —
  e.g. Djamo `ci.djamo` / `sn.djamo`): `WajubSession.payWallet(channelSlug:)` and
  `PaymentMapper.isRedirectWalletChannel`; `PaymentSheet` shows them in a new "Wallet" tab.

## 1.3.0

- `hosted_redirect` cards now cover Kkiapay, FedaPay, PayDunya and CinetPay too:
  `payCardHostedRedirect(channelSlug:, billing:)` sends the contact/billing fields the channel's
  `requiredFields` lists (`PaymentMapper.hostedCardFields` — email, or CinetPay's name/phone/
  address/city/country/zip), and `PaymentSheet` asks the payer for them before redirecting.
- Adyen cards go through the client-session flow (Pay by Link) — no SDK change needed, the
  backend now flags them `clientSession: true`.

## 1.2.0

- Card via Paystack / Flutterwave: `WajubSession.startClientSession` / `completeClientSession`
  (`POST /pay/client-session[/complete]`), new `ClientSession` model, `ActionKind.clientSession`,
  `PaymentRequiresAction.clientSession`, `SdkChannelConfig.clientSession`.
- `PaymentSheet` card tab picks its UI from the sdk-config flavor: client session (PSP-hosted
  checkout, optional email), `stripe_elements`, `hosted_redirect` (`payCardHostedRedirect`);
  `adyen_custom_card` is shown as unavailable. Submit errors (e.g. email required) show inline.
- Unhandled `action` values now map to `PaymentFailed` with code `unsupported_action` instead of
  `PaymentProcessing`; the mobile-money push-approval fallback only applies when there is no action.

## 1.1.1

- Fixed README links so they resolve outside the monorepo (standalone repo/pub.dev listing).
- Added `repository` field to `pubspec.yaml`.

## 1.1.0

- Initial release of `wajub_mobile` — native Flutter checkout SDK (Mobile Money, Stripe, no WebView).
