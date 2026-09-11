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
    this.clientSession,
  });

  final int code;
  final String status;
  final String message;
  final String? action;
  final SessionTransaction? transaction;
  final String? confirmUrl;
  final String? simulatorUrl;

  /// Set on `action: "client_session"` (POST /pay/client-session).
  final ClientSession? clientSession;

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
        clientSession: json['client_session'] is Map<String, dynamic>
            ? ClientSession.fromJson(json['client_session'] as Map<String, dynamic>)
            : null,
      );
}

class PaymentMapper {
  static const _successStatuses = {'success', 'successful', 'succeeded', 'paid', 'complete'};

  /// Error code for an `action` this SDK can't perform natively
  /// (`confirm_otp`, `confirm_pin`, `card_reauth`, …) — see spec/README.md.
  static const unsupportedActionCode = 'unsupported_action';

  /// A `wallet` channel payable with a single tap — nothing to collect,
  /// `/pay/process` answers with a redirect to the wallet's own page/app
  /// (e.g. Djamo). Apple Pay / Google Pay / PayPal-via-Stripe need their own
  /// SDK flavor and are excluded by `sdk: form` + no `requiredFields`.
  static bool isRedirectWalletChannel(SessionChannel channel, SdkChannelConfig? config) =>
      channel.type.toLowerCase() == 'wallet' &&
      config != null &&
      config.available &&
      config.sdk == SdkFlavor.form &&
      config.requiredFields.isEmpty;

  /// Contact/billing fields a `hosted_redirect` card PSP may still need
  /// before it opens its page — sdk-config lists the missing ones in
  /// `required_fields` (Kkiapay/FedaPay/PayDunya: `email`; CinetPay:
  /// `first_name` … `zip_code`).
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

  /// Why a hosted-redirect billing value can't be sent yet, or null.
  static String? hostedCardFieldError(String field, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Required';
    if (field == 'email' && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
      return 'Invalid email';
    }
    // CinetPay's customer_country is a 2-letter ISO code.
    if (field == 'country' && !RegExp(r'^[A-Za-z]{2}$').hasMatch(v)) {
      return 'Use the 2-letter country code';
    }
    return null;
  }

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
