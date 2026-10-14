import 'json_read.dart';

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
        channelSlug: readString(json['channel_slug']),
        isMobileMoney: readBool(json['is_mobile_money']) ?? false,
        payerInstruction: readString(json['payer_instruction']),
        actionUrl: readString(json['action_url']),
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
        id: readString(json['id']) ?? readString(json['reference']) ?? '',
        reference: readString(json['reference']) ?? readString(json['id']) ?? '',
        trxref: readString(json['trxref']),
        amount: readDouble(json['amount']) ?? 0,
        amountTotal: readDouble(json['amount_total']),
        currency: readString(json['currency']) ?? '',
        status: readString(json['status']) ?? 'pending',
        statusLabel: readString(json['status_label']),
        sandbox: readBool(json['sandbox']) ?? false,
        description: readString(json['description']),
        processingContext: readMap(json['processing_context']) != null
            ? ProcessingContext.fromJson(readMap(json['processing_context'])!)
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
        id: readString(json['id']) ?? readString(json['slug']) ?? '',
        slug: readString(json['slug']) ?? readString(json['id']) ?? '',
        name: readString(json['name']) ?? readString(json['slug']) ?? '',
        // The API sends the French name under the literal key `name.fr`.
        nameFr: readString(json['name.fr']) ?? readString(json['name_fr']),
        type: readString(json['type']) ?? 'mobile_money',
        logo: readString(json['logo']),
        countries: readStringList(json['countries']),
        minAmount: readDouble(json['min_amount']),
        maxAmount: readDouble(json['max_amount']),
        currency: readString(json['currency']) ?? '',
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
        key: readString(json['key']) ?? '',
        wsHost: readString(json['ws_host']) ?? '',
        wsPort: readInt(json['ws_port']) ?? 443,
        channelPrefix: readString(json['channel_prefix']) ?? 'private-payment.',
        broadcaster: readString(json['broadcaster']) ?? 'pusher',
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
    final brandingRaw = readMap(json['branding']) ?? const {};
    final echoRaw = readMap(json['echo']);
    return SessionData(
      transaction: SessionTransaction.fromJson(readMap(json['transaction']) ?? const {}),
      channels: (json['channels'] is List ? json['channels'] as List<dynamic> : const [])
          .map(readMap)
          .whereType<Map<String, dynamic>>()
          .map(SessionChannel.fromJson)
          .toList(),
      locale: readString(json['locale']) ?? 'en',
      // Values keep their text form: `white_label` (bool) reads "true" or
      // "false", `overlay_intensity` (int) its digits.
      branding: brandingRaw.map((k, v) => MapEntry(k, readString(v))),
      echo: echoRaw != null && readString(echoRaw['key']) != null ? EchoConfig.fromJson(echoRaw) : null,
      callback: readString(json['callback']),
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
        available: readBool(json['available']) ?? false,
        provider: readString(json['provider']),
        sdk: readString(json['sdk']),
        publishableKey: readString(json['publishable_key']),
        requiredFields: readStringList(json['required_fields']),
        clientSession: readBool(json['client_session']) ?? false,
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
        provider: readString(json['provider']) ?? '',
        reference: readString(json['reference']),
        amount: json['amount'] is num ? json['amount'] as num : readDouble(json['amount']),
        currency: readString(json['currency']),
        hostedUrl: readString(json['hosted_url']),
        accessCode: readString(json['access_code']),
        publicKey: readString(json['public_key']),
        encryptionKey: readString(json['encryption_key']),
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
    final raw = readMap(json['channels']) ?? const {};
    return SdkConfig(
      channels: {
        for (final entry in raw.entries)
          if (readMap(entry.value) != null) entry.key: SdkChannelConfig.fromJson(readMap(entry.value)!),
      },
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
