import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/models.dart';
import '../models/wajub_error.dart';
import '../mapper/payment_mapper.dart';

class PayClient {
  PayClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<SessionData> getSession(String token) async {
    final body = await _request('GET', token, '/pay/session');
    return SessionData.fromJson(body);
  }

  Future<SdkConfig> getSdkConfig(String token) async {
    final body = await _request('GET', token, '/pay/sdk-config');
    return SdkConfig.fromJson(body);
  }

  Future<RawProcessResponse> process(
    String token,
    String channel,
    Map<String, dynamic> data,
  ) async {
    final body = await _request(
      'POST',
      token,
      '/pay/process',
      jsonBody: {'channel': channel, 'data': data},
      extraHeaders: {'Idempotency-Key': _idempotencyKey()},
    );
    return RawProcessResponse.fromJson(body);
  }

  Future<CancelResult> cancel(String token) async {
    final body = await _request('POST', token, '/pay/cancel', jsonBody: {});
    return CancelResult(redirectUrl: body['redirect_url'] as String?);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String token,
    String path, {
    Map<String, dynamic>? jsonBody,
    Map<String, String> extraHeaders = const {},
  }) async {
    final uri = Uri.parse('${apiUrl.replaceAll(RegExp(r'/+$'), '')}$path');
    final headers = {
      'Accept': 'application/json',
      // AuthenticatePaymentSession (api.wajub) reads this via Laravel's
      // Request::bearerToken(), which requires the literal "Bearer " prefix —
      // without it every /pay/* call 401s with "Payment session token required."
      'Authorization': 'Bearer $token',
      ...extraHeaders,
    };

    late http.Response response;
    if (method == 'GET') {
      response = await _http.get(uri, headers: headers);
    } else {
      headers['Content-Type'] = 'application/json; charset=utf-8';
      response = await _http.post(
        uri,
        headers: headers,
        body: jsonEncode(jsonBody ?? {}),
      );
    }

    final correlationId = response.headers['x-request-id'] ?? response.headers['x-trace-id'];
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    final text = response.body;
    final body = text.isNotEmpty ? jsonDecode(text) as Map<String, dynamic> : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapError(response.statusCode, body, correlationId, retryAfter);
    }
    return body;
  }

  WajubError _mapError(
    int code,
    Map<String, dynamic> body,
    String? correlationId,
    int? retryAfter,
  ) {
    final message = (body['message'] as String?)?.isNotEmpty == true
        ? body['message'] as String
        : 'Request failed ($code)';
    final errorCode = body['error_code'] as String? ??
        switch (code) {
          402 => 'insufficient_funds',
          403 => 'blocked',
          410 => 'session_terminal_expired',
          422 => 'validation_error',
          429 => 'rate_limited',
          401 || 404 => 'session_not_found',
          >= 500 => 'server_error',
          _ => 'payment_error',
        };
    final details = _flattenErrors(body['errors']);
    return WajubError.fromHttp(code, message, errorCode, details, correlationId, retryAfter);
  }

  Map<String, String> _flattenErrors(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map((key, value) {
      if (value is List && value.isNotEmpty) {
        return MapEntry(key.toString(), value.first.toString());
      }
      return MapEntry(key.toString(), value.toString());
    });
  }

  String _idempotencyKey() => 'wajub-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
}
