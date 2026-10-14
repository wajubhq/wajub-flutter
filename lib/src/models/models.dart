import 'json_read.dart';

/// `transaction.processing_context`: present while the payment is
/// `processing` or `partial`, to restore what the payer was doing.
class ProcessingContext {
  const ProcessingContext({
    this.channelSlug,
    this.isMobileMoney = false,
    this.isUssd = false,
    this.isBankTransfer = false,
    this.payerInstruction,
    this.actionUrl,
    this.threeDsId,
    this.threeDsMethod,
    this.maskedEmail,
    this.threeDsTimeout,
  });

  final String? channelSlug;
  final bool isMobileMoney;
  final bool isUssd;
  final bool isBankTransfer;

  /// English. May hold a USSD fallback ("dial *126#").
  final String? payerInstruction;

  /// The provider's page to reopen ("Continue payment").
  final String? actionUrl;

  /// Sandbox 3-D Secure email code.
  final String? threeDsId;
  final String? threeDsMethod;
  final String? maskedEmail;

  /// Seconds.
  final int? threeDsTimeout;

  factory ProcessingContext.fromJson(Map<String, dynamic> json) => ProcessingContext(
        channelSlug: readString(json['channel_slug']),
        isMobileMoney: readBool(json['is_mobile_money']) ?? false,
        isUssd: readBool(json['is_ussd']) ?? false,
        isBankTransfer: readBool(json['is_bank_transfer']) ?? false,
        payerInstruction: readText(json['payer_instruction']),
        actionUrl: readText(json['action_url']),
        threeDsId: readText(json['three_ds_id']),
        threeDsMethod: readString(json['three_ds_method']),
        maskedEmail: readString(json['masked_email']),
        threeDsTimeout: readInt(json['three_ds_timeout']),
      );
}

/// `transaction.fee` when the payer bears it.
class TransactionFee {
  const TransactionFee({required this.amount, this.rate, this.description});

  /// Major units.
  final double amount;

  /// Decimal, e.g. 0.035.
  final double? rate;
  final String? description;

  static TransactionFee? fromJson(Object? json) {
    final map = readMap(json);
    final amount = readDouble(map?['amount']);
    if (map == null || amount == null) return null;
    return TransactionFee(amount: amount, rate: readDouble(map['rate']), description: readString(map['description']));
  }
}

/// `transaction.customer`.
class TransactionCustomer {
  const TransactionCustomer({this.name, this.email});

  final String? name;
  final String? email;

  static TransactionCustomer? fromJson(Object? json) {
    final map = readMap(json);
    if (map == null) return null;
    return TransactionCustomer(name: readText(map['name']), email: readText(map['email']));
  }
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
    this.bearer,
    this.fee,
    this.customer,
    this.receiptUrl,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
    this.terminalAt,
  });

  /// Wajub's payment id (`trx_…`): the realtime channel's suffix.
  final String id;

  /// The merchant's reference. `GET /pay/status` calls the payment id
  /// `reference`: never compare the two.
  final String reference;
  final String? trxref;

  /// Major units.
  final double amount;

  /// What the payer pays: [amount] plus the fee when the payer bears it.
  final double? amountTotal;
  final String currency;
  final String status;
  final String? statusLabel;
  final bool sandbox;
  final String? description;
  final ProcessingContext? processingContext;

  /// `merchant` or `customer`: who bears the fee.
  final String? bearer;
  final TransactionFee? fee;
  final TransactionCustomer? customer;
  final String? receiptUrl;

  /// ISO 8601.
  final String? expiresAt;
  final String? createdAt;
  final String? updatedAt;
  final String? terminalAt;

  /// The amount to show and to report: [amountTotal], else [amount].
  double get payableAmount => amountTotal ?? amount;

  SessionTransaction copyWith({ProcessingContext? processingContext, String? status}) => SessionTransaction(
        id: id,
        reference: reference,
        trxref: trxref,
        amount: amount,
        amountTotal: amountTotal,
        currency: currency,
        status: status ?? this.status,
        statusLabel: statusLabel,
        sandbox: sandbox,
        description: description,
        processingContext: processingContext ?? this.processingContext,
        bearer: bearer,
        fee: fee,
        customer: customer,
        receiptUrl: receiptUrl,
        expiresAt: expiresAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        terminalAt: terminalAt,
      );

  /// Throws a [FormatException] when `amount` is not a number: every other
  /// key falls back.
  factory SessionTransaction.fromJson(Map<String, dynamic> json) => SessionTransaction(
        id: readString(json['id']) ?? readString(json['reference']) ?? '',
        reference: readString(json['reference']) ?? readString(json['id']) ?? '',
        trxref: readString(json['trxref']),
        amount: requireDouble(json['amount'], 'transaction.amount'),
        amountTotal: readDouble(json['amount_total']),
        currency: readString(json['currency']) ?? '',
        status: readString(json['status']) ?? 'pending',
        statusLabel: readString(json['status_label']),
        sandbox: readBool(json['sandbox']) ?? false,
        description: readString(json['description']),
        processingContext: readMap(json['processing_context']) != null
            ? ProcessingContext.fromJson(readMap(json['processing_context'])!)
            : null,
        bearer: readString(json['bearer']),
        fee: TransactionFee.fromJson(json['fee']),
        customer: TransactionCustomer.fromJson(json['customer']),
        receiptUrl: readText(json['receipt_url']),
        expiresAt: readText(json['expires_at']),
        createdAt: readText(json['created_at']),
        updatedAt: readText(json['updated_at']),
        terminalAt: readText(json['terminal_at']),
      );
}

/// One member of an aggregate channel (`cm.mobile`): a real operator channel.
class ChannelOperator {
  const ChannelOperator({required this.slug, required this.operator, required this.name, this.logo});

  /// The operator's own channel, e.g. `cm.orange`.
  final String slug;

  /// `mtn`, `orange`.
  final String operator;

  /// In the session's locale.
  final String name;
  final String? logo;

  factory ChannelOperator.fromJson(Map<String, dynamic> json) {
    final slug = readString(json['slug']) ?? '';
    return ChannelOperator(
      slug: slug,
      operator: readString(json['operator']) ?? (slug.contains('.') ? slug.substring(slug.indexOf('.') + 1) : slug),
      name: readString(json['name']) ?? slug,
      logo: readText(json['logo']),
    );
  }
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
    this.operators = const [],
  });

  final String id;
  final String slug;

  /// In the session's locale.
  final String name;

  /// Always French (the API's literal key `name.fr`).
  final String? nameFr;
  final String type;
  final String? logo;

  /// ISO-2, upper case. Empty for card.
  final List<String> countries;
  final double? minAmount;
  final double? maxAmount;
  final String currency;

  /// The members of an aggregate (`cm.mobile`); empty for any other channel.
  final List<ChannelOperator> operators;

  /// An aggregate folds several operators of one country (`cm.mobile`).
  bool get isAggregate => operators.isNotEmpty;

  /// `name.fr` in French, `name` otherwise.
  String localizedName(String language) => language == 'fr' ? (nameFr ?? name) : name;

  factory SessionChannel.fromJson(Map<String, dynamic> json) => SessionChannel(
        id: readString(json['id']) ?? readString(json['slug']) ?? '',
        slug: readString(json['slug']) ?? readString(json['id']) ?? '',
        name: readString(json['name']) ?? readString(json['slug']) ?? '',
        // The API sends the French name under the literal key `name.fr`.
        nameFr: readString(json['name.fr']) ?? readString(json['name_fr']),
        type: readString(json['type']) ?? 'mobile_money',
        logo: readText(json['logo']),
        countries: readStringList(json['countries']).map((c) => c.toUpperCase()).toList(),
        minAmount: readDouble(json['min_amount']),
        maxAmount: readDouble(json['max_amount']),
        currency: readString(json['currency']) ?? '',
        operators: readMapList(json['operators']).map(ChannelOperator.fromJson).toList(),
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

  /// With its scheme: `wss://ws.wajub.com`, `ws://localhost`.
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

/// The merchant's look, from `GET /pay/session` `branding`. It comes from
/// one of three sources with slightly different keys: every one is optional.
class Branding {
  const Branding({
    this.primaryColor,
    this.secondaryColor,
    this.backgroundColor,
    this.logoUrl,
    this.logoSquareUrl,
    this.iconUrl,
    this.businessName,
    this.borderRadius,
    this.font,
    this.appearanceMode,
    this.density,
    this.whiteLabel = false,
    this.inputBackgroundColor,
    this.inputBorderColor,
    this.textMutedColor,
    this.buttonTextColor,
    this.successColor,
    this.errorColor,
    this.shadow,
    this.overlayIntensity,
    this.fontWeightHeading,
    this.fontWeightBody,
    this.separatorColor,
    this.cardBackgroundColor,
    this.cardBorderColor,
  });

  final String? primaryColor;
  final String? secondaryColor;
  final String? backgroundColor;
  final String? logoUrl;
  final String? logoSquareUrl;
  final String? iconUrl;
  final String? businessName;

  /// `"12px"`, `"12"`, or `none`, `sm`, `md`, `lg`, `xl`.
  final String? borderRadius;
  final String? font;

  /// `light`, `dark`, `system`, or absent.
  final String? appearanceMode;

  /// `comfortable` or `compact`.
  final String? density;

  /// Hides "Secured by Wajub". The API sends a boolean, the web also takes
  /// `{enabled: …}`: both read here.
  final bool whiteLabel;
  final String? inputBackgroundColor;
  final String? inputBorderColor;
  final String? textMutedColor;
  final String? buttonTextColor;
  final String? successColor;
  final String? errorColor;

  /// `none`, `low`, `high`.
  final String? shadow;

  /// 0–100.
  final int? overlayIntensity;
  final int? fontWeightHeading;
  final int? fontWeightBody;
  final String? separatorColor;

  /// The literal keys `card.background_color` and `card.border_color`.
  final String? cardBackgroundColor;
  final String? cardBorderColor;

  /// The header logo: `logo_url`, else `logo_square_url`, else `icon_url`.
  String? get logo => logoUrl ?? logoSquareUrl ?? iconUrl;

  factory Branding.fromJson(Map<String, dynamic> json) {
    final whiteLabel = json['white_label'];
    return Branding(
      primaryColor: readText(json['primary_color']),
      secondaryColor: readText(json['secondary_color']),
      backgroundColor: readText(json['background_color']),
      logoUrl: readText(json['logo_url']),
      logoSquareUrl: readText(json['logo_square_url']),
      iconUrl: readText(json['icon_url']),
      businessName: readText(json['business_name']),
      borderRadius: readText(json['border_radius']),
      font: readText(json['font']),
      appearanceMode: readText(json['appearance_mode'])?.toLowerCase(),
      density: readText(json['density'])?.toLowerCase(),
      whiteLabel: (whiteLabel is Map ? readBool(readMap(whiteLabel)!['enabled']) : readBool(whiteLabel)) ?? false,
      inputBackgroundColor: readText(json['input_background_color']),
      inputBorderColor: readText(json['input_border_color']),
      textMutedColor: readText(json['text_muted_color']),
      buttonTextColor: readText(json['button_text_color']),
      successColor: readText(json['success_color']),
      errorColor: readText(json['error_color']),
      shadow: readText(json['shadow'])?.toLowerCase(),
      overlayIntensity: readInt(json['overlay_intensity']),
      fontWeightHeading: _fontWeight(json['font_weight_heading']),
      fontWeightBody: _fontWeight(json['font_weight_body']),
      separatorColor: readText(json['separator_color']),
      cardBackgroundColor: readText(json['card.background_color']),
      cardBorderColor: readText(json['card.border_color']),
    );
  }

  /// An integer, or a string the dashboard stored: `"400"`, `"bold"`.
  static int? _fontWeight(Object? value) => switch (readText(value)?.toLowerCase()) {
        'normal' => 400,
        'bold' => 700,
        final text => readInt(text),
      };
}

/// The Altcha proof-of-work challenge the API may ask for before a payment.
class AltchaChallenge {
  const AltchaChallenge({
    required this.algorithm,
    required this.challenge,
    required this.salt,
    required this.signature,
    required this.maxNumber,
  });

  final String algorithm;
  final String challenge;
  final String salt;
  final String signature;
  final int maxNumber;

  static AltchaChallenge? fromJson(Object? json) {
    final map = readMap(json);
    final challenge = readText(map?['challenge']);
    final salt = readString(map?['salt']);
    if (map == null || challenge == null || salt == null) return null;
    return AltchaChallenge(
      algorithm: readString(map['algorithm']) ?? 'SHA-256',
      challenge: challenge,
      salt: salt,
      signature: readString(map['signature']) ?? '',
      maxNumber: readInt(map['maxnumber']) ?? 1000000,
    );
  }
}

class SessionData {
  const SessionData({
    required this.transaction,
    required this.channels,
    this.locale = 'en',
    this.branding = const {},
    this.echo,
    this.callback,
    this.sessionLocale,
    this.merchantBranding = const Branding(),
    this.altcha,
    this.geoCountry,
    this.returnUrl,
    this.cancelUrl,
    this.echoSettings,
  });

  final SessionTransaction transaction;
  final List<SessionChannel> channels;

  /// The session's language, `en` when it names none (see [sessionLocale]).
  final String locale;

  /// The raw branding values in their text form. [merchantBranding] reads
  /// them with their types.
  final Map<String, String?> branding;

  /// The realtime settings, when they name an app key. [echoSettings] keeps
  /// them even without one.
  final EchoConfig? echo;
  final String? callback;

  /// The session's `locale` as sent: `fr`, `en`, or null.
  final String? sessionLocale;
  final Branding merchantBranding;

  /// Non-null when the API asks for a proof of work before a payment.
  final AltchaChallenge? altcha;

  /// ISO-2 of the payer's IP, when the API could tell.
  final String? geoCountry;

  /// The merchant callbacks with `status=succeeded` / `status=cancelled`.
  final String? returnUrl;
  final String? cancelUrl;

  /// `echo` as sent, `key` included even when null.
  final EchoConfig? echoSettings;

  factory SessionData.fromJson(Map<String, dynamic> json) {
    final brandingRaw = readMap(json['branding']) ?? const {};
    final echoRaw = readMap(json['echo']);
    final sessionLocale = readText(json['locale'])?.toLowerCase();
    return SessionData(
      transaction: SessionTransaction.fromJson(readMap(json['transaction']) ?? const {}),
      channels: readMapList(json['channels']).map(SessionChannel.fromJson).toList(),
      locale: sessionLocale ?? 'en',
      // Values keep their text form: `white_label` (bool) reads "true" or
      // "false", `overlay_intensity` (int) its digits.
      branding: brandingRaw.map((k, v) => MapEntry(k, readString(v))),
      echo: echoRaw != null && readText(echoRaw['key']) != null ? EchoConfig.fromJson(echoRaw) : null,
      callback: readString(json['callback']),
      sessionLocale: sessionLocale,
      merchantBranding: Branding.fromJson(brandingRaw),
      altcha: AltchaChallenge.fromJson(json['altcha']),
      geoCountry: readText(json['geo_country'])?.toUpperCase(),
      returnUrl: readText(json['return_url']),
      cancelUrl: readText(json['cancel_url']),
      echoSettings: echoRaw != null ? EchoConfig.fromJson(echoRaw) : null,
    );
  }
}

/// Known `sdk-config` flavors (`SdkChannelConfig.sdk`). `adyen_custom_card`
/// and `psp_inline` need a web component: on mobile those cards go through a
/// client session when sdk-config allows one, and are hidden otherwise.
/// `paystack_inline`/`flutterwave_inline` are legacy values api.wajub no
/// longer sends.
abstract final class SdkFlavor {
  static const form = 'form';
  static const stripeElements = 'stripe_elements';
  static const hostedRedirect = 'hosted_redirect';
  static const adyenCustomCard = 'adyen_custom_card';
  static const pspInline = 'psp_inline';
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
        publishableKey: readText(json['publishable_key']),
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
    this.customerEmail,
    this.customerName,
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
  final String? customerEmail;
  final String? customerName;

  factory ClientSession.fromJson(Map<String, dynamic> json) => ClientSession(
        id: json['id']?.toString() ?? '',
        provider: readString(json['provider']) ?? '',
        reference: readString(json['reference']),
        amount: json['amount'] is num ? json['amount'] as num : readDouble(json['amount']),
        currency: readString(json['currency']),
        hostedUrl: readText(json['hosted_url']),
        accessCode: readString(json['access_code']),
        publicKey: readString(json['public_key']),
        encryptionKey: readString(json['encryption_key']),
        customerEmail: readText(json['customer_email']),
        customerName: readText(json['customer_name']),
      );
}

/// Optional body fields of `POST /pay/client-session` (besides `channel`).
class ClientSessionOptions {
  const ClientSessionOptions({
    this.email,
    this.name,
    this.returnUrl,
    this.restart = false,
    this.billing = const {},
  });

  /// Required by Paystack/Flutterwave when the transaction has no customer email.
  final String? email;
  final String? name;

  /// http(s) URL the PSP's hosted page redirects to after payment.
  final String? returnUrl;

  /// Replace a session that died on the PSP side (the old one is re-verified first).
  final bool restart;

  /// Other contact or billing fields sdk-config lists in `required_fields`
  /// (`first_name`, `phone`, `country`…), sent flat.
  final Map<String, String> billing;

  Map<String, dynamic> toJson() => {
        for (final entry in billing.entries)
          if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
        if (email != null && email!.isNotEmpty) 'email': email,
        if (name != null && name!.isNotEmpty) 'name': name,
        if (returnUrl != null && returnUrl!.isNotEmpty) 'return_url': returnUrl,
        if (restart) 'restart': true,
      };
}

class SdkConfig {
  const SdkConfig({required this.channels});

  /// Keyed by RAW slug (`cm.mtn`, `cm.orange` — never `cm.mobile`).
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
    this.operator,
  });

  final String channelSlug;

  /// E.164 (`+237677123456`); [PaymentSheet] builds it from what the payer typed.
  final String phone;
  final String country;

  /// Only for an aggregate channel (`cm.mobile`): the operator the payer
  /// named (`mtn`). See `MobileMoneyRules.operatorHint`.
  final String? operator;
}

class CancelResult {
  const CancelResult({this.redirectUrl});

  final String? redirectUrl;
}

/// One answer of `GET /pay/status`, or one realtime `PaymentStatusUpdated`
/// event: both carry the same fields.
class PaymentStatusUpdate {
  const PaymentStatusUpdate({required this.status, this.reference, this.errorCode, this.payerMessage});

  final String status;

  /// Wajub's payment id (`trx_…`) — not the merchant's reference.
  final String? reference;

  /// Why the last attempt was refused, while the payment is back at `pending`.
  final String? errorCode;

  /// English.
  final String? payerMessage;

  /// `GET /pay/status` nests the fields under `transaction`; a realtime
  /// event carries them at its root.
  factory PaymentStatusUpdate.fromJson(Map<String, dynamic> json) {
    final fields = readMap(json['transaction']) ?? json;
    return PaymentStatusUpdate(
      status: readString(fields['status'])?.toLowerCase() ?? 'pending',
      reference: readString(fields['reference']),
      errorCode: readText(fields['error_code']),
      payerMessage: readText(fields['payer_message']),
    );
  }
}

/// The answer of `POST /pay/{otp,pin,phone,birthday,address}/verify`. Both
/// outcomes arrive as HTTP 200.
class StepVerifyResult {
  const StepVerifyResult({
    required this.success,
    this.transaction,
    this.attemptsRemaining,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;

  /// On success: its `status` decides (it may still be `processing`).
  final SessionTransaction? transaction;
  final int? attemptsRemaining;

  /// `invalid_otp`, `otp_expired`, `max_attempts_exceeded`, …
  final String? errorCode;

  /// The API's own (English) message.
  final String? errorMessage;

  factory StepVerifyResult.fromJson(Map<String, dynamic> json) {
    final error = readMap(json['error']);
    final transaction = readMap(json['transaction']);
    return StepVerifyResult(
      success: readString(json['status'])?.toLowerCase() == 'success',
      transaction: transaction != null ? SessionTransaction.fromJson(transaction) : null,
      attemptsRemaining: readInt(json['attempts_remaining']),
      errorCode: readText(error?['code']),
      errorMessage: readText(error?['message']),
    );
  }
}
