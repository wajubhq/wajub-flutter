enum WajubErrorType {
  apiError,
  authenticationError,
  invalidRequestError,
  paymentError,
  rateLimitError,
}

class WajubError implements Exception {
  const WajubError({
    required this.type,
    required this.message,
    required this.code,
    this.declineCode,
    this.retryable = false,
    this.param,
    this.correlationId,
    this.retryAfterSeconds,
    this.details = const {},
  });

  final WajubErrorType type;
  final String message;
  final String code;
  final String? declineCode;
  final bool retryable;
  final String? param;
  final String? correlationId;
  final int? retryAfterSeconds;
  final Map<String, String> details;

  factory WajubError.network(String message) => WajubError(
        type: WajubErrorType.apiError,
        message: message,
        code: 'network_error',
        retryable: true,
      );

  factory WajubError.fromHttp(
    int status,
    String message,
    String code,
    Map<String, String> details,
    String? correlationId,
    int? retryAfterSeconds,
  ) {
    // 410 is an ended session: no retry of the same token can succeed. A 5xx
    // is Wajub's side, not the payer's payment.
    final type = switch (status) {
      401 || 404 || 410 => WajubErrorType.authenticationError,
      422 => WajubErrorType.invalidRequestError,
      429 => WajubErrorType.rateLimitError,
      >= 500 => WajubErrorType.apiError,
      _ => WajubErrorType.paymentError,
    };
    return WajubError(
      type: type,
      message: message,
      code: code,
      retryable: status != 403 && status != 410,
      // The field the refusal is about, when it names exactly one.
      param: details.length == 1 ? details.keys.single : null,
      correlationId: correlationId,
      retryAfterSeconds: retryAfterSeconds,
      details: details,
      declineCode: status == 402 ? code : null,
    );
  }

  @override
  String toString() => 'WajubError($code): $message';
}
