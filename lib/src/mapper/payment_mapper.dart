import '../models/json_read.dart';
import '../models/models.dart';
import '../models/payer_otp.dart';
import '../models/sdk_flavor.dart';
import '../models/payment_result.dart';
import '../models/step_keys.dart';
import '../models/wajub_error.dart';

/// A 2xx answer of `/pay/process`, `/pay/client-session` or
/// `/pay/client-session/complete`, as sent.
class RawProcessResponse {
  const RawProcessResponse({
    required this.code,
    required this.status,
    required this.message,
    this.action,
    this.transaction,
    this.confirmUrl,
    this.simulatorUrl,
    this.clientSession,
    this.httpStatus,
    this.threeDsId,
    this.threeDsMethod,
    this.maskedEmail,
    this.threeDsTimeout,
    this.stepIds = const {},
    this.stepHints = const {},
    this.payerOtp,
  });

  final int code;
  final String status;

  /// Never decide on it: a success may say "Confirm the transaction on your
  /// phone.".
  final String message;
  final String? action;
  final SessionTransaction? transaction;
  final String? confirmUrl;
  final String? simulatorUrl;

  /// Set on `action: "client_session"` (POST /pay/client-session).
  final ClientSession? clientSession;

  /// The HTTP status the API answered with (`200`, `202`).
  final int? httpStatus;

  /// `action: "confirm_3ds"` in sandbox: the email code challenge.
  final String? threeDsId;
  final String? threeDsMethod;
  final String? maskedEmail;
  final int? threeDsTimeout;

  /// `otp_id`, `pin_id`… by step.
  final Map<PaymentStepKind, String> stepIds;

  /// `otp_masked_contact`, `pin_instruction`… by step.
  final Map<PaymentStepKind, String> stepHints;

  /// `action: "payer_otp"`: the code the payer generates in the operator's
  /// menu, why it is asked, the tries left.
  final PayerOtpInstructions? payerOtp;

  factory RawProcessResponse.fromJson(Map<String, dynamic> json, {int? httpStatus}) => RawProcessResponse(
        code: readInt(json['code']) ?? httpStatus ?? 0,
        status: readString(json['status']) ?? '',
        message: readString(json['message']) ?? '',
        action: readText(json['action']),
        transaction:
            readMap(json['transaction']) != null ? SessionTransaction.fromJson(readMap(json['transaction'])!) : null,
        confirmUrl: readText(json['confirm_url']),
        simulatorUrl: readText(json['simulator_url']),
        clientSession:
            readMap(json['client_session']) != null ? ClientSession.fromJson(readMap(json['client_session'])!) : null,
        httpStatus: httpStatus,
        threeDsId: readText(json['three_ds_id']),
        threeDsMethod: readText(json['three_ds_method']),
        maskedEmail: readText(json['masked_email']),
        threeDsTimeout: readInt(json['three_ds_timeout']),
        stepIds: {
          for (final kind in PaymentStepKind.values)
            if (readText(json[kind.idKey]) != null) kind: readText(json[kind.idKey])!,
        },
        stepHints: {
          for (final kind in PaymentStepKind.values)
            if (readText(json[kind.hintKey]) != null) kind: readText(json[kind.hintKey])!,
        },
        payerOtp: PayerOtpInstructions.fromJson(json['payer_otp']),
      );
}

class PaymentMapper {
  static const _successStatuses = {'success', 'successful', 'succeeded', 'paid', 'complete'};

  /// Error code for an `action` this SDK can't perform, or one missing what
  /// it needs (a `redirect` without `confirm_url`, a `confirm_otp` without
  /// `otp_id`).
  static const unsupportedActionCode = 'unsupported_action';

  /// A `wallet` channel payable with a single tap — nothing to collect, and
  /// the answer is a redirect to the wallet's own page or app. Wallets that
  /// need fields of their own are left out.
  static bool isRedirectWalletChannel(SessionChannel channel, SdkChannelConfig? config) =>
      channel.type.toLowerCase() == 'wallet' &&
      config != null &&
      config.available &&
      config.sdk == SdkFlavor.form &&
      config.requiredFields.isEmpty;

  /// Contact and billing fields a card provider's page may still need before
  /// it opens — the configuration lists the missing ones in
  /// `required_fields` (an email, or a name, phone and address).
  static const hostedCardFields = [
    'first_name',
    'last_name',
    'email',
    'phone',
    'address',
    'city',
    'country',
    'state',
    'zip_code',
  ];

  /// A plausible email address: something, an `@`, a dotted domain.
  static bool isEmail(String value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

  /// `data` for a hosted-redirect card charge — flat keys, as sdk-config
  /// names them.
  static Map<String, dynamic> buildHostedCardRequest(Map<String, String> billing) {
    final data = <String, dynamic>{};
    for (final field in hostedCardFields) {
      final v = (billing[field] ?? '').trim();
      if (v.isNotEmpty) data[field] = field == 'country' ? v.toUpperCase() : v;
    }
    return data;
  }

  static Map<String, dynamic> buildMobileMoneyRequest(MobileMoneyInput input) => {
        'phone': input.phone,
        'country': input.country.toUpperCase(),
        if (input.operator != null) 'operator': input.operator,
      };

  /// 1.5's mapping, kept as it was for the calls that return it
  /// ([WajubSession.process], `payMobileMoney`…): a confirmation step
  /// (`confirm_otp`…) is `unsupported_action` there. The payment sheet, and
  /// [WajubSession.processPayment], read the answer with [mapProcessAnswer].
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
      case 'client_session':
        final clientSession = body.clientSession;
        if (clientSession != null) {
          return PaymentRequiresAction(
            action: ActionKind.clientSession,
            actionUrl: clientSession.hostedUrl,
            transaction: txn,
            clientSession: clientSession,
          );
        }
    }

    // Any other non-null action is a step this SDK can't perform natively.
    // Mapping it to processing would leave the payer on an endless spinner.
    final action = body.action;
    if (action != null) {
      return PaymentFailed(
        error: WajubError(
          type: WajubErrorType.paymentError,
          message: 'This payment requires a step the SDK cannot handle natively ($action).',
          code: unsupportedActionCode,
        ),
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

  /// What one answer leaves to do. Decides on the action
  /// and `transaction.status`, never on `message`. [methodType]
  /// (`mobile_money`, `card`, `wallet`) tells a push approval from a wait.
  /// A confirmation step is [ActionKind.confirm] with a
  /// [PaymentRequiresAction.step]; an action without what it needs is
  /// `unsupported_action`. [fallback] stands in for a missing `transaction`.
  static PaymentResult mapProcessAnswer(RawProcessResponse body, String methodType, {SessionTransaction? fallback}) {
    final txn = body.transaction ?? fallback;
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

    final action = body.action;
    if (action != null) return _mapAction(action, body, txn);

    final context = txn.processingContext;
    if (context?.isUssd ?? false) {
      return PaymentProcessing(txn, instruction: context?.payerInstruction, kind: ProcessingKind.ussd);
    }
    if (methodType == 'mobile_money' || (context?.isMobileMoney ?? false)) {
      return PaymentRequiresAction(
        action: ActionKind.pushApproval,
        actionUrl: body.confirmUrl,
        transaction: txn.copyWith(
          processingContext: context ?? const ProcessingContext(isMobileMoney: true),
        ),
      );
    }

    return PaymentProcessing(txn, instruction: context?.payerInstruction);
  }

  static PaymentResult _mapAction(String action, RawProcessResponse body, SessionTransaction txn) {
    final url = body.confirmUrl ?? body.simulatorUrl;
    switch (action) {
      case 'redirect' when url != null:
        return PaymentRequiresAction(action: ActionKind.redirect, actionUrl: url, transaction: txn);
      case 'confirm' when url != null:
        return PaymentRequiresAction(action: ActionKind.confirm, actionUrl: url, transaction: txn);
      case 'confirm_3ds' when url != null:
        return PaymentRequiresAction(action: ActionKind.confirm3ds, actionUrl: url, transaction: txn);
      case 'confirm_3ds' when body.threeDsId != null:
        return PaymentRequiresAction(
          action: ActionKind.confirm3ds,
          transaction: txn,
          stepId: body.threeDsId,
          hint: body.maskedEmail,
          timeoutSeconds: body.threeDsTimeout,
        );
      case 'client_session' when body.clientSession != null:
        return PaymentRequiresAction(
          action: ActionKind.clientSession,
          actionUrl: body.clientSession!.hostedUrl,
          transaction: txn,
          clientSession: body.clientSession,
        );
      case 'payer_otp' when body.payerOtp != null:
        return PaymentRequiresAction(action: ActionKind.payerOtp, transaction: txn, payerOtp: body.payerOtp);
    }
    final step = stepKindOf(action);
    final stepId = step == null ? null : body.stepIds[step];
    if (step != null && stepId != null) {
      return PaymentRequiresAction(
        action: ActionKind.confirm,
        transaction: txn,
        step: step,
        stepId: stepId,
        hint: body.stepHints[step],
      );
    }
    // An action this SDK can't perform, or one without what it needs.
    // Mapping it to processing would leave the payer on an endless spinner.
    return PaymentFailed(
      error: WajubError.of(unsupportedActionCode, apiMessage: 'Unsupported payment action: $action'),
      transaction: txn,
    );
  }
}
