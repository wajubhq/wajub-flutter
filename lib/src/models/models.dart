class ProcessingContext {
  const ProcessingContext({
    this.channelSlug,
    this.isMobileMoney = false,
    this.payerInstruction,
    this.actionUrl,
  });

  final String? channelSlug;
  final bool isMobileMoney;
  final String? payerInstruction;
  final String? actionUrl;

  factory ProcessingContext.fromJson(Map<String, dynamic> json) => ProcessingContext(
        channelSlug: json['channel_slug'] as String?,
        isMobileMoney: json['is_mobile_money'] as bool? ?? false,
        payerInstruction: json['payer_instruction'] as String?,
        actionUrl: json['action_url'] as String?,
      );
}

class SessionTransaction {
  const SessionTransaction({
    required this.id,
    required this.reference,
    this.trxref,
    required this.amount,
    this.amountTotal,
    required this.currency,
    required this.status,
    this.statusLabel,
    this.sandbox = false,
    this.description,
    this.processingContext,
  });

  final String id;
  final String reference;
  final String? trxref;
  final double amount;
  final double? amountTotal;
  final String currency;
  final String status;
  final String? statusLabel;
  final bool sandbox;
  final String? description;
  final ProcessingContext? processingContext;

  SessionTransaction copyWith({ProcessingContext? processingContext}) => SessionTransaction(
        id: id,
        reference: reference,
        trxref: trxref,
        amount: amount,
        amountTotal: amountTotal,
        currency: currency,
        status: status,
        statusLabel: statusLabel,
        sandbox: sandbox,
        description: description,
        processingContext: processingContext ?? this.processingContext,
      );

  factory SessionTransaction.fromJson(Map<String, dynamic> json) => SessionTransaction(
        id: json['id'] as String? ?? json['reference'] as String,
        reference: json['reference'] as String? ?? json['id'] as String,
        trxref: json['trxref'] as String?,
        amount: (json['amount'] as num).toDouble(),
        amountTotal: json['amount_total'] != null ? (json['amount_total'] as num).toDouble() : null,
        currency: json['currency'] as String,
        status: json['status'] as String,
        statusLabel: json['status_label'] as String?,
        sandbox: json['sandbox'] as bool? ?? false,
        description: json['description'] as String?,
        processingContext: json['processing_context'] != null
            ? ProcessingContext.fromJson(json['processing_context'] as Map<String, dynamic>)
            : null,
      );
}

class SessionChannel {
  const SessionChannel({
    required this.id,
    required this.slug,
    required this.name,
    this.nameFr,
    required this.type,
    this.logo,
    this.countries = const [],
    this.minAmount,
    this.maxAmount,
    required this.currency,
  });

  final String id;
  final String slug;
  final String name;
  final String? nameFr;
  final String type;
  final String? logo;
  final List<String> countries;
  final double? minAmount;
  final double? maxAmount;
  final String currency;

  factory SessionChannel.fromJson(Map<String, dynamic> json) => SessionChannel(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        nameFr: json['name_fr'] as String?,
        type: json['type'] as String,
        logo: json['logo'] as String?,
        countries: (json['countries'] as List<dynamic>? ?? []).cast<String>(),
        minAmount: json['min_amount'] != null ? (json['min_amount'] as num).toDouble() : null,
        maxAmount: json['max_amount'] != null ? (json['max_amount'] as num).toDouble() : null,
        currency: json['currency'] as String,
      );
}

class EchoConfig {
  const EchoConfig({
    required this.key,
    required this.wsHost,
    required this.wsPort,
    required this.channelPrefix,
    required this.broadcaster,
  });

  final String key;
  final String wsHost;
  final int wsPort;
  final String channelPrefix;
  final String broadcaster;

  factory EchoConfig.fromJson(Map<String, dynamic> json) => EchoConfig(
        key: json['key'] as String,
        wsHost: json['ws_host'] as String,
        wsPort: json['ws_port'] as int,
        channelPrefix: json['channel_prefix'] as String,
        broadcaster: json['broadcaster'] as String,
      );
}

class SessionData {
  const SessionData({
    required this.transaction,
    required this.channels,
    this.locale = 'en',
    this.branding = const {},
    this.echo,
    this.callback,
  });

  final SessionTransaction transaction;
  final List<SessionChannel> channels;
  final String locale;
  final Map<String, String?> branding;
  final EchoConfig? echo;
  final String? callback;

  factory SessionData.fromJson(Map<String, dynamic> json) {
    final brandingRaw = json['branding'] as Map<String, dynamic>? ?? {};
    return SessionData(
      transaction: SessionTransaction.fromJson(json['transaction'] as Map<String, dynamic>),
      channels: (json['channels'] as List<dynamic>? ?? [])
          .map((e) => SessionChannel.fromJson(e as Map<String, dynamic>))
          .toList(),
      locale: json['locale'] as String? ?? 'en',
      branding: brandingRaw.map((k, v) => MapEntry(k, v as String?)),
      echo: json['echo'] != null ? EchoConfig.fromJson(json['echo'] as Map<String, dynamic>) : null,
      callback: json['callback'] as String?,
    );
  }
}

/// Known `sdk-config` flavors (`SdkChannelConfig.sdk`). `adyen_custom_card`
/// needs Adyen's own client-side encryption, which this SDK doesn't embed —
/// treat it as unavailable. `paystack_inline`/`flutterwave_inline` are legacy
/// values api.wajub no longer sends (those cards use client sessions).
abstract final class SdkFlavor {
  static const form = 'form';
  static const stripeElements = 'stripe_elements';
  static const hostedRedirect = 'hosted_redirect';
  static const adyenCustomCard = 'adyen_custom_card';
  static const paystackInline = 'paystack_inline';
  static const flutterwaveInline = 'flutterwave_inline';
}

class SdkChannelConfig {
  const SdkChannelConfig({
    required this.available,
    this.provider,
    this.sdk,
    this.publishableKey,
    this.requiredFields = const [],
    this.clientSession = false,
  });

  final bool available;

  /// PREDICTION of the provider — the router re-runs per call. The pinned,
  /// authoritative provider is [ClientSession.provider].
  final String? provider;
  final String? sdk;
  final String? publishableKey;
  final List<String> requiredFields;

  /// `true` → `WajubSession.startClientSession` can hand this channel to the
  /// PSP's own hosted checkout (PIN/OTP/AVS handled by the PSP).
  final bool clientSession;

  factory SdkChannelConfig.fromJson(Map<String, dynamic> json) => SdkChannelConfig(
        available: json['available'] as bool? ?? false,
        provider: json['provider'] as String?,
        sdk: json['sdk'] as String?,
        publishableKey: json['publishable_key'] as String?,
        requiredFields: (json['required_fields'] as List<dynamic>? ?? []).cast<String>(),
        clientSession: json['client_session'] as bool? ?? false,
      );
}

/// PSP-hosted checkout session (`client_session` of `POST /pay/client-session`).
///
/// Default flow: open [hostedUrl] in the system browser, then call
/// `WajubSession.completeClientSession` with [id] when the payer returns.
/// Apps may instead launch the PSP's native SDK themselves — Paystack
/// Android/Flutter ([publicKey] + [accessCode]), Flutterwave Android
/// ([publicKey] + [encryptionKey] + [reference] as tx_ref, [amount],
/// [currency]) — then complete the same way.
class ClientSession {
  const ClientSession({
    required this.id,
    required this.provider,
    this.reference,
    this.amount,
    this.currency,
    this.hostedUrl,
    this.accessCode,
    this.publicKey,
    this.encryptionKey,
  });

  /// Pass back to `POST /pay/client-session/complete` as `client_session_id`.
  final String id;
  final String provider;

  /// PSP-side reference (Paystack `reference`, Flutterwave `tx_ref`).
  final String? reference;

  /// In the PSP's own units (Paystack: subunit; Flutterwave: major).
  final num? amount;
  final String? currency;
  final String? hostedUrl;
  final String? accessCode;
  final String? publicKey;
  final String? encryptionKey;

  factory ClientSession.fromJson(Map<String, dynamic> json) => ClientSession(
        id: json['id']?.toString() ?? '',
        provider: json['provider'] as String? ?? '',
        reference: json['reference'] as String?,
        amount: json['amount'] as num?,
        currency: json['currency'] as String?,
        hostedUrl: json['hosted_url'] as String?,
        accessCode: json['access_code'] as String?,
        publicKey: json['public_key'] as String?,
        encryptionKey: json['encryption_key'] as String?,
      );
}

/// Optional body fields of `POST /pay/client-session` (besides `channel`).
class ClientSessionOptions {
  const ClientSessionOptions({this.email, this.name, this.returnUrl, this.restart = false});

  /// Required by Paystack/Flutterwave when the transaction has no customer email.
  final String? email;
  final String? name;

  /// http(s) URL the PSP's hosted page redirects to after payment.
  final String? returnUrl;

  /// Replace a session that died on the PSP side (the old one is re-verified first).
  final bool restart;

  Map<String, dynamic> toJson() => {
        if (email != null && email!.isNotEmpty) 'email': email,
        if (name != null && name!.isNotEmpty) 'name': name,
        if (returnUrl != null && returnUrl!.isNotEmpty) 'return_url': returnUrl,
        if (restart) 'restart': true,
      };
}

class SdkConfig {
  const SdkConfig({required this.channels});

  final Map<String, SdkChannelConfig> channels;

  factory SdkConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['channels'] as Map<String, dynamic>? ?? {};
    return SdkConfig(
      channels: raw.map(
        (slug, value) => MapEntry(slug, SdkChannelConfig.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }
}

class MobileMoneyInput {
  const MobileMoneyInput({
    required this.channelSlug,
    required this.phone,
    required this.country,
  });

  final String channelSlug;
  final String phone;
  final String country;
}

class CancelResult {
  const CancelResult({this.redirectUrl});

  final String? redirectUrl;
}
