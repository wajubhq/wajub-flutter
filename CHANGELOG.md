# Changelog

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
  names the refused field when a refusal is about exactly one.

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
