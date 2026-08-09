import '../models/models.dart';
import '../models/payment_result.dart';
import '../models/wajub_error.dart';

class RawProcessResponse {
  const RawProcessResponse({
    required this.code,
    required this.status,
    required this.message,
    this.action,
    this.transaction,
    this.confirmUrl,
    this.simulatorUrl,
  });

  final int code;
  final String status;
  final String message;
  final String? action;
  final SessionTransaction? transaction;
  final String? confirmUrl;
  final String? simulatorUrl;

  factory RawProcessResponse.fromJson(Map<String, dynamic> json) => RawProcessResponse(
        code: json['code'] as int? ?? 0,
        status: json['status'] as String? ?? '',
        message: json['message'] as String? ?? '',
        action: json['action'] as String?,
        transaction: json['transaction'] != null
            ? SessionTransaction.fromJson(json['transaction'] as Map<String, dynamic>)
            : null,
        confirmUrl: json['confirm_url'] as String?,
        simulatorUrl: json['simulator_url'] as String?,
      );
}

class PaymentMapper {
  static const _successStatuses = {'success', 'successful', 'succeeded', 'paid', 'complete'};

  static Map<String, dynamic> buildMobileMoneyRequest(MobileMoneyInput input) => {
        'phone': input.phone,
        'country': input.country.toUpperCase(),
      };

  static PaymentResult mapProcessResponse(RawProcessResponse body, String methodType) {
    final txn = body.transaction;
    if (txn == null) {
      return PaymentFailed(
        error: const WajubError(
          type: WajubErrorType.paymentError,
          message: 'Missing transaction',
          code: 'invalid_response',
        ),
      );
    }

    if (body.action == null && _successStatuses.contains(txn.status.toLowerCase())) {
      return PaymentComplete(txn);
    }

    switch (body.action) {
      case 'redirect':
        return PaymentRequiresAction(
          action: ActionKind.redirect,
          actionUrl: body.confirmUrl ?? body.simulatorUrl,
          transaction: txn,
        );
      case 'confirm':
        return PaymentRequiresAction(
          action: ActionKind.confirm,
          actionUrl: body.confirmUrl ?? body.simulatorUrl,
          transaction: txn,
        );
      case 'confirm_3ds':
        return PaymentRequiresAction(
          action: ActionKind.confirm3ds,
          actionUrl: body.confirmUrl ?? body.simulatorUrl,
          transaction: txn,
        );
    }

    if (methodType == 'mobile_money') {
      return PaymentRequiresAction(
        action: ActionKind.pushApproval,
        actionUrl: body.confirmUrl,
        transaction: txn.copyWith(
          processingContext: ProcessingContext(
            payerInstruction: txn.processingContext?.payerInstruction,
          ),
        ),
      );
    }

    return PaymentProcessing(txn, instruction: txn.processingContext?.payerInstruction);
  }

  static PaymentResult mapStatusToResult(String status, SessionTransaction transaction) {
    final normalized = status.toLowerCase();
    if (_successStatuses.contains(normalized)) {
      return PaymentComplete(transaction);
    }
    if (const {'failed', 'cancelled', 'expired'}.contains(normalized)) {
      return PaymentFailed(
        error: WajubError(
          type: WajubErrorType.paymentError,
          message: status,
          code: normalized,
        ),
        transaction: transaction,
      );
    }
    return PaymentProcessing(transaction);
  }
}
