import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../constants.dart';
import '../mapper/payment_mapper.dart';
import '../models/json_read.dart';
import '../models/models.dart';
import '../models/payment_result.dart';
import '../models/step_keys.dart';
import '../models/wajub_error.dart';
import 'client_info.dart';
import 'ids.dart';
import 'platform_web.dart' if (dart.library.io) 'platform_io.dart';

/// How a call may be tried again (spec README §2.5).
enum _Retry {
  /// GETs: network, timeout, 408, 429 (`Retry-After` ≤ 10 s), 5xx but 501.
  read,

  /// Payment POSTs: network, timeout, 502, 503, 504 — the same body again.
  payment,

  /// `POST /pay/cancel`: network and timeout only.
  cancel,

  /// Verify calls and the rest: never.
  never,
}

/// Sends the SDK's calls to Wajub.
///
/// Pass one to `Wajub.createSession` or `WajubSession` to send the calls
/// through your own [http.Client] (a proxy, certificate pinning, tests). Its
/// other members serve `WajubSession`; call them through it.
class PayClient {
  PayClient({
    http.Client? httpClient,
    @visibleForTesting Future<ClientInfo> Function()? clientInfo,
    @visibleForTesting Random? random,
    @visibleForTesting Stopwatch Function()? stopwatch,
  })  : _http = httpClient ?? createHttpClient(connectTimeout),
        // Never waits on a platform channel (ClientInfo.now).
        _clientInfo = clientInfo ?? _nowInfo,
        _random = random ?? Random(),
        _newStopwatch = stopwatch ?? Stopwatch.new;

  static Future<ClientInfo> _nowInfo() async => ClientInfo.now();

  final http.Client _http;
  final Future<ClientInfo> Function() _clientInfo;
  final Random _random;
  final Stopwatch Function() _newStopwatch;
  final _sent = <String, Stopwatch>{};

  @internal
  static const connectTimeout = Duration(seconds: 10);

  @internal
  static const requestTimeout = Duration(seconds: 30);

  @internal
  static const paymentRequestTimeout = Duration(seconds: 60);

  static const _maxReadRetries = 3;
  static const _maxPostRetries = 2;
  static const _maxRetryAfter = Duration(seconds: 10);

  @internal
  Duration? sinceSent(String path) => _sent[path]?.elapsed;

  @internal
  Stopwatch newStopwatch() => _newStopwatch();

  /// The language of the [WajubError] messages: `fr` or `en`.
  String language = PlatformDispatcher.instance.locale.languageCode == 'fr' ? 'fr' : 'en';

  @internal
  Future<SessionData> getSession(String token) async {
    final answer = await _send('GET', token, '/pay/session', retry: _Retry.read, loading: true);
    return _parse(answer, SessionData.fromJson);
  }

  @internal
  Future<SdkConfig> getSdkConfig(String token) async {
    final answer = await _send('GET', token, '/pay/sdk-config', retry: _Retry.read, loading: true);
    return _parse(answer, SdkConfig.fromJson);
  }

  @internal
  Future<PaymentStatusUpdate> getStatus(String token) async {
    final answer = await _send('GET', token, '/pay/status', retry: _Retry.read, loading: true);
    return _parse(answer, PaymentStatusUpdate.fromJson);
  }

  @internal
  Future<RawProcessResponse> process(
    String token,
    String channel,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final info = await _clientInfo();
    final answer = await _send(
      'POST',
      token,
      '/pay/process',
      body: {
        'channel': channel,
        'data': {...data, '_client': info.signals},
      },
      timeout: paymentRequestTimeout,
      retry: _Retry.payment,
      headers: {'Idempotency-Key': idempotencyKey ?? uuidV4()},
    );
    return _parse(answer, (json) => RawProcessResponse.fromJson(json, httpStatus: answer.status));
  }

  @internal
  Future<RawProcessResponse> startClientSession(
    String token,
    String channel, {
    String? email,
    String? name,
    String? returnUrl,
    bool restart = false,
    Map<String, String> billing = const {},
    Map<String, Object?>? altcha,
  }) async {
    final options = ClientSessionOptions(
      email: email,
      name: name,
      returnUrl: returnUrl,
      restart: restart,
      billing: billing,
    );
    final answer = await _send(
      'POST',
      token,
      '/pay/client-session',
      body: {'channel': channel, ...options.toJson(), if (altcha != null) 'altcha': altcha},
      timeout: paymentRequestTimeout,
      retry: _Retry.payment,
    );
    return _parse(answer, (json) => RawProcessResponse.fromJson(json, httpStatus: answer.status));
  }

  @internal
  Future<RawProcessResponse> completeClientSession(String token, String clientSessionId) async {
    final answer = await _send(
      'POST',
      token,
      '/pay/client-session/complete',
      body: {'client_session_id': clientSessionId},
      timeout: paymentRequestTimeout,
      retry: _Retry.payment,
    );
    return _parse(answer, (json) => RawProcessResponse.fromJson(json, httpStatus: answer.status));
  }

  @internal
  Future<StepVerifyResult> verifyStep(
    String token,
    PaymentStepKind kind,
    String stepId,
    Map<String, String> fields,
  ) async {
    final answer = await _send(
      'POST',
      token,
      '/pay/${kind.name}/verify',
      body: {kind.idKey: stepId, ...fields},
      timeout: paymentRequestTimeout,
    );
    return _parse(answer, (json) {
      final result = StepVerifyResult.fromJson(json);
      if (!result.success || result.action == null) return result;
      // Another step: its action and fields read as a 202 of /pay/process.
      return result.withNext(
        PaymentMapper.mapProcessAnswer(RawProcessResponse.fromJson(json, httpStatus: 202), 'card'),
      );
    });
  }

  @internal
  Future<void> resendStep(String token, PaymentStepKind kind, String stepId) =>
      _send('POST', token, '/pay/${kind.name}/resend', body: {kind.idKey: stepId});

  @internal
  Future<RawProcessResponse> verifyThreeDs(String token, String threeDsId, String code) async {
    final answer = await _send(
      'POST',
      token,
      '/pay/3ds/verify',
      body: {'three_ds_id': threeDsId, 'code': code},
      timeout: paymentRequestTimeout,
    );
    return _parse(answer, (json) => RawProcessResponse.fromJson(json, httpStatus: answer.status));
  }

  @internal
  Future<String?> sendThreeDs(String token, String threeDsId) async {
    final answer = await _send('POST', token, '/pay/3ds/send', body: {'three_ds_id': threeDsId});
    return readText(answer.body['masked_email']);
  }

  @internal
  Future<CancelResult> cancel(String token) async {
    final answer = await _send('POST', token, '/pay/cancel', body: const {}, retry: _Retry.cancel);
    return CancelResult(redirectUrl: readText(answer.body['redirect_url']));
  }

  @internal
  Future<String> authorizeChannel(String token, String socketId, String channelName) async {
    final answer = await _send(
      'POST',
      token,
      '/pay/broadcasting/auth',
      body: {'socket_id': socketId, 'channel_name': channelName},
      loading: true,
    );
    final auth = readText(answer.body['auth']);
    if (auth == null) throw WajubError.of('server_error', language: language);
    return auth;
  }

  T _parse<T>(_Answer answer, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(answer.body);
    } on FormatException catch (e) {
      throw WajubError.of(
        'server_error',
        language: language,
        httpStatus: answer.status,
        apiMessage: 'Unreadable answer: ${e.message}',
        correlationId: answer.requestId,
      );
    }
  }

  Future<_Answer> _send(
    String method,
    String token,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = requestTimeout,
    _Retry retry = _Retry.never,
    Map<String, String> headers = const {},
    bool loading = false,
  }) async {
    final info = await _clientInfo();
    final encoded = body == null ? null : jsonEncode(body);
    final uri = Uri.parse('${apiUrl.replaceAll(RegExp(r'/+$'), '')}$path');
    for (var attempt = 0;; attempt++) {
      final request = http.Request(method, uri)
        ..headers.addAll({
          // AuthenticatePaymentSession (api.wajub) reads this via Laravel's
          // Request::bearerToken(), which requires the literal "Bearer " prefix.
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Accept-Language': info.acceptLanguage,
          'X-Request-Id': uuidV4(_random),
          'X-Wajub-Client': info.wajubClient,
          if (info.userAgent != null) 'User-Agent': info.userAgent!,
          if (encoded != null) 'Content-Type': 'application/json',
          ...headers,
        });
      if (encoded != null) request.body = encoded;
      if (path == '/pay/process' || path == '/pay/client-session') _sent[path] = _newStopwatch()..start();

      http.Response response;
      try {
        response = await _http.send(request).then(http.Response.fromStream).timeout(timeout);
      } on TimeoutException {
        if (_retries(retry, null) && attempt < _maxRetries(retry)) {
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        throw WajubError.of('timeout', language: language);
      } on WajubError {
        rethrow;
      } catch (e) {
        if (_retries(retry, null) && attempt < _maxRetries(retry)) {
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        throw WajubError.of('network_error', language: language, apiMessage: '$e');
      }

      final requestId = response.headers['x-request-id'];
      final status = response.statusCode;
      final json = _decode(response.body);
      if (status >= 200 && status < 300) {
        if (json == null) {
          throw WajubError.of(
            'server_error',
            language: language,
            httpStatus: status,
            apiMessage: 'The answer is not JSON.',
            correlationId: requestId,
          );
        }
        return _Answer(status, json, requestId);
      }

      final retryAfter = int.tryParse(response.headers['retry-after']?.trim() ?? '');
      if (_retries(retry, status) && attempt < _maxRetries(retry)) {
        if (status != 429) {
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        final wait = retryAfter == null ? _backoff(attempt) : Duration(seconds: retryAfter);
        if (wait <= _maxRetryAfter) {
          await Future<void>.delayed(wait);
          continue;
        }
      }
      throw WajubError.fromResponse(
        status: status,
        body: json ?? const {},
        correlationId: requestId,
        retryAfterHeader: retryAfter,
        language: language,
        loading: loading,
      );
    }
  }

  static bool _retries(_Retry retry, int? status) => switch (retry) {
        _Retry.read => status == null || const {408, 429, 500, 502, 503, 504}.contains(status),
        _Retry.payment => status == null || const {502, 503, 504}.contains(status),
        _Retry.cancel => status == null,
        _Retry.never => false,
      };

  static int _maxRetries(_Retry retry) => retry == _Retry.read ? _maxReadRetries : _maxPostRetries;

  /// `min(1 s × 2^n, 10 s) ± 30 %`.
  Duration _backoff(int attempt) {
    final base = min(1000 * pow(2, attempt), 10000).toDouble();
    final jitter = 1 + (_random.nextDouble() * 0.6 - 0.3);
    return Duration(milliseconds: (base * jitter).round());
  }

  /// A proxy's HTML error page is not JSON: read as no body, so the status
  /// still maps to a [WajubError].
  static Map<String, dynamic>? _decode(String text) {
    if (text.trim().isEmpty) return const {};
    try {
      return readMap(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }
}

class _Answer {
  const _Answer(this.status, this.body, this.requestId);

  final int status;
  final Map<String, dynamic> body;
  final String? requestId;
}
