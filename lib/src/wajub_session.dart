import 'dart:async';

import 'adapters/hosted_redirect.dart';
import 'adapters/stripe_adapter.dart';
import 'checkout/present_options.dart';
import 'client/pay_client.dart';
import 'mapper/payment_mapper.dart';
import 'models/models.dart';
import 'models/payment_result.dart';
import 'models/wajub_error.dart';
import 'realtime/payment_watcher.dart';
import 'realtime/pusher_socket.dart';

/// Session-scoped checkout client — the hosted checkout's `/pay/*` calls,
/// for apps that draw their own UI. `presentWajubCheckout` drives all of it.
class WajubSession {
  WajubSession(this._token, {PayClient? client}) : _client = client ?? PayClient();

  final String _token;
  final PayClient _client;
  SessionData? _cachedSession;

  /// The language of the [WajubError] messages: `fr` or `en`.
  String get language => _client.language;
  set language(String value) => _client.language = value == 'fr' ? 'fr' : 'en';

  /// The session's token, for the payment sheet.
  String get token => _token;

  /// The HTTP client, for the payment sheet.
  PayClient get client => _client;

  Future<SessionData> loadSession({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSession != null) {
      return _cachedSession!;
    }
    final session = await _client.getSession(_token);
    _cachedSession = session;
    return session;
  }

  Future<SdkConfig> getSdkConfig() => _client.getSdkConfig(_token);

  /// `GET /pay/status`: the payment's current status. After a crash, read it
  /// (or ask your server) to learn how a payment ended.
  Future<PaymentStatusUpdate> status() => _client.getStatus(_token);

  /// [MobileMoneyInput.phone] in E.164 (`+237677123456`); `operator` only for
  /// an aggregate channel. [idempotencyKey]: one per press of Pay.
  Future<PaymentResult> payMobileMoney(MobileMoneyInput input, {String? returnUrl, String? idempotencyKey}) async {
    await loadSession();
    final body = {
      ...PaymentMapper.buildMobileMoneyRequest(input),
      if (returnUrl != null) 'return_url': returnUrl,
    };
    final raw = await _client.process(_token, input.channelSlug, body, idempotencyKey: idempotencyKey);
    return PaymentMapper.mapProcessResponse(raw, 'mobile_money');
  }

  /// Stripe `stripe_elements` — tokenizes via native Stripe SDK, then processes.
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

  /// Initializes Stripe from sdk-config and creates a PaymentMethod in one call.
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

  /// One-tap wallet channel (sdk-config `form`, no `requiredFields`, channel
  /// type `wallet` — e.g. Djamo): returns [PaymentRequiresAction] redirecting
  /// to the wallet's payment page, which opens the wallet app.
  Future<PaymentResult> payWallet({required String channelSlug, String? returnUrl}) async {
    await loadSession();
    return process(channelSlug, {if (returnUrl != null) 'return_url': returnUrl});
  }

  /// `POST /pay/process` with [data] as given (plus the device signals),
  /// read as 1.5 did: a confirmation step is `unsupported_action`.
  Future<PaymentResult> process(String channel, Map<String, dynamic> data, {String? idempotencyKey}) async {
    final raw = await _client.process(_token, channel, data, idempotencyKey: idempotencyKey);
    return PaymentMapper.mapProcessResponse(raw, _methodType(channel));
  }

  /// `POST /pay/process`, read as the spec v2 reads it: a confirmation step
  /// (`confirm_otp`…) is [PaymentRequiresAction] with [ActionKind.confirm], a
  /// [PaymentRequiresAction.step] and its `stepId` (answer it with
  /// [verifyStep]); the sandbox 3-D Secure code is [ActionKind.confirm3ds]
  /// with a `stepId`; an action missing what it needs is `unsupported_action`.
  /// Give one [idempotencyKey] per press of Pay.
  Future<PaymentResult> processPayment(String channel, Map<String, dynamic> data, {String? idempotencyKey}) async {
    final session = await loadSession();
    final raw = await _client.process(_token, channel, data, idempotencyKey: idempotencyKey);
    return PaymentMapper.mapProcessAnswer(raw, _methodType(channel), fallback: session.transaction);
  }

  /// sdk-config `hosted_redirect` (PayPal, Mollie, Paddle, Kkiapay, FedaPay,
  /// PayDunya, CinetPay): the PSP's own page collects the card — submit no
  /// card data, then open the redirect. [billing] must carry every field the
  /// channel's `requiredFields` lists (see [PaymentMapper.hostedCardFields]).
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

  /// `POST /pay/client-session` — PSP-hosted checkout (sdk-config
  /// `clientSession == true`, e.g. Paystack / Flutterwave cards). Returns
  /// [PaymentRequiresAction] with [ActionKind.clientSession] and a
  /// [ClientSession]; open its `hostedUrl` (see [handleRedirectAction]) or
  /// launch the PSP's native SDK, then call [completeClientSession].
  /// Idempotent: calling again returns the same open session. [billing]:
  /// the other contact fields sdk-config lists in `required_fields`.
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

  /// `POST /pay/client-session/complete` — call when the payer returns from
  /// the PSP's UI. [PaymentComplete] when verified, [PaymentProcessing] while
  /// the PSP hasn't confirmed yet (keep [watchStatus] running — the PSP
  /// webhook settles it). A definitive failure throws [WajubError].
  Future<PaymentResult> completeClientSession(String clientSessionId) async {
    final raw = await _client.completeClientSession(_token, clientSessionId);
    return PaymentMapper.mapProcessResponse(raw, 'card');
  }

  /// `POST /pay/{otp,pin,phone,birthday,address}/verify` for the step of a
  /// [PaymentRequiresAction] ([PaymentRequiresAction.step],
  /// [PaymentRequiresAction.stepId]). [fields]: `{code}`, `{pin}`, `{phone}`,
  /// `{birthday: 'YYYY-MM-DD'}`, or `{address, city, state, zip_code}`.
  Future<StepVerifyResult> verifyStep(PaymentStepKind kind, String stepId, Map<String, String> fields) =>
      _client.verifyStep(_token, kind, stepId, fields);

  /// Asks for the step again; the providers have no resend, so this does
  /// nothing visible today.
  Future<void> resendStep(PaymentStepKind kind, String stepId) => _client.resendStep(_token, kind, stepId);

  /// Sandbox 3-D Secure email code. Throws [WajubError] `invalid_code` on a
  /// wrong code (the API answers it with a 500 today).
  Future<void> verifyThreeDs(String threeDsId, String code) => _client.verifyThreeDs(_token, threeDsId, code);

  /// Sandbox 3-D Secure: sends a new code; returns the masked email.
  Future<String?> sendThreeDs(String threeDsId) => _client.sendThreeDs(_token, threeDsId);

  /// Opens redirect / hosted PSP URLs in the system browser (not WebView).
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

  /// Follows the payment until it ends: polls `GET /pay/status` and, when
  /// the session has realtime settings, listens to the payment's channel.
  /// Delivers a [PaymentProcessing] each time the status changes, then the
  /// outcome: [PaymentComplete], or [PaymentFailed] whose code is the status
  /// (`failed`, `cancelled`, `expired`) as in 1.5, or the refusal's code when
  /// an attempt went back to `pending` without charging. A session that is no
  /// longer readable (`401`, `403`, `404`, `410`) ends the stream with its
  /// [WajubError]. It watches until then; cancelling the subscription stops
  /// it. [interval] is the base polling interval.
  Stream<PaymentResult> watchStatus({
    Duration interval = PaymentWatcher.defaultInterval,
    RealtimeOptions realtime = const RealtimeOptions(),
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
        realtime: RealtimeEndpoint.resolve(session, realtime),
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
