import '../models/models.dart';
import '../models/wajub_error.dart';

/// Where the checkout is, under Wajub.js's 17 names (spec states.md §2).
enum CheckoutState {
  initiated('INITIATED'),
  collectingDetails('COLLECTING_DETAILS'),
  processing('PROCESSING'),
  otpRequired('OTP_REQUIRED'),
  pinRequired('PIN_REQUIRED'),
  phoneRequired('PHONE_REQUIRED'),
  birthdayRequired('BIRTHDAY_REQUIRED'),
  addressRequired('ADDRESS_REQUIRED'),
  threeDsRequired('3DS_REQUIRED'),
  ussdRequired('USSD_REQUIRED'),
  approvalRequired('APPROVAL_REQUIRED'),
  verifying('VERIFYING'),
  pending('PENDING'),
  success('SUCCESS'),
  failed('FAILED'),
  expired('EXPIRED'),
  cancelled('CANCELLED');

  const CheckoutState(this.wireName);

  /// Wajub.js's name: `COLLECTING_DETAILS`, `3DS_REQUIRED`…
  final String wireName;
}

/// Why the sheet closed as `cancelled`.
enum CancelReason {
  /// "Cancel payment" in the sheet.
  payerCancelled('payer_cancelled'),

  /// The payer closed the sheet (close button, swipe down, back) before any attempt.
  dismissed('dismissed'),

  /// The screen that presented the sheet went away before any attempt.
  hostGone('host_gone');

  const CancelReason(this.wireName);

  final String wireName;
}

/// A successful payment, as Wajub.js reports it. Confirm it server-side
/// (`GET /payments/{id}` or the `payment.succeeded` webhook) before
/// delivering.
class PaymentSuccess {
  const PaymentSuccess({
    required this.id,
    this.reference,
    required this.amount,
    required this.currency,
    required this.method,
    required this.timestamp,
    this.receiptUrl,
  });

  /// Wajub's payment id (`transaction.id`).
  final String id;

  /// The merchant's reference.
  final String? reference;

  /// What the payer paid (`amount_total`), major units.
  final double amount;
  final String currency;

  /// `mobile_money`, `card`, `wallet`, or `unknown` when it was already paid
  /// when the sheet opened.
  final String method;

  /// Always `success`.
  String get status => 'success';

  /// ISO 8601: `terminal_at`, else `updated_at`, else when the sheet saw it.
  final String timestamp;
  final String? receiptUrl;

  factory PaymentSuccess.from(SessionTransaction transaction, {required String method}) => PaymentSuccess(
        id: transaction.id,
        reference: transaction.reference.isEmpty ? null : transaction.reference,
        amount: transaction.payableAmount,
        currency: transaction.currency,
        method: method,
        timestamp: transaction.terminalAt ?? transaction.updatedAt ?? DateTime.now().toUtc().toIso8601String(),
        receiptUrl: transaction.receiptUrl,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'reference': reference,
        'amount': amount,
        'currency': currency,
        'method': method,
        'status': status,
        'timestamp': timestamp,
        'receipt_url': receiptUrl,
      };
}

/// What `presentWajubCheckout` resolves with, exactly once (states.md §4).
sealed class CheckoutResult {
  const CheckoutResult();

  /// `complete`, `processing`, `failed` or `cancelled`.
  String get status;

  /// The last transaction the sheet saw, when it saw one.
  SessionTransaction? get transaction;
}

/// The payment succeeded.
class CheckoutComplete extends CheckoutResult {
  const CheckoutComplete({required this.payment, this.transaction});

  final PaymentSuccess payment;
  @override
  final SessionTransaction? transaction;

  @override
  String get status => 'complete';
}

/// The sheet closed after a payment started and before its outcome — money
/// may still move: confirm it server-side.
class CheckoutProcessing extends CheckoutResult {
  const CheckoutProcessing({this.transaction});

  @override
  final SessionTransaction? transaction;

  @override
  String get status => 'processing';
}

/// The sheet closed on a failure, an ended or expired payment, or a load error.
class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed({required this.error, this.transaction});

  final WajubError error;
  @override
  final SessionTransaction? transaction;

  @override
  String get status => 'failed';
}

/// "Cancel payment", or the sheet closed before any payment started.
class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled({required this.reason, this.redirectUrl});

  final CancelReason reason;

  /// The merchant's callback `POST /pay/cancel` returned, when it was called.
  final String? redirectUrl;

  @override
  SessionTransaction? get transaction => null;

  @override
  String get status => 'cancelled';
}

/// `onReady`: the first real screen is drawn.
class ReadyEvent {
  const ReadyEvent({
    required this.sessionId,
    required this.environment,
    required this.amount,
    required this.currency,
    required this.methods,
  });

  /// `transaction.id`.
  final String sessionId;

  /// `sandbox` or `live`.
  final String environment;
  final double amount;
  final String currency;

  /// The slugs of the channels shown.
  final List<String> methods;
}

/// `onStateChange`.
class StateChangeEvent {
  const StateChangeEvent({required this.state, this.method});

  final CheckoutState state;

  /// `mobile_money`, `card`, `wallet`, or `unknown` before one is chosen.
  final String? method;
}

/// `onPaymentStarted`: from now on, closing the sheet resolves `processing`.
class PaymentStartedEvent {
  const PaymentStartedEvent({required this.method, required this.channel});

  final String method;
  final String channel;
}

/// `onRedirect`: right before a page opens in the system browser.
class RedirectEvent {
  const RedirectEvent({required this.url});

  final String url;

  /// Always `GET`.
  String get method => 'GET';
}

/// `onCancel`.
class CancelEvent {
  const CancelEvent({required this.reason, this.redirectUrl});

  final CancelReason reason;
  final String? redirectUrl;
}

/// What the sheet reports while it runs, all optional, in this order for a
/// payment: [onReady] → [onStateChange]… → [onPaymentStarted], [onRedirect] →
/// [onSuccess] / [onError] / [onCancel] → [onComplete], exactly once. A
/// callback that throws does not break the sheet.
class CheckoutCallbacks {
  const CheckoutCallbacks({
    this.onReady,
    this.onStateChange,
    this.onLoadError,
    this.onPaymentStarted,
    this.onRedirect,
    this.onSuccess,
    this.onError,
    this.onCancel,
    this.onComplete,
  });

  final void Function(ReadyEvent event)? onReady;
  final void Function(StateChangeEvent event)? onStateChange;

  /// The sheet could not offer a payment: `session_not_found`,
  /// `session_terminal_*`, `load_error`, `ready_timeout`, `no_payment_method`.
  final void Function(WajubError error)? onLoadError;
  final void Function(PaymentStartedEvent event)? onPaymentStarted;
  final void Function(RedirectEvent event)? onRedirect;
  final void Function(PaymentSuccess payment)? onSuccess;

  /// Every failure the payer sees, retryable ones included.
  final void Function(WajubError error)? onError;
  final void Function(CancelEvent event)? onCancel;

  /// The value `presentWajubCheckout` resolves with.
  final void Function(CheckoutResult result)? onComplete;
}
