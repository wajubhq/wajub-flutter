import 'client/pay_client.dart';
import 'mapper/payment_mapper.dart';
import 'models/models.dart';
import 'models/payment_result.dart';
import 'realtime/status_subscriber.dart';
import 'adapters/hosted_redirect.dart';
import 'adapters/stripe_adapter.dart';

/// Session-scoped checkout client — mirrors hosted checkout `/pay/*` without WebView.
class WajubSession {
  WajubSession(this._token, {PayClient? client}) : _client = client ?? PayClient();

  final String _token;
  final PayClient _client;
  SessionData? _cachedSession;

  Future<SessionData> loadSession({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSession != null) {
      return _cachedSession!;
    }
    final session = await _client.getSession(_token);
    _cachedSession = session;
    return session;
  }

  Future<SdkConfig> getSdkConfig() => _client.getSdkConfig(_token);

  Future<PaymentResult> payMobileMoney(MobileMoneyInput input) async {
    await loadSession();
    final body = PaymentMapper.buildMobileMoneyRequest(input);
    final raw = await _client.process(_token, input.channelSlug, body);
    return PaymentMapper.mapProcessResponse(raw, 'mobile_money');
  }

  /// Stripe `stripe_elements` — tokenizes via native Stripe SDK, then processes.
  Future<PaymentResult> payCard({
    required String channelSlug,
    required String paymentMethodId,
    String? cardholderName,
  }) async {
    await loadSession();
    final body = buildStripeCardRequest(
      paymentMethodId: paymentMethodId,
      cardholderName: cardholderName,
    );
    final raw = await _client.process(_token, channelSlug, body);
    return PaymentMapper.mapProcessResponse(raw, 'card');
  }

  /// Initializes Stripe from sdk-config and creates a PaymentMethod in one call.
  Future<PaymentResult> payCardWithStripeElements({
    required String channelSlug,
    required String publishableKey,
    String? cardholderName,
  }) async {
    await StripeAdapter.ensureInitialized(publishableKey);
    final paymentMethodId = await StripeAdapter.createPaymentMethod(cardholderName: cardholderName);
    return payCard(
      channelSlug: channelSlug,
      paymentMethodId: paymentMethodId,
      cardholderName: cardholderName,
    );
  }

  Future<PaymentResult> process(String channel, Map<String, dynamic> data) async {
    final raw = await _client.process(_token, channel, data);
    return PaymentMapper.mapProcessResponse(raw, _methodType(channel));
  }

  /// Opens redirect / hosted PSP URLs in the system browser (not WebView).
  Future<bool> handleRedirectAction(PaymentResult result) async {
    if (result is! PaymentRequiresAction) return false;
    if (result.action != ActionKind.redirect &&
        result.action != ActionKind.confirm &&
        result.action != ActionKind.confirm3ds) {
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

  /// Pusher/Reverb when `echo` is present, otherwise polling.
  Stream<PaymentResult> watchStatus({Duration interval = const Duration(seconds: 5)}) async* {
    final session = await loadSession();
    yield* StatusSubscriber(_client, _token, interval: interval).subscribe(session);
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
      _ => 'unknown',
    };
  }
}
