import 'models.dart';
import 'wajub_error.dart';

enum ActionKind { redirect, confirm, confirm3ds, pushApproval }

sealed class PaymentResult {
  const PaymentResult();
}

class PaymentComplete extends PaymentResult {
  const PaymentComplete(this.transaction);
  final SessionTransaction transaction;
}

class PaymentProcessing extends PaymentResult {
  const PaymentProcessing(this.transaction, {this.instruction});
  final SessionTransaction transaction;
  final String? instruction;
}

class PaymentRequiresAction extends PaymentResult {
  const PaymentRequiresAction({
    required this.action,
    this.actionUrl,
    required this.transaction,
  });

  final ActionKind action;
  final String? actionUrl;
  final SessionTransaction transaction;
}

class PaymentFailed extends PaymentResult {
  const PaymentFailed({required this.error, this.transaction});
  final WajubError error;
  final SessionTransaction? transaction;
}
