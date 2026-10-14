import 'models.dart';
import 'wajub_error.dart';

/// What a [PaymentRequiresAction] asks for. A confirmation step
/// (`confirm_otp`…) is [confirm] with [PaymentRequiresAction.step] set and no
/// URL; the sandbox 3-D Secure email code is [confirm3ds] with a
/// [PaymentRequiresAction.stepId] and no URL.
enum ActionKind { redirect, confirm, confirm3ds, pushApproval, clientSession }

/// What a payment in progress leaves the payer to do.
enum ProcessingKind {
  /// Approve the push on their phone (Mobile Money).
  approval,

  /// Dial the USSD code of [PaymentProcessing.instruction].
  ussd,

  /// Nothing: wait for the outcome.
  pending,
}

/// A confirmation step a provider can ask of the payer (`confirm_otp`…),
/// each verified on its own endpoint: `POST /pay/{name}/verify`.
enum PaymentStepKind {
  otp,
  pin,
  phone,
  birthday,
  address;

  /// The id key of the step's `202` and of its verify body: `otp_id`.
  String get idKey => '${name}_id';

  /// The key of the step's text in the `202`: `otp_masked_contact`,
  /// `pin_instruction`…
  String get hintKey => this == otp ? 'otp_masked_contact' : '${name}_instruction';

  /// `confirm_otp` → [otp]; anything else → null.
  static PaymentStepKind? fromAction(String? action) {
    for (final kind in values) {
      if (action == 'confirm_${kind.name}') return kind;
    }
    return null;
  }
}

/// The outcome of one `/pay/process` (or client session) answer, for apps
/// that draw their own UI. The payment sheet goes on from here by itself.
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

  /// `processing_context.payer_instruction`, English.
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

  /// The page to open in the system browser: `confirm_url`, or the client
  /// session's `hosted_url`.
  final String? actionUrl;
  final SessionTransaction transaction;

  /// Set when [action] is [ActionKind.clientSession]; [actionUrl] is then
  /// its `hostedUrl`.
  final ClientSession? clientSession;

  /// The confirmation step to show (`confirm_otp`… with [action]
  /// [ActionKind.confirm]); null otherwise.
  final PaymentStepKind? step;

  /// A confirmation step's id (`otp_id`…), or the sandbox 3-D Secure
  /// `three_ds_id`: send it back to the step's verify call.
  final String? stepId;

  /// `otp_masked_contact`, a step's `*_instruction`, or the 3-D Secure
  /// `masked_email`. English, possibly empty.
  final String? hint;

  /// Sandbox 3-D Secure: seconds the code is valid for.
  final int? timeoutSeconds;
}

class PaymentFailed extends PaymentResult {
  const PaymentFailed({required this.error, this.transaction});
  final WajubError error;
  final SessionTransaction? transaction;
}
