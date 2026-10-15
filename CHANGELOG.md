# Changelog

## 1.6.0

Everything that changed since 1.1.1.

- `presentWajubCheckout(context, PresentOptions(sessionToken: …))` (also `Wajub.present`) presents a new native
  payment sheet and resolves exactly once, when it closes, with a `CheckoutResult`: `CheckoutComplete` (with a
  `PaymentSuccess`), `CheckoutProcessing`, `CheckoutFailed` or `CheckoutCancelled` (with its reason:
  `payer_cancelled`, `dismissed`, `host_gone`). Presenting a second sheet while one is open fails with
  `sheet_already_presented`; the next sheet can open as soon as the last one has closed, from `onComplete` too.
- `PresentOptions.callbacks` reports, in order, `onReady`, `onStateChange` (with the 17 `CheckoutState` values),
  `onLoadError`, `onPaymentStarted`, `onRedirect`, `onSuccess`, `onError`, `onCancel` and `onComplete`. A callback
  that throws does not break the sheet.
- Options: `locale` (French or English), `appearance`, `loader` (a skeleton or a spinner), `readyTimeout` (past
  it, "We couldn't load the payment" with Retry and `ready_timeout`), `returnUrl`, `mobileMoney` (the starting
  country, locked or not, and whether the number picks the operator), `cancelOnDismiss`, `autoCloseSuccess`, and
  `stripe` (`StripeOptions(appPublishableKey:)`: your app's own Stripe key, put back when the sheet closes).
- A payment already paid opens on the success screen and resolves `CheckoutComplete`; a failed, cancelled or
  expired one shows that it has ended (`session_terminal_failed`, `session_terminal_cancelled`,
  `session_terminal_expired`); one already in progress reopens where it was. A payment that cannot be loaded offers
  Retry (`load_error`).
- Mobile Money: one form for every operator of the payment, with the country, the operators and their logos, and
  the number formatted as it is typed. Numbers are read by each country's current numbering plan (a number typed
  the earlier way is taken in its current form), and the operator is recognised from the number: it is preselected
  until the payer picks one, and a number of another operator is refused before anything is sent (a warning only
  in sandbox). A sandbox session accepts the sandbox test numbers with the operator they test. After Pay, "Approve
  the payment on your phone" with the operator's instructions, or a USSD code to dial.
- Cards: Stripe's card form (it needs `FlutterFragmentActivity` on Android), the provider's secure page or its own
  checkout in the system browser with "Continue payment" to reopen it, and a test card form in sandbox. One-tap
  wallets are offered too. Your app never handles card numbers in live.
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
- `PresentOptions.appearance` sets the sheet's look (`Appearance`, or `Appearance.fromMap` of a JSON object):
  variables, presets, a light, dark or automatic colour scheme, your app's theme with `inherit`, and
  `disableAnimations`. What you leave unset comes from the merchant's branding, and white label hides "Secured by
  Wajub".
- `WajubError` carries the payer's message in the sheet's language (`localized()` for another one),
  `correlationId` (the reference to quote to Wajub support), `blockReference`, `attemptsRemaining`, `httpStatus`,
  `apiMessage` and `toMap()`; `param` names the refused field when a refusal is about exactly one. An ended
  payment is a non-retryable error (an `invalidRequestError` from the sheet and `WajubSession`, an
  `authenticationError` from `WajubError.fromHttp`), a server error an `apiError`, and a token that is not a
  payment is not retryable; they used to come back as retryable `paymentError`s. A decline code the SDK does not
  know reads "This payment could not be completed…".
- **`ActionKind` has a new value, `clientSession`**: an exhaustive `switch` over `ActionKind` needs a case for it.
  `PaymentRequiresAction` gains `clientSession`, `step`, `stepId`, `hint` and `timeoutSeconds`, and
  `PaymentProcessing` gains `kind` (`ProcessingKind`: approve on the phone, dial a code, or wait).
- An action the SDK cannot handle is `PaymentFailed` with code `unsupported_action`, instead of
  `PaymentProcessing`.
- For apps with their own UI, `WajubSession` gains `processPayment()`, which returns every answer as an outcome: a
  confirmation step as `PaymentRequiresAction` with `ActionKind.confirm` and its `step` and `stepId`; a refusal as
  `PaymentFailed`; a payment whose outcome is not known yet as `PaymentProcessing`. `verifyStep()` (whose answer
  gives the next step in `StepVerifyResult.next`, when there is one), `resendStep()`, `verifyThreeDs()`,
  `sendThreeDs()` and `status()` complete it, with `payWallet()` for one-tap wallets, `payCardHostedRedirect()`
  for a card paid on the provider's page, and `startClientSession()` / `completeClientSession()` (the new
  `ClientSession` model) for a card paid on the provider's own checkout. `PayClient` is exported:
  `Wajub.createSession(token, client: PayClient(httpClient: …))` uses your own `http.Client`.
- The other `WajubSession` calls (`process()`, `payMobileMoney()`, `payCard()`…) take new optional parameters and
  read a confirmation step as `unsupported_action`. `MobileMoneyInput.phone` is sent as you give it: give it in
  E.164 (`+237677123456`); `MobileMoneyInput.operator` names the operator of a channel that groups several.
- `watchStatus()` receives the payment's live updates, keeps checking the status for the whole watch, delivers a
  result when it changes and nothing after a final one, tries a failed read again, and ends with the `WajubError`
  when the payment can no longer be read. A refused attempt is `PaymentFailed` with the refusal's code. Cancelling
  the subscription stops it.
- `showWajubPaymentSheet` and `PaymentSheet` are deprecated in favour of `presentWajubCheckout`, and now draw the
  new sheet. `showWajubPaymentSheet` takes an `onCancel` callback and a `locale`; `PaymentSheet` takes a `locale`
  and an `onPaymentStarted` callback, called when the payer submits. `onResult` comes once, when the sheet closes,
  with `PaymentComplete`, `PaymentFailed`, or `PaymentProcessing` when it closed while a payment was running;
  `onCancel` (and `PaymentSheet.onDismiss`) when the payer closed it or cancelled, or the payment could not load.
  Closing `showWajubPaymentSheet` before submitting cancels the payment, never once a payment was submitted, and it
  opens over a sheet already open.
- `loadSession()` reads the session whatever the JSON type of its values: the merchant's branding values come in
  their text form in `SessionData.branding` (`"true"`, `"40"`), and an error page that is not JSON comes back as a
  `WajubError`. `SessionTransaction.status` reads `unknown` when an answer carries none, and a session whose amount
  is not a number throws a `FormatException`.
- New models: `PaymentStatusUpdate`, `StepVerifyResult`, `Branding` (`SessionData.merchantBranding`),
  `ChannelOperator` (`SessionChannel.operators`), `TransactionFee`, `TransactionCustomer`, `ClientSession`.
  `SessionTransaction` gains `fee`, `customer`, `receiptUrl`, `errorCode` and its timestamps; channels and
  operators gain `logoPng`; `SdkChannelConfig` gains `clientSession`.
- For fraud prevention, payments send basic device information and a random install identifier, which is not the
  advertising identifier. The README lists what to declare in the App Store privacy labels and Google Play's data
  safety form.
- Requirements: Flutter 3.24 or later; Java 17, `compileSdk` 35 and `minSdk` 24 on Android; iOS 13. On Flutter
  3.24 to 3.26, pin `flutter_stripe` 11.4 (see the README). The package now depends on `flutter_svg`,
  `shared_preferences`, `device_info_plus`, `flutter_timezone` and `web_socket_channel`, and drops a native
  dependency it no longer needs.

## 1.1.1

- Fixed the README links.
- Added the `repository` field to `pubspec.yaml`.

## 1.1.0

- Initial release of `wajub_mobile`: a native Flutter checkout SDK (Mobile Money, Stripe, no WebView).
