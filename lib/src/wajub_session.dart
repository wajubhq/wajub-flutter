import 'dart:async';

import 'package:flutter/foundation.dart';

import 'adapters/hosted_redirect.dart';
import 'adapters/stripe_adapter.dart';
import 'checkout/altcha.dart';
import 'client/ids.dart';
import 'client/pay_client.dart';
import 'mapper/payment_mapper.dart';
import 'models/models.dart';
import 'models/payment_result.dart';
import 'models/security_challenge.dart';
import 'models/wajub_error.dart';
import 'realtime/payment_watcher.dart';
import 'realtime/pusher_socket.dart';

/// One payment, for apps that draw their own payment screens: what it
/// offers, paying it, and following it to its outcome. The payment sheet
/// (`presentWajubCheckout`) does all of this by itself.
class WajubSession {
  WajubSession(
    this._token, {
    PayClient? client,
    @visibleForTesting Future<int?> Function(SecurityChallenge challenge)? securityChallengeSolver,
  })  : _client = client ?? PayClient(),
        _solveChallenge = securityChallengeSolver ?? _solveInBackground;

  final String _token;
  final PayClient _client;
  final Future<int?> Function(SecurityChallenge challenge) _solveChallenge;

  static Future<int?> _solveInBackground(SecurityChallenge challenge) => compute(solveAltcha, challenge);
  SessionData? _cachedSession;

  /// The language of the [WajubError] messages: `fr` or `en`.
  String get language => _client.language;
  set language(String value) => _client.language = value == 'fr' ? 'fr' : 'en';

  /// The session's token, for the payment sheet.
  String get token => _token;

  /// The HTTP client, for the payment sheet.
  PayClient get client => _client;

  /// The payment and the methods it offers, read once unless [forceRefresh].
  Future<SessionData> loadSession({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSession != null) {
      return _cachedSession!;
    }
    final session = await _client.getSession(_token);
    _cachedSession = session;
    return session;
  }

  /// How each payment method collects what it needs, by channel slug.
  Future<SdkConfig> getSdkConfig() => _client.getSdkConfig(_token);

  /// The payment's current status. After a crash, read it (or ask your
  /// server) to learn how a payment ended.
  Future<PaymentStatusUpdate> status() => _client.getStatus(_token);

  /// Pays with Mobile Money. [MobileMoneyInput.phone] in E.164
  /// (`+237677123456`); `operator` only for a channel that groups several
  /// operators. [idempotencyKey]: one per press of Pay.
  Future<PaymentResult> payMobileMoney(MobileMoneyInput input, {String? returnUrl, String? idempotencyKey}) async {
    await loadSession();
    final body = {
      ...PaymentMapper.buildMobileMoneyRequest(input),
      if (returnUrl != null) 'return_url': returnUrl,
    };
    final raw = await _client.process(_token, input.channelSlug, body, idempotencyKey: idempotencyKey);
    return PaymentMapper.mapProcessResponse(raw, 'mobile_money');
  }

  /// Pays with a card Stripe tokenized (`StripeAdapter.createPaymentMethod`).
  Future<PaymentResult> payCard({
    required String channelSlug,
    required String paymentMethodId,
    String? cardholderName,
    String? returnUrl,
  }) async {
    await loadSession();
    final body = {
      ...buildStripeCardRequest(paymentMethodId: paymentMethodId, cardholderName: cardholderName),
      if (returnUrl != null) 'return_url': returnUrl,
    };
    final raw = await _client.process(_token, channelSlug, body);
    return PaymentMapper.mapProcessResponse(raw, 'card');
  }

  /// Pays with the card in Stripe's card field, [publishableKey] being the
  /// card's `SdkChannelConfig.publishableKey`.
  Future<PaymentResult> payCardWithStripeElements({
    required String channelSlug,
    required String publishableKey,
    String? cardholderName,
    String? returnUrl,
  }) async {
    await StripeAdapter.ensureInitialized(publishableKey);
    final paymentMethodId = await StripeAdapter.createPaymentMethod(cardholderName: cardholderName);
    return payCard(
      channelSlug: channelSlug,
      paymentMethodId: paymentMethodId,
      cardholderName: cardholderName,
      returnUrl: returnUrl,
    );
  }

  /// Pays with a one-tap wallet: returns [PaymentRequiresAction] with the
  /// wallet's page, which opens the wallet app.
  Future<PaymentResult> payWallet({required String channelSlug, String? returnUrl}) async {
    await loadSession();
    return process(channelSlug, {if (returnUrl != null) 'return_url': returnUrl});
  }

  /// Pays with [channel] and [data] as given. A confirmation step comes back
  /// as `unsupported_action`; [processPayment] reads it.
  Future<PaymentResult> process(String channel, Map<String, dynamic> data, {String? idempotencyKey}) async {
    final raw = await _client.process(_token, channel, data, idempotencyKey: idempotencyKey);
    return PaymentMapper.mapProcessResponse(raw, _methodType(channel));
  }

  /// Pays with [channel] and [data], and returns where the payment stands: a
  /// confirmation step is [PaymentRequiresAction] with [ActionKind.confirm],
  /// a [PaymentRequiresAction.step] and its `stepId` (answer it with
  /// [verifyStep]); the sandbox 3-D Secure code is [ActionKind.confirm3ds]
  /// with a `stepId`; the code the payer generates in the operator's menu is
  /// [ActionKind.payerOtp] with its [PaymentRequiresAction.payerOtp] (call
  /// again with the code as `otp` in [data] and a new [idempotencyKey]); a
  /// refusal is [PaymentFailed]; a payment whose outcome is not known yet is
  /// [PaymentProcessing] — follow it with [status] or [watchStatus]. Only a
  /// payment that cannot be loaded throws.
  ///
  /// Give one [idempotencyKey] per press of Pay, and the same one again to
  /// retry a payment whose outcome is not known: it is never charged twice.
  /// The payment's security check is completed by itself.
  Future<PaymentResult> processPayment(String channel, Map<String, dynamic> data, {String? idempotencyKey}) async {
    var session = await loadSession();
    var key = idempotencyKey;
    for (var renewed = false;; renewed = true) {
      // The challenge's solution goes with the payment; a refused one is
      // renewed once (a new challenge, so a new key), then the refusal stands.
      final challenge = session.securityChallenge;
      var body = data;
      if (challenge != null) {
        final number = await _solveChallenge(challenge).catchError((Object _) => null);
        if (number == null) {
          return PaymentFailed(error: WajubError.of('security_check_failed', language: language));
        }
        body = {...data, 'altcha': altchaPayload(challenge, number)};
      }
      final RawProcessResponse raw;
      try {
        raw = await _client.process(_token, channel, body, idempotencyKey: key);
      } on WajubError catch (error) {
        if (isSecurityRefusal(error)) {
          if (renewed) {
            return PaymentFailed(error: WajubError.of('security_check_failed', language: language, httpStatus: 422));
          }
          session = await loadSession(forceRefresh: true);
          key = uuidV4();
          continue;
        }
        final status = error.httpStatus;
        final unanswered = status == null || status >= 500 || error.code == 'timeout' || error.code == 'network_error';
        if (unanswered || (status == 409 && error.code == 'payment_in_progress')) {
          return PaymentProcessing(session.transaction);
        }
        return PaymentFailed(error: error);
      }
      return PaymentMapper.mapProcessAnswer(raw, _methodType(channel), fallback: session.transaction);
    }
  }

  /// Pays a card on the provider's own page: returns the page to open.
  /// [billing] carries the contact fields the card asks for
  /// (`SdkChannelConfig.requiredFields`).
  Future<PaymentResult> payCardHostedRedirect({
    required String channelSlug,
    Map<String, String> billing = const {},
    String? returnUrl,
  }) async {
    await loadSession();
    final data = {
      ...PaymentMapper.buildHostedCardRequest(billing),
      if (returnUrl != null) 'return_url': returnUrl,
    };
    final raw = await _client.process(_token, channelSlug, data);
    return PaymentMapper.mapProcessResponse(raw, 'card');
  }

  /// Pays a card on the provider's own checkout
  /// (`SdkChannelConfig.clientSession`). Returns [PaymentRequiresAction]
  /// with [ActionKind.clientSession] and a [ClientSession]: open its page
  /// ([handleRedirectAction]), then call [completeClientSession]. Calling
  /// again returns the same checkout. [billing]: the other contact fields
  /// the card asks for (`SdkChannelConfig.requiredFields`).
  Future<PaymentResult> startClientSession({
    required String channelSlug,
    String? email,
    String? name,
    String? returnUrl,
    bool restart = false,
    Map<String, String> billing = const {},
  }) async {
    await loadSession();
    final raw = await _client.startClientSession(
      _token,
      channelSlug,
      email: email,
      name: name,
      returnUrl: returnUrl,
      restart: restart,
      billing: billing,
    );
    return PaymentMapper.mapProcessResponse(raw, 'card');
  }

  /// Call when the payer comes back from the provider's checkout:
  /// [PaymentComplete] when paid, [PaymentProcessing] while the provider has
  /// not confirmed yet (keep [watchStatus] running). A definitive failure
  /// throws [WajubError].
  Future<PaymentResult> completeClientSession(String clientSessionId) async {
    final raw = await _client.completeClientSession(_token, clientSessionId);
    return PaymentMapper.mapProcessResponse(raw, 'card');
  }

  /// Answers the confirmation step of a [PaymentRequiresAction]
  /// ([PaymentRequiresAction.step], [PaymentRequiresAction.stepId]).
  /// [fields]: `{code}`, `{pin}`, `{phone}`, `{birthday: 'YYYY-MM-DD'}`, or
  /// `{address, city, state, zip_code}`. When another step follows, it is in
  /// [StepVerifyResult.next].
  Future<StepVerifyResult> verifyStep(PaymentStepKind kind, String stepId, Map<String, String> fields) =>
      _client.verifyStep(_token, kind, stepId, fields, fallback: _cachedSession?.transaction);

  /// Asks for the step again.
  Future<void> resendStep(PaymentStepKind kind, String stepId) => _client.resendStep(_token, kind, stepId);

  /// Answers the sandbox 3-D Secure email code. A wrong code throws a
  /// retryable [WajubError].
  Future<void> verifyThreeDs(String threeDsId, String code) => _client.verifyThreeDs(_token, threeDsId, code);

  /// Sandbox 3-D Secure: sends a new code; returns the masked email.
  Future<String?> sendThreeDs(String threeDsId) => _client.sendThreeDs(_token, threeDsId);

  /// Opens the page a [PaymentRequiresAction] asks for in the system browser.
  Future<bool> handleRedirectAction(PaymentResult result) async {
    if (result is! PaymentRequiresAction) return false;
    if (result.action != ActionKind.redirect &&
        result.action != ActionKind.confirm &&
        result.action != ActionKind.confirm3ds &&
        result.action != ActionKind.clientSession) {
      return false;
    }
    final url = result.actionUrl;
    if (url == null || url.isEmpty) return false;
    return HostedRedirect.open(url);
  }

  Future<String?> cancel() async {
    final result = await _client.cancel(_token);
    return result.redirectUrl;
  }

  /// Follows the payment until it ends: a [PaymentProcessing] each time its
  /// status changes, then the outcome — [PaymentComplete], or [PaymentFailed]
  /// whose code is the status (`failed`, `cancelled`, `expired`) or the
  /// refusal's code when an attempt was refused. A payment that can no longer
  /// be read ends the stream with its [WajubError]. Cancelling the
  /// subscription stops it. [interval]: how often to check at most.
  Stream<PaymentResult> watchStatus({
    Duration interval = PaymentWatcher.defaultInterval,
  }) {
    PaymentWatcher? watcher;
    var cancelled = false;
    late final StreamController<PaymentResult> controller;

    Future<void> run() async {
      final SessionData session;
      try {
        session = await loadSession();
      } catch (error, stack) {
        controller.addError(error, stack);
        await controller.close();
        return;
      }
      if (cancelled) return;
      var transaction = session.transaction;
      String? lastStatus;
      watcher = PaymentWatcher(
        client: _client,
        token: _token,
        language: language,
        interval: interval,
        realtime: RealtimeEndpoint.resolve(session),
        capped: false,
        seenProcessing: transaction.status == 'processing' || transaction.status == 'partial',
        onStatus: (update) {
          final status = update.status;
          if (status == null) return;
          transaction = transaction.copyWith(status: status);
          if (status == lastStatus) return;
          lastStatus = status;
          controller.add(PaymentProcessing(transaction));
        },
        onDecision: (decision) {
          final status = decision.update?.status;
          if (status != null) transaction = transaction.copyWith(status: status);
          final error = decision.error;
          if (decision.verdict == WatchVerdict.success) {
            controller.add(PaymentComplete(transaction));
          } else if (error != null && const {'session_not_found', 'session_terminal_expired'}.contains(error.code)) {
            controller.addError(error);
          } else if (error != null && status != null && status != 'pending') {
            // 1.5's codes: the status itself.
            controller.add(PaymentFailed(
              error: WajubError(type: WajubErrorType.paymentError, message: status, code: status),
              transaction: transaction,
            ));
          } else if (error != null) {
            controller.add(PaymentFailed(error: error, transaction: transaction));
          }
          unawaited(controller.close());
        },
      )..start(pollNow: true);
    }

    controller = StreamController<PaymentResult>(
      onListen: () => unawaited(run()),
      onCancel: () {
        cancelled = true;
        watcher?.stop();
      },
    );
    return controller.stream;
  }

  String? cardChannelSlug() {
    for (final channel in _cachedSession?.channels ?? const <SessionChannel>[]) {
      if (channel.type.toLowerCase() == 'card') {
        return channel.slug;
      }
    }
    return null;
  }

  String _methodType(String channel) {
    final match = _cachedSession?.channels.where((c) => c.slug == channel).firstOrNull;
    return switch (match?.type.toLowerCase()) {
      'mobile_money' || 'mobile' => 'mobile_money',
      'card' => 'card',
      'wallet' => 'wallet',
      _ => 'unknown',
    };
  }
}
