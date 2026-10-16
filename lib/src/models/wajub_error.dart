import 'package:meta/meta.dart';

import '../errors/error_catalogue.dart';
import 'json_read.dart';
import 'models.dart';

/// The kind of a [WajubError].
enum WajubErrorType {
  apiError,
  authenticationError,
  invalidRequestError,
  paymentError,
  rateLimitError;

  /// The type's name: `api_error`, `authentication_error`…
  String get wireName => switch (this) {
        apiError => 'api_error',
        authenticationError => 'authentication_error',
        invalidRequestError => 'invalid_request_error',
        paymentError => 'payment_error',
        rateLimitError => 'rate_limit_error',
      };
}

/// Every failure the SDK reports. [message] is for the payer, in the sheet's
/// language; branch on [code].
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
    this.httpStatus,
    this.blockReference,
    this.apiMessage,
    this.attemptsRemaining,
    this.cancelRefusal = false,
  });

  final WajubErrorType type;
  final String message;

  /// The code to branch on: `insufficient_funds`, `session_not_found`…
  final String code;

  /// On a decline, the reason's code.
  final String? declineCode;
  final bool retryable;

  /// The field at fault, when the refusal names exactly one.
  final String? param;

  /// The request id to quote to Wajub support.
  final String? correlationId;

  /// On `rate_limited`, how long to wait before trying again.
  final int? retryAfterSeconds;

  /// Each field at fault, with its message. Empty when none.
  final Map<String, String> details;
  final int? httpStatus;

  /// On `shield_blocked`, the reference to quote to Wajub support.
  final String? blockReference;

  /// Wajub's own message, in English, for your logs.
  final String? apiMessage;

  /// A confirmation step refused: the attempts the payer has left.
  final int? attemptsRemaining;

  /// The answer to a cancel: `payment_in_progress` then means the payment
  /// cannot be cancelled while it is being paid.
  @internal
  final bool cancelRefusal;

  /// Always `WajubError`.
  String get name => 'WajubError';

  factory WajubError.network(String message) => WajubError(
        type: WajubErrorType.apiError,
        message: message,
        code: 'network_error',
        retryable: true,
      );

  /// An error of the catalogue, its message in [language] (`fr` or `en`).
  factory WajubError.of(
    String code, {
    String language = 'en',
    int? httpStatus,
    String? apiMessage,
    String? correlationId,
    int? retryAfterSeconds,
    String? blockReference,
    int? attemptsRemaining,
    String? declineCode,
    String? param,
    Map<String, String> details = const {},
  }) {
    final entry = ErrorCatalogue.lookup(code) ?? ErrorCatalogue.declineFallback;
    return WajubError(
      type: entry.type,
      message: ErrorCatalogue.text(entry, language, {
        'seconds': retryAfterSeconds,
        'block_reference': blockReference,
        'n': attemptsRemaining,
      }),
      code: code,
      retryable: entry.retryable,
      httpStatus: httpStatus,
      apiMessage: apiMessage,
      correlationId: correlationId,
      retryAfterSeconds: retryAfterSeconds,
      blockReference: blockReference,
      attemptsRemaining: attemptsRemaining,
      declineCode: declineCode,
      param: param,
      details: details,
    );
  }

  /// The error of one of Wajub's error answers, as the SDK reads it.
  factory WajubError.fromResponse({
    required int status,
    required Map<String, dynamic> body,
    String? correlationId,
    int? retryAfterHeader,
    String language = 'en',
    bool loading = false,
    bool cancelling = false,
  }) {
    final nested = readMap(body['error']);
    var code = readText(body['error_code']) ??
        readText(nested?['code']) ??
        switch (status) {
          400 => 'not_processable',
          401 || 404 => 'session_not_found',
          402 => 'payment_declined',
          403 => loading ? 'session_not_found' : 'merchant_restricted',
          409 => 'order_not_validated',
          410 => 'session_terminal_expired',
          422 => 'validation_error',
          429 => 'rate_limited',
          >= 500 => 'server_error',
          _ => 'request_failed',
        };
    if (status == 410) code = 'session_terminal_expired';
    final details = _firstMessages(body['errors']);
    final error = WajubError(
      type: _typeFor(code, status),
      message: '',
      code: code,
      declineCode: status == 402 ? readText(body['error_code']) : null,
      retryable: _retryableFor(code, status, nested),
      param: details.length == 1 ? details.keys.single : null,
      correlationId: correlationId,
      retryAfterSeconds: readInt(body['retry_after']) ?? retryAfterHeader,
      details: details,
      httpStatus: status,
      blockReference: readText(body['block_reference']),
      apiMessage: readText(nested?['message']) ?? readText(body['message']),
      attemptsRemaining: readInt(body['attempts_remaining']),
      cancelRefusal: cancelling,
    );
    return error.localized(language);
  }

  /// The error of a confirmation step `WajubSession.verifyStep` refused.
  factory WajubError.fromStep(StepVerifyResult result, {String language = 'en'}) => WajubError.of(
        result.errorCode ?? 'validation_error',
        language: language,
        attemptsRemaining: result.attemptsRemaining,
        apiMessage: result.errorMessage,
      );

  /// An error from an HTTP status, [code] and [message] already known.
  factory WajubError.fromHttp(
    int status,
    String message,
    String code,
    Map<String, String> details,
    String? correlationId,
    int? retryAfterSeconds,
  ) {
    // 401, 404 and 410 are a token that is not, or no longer, a payment
    // session: no retry of the same token can succeed. A 5xx is Wajub's side,
    // not the payer's payment.
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
      retryable: !const {401, 403, 404, 410}.contains(status),
      // The field the refusal is about, when it names exactly one.
      param: details.length == 1 ? details.keys.single : null,
      correlationId: correlationId,
      retryAfterSeconds: retryAfterSeconds,
      details: details,
      declineCode: status == 402 ? code : null,
      httpStatus: status,
      apiMessage: message,
    );
  }

  /// The same error with its [message] in [language] (`fr` or `en`).
  WajubError localized(String language) {
    final entry = ErrorCatalogue.entryFor(code, cancelling: cancelRefusal) ??
        (httpStatus == 402 ? ErrorCatalogue.declineFallback : null);
    final String text;
    if (code == 'validation_error' && language != 'fr' && apiMessage != null) {
      text = apiMessage!;
    } else if (entry != null) {
      text = ErrorCatalogue.text(entry, language, {
        'seconds': retryAfterSeconds,
        'block_reference': blockReference,
        'n': attemptsRemaining,
      });
    } else if (language != 'fr' && (apiMessage ?? message).isNotEmpty) {
      text = apiMessage ?? message;
    } else {
      final fallback = switch (httpStatus) {
        402 => 'payment_declined',
        422 => 'validation_error',
        _ => 'server_error',
      };
      text = ErrorCatalogue.text(ErrorCatalogue.lookup(fallback)!, language);
    }
    return copyWith(message: text);
  }

  WajubError copyWith({String? message, bool? retryable, String? code, WajubErrorType? type}) => WajubError(
        type: type ?? this.type,
        message: message ?? this.message,
        code: code ?? this.code,
        declineCode: declineCode,
        retryable: retryable ?? this.retryable,
        param: param,
        correlationId: correlationId,
        retryAfterSeconds: retryAfterSeconds,
        details: details,
        httpStatus: httpStatus,
        blockReference: blockReference,
        apiMessage: apiMessage,
        attemptsRemaining: attemptsRemaining,
        cancelRefusal: cancelRefusal,
      );

  /// The error as a JSON map (`name`, `type`, `code`, `message`…), for your
  /// logs.
  Map<String, Object?> toMap() => {
        'name': name,
        'type': type.wireName,
        'code': code,
        'message': message,
        'decline_code': declineCode,
        'retryable': retryable,
        'param': param,
        'http_status': httpStatus,
        'correlation_id': correlationId,
        'retry_after_seconds': retryAfterSeconds,
        'details': details.isEmpty ? null : details,
        'block_reference': blockReference,
        'api_message': apiMessage,
      };

  static WajubErrorType _typeFor(String code, int status) =>
      ErrorCatalogue.lookup(code)?.type ??
      switch (status) {
        402 || 403 => WajubErrorType.paymentError,
        401 || 404 => WajubErrorType.authenticationError,
        429 => WajubErrorType.rateLimitError,
        >= 500 => WajubErrorType.apiError,
        _ => WajubErrorType.invalidRequestError,
      };

  static bool _retryableFor(String code, int status, Map<String, dynamic>? nested) =>
      ErrorCatalogue.lookup(code)?.retryable ??
      readBool(nested?['retryable']) ??
      (status == 402 || status == 422 || status >= 500);

  static Map<String, String> _firstMessages(Object? raw) {
    final map = readMap(raw);
    if (map == null) return const {};
    return {
      for (final entry in map.entries)
        entry.key: entry.value is List && (entry.value as List).isNotEmpty
            ? '${(entry.value as List).first}'
            : '${entry.value}',
    };
  }

  @override
  String toString() => 'WajubError($code): $message';
}
