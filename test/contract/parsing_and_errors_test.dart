import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/checkout/altcha.dart';
import 'package:wajub_mobile/src/checkout/checkout_methods.dart';
import 'package:wajub_mobile/src/checkout/checkout_types.dart';
import 'package:wajub_mobile/src/mapper/payment_mapper.dart';
import 'package:wajub_mobile/src/models/json_read.dart';
import 'package:wajub_mobile/src/models/models.dart';
import 'package:wajub_mobile/src/models/wajub_error.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

/// Parses [name] with the wire model of its endpoint.
Object parseFixture(String name) {
  final envelope = fixture(name);
  if (name.startsWith('realtime-')) {
    return PaymentStatusUpdate.fromJson(Map<String, dynamic>.from(envelope['data'] as Map));
  }
  final status = envelope['http_status'] as int;
  final body = Map<String, dynamic>.from(envelope['body'] as Map);
  final path = (envelope['request'] as Map)['path'] as String;
  if (status >= 400) return WajubError.fromResponse(status: status, body: body, loading: path == '/pay/session');
  return switch (path) {
    '/pay/session' => SessionData.fromJson(body),
    '/pay/sdk-config' => SdkConfig.fromJson(body),
    '/pay/status' => PaymentStatusUpdate.fromJson(body),
    '/pay/cancel' => CancelResult(redirectUrl: readText(body['redirect_url'])),
    '/pay/broadcasting/auth' => readText(body['auth'])!,
    final p when p.endsWith('/verify') && p != '/pay/3ds/verify' => StepVerifyResult.fromJson(body),
    _ => RawProcessResponse.fromJson(body, httpStatus: status),
  };
}

Map<String, dynamic> withUnknownKeys(Map<String, dynamic> body) {
  final copy = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
  copy['zz_unknown'] = {'nested': true};
  (copy['transaction'] as Map)['zz_unknown'] = [1, 2];
  (copy['branding'] as Map)['zz_unknown'] = 'x';
  ((copy['channels'] as List)[1] as Map)['zz_unknown'] = 3;
  ((((copy['channels'] as List)[1] as Map)['operators'] as List)[0] as Map)['zz_unknown'] = null;
  return copy;
}

void main() {
  test('PR-01 parses every fixture', () {
    final names = fixtureNames();
    expect(names, hasLength(97));
    for (final name in names) {
      expect(() => parseFixture(name), returnsNormally, reason: name);
    }
    final session = parseFixture('session-cm-aggregate.json') as SessionData;
    expect(session.transaction.id, 'trx_PVrU8x2kQ1mNa7Lb3cDe');
    expect(session.channels.last.operators.map((o) => o.operator), ['mtn', 'orange']);
    final process = parseFixture('process-requires-3ds-sandbox.json') as RawProcessResponse;
    expect(process.threeDsTimeout, 600);
    final step = parseFixture('otp-verify-invalid.json') as StepVerifyResult;
    expect((step.success, step.attemptsRemaining, step.errorCode), (false, 2, 'invalid_otp'));
    final chained = parseFixture('birthday-verify-chained-otp.json') as StepVerifyResult;
    expect((chained.success, chained.action), (true, 'confirm_otp'));
    final status = parseFixture('status-processing.json') as PaymentStatusUpdate;
    expect((status.errorCode, status.payerMessage), (null, null), reason: '2.1: always there, null');
    final logos = session.channels.last;
    expect(logos.logoPng, 'https://api.wajub.com/img/channels/momo.png');
    expect(logos.operators.last.logoPng, 'https://api.wajub.com/img/channels/om.png');
    expect(session.transaction.errorCode, isNull);
    final event = parseFixture('realtime-payment-status-updated-refused.json') as PaymentStatusUpdate;
    expect((event.status, event.errorCode), ('pending', 'insufficient_funds'));
  });

  test('PR-02 ignores unknown keys', () {
    final plain = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
    final extra = SessionData.fromJson(withUnknownKeys(fixtureBody('session-cm-aggregate.json')));
    expect(extra.transaction.amount, plain.transaction.amount);
    expect(extra.merchantBranding.primaryColor, plain.merchantBranding.primaryColor);
    expect(extra.channels.map((c) => c.slug), plain.channels.map((c) => c.slug));
    expect(extra.channels[1].operators.first.slug, 'cm.mtn');
  });

  test('PR-03 accepts numbers as int, double or numeric string', () {
    final fee = SessionData.fromJson(fixtureBody('session-payer-bears-fee.json')).transaction;
    expect(fee.fee?.rate, 0.035);
    expect(fee.amount, 10000);
    expect(fee.amountTotal, 10350);
    for (final amount in [25000, 25000.0, '25000', '25000.00']) {
      final body = fixtureBody('session-payer-bears-fee.json');
      (body['transaction'] as Map)['amount'] = amount;
      ((body['transaction'] as Map)['fee'] as Map)['rate'] = '0.035';
      final transaction = SessionData.fromJson(body).transaction;
      expect(transaction.amount, 25000, reason: '$amount');
      expect(transaction.fee?.rate, 0.035);
    }
    for (final optional in ['abc', null]) {
      final body = fixtureBody('session-payer-bears-fee.json');
      ((body['transaction'] as Map)['fee'] as Map)['rate'] = optional;
      ((body['channels'] as List).first as Map)['min_amount'] = optional;
      final session = SessionData.fromJson(body);
      expect(session.transaction.fee?.rate, isNull);
      expect(session.channels.first.minAmount, isNull);
    }
    for (final amount in ['abc', null]) {
      final body = fixtureBody('session-payer-bears-fee.json');
      (body['transaction'] as Map)['amount'] = amount;
      expect(() => SessionData.fromJson(body), throwsFormatException, reason: '$amount');
    }
  });

  test('PR-04 accepts booleans in every encoding', () {
    for (final (value, expected) in [
      (true, true),
      (1, true),
      ('true', true),
      ('1', true),
      (false, false),
      (0, false),
      ('false', false),
      ('0', false),
    ]) {
      final body = fixtureBody('session-cm-aggregate.json');
      (body['branding'] as Map)['white_label'] = value;
      (body['transaction'] as Map)['sandbox'] = value;
      final session = SessionData.fromJson(body);
      expect(session.merchantBranding.whiteLabel, expected, reason: '$value');
      expect(session.transaction.sandbox, expected);
    }
  });

  test('PR-05 parses branding with mixed types', () {
    // 2.1 sends the weights as integers, 2.0 sent `"400"`.
    for (final name in ['session-cm-aggregate.json', 'session-saved-methods.json', 'session-payer-bears-fee.json']) {
      final branding = SessionData.fromJson(fixtureBody(name)).merchantBranding;
      expect(branding.whiteLabel, isTrue, reason: name);
      expect(branding.overlayIntensity, 40, reason: name);
      expect(branding.fontWeightHeading, 600, reason: name);
      expect(branding.fontWeightBody, 400, reason: name);
    }
    final branding = SessionData.fromJson(fixtureBody('session-cm-aggregate.json')).merchantBranding;
    expect(branding.borderRadius, '12px');
    expect(branding.appearanceMode, 'light');
    final plain = SessionData.fromJson(fixtureBody('session-ci-xof-wallets.json')).merchantBranding;
    expect(plain.whiteLabel, isFalse);
    expect(plain.primaryColor, isNull);
    final object = Branding.fromJson({
      'white_label': {'enabled': true, 'brand_name': 'Akwa'}
    });
    expect(object.whiteLabel, isTrue);
    expect(Branding.fromJson(const {}).whiteLabel, isFalse, reason: 'every key may be missing');
  });

  test('PR-06 reads dotted keys literally', () {
    final session = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
    expect(session.channels.first.nameFr, 'Carte bancaire');
    expect(session.merchantBranding.cardBackgroundColor, '#FFFFFF');
    expect(session.merchantBranding.cardBorderColor, '#E5E7EB');
  });

  test('PR-07 accepts null optionals', () {
    final ci = SessionData.fromJson(fixtureBody('session-ci-xof-wallets.json'));
    expect(ci.transaction.customer, isNull);
    expect(ci.transaction.fee, isNull);
    expect(ci.transaction.receiptUrl, isNull);
    expect(ci.sessionLocale, isNull);
    expect(ci.channels.firstWhere((c) => c.slug == 'ci.moov').logo, isNull);
    expect(ci.channels.first.minAmount, isNull);
    final sandbox = SessionData.fromJson(fixtureBody('session-sandbox-cm.json'));
    expect(sandbox.echo, isNull, reason: '2.1: no echo without a key');
    expect(sandbox.altcha, isNull);
    final keyless = SessionData.fromJson(fixtureBody('session-processing-mobile-money.json'));
    expect(keyless.echo, isNull, reason: '2.0: echo.key null, no socket');
    expect(keyless.echoSettings?.wsHost, 'ws://localhost');
    expect(ci.transaction.errorCode, isNull, reason: 'a 2.0 session has no error_code');
    expect(ci.channels.first.logoPng, isNull, reason: 'a 2.0 session has no logo_png');
  });

  test('PR-08 accepts absent optional objects', () {
    final session = SessionData.fromJson(fixtureBody('session-cm-aggregate.json'));
    expect(session.transaction.processingContext, isNull);
    final noEcho = fixtureBody('session-cm-aggregate.json')..remove('echo');
    expect(SessionData.fromJson(noEcho).echoSettings, isNull);
    final sandbox = SdkConfig.fromJson(fixtureBody('sdk-config-sandbox.json'));
    expect(sandbox.channels['card']?.clientSession, isFalse);
    final process = RawProcessResponse.fromJson(fixtureBody('process-processing-mobile-money-sandbox.json'));
    expect(process.action, isNull);
    expect(process.transaction?.processingContext?.isMobileMoney, isTrue);
  });

  test('ER-01 exposes the error shape', () {
    final error = WajubError.fromResponse(
      status: 403,
      body: fixtureBody('process-403-shield-blocked.json'),
      correlationId: 'req-1',
    );
    expect(error.toMap().keys, [
      'name',
      'type',
      'code',
      'message',
      'decline_code',
      'retryable',
      'param',
      'http_status',
      'correlation_id',
      'retry_after_seconds',
      'details',
      'block_reference',
      'api_message',
    ]);
    expect(error.toMap()['name'], 'WajubError');
    expect(error.toMap()['type'], 'payment_error');
    expect(error.toMap()['correlation_id'], 'req-1');
    expect(error.toMap()['details'], isNull);
    expect(error, isA<Exception>());
  });

  test('ER-02 maps every error fixture', () {
    // name: (code, type, retryable, decline_code, param, retry_after, block_reference)
    const p = 'payment_error', i = 'invalid_request_error', a = 'api_error', auth = 'authentication_error';
    final expected = <String, (String, String, bool, String?, String?, int?, String?)>{
      '3ds-verify-422-invalid-code.json': ('invalid_code', i, true, null, 'request', null, null),
      '3ds-verify-500-invalid-code-api-bug.json': ('server_error', a, true, null, null, null, null),
      'address-verify-422-missing-fields.json': ('validation_error', i, true, null, null, null, null),
      'birthday-verify-422-format.json': ('validation_error', i, true, null, 'birthday', null, null),
      'broadcasting-auth-403.json': ('session_not_found', auth, false, null, null, null, null),
      'cancel-400-not-cancellable.json': ('not_processable', i, false, null, null, null, null),
      'client-session-422-sandbox.json': ('client_session_unavailable', i, false, null, 'request', null, null),
      'client-session-complete-402.json': ('failed', p, true, 'failed', null, null, null),
      'client-session-complete-422-expired.json': ('client_session_expired', i, true, null, 'request', null, null),
      'error-401-invalid-token.json': ('session_not_found', auth, false, null, null, null, null),
      'error-401-missing-token.json': ('session_not_found', auth, false, null, null, null, null),
      'error-403-not-a-payment-session.json': ('session_not_found', auth, false, null, null, null, null),
      'error-410-process-session-ended.json': ('session_terminal_expired', i, false, null, null, null, null),
      'error-410-session-expired.json': ('session_terminal_expired', i, false, null, null, null, null),
      'error-410-session-terminal-expired.json': ('session_terminal_expired', i, false, null, null, null, null),
      'error-429-rate-limited.json': ('rate_limited', 'rate_limit_error', true, null, null, 300, null),
      'error-500-production.json': ('server_error', a, true, null, null, null, null),
      'process-400-not-processable.json': ('not_processable', i, false, null, null, null, null),
      'process-402-insufficient-funds-sandbox.json': (
        'insufficient_funds',
        p,
        true,
        'insufficient_funds',
        null,
        null,
        null
      ),
      'process-402-merchant-not-verified.json': (
        'merchant_not_verified',
        p,
        false,
        'merchant_not_verified',
        null,
        null,
        null
      ),
      'process-403-restricted.json': ('payment_method_restricted', p, true, null, null, null, null),
      'process-403-shield-blocked.json': ('shield_blocked', p, false, null, null, null, 'BLK-PLACEHOLDER'),
      'process-409-order-not-validated.json': ('order_not_validated', i, false, null, null, null, null),
      'process-409-payment-in-progress.json': ('payment_in_progress', i, false, null, null, null, null),
      'process-422-idempotency-key-invalid.json': ('validation_error', i, true, null, 'idempotency_key', null, null),
      'process-422-operator-mismatch.json': ('validation_error', i, true, null, 'phone', null, null),
      'process-422-over-mobile-money-limit-sandbox.json': ('validation_error', i, true, null, 'request', null, null),
      'process-422-raw-card-data-live.json': ('raw_card_data_not_accepted', i, false, null, 'card', null, null),
      'process-422-sandbox-invalid-test-number.json': ('validation_error', i, true, null, 'data.phone', null, null),
      'process-422-unknown-channel.json': ('validation_error', i, true, null, 'channel', null, null),
      'process-422-validation.json': ('validation_error', i, true, null, null, null, null),
      'process-failed-402.json': ('insufficient_funds', p, true, 'insufficient_funds', null, null, null),
      'process-422-security-check-failed.json': ('security_check_failed', i, true, null, 'request', null, null),
      'client-session-422-security-check-failed.json': ('security_check_failed', i, true, null, 'request', null, null),
    };
    final failing =
        fixtureNames().where((name) => !name.startsWith('realtime-') && fixtureStatus(name) >= 400).toList();
    expect(failing.toSet(), expected.keys.toSet(), reason: 'every error fixture is mapped here');
    expected.forEach((name, row) {
      final path = (fixture(name)['request'] as Map)['path'] as String;
      final error = WajubError.fromResponse(
        status: fixtureStatus(name),
        body: fixtureBody(name),
        correlationId: 'req-$name',
        loading: const {'/pay/session', '/pay/status', '/pay/broadcasting/auth'}.contains(path),
      );
      final (code, type, retryable, decline, param, retryAfter, block) = row;
      expect(
        (
          error.code,
          error.type.wireName,
          error.retryable,
          error.declineCode,
          error.param,
          error.retryAfterSeconds,
          error.blockReference
        ),
        (code, type, retryable, decline, param, retryAfter, block),
        reason: name,
      );
      expect(error.httpStatus, fixtureStatus(name));
      expect(error.correlationId, 'req-$name');
      expect(error.message, isNotEmpty);
    });

    // The HTTP-200 step failures.
    for (final (name, code, type) in [
      ('otp-verify-invalid.json', 'invalid_otp', i),
      ('otp-verify-max-attempts.json', 'max_attempts_exceeded', p),
      ('otp-verify-expired.json', 'otp_expired', i),
      ('pin-verify-invalid.json', 'invalid_pin', i),
    ]) {
      final error = WajubError.fromStep(StepVerifyResult.fromJson(fixtureBody(name)));
      expect((error.code, error.type.wireName, error.retryable), (code, type, true), reason: name);
    }
  });

  test('ER-02 reads the correlation id from X-Request-Id', () async {
    final api = FakeApi(routes: {
      'POST /pay/process': FakeAnswer.fixture('process-failed-402.json', headers: {'x-request-id': 'req_7c1e'}),
    });
    await expectLater(
      api.payClient().process('tok_test', 'cm.mobile', const {}),
      throwsA(isA<WajubError>().having((e) => e.correlationId, 'correlation_id', 'req_7c1e')),
    );
  });

  test('ER-03 localises error messages', () {
    WajubError map(String name, String language, {bool loading = false}) => WajubError.fromResponse(
        status: fixtureStatus(name), body: fixtureBody(name), language: language, loading: loading);
    expect(map('process-failed-402.json', 'en').message, 'Insufficient funds.');
    expect(map('process-failed-402.json', 'fr').message, 'Fonds insuffisants.');
    // An unknown PSP decline code: the generic decline text.
    expect(map('client-session-complete-402.json', 'en').message,
        'This payment could not be completed. Try again or use another payment method.');
    expect(map('client-session-complete-402.json', 'fr').message,
        "Ce paiement n'a pas abouti. Réessayez ou utilisez un autre moyen de paiement.");
    expect(map('error-401-invalid-token.json', 'fr', loading: true).message,
        "Nous n'avons pas pu retrouver cette session de paiement. Vérifiez le lien reçu ou demandez-en un nouveau au marchand.");
    // A code the catalogue does not know: the API's text in English, the status's in French.
    const unknown = {'code': 403, 'status': 'Forbidden', 'message': 'Brand new refusal.', 'error_code': 'brand_new'};
    expect(WajubError.fromResponse(status: 403, body: unknown).message, 'Brand new refusal.');
    expect(WajubError.fromResponse(status: 403, body: unknown, language: 'fr').message,
        'Service temporairement indisponible.');
    const unknown422 = {'code': 422, 'status': 'Unprocessable Content', 'message': 'Odd.', 'error_code': 'odd'};
    expect(WajubError.fromResponse(status: 422, body: unknown422, language: 'fr').message,
        'Vérifiez les informations saisies.');
    final error = map('error-429-rate-limited.json', 'fr');
    expect(error.message, 'Trop de tentatives. Merci de patienter 300 s avant de réessayer.');
    expect(error.localized('en').message, 'Too many attempts. Please wait 300 s before trying again.');
    expect(error.apiMessage, 'Too many requests');
  });

  test('AL-01 solves altcha challenges', () {
    String sha(String text) => sha256.convert(utf8.encode(text)).toString();
    final challenge = AltchaChallenge(
      algorithm: 'SHA-256',
      challenge: sha('s4lt1234'),
      salt: 's4lt',
      signature: 'sig',
      maxNumber: 5000,
    );
    expect(solveAltcha(challenge), 1234);
    expect(
        solveAltcha(
            AltchaChallenge(algorithm: 'SHA-256', challenge: sha('none'), salt: 's', signature: '', maxNumber: 10)),
        isNull);

    virtual((async) {
      final session = fixtureBody('session-cm-aggregate.json')
        ..['altcha'] = {
          'algorithm': 'SHA-256',
          'challenge': sha('s4lt1234'),
          'salt': 's4lt',
          'signature': 'sig',
          'maxnumber': 5000,
        };
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer(200, session),
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-processing-mobile-money-live.json',
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api, altchaSolver: (c) async => solveAltcha(c));
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      final data = api.bodies('/pay/process').single['data'] as Map;
      expect(data['altcha'], {
        'algorithm': 'SHA-256',
        'challenge': sha('s4lt1234'),
        'number': 1234,
        'salt': 's4lt',
        'signature': 'sig',
      });
      checkout.end();
    });

    virtual((async) {
      // Refused twice: one new session, then security_check_failed.
      final session = fixtureBody('session-cm-aggregate.json')
        ..['altcha'] = {
          'algorithm': 'SHA-256',
          'challenge': sha('s4lt7'),
          'salt': 's4lt',
          'signature': 'sig',
          'maxnumber': 50
        };
      const refused = FakeAnswer(422, {
        'code': 422,
        'status': 'Unprocessable Content',
        'message': 'Security challenge verification failed',
        'errors': {
          'altcha': ['Security challenge verification failed'],
        },
      });
      final api = FakeApi(routes: {
        'GET /pay/session': FakeAnswer(200, session),
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': refused,
      });
      final checkout = Checkout(async, api, altchaSolver: (c) async => solveAltcha(c));
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      expect(api.calls('/pay/process'), hasLength(2));
      expect(api.calls('/pay/session'), hasLength(2), reason: 'a new challenge once');
      final keys = api.calls('/pay/process').map((r) => r.headers['Idempotency-Key']).toSet();
      expect(keys, hasLength(2), reason: 'the second submission is a new attempt');
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.error?.code, 'security_check_failed');
      checkout.end();
    });
  });

  test('AL-02 recognises the altcha refusal by its code', () {
    String sha(String text) => sha256.convert(utf8.encode(text)).toString();
    Map<String, dynamic> withChallenge(String salt, int number) => fixtureBody('session-cm-aggregate.json')
      ..['altcha'] = {
        'algorithm': 'SHA-256',
        'challenge': sha('$salt$number'),
        'salt': salt,
        'signature': 'sig',
        'maxnumber': 100,
      };
    int? numberOf(Map<String, dynamic> body) =>
        (((body['data'] as Map?) ?? body)['altcha'] ?? body['altcha'] as Map?)?['number'] as int?;

    // Whatever the message says: the code decides.
    final otherMessage = fixtureBody('process-422-security-check-failed.json')
      ..['message'] = 'La vérification de sécurité a échoué.'
      ..['errors'] = {
        'request': ['La vérification de sécurité a échoué.'],
      };
    for (final refusal in [
      FakeAnswer.fixture('process-422-security-check-failed.json'),
      FakeAnswer(422, otherMessage),
    ]) {
      virtual((async) {
        final api = FakeApi(routes: {
          'GET /pay/session': [FakeAnswer(200, withChallenge('s1', 7)), FakeAnswer(200, withChallenge('s2', 42))],
          'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
          'POST /pay/process': [refusal, FakeAnswer.fixture('process-processing-mobile-money-live.json')],
          'GET /pay/status': 'status-processing.json',
        });
        final checkout = Checkout(async, api, altchaSolver: (c) async => solveAltcha(c));
        checkout.mobileMoney('677123456', pick: 'mtn');
        checkout.run(checkout.controller.payMobileMoney);
        expect(api.calls('/pay/session'), hasLength(2), reason: 'reloaded once for a new challenge');
        expect(api.bodies('/pay/process').map(numberOf), [7, 42]);
        final keys = api.calls('/pay/process').map((r) => r.headers['Idempotency-Key']).toSet();
        expect(keys, hasLength(2), reason: 'a new Idempotency-Key');
        expect(checkout.controller.state, CheckoutState.approvalRequired);
        expect(checkout.controller.fieldErrors, isEmpty);
        checkout.end();
      });
    }

    virtual((async) {
      // A second refusal: security_check_failed, retryable, no field errors.
      final api = FakeApi(routes: {
        'GET /pay/session': [FakeAnswer(200, withChallenge('s1', 7)), FakeAnswer(200, withChallenge('s2', 42))],
        'GET /pay/sdk-config': 'sdk-config-cm-stripe.json',
        'POST /pay/process': 'process-422-security-check-failed.json',
      });
      final checkout = Checkout(async, api, altchaSolver: (c) async => solveAltcha(c));
      checkout.mobileMoney('677123456', pick: 'mtn');
      checkout.run(checkout.controller.payMobileMoney);
      expect(api.calls('/pay/process'), hasLength(2));
      expect(checkout.controller.state, CheckoutState.failed);
      expect(checkout.controller.error?.code, 'security_check_failed');
      expect(checkout.controller.error?.retryable, isTrue);
      expect(checkout.controller.fieldErrors, isEmpty);
      checkout.end();
    });

    virtual((async) {
      // The same on a client session, its solution sent as `altcha`.
      final api = FakeApi(routes: {
        'GET /pay/session': [FakeAnswer(200, withChallenge('s1', 7)), FakeAnswer(200, withChallenge('s2', 42))],
        'GET /pay/sdk-config': 'sdk-config-card-paystack.json',
        'POST /pay/client-session': [
          FakeAnswer.fixture('client-session-422-security-check-failed.json'),
          FakeAnswer.fixture('client-session-start-202.json'),
        ],
        'GET /pay/status': 'status-processing.json',
      });
      final checkout = Checkout(async, api, locale: 'en', altchaSolver: (c) async => solveAltcha(c));
      checkout.controller.selectMethod(checkout.method(MethodFamily.card));
      checkout.run(checkout.controller.payCard);
      expect(api.bodies('/pay/client-session').map(numberOf), [7, 42]);
      expect(checkout.controller.state, CheckoutState.pending);
      checkout.end();
    });
  });

  test('SY-01 uses the synced spec files', () {
    final manifest = File('$fixturesDir/spec.sha256').readAsLinesSync().where((line) => line.trim().isNotEmpty);
    expect(manifest, hasLength(99));
    for (final line in manifest) {
      final hash = line.substring(0, 64);
      final path = line.substring(66);
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');
      expect(sha256.convert(file.readAsBytesSync()).toString(), hash, reason: '$path differs from the spec');
    }
  });
}
