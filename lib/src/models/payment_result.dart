import 'models.dart';
import 'wajub_error.dart';

/// What a [PaymentRequiresAction] asks for. A confirmation step is [confirm]
/// with [PaymentRequiresAction.step] set and no URL; the sandbox 3-D Secure
/// email code is [confirm3ds] with a [PaymentRequiresAction.stepId] and no
/// URL.
enum ActionKind { redirect, confirm, confirm3ds, pushApproval, clientSession }

/// What a payment in progress leaves the payer to do.
enum ProcessingKind {
  /// Approve the payment on the phone (Mobile Money).
  approval,

  /// Dial the code of [PaymentProcessing.instruction].
  ussd,

  /// Nothing: wait for the outcome.
  pending,
}

/// A confirmation step a payment can ask of the payer; answer it with
/// `WajubSession.verifyStep`.
enum PaymentStepKind {
  /// A one-time code.
  otp,

  /// The card PIN.
  pin,

  /// A phone number.
  phone,

  /// A date of birth, `YYYY-MM-DD`.
  birthday,

  /// A billing address: `address`, `city`, `state`, `zip_code`.
  address,
}

/// Where a payment stands after a `WajubSession` call, for apps that draw
/// their own payment screens.
sealed class PaymentResult {
  const PaymentResult();
}

class PaymentComplete extends PaymentResult {
  const PaymentComplete(this.transaction);
  final SessionTransaction transaction;
}

class PaymentProcessing extends PaymentResult {
  const PaymentProcessing(this.transaction, {this.instruction, this.kind = ProcessingKind.pending});
  final SessionTransaction transaction;

  /// The provider's instruction for the payer, in English.
  final String? instruction;
  final ProcessingKind kind;
}

class PaymentRequiresAction extends PaymentResult {
  const PaymentRequiresAction({
    required this.action,
    this.actionUrl,
    required this.transaction,
    this.clientSession,
    this.step,
    this.stepId,
    this.hint,
    this.timeoutSeconds,
  });

  final ActionKind action;

  /// The page to open in the system browser.
  final String? actionUrl;
  final SessionTransaction transaction;

  /// Set when [action] is [ActionKind.clientSession]; [actionUrl] is then
  /// its `hostedUrl`.
  final ClientSession? clientSession;

  /// The confirmation step to show (with [action] [ActionKind.confirm]);
  /// null otherwise.
  final PaymentStepKind? step;

  /// The id of a confirmation step, or of the sandbox 3-D Secure code: pass
  /// it to `WajubSession.verifyStep` or `WajubSession.verifyThreeDs`.
  final String? stepId;

  /// Where the code was sent, the step's instruction, or the email the 3-D
  /// Secure code was sent to. English, possibly empty.
  final String? hint;

  /// Sandbox 3-D Secure: seconds the code is valid for.
  final int? timeoutSeconds;
}

class PaymentFailed extends PaymentResult {
  const PaymentFailed({required this.error, this.transaction});
  final WajubError error;
  final SessionTransaction? transaction;
}
