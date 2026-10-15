# Changelog

## 1.6.0

- `presentWajubCheckout(context, PresentOptions(sessionToken: …))` (also `Wajub.present`) presents a new native
  payment sheet and resolves exactly once, when it closes, with a `CheckoutResult`: `CheckoutComplete` (with a
  `PaymentSuccess`), `CheckoutProcessing`, `CheckoutFailed` or `CheckoutCancelled` (with its reason:
  `payer_cancelled`, `dismissed`, `host_gone`). Presenting a second sheet while one is open fails with
  `sheet_already_presented`; the next sheet can open as soon as the last one has closed, from `onComplete` too.
- `PresentOptions.callbacks` reports, in order, `onReady`, `onStateChange` (with the 17 `CheckoutState` values),
  `onLoadError`, `onPaymentStarted`, `onRedirect`, `onSuccess`, `onError`, `onCancel` and `onComplete`. A callback
  that throws does not break the sheet.
- Options: `locale`, `appearance`, `loader` (a skeleton or a spinner), `readyTimeout` (past it, "We couldn't load
  the payment" with Retry and `ready_timeout`), `returnUrl`, `mobileMoney` (the starting country, locked or not,
  and whether the number picks the operator), `cancelOnDismiss`, `autoCloseSuccess`, and `stripe`
  (`StripeOptions(appPublishableKey:)`: your app's own Stripe key, put back when the sheet closes).
- A payment already paid opens on the success screen and resolves `CheckoutComplete`; a failed, cancelled or
  expired one shows that it has ended (`session_terminal_failed`, `session_terminal_cancelled`,
  `session_terminal_expired`); one already in progress reopens where it was. A payment that cannot be loaded offers
  Retry (`load_error`).
- Mobile Money: one form for every operator of the payment, with the country, the operators and their logos, and
  the number formatted as it is typed. The number preselects its operator until the payer picks one, and a number
  of another operator is refused before anything is sent (a warning only in sandbox). After Pay, "Approve the
  payment on your phone" with the operator's instructions, or a USSD code to dial.
- Cards: Stripe's card form (it needs `FlutterFragmentActivity` on Android), the provider's secure page in the
  system browser with "Continue payment" to reopen it, and a test card form in sandbox. Your app never handles card
  numbers in live.
- Confirmation steps — a one-time code, the card PIN, a phone number, a date of birth, a billing address, and the
  sandbox 3-D Secure code — each have their own screen, with the attempts left and "Resend". A step can lead to
  another step or to a provider page, and a step can complete the payment at once.
- Closing the sheet: while the payment loads, `cancelled`; before any payment, `cancelled` and the payment is
  cancelled (unless `cancelOnDismiss` is `false`); while a payment is under way, `processing`, and the payment keeps
  running; on the failure screen, `failed`, and the payment is cancelled when it still can be. "Cancel payment" is
  offered only while no payment is under way. When the page that presented the sheet goes away, the sheet resolves
  without cancelling anything.
- The sheet never shows a failure when the outcome is unknown: it shows "Payment in progress", and closing it then
  resolves `processing`. Paying again after a connection error never charges twice.
- `WajubError` carries the payer's message in the sheet's language (`localized()` for another one),
  `correlationId` (the reference to quote to Wajub support), `blockReference`, `attemptsRemaining`, `httpStatus`,
  `apiMessage` and `toMap()`. An ended payment is an `invalidRequestError`; a decline code the SDK does not know
  reads "This payment could not be completed…". `WajubError.fromHttp` keeps its 1.5 mapping.
- `PresentOptions.appearance` takes the appearance object of Wajub's web components (`Appearance`, or
  `Appearance.fromMap` of the same JSON): variables, presets, a light, dark or automatic colour scheme, your app's
  theme with `inherit`, and `disableAnimations`. What you leave unset comes from the merchant's branding, and white
  label hides "Secured by Wajub".
- Logos that cannot be drawn fall back to their PNG version, then to the operator's badge.
- For apps with their own UI, `WajubSession.processPayment()` returns every answer as an outcome: a confirmation
  step as `PaymentRequiresAction` with `ActionKind.confirm` and the new `step`, `stepId` and `hint`; a refusal as
  `PaymentFailed`; a payment whose outcome is unknown as `PaymentProcessing`. `verifyStep()` (whose answer gives
  the next step in `StepVerifyResult.next`, when there is one), `resendStep()`, `verifyThreeDs()`, `sendThreeDs()`
  and `status()` complete it. `PayClient` is exported: `Wajub.createSession(token, client: PayClient(httpClient:
  …))` uses your own `http.Client`.
- `showWajubPaymentSheet` and `PaymentSheet` are deprecated in favour of `presentWajubCheckout`. They keep their
  callbacks and now draw the new sheet: `onResult` comes once, when the sheet closes, with `PaymentComplete`,
  `PaymentFailed`, or `PaymentProcessing` when it closed while a payment was running; `onCancel` (and
  `PaymentSheet.onDismiss`) when the payer closed it or cancelled, or the payment could not load;
  `PaymentSheet.onPaymentStarted` when the payer submits. An already paid payment reports `PaymentComplete`. As in
  1.5, `showWajubPaymentSheet` opens over a sheet already open and never cancels a payment once one was submitted.
- The 1.5 calls (`process()`, `payMobileMoney()`, `payCard()`…) keep their results, a confirmation step being
  `unsupported_action` there. `MobileMoneyInput.phone` is sent as you give it: give it in E.164
  (`+237677123456`). `watchStatus()` keeps its results and watches until one, ends with the `WajubError` when the
  payment can no longer be read, and reports a refused attempt as `PaymentFailed` with the refusal's code instead
  of waiting forever. `SessionTransaction.status` reads `unknown` when an answer carries none (1.5 read
  `pending`).
- New models: `PaymentStatusUpdate`, `StepVerifyResult`, `Branding` (`SessionData.merchantBranding`),
  `ChannelOperator` (`SessionChannel.operators`), `TransactionFee`, `TransactionCustomer`. `SessionTransaction`
  gains `fee`, `customer`, `receiptUrl`, `errorCode` and its timestamps; channels and operators gain `logoPng`.
- For fraud prevention, payments send basic device information and a random install identifier, which is not the
  advertising identifier. The README lists what to declare in the App Store privacy labels and Google Play's data
  safety form.
- Requirements: Flutter 3.24 or later; Java 17, `compileSdk` 35 and `minSdk` 24 on Android; iOS 13. On Flutter
  3.24 to 3.26, pin `flutter_stripe` 11.4 (see the README). The package now depends on `flutter_svg`,
  `shared_preferences`, `device_info_plus`, `flutter_timezone` and `web_socket_channel`, and no longer on
  `pusher_channels_flutter`.

## 1.5.1

- `WajubSession.loadSession` no longer throws on sessions whose merchant branding holds booleans and integers.
  `SessionData.branding` keeps those values in their text form (`"true"`, `"40"`).
- Amounts and flags are read whatever their JSON type, the French channel name is read, and an error page that is
  not JSON comes back as a `WajubError` rather than a `FormatException`.

## 1.5.0

- `showWajubPaymentSheet` reports a sheet the payer closes (the close button, a swipe down, the back button)
  through a new `onCancel` callback. When nothing had been submitted yet, the payment is also cancelled; when a
  payment was under way it is left alone, since a Mobile Money approval can still land.
- The payment sheet speaks French: `showWajubPaymentSheet(locale: 'fr')` asks for it, and without `locale` the
  sheet follows the payment's own language. `PaymentSheet` takes the same `locale`, and an `onPaymentStarted`
  callback.
- An ended payment is an `authenticationError` with `retryable: false`, and a server error an `apiError`; both used
  to come back as a retryable `paymentError`. `WajubError.param` names the refused field when a refusal is about
  exactly one. A token that is not a payment is not retryable either.
- `watchStatus()` now receives the payment's live updates, keeps checking the status for the whole watch,
  delivers a result when it changes and nothing after a final one, and tries a failed read again rather than
  ending the stream. Cancelling the subscription stops it.

## 1.4.0

- One-tap wallets: `WajubSession.payWallet(channelSlug:)`, and `PaymentSheet` shows them in a new "Wallet" tab.

## 1.3.0

- Cards paid on the provider's own page: `payCardHostedRedirect(channelSlug:, billing:)` sends the contact fields
  the provider needs, and `PaymentSheet` asks the payer for them before opening the page.

## 1.2.0

- Cards on the provider's own checkout: `WajubSession.startClientSession` / `completeClientSession`, the new
  `ClientSession` model, `ActionKind.clientSession`, `PaymentRequiresAction.clientSession` and
  `SdkChannelConfig.clientSession`.
- `PaymentSheet`'s card tab picks its form from the payment's configuration, and shows submit errors (such as a
  missing email) inline.
- An action the SDK cannot handle is `PaymentFailed` with code `unsupported_action` instead of
  `PaymentProcessing`.

## 1.1.1

- Fixed the README links.
- Added the `repository` field to `pubspec.yaml`.

## 1.1.0

- Initial release of `wajub_mobile`: a native Flutter checkout SDK (Mobile Money, Stripe, no WebView).
