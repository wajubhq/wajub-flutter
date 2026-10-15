import 'package:meta/meta.dart';

import 'json_read.dart';
import 'payment_result.dart';

/// What the payer is doing while a payment is under way: approving it on the
/// phone, dialling a code, or on a provider's page.
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

  /// The provider's instruction for the payer, in English. May hold a code to
  /// dial ("dial *126#").
  final String? payerInstruction;

  /// The provider's page to reopen ("Continue payment").
  final String? actionUrl;

  /// The sandbox 3-D Secure email code.
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

/// The fee, when the payer bears it.
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

/// The customer the payment was created for.
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
    this.errorCode,
    this.errorCodeKnown = false,
  });

  /// Wajub's payment id (`trx_…`), what `GET /payments/{id}` takes.
  final String id;

  /// Your reference for the payment.
  final String reference;
  final String? trxref;

  /// Major units.
  final double amount;

  /// What the payer pays: [amount] plus the fee when the payer bears it.
  final double? amountTotal;
  final String currency;

  /// `pending`, `processing`, `succeeded`, `failed`, `cancelled`, `expired`…;
  /// `unknown` when Wajub did not say.
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

  /// Why the last attempt was refused, while the payment can be paid again.
  final String? errorCode;

  /// Whether the answer said whether a refusal is left (older answers did
  /// not): when false, a null [errorCode] means "not known", not "none".
  @internal
  final bool errorCodeKnown;

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
        errorCode: errorCode,
        errorCodeKnown: errorCodeKnown,
      );

  /// Throws a [FormatException] when the amount is not a number.
  factory SessionTransaction.fromJson(Map<String, dynamic> json) => SessionTransaction(
        id: readString(json['id']) ?? readString(json['reference']) ?? '',
        reference: readString(json['reference']) ?? readString(json['id']) ?? '',
        trxref: readString(json['trxref']),
        amount: requireDouble(json['amount'], 'transaction.amount'),
        amountTotal: readDouble(json['amount_total']),
        currency: readString(json['currency']) ?? '',
        status: readString(json['status']) ?? 'unknown',
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
        errorCode: readText(json['error_code']),
        errorCodeKnown: json.containsKey('error_code'),
      );
}

/// One operator of a Mobile Money channel that groups several (`cm.mobile`).
class ChannelOperator {
  const ChannelOperator({required this.slug, required this.operator, required this.name, this.logo, this.logoPng});

  /// The operator's channel, e.g. `cm.orange`.
  final String slug;

  /// `mtn`, `orange`.
  final String operator;

  /// In the session's locale.
  final String name;
  final String? logo;

  /// The same logo as a PNG, when there is one.
  final String? logoPng;

  factory ChannelOperator.fromJson(Map<String, dynamic> json) {
    final slug = readString(json['slug']) ?? '';
    return ChannelOperator(
      slug: slug,
      operator: readString(json['operator']) ?? (slug.contains('.') ? slug.substring(slug.indexOf('.') + 1) : slug),
      name: readString(json['name']) ?? slug,
      logo: readText(json['logo']),
      logoPng: readText(json['logo_png']),
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
    this.logoPng,
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

  /// The French name.
  final String? nameFr;
  final String type;

  /// The logo, mostly an SVG.
  final String? logo;

  /// The same logo as a PNG, when there is one.
  final String? logoPng;

  /// ISO-2, upper case. Empty for card.
  final List<String> countries;
  final double? minAmount;
  final double? maxAmount;
  final String currency;

  /// The operators of a channel that groups several (`cm.mobile`); empty for
  /// any other channel.
  final List<ChannelOperator> operators;

  /// Whether the channel groups several operators of one country.
  bool get isAggregate => operators.isNotEmpty;

  /// The French name in French, [name] otherwise.
  String localizedName(String language) => language == 'fr' ? (nameFr ?? name) : name;

  factory SessionChannel.fromJson(Map<String, dynamic> json) => SessionChannel(
        id: readString(json['id']) ?? readString(json['slug']) ?? '',
        slug: readString(json['slug']) ?? readString(json['id']) ?? '',
        name: readString(json['name']) ?? readString(json['slug']) ?? '',
        // The API sends the French name under the literal key `name.fr`.
        nameFr: readString(json['name.fr']) ?? readString(json['name_fr']),
        type: readString(json['type']) ?? 'mobile_money',
        logo: readText(json['logo']),
        logoPng: readText(json['logo_png']),
        countries: readStringList(json['countries']).map((c) => c.toUpperCase()).toList(),
        minAmount: readDouble(json['min_amount']),
        maxAmount: readDouble(json['max_amount']),
        currency: readString(json['currency']) ?? '',
        operators: readMapList(json['operators']).map(ChannelOperator.fromJson).toList(),
      );
}

/// Used by the SDK to follow the payment.
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

/// The merchant's look, set in the Dashboard. Every value is optional.
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

  /// White label: hides "Secured by Wajub".
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

  /// The card's background and border colours.
  final String? cardBackgroundColor;
  final String? cardBorderColor;

  /// The logo the sheet's header shows: [logoUrl], else [logoSquareUrl],
  /// else [iconUrl].
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

/// A security check the payment may carry; the SDK completes it, nothing to
/// do with it.
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

  /// Used by the SDK to follow the payment.
  final EchoConfig? echo;
  final String? callback;

  /// The session's `locale` as sent: `fr`, `en`, or null.
  final String? sessionLocale;
  final Branding merchantBranding;

  /// A security check the SDK completes before a payment.
  final AltchaChallenge? altcha;

  /// The payer's country (ISO-2), when Wajub can tell.
  final String? geoCountry;

  /// The merchant's pages for a paid and a cancelled payment.
  final String? returnUrl;
  final String? cancelUrl;

  /// Used by the SDK to follow the payment.
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

/// The values of [SdkChannelConfig.sdk]: how a payment method collects what
/// it needs. String constants, not an enum.
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

  /// The provider expected to take the payment; the one that does is
  /// [ClientSession.provider].
  final String? provider;
  final String? sdk;
  final String? publishableKey;
  final List<String> requiredFields;

  /// Whether the card is paid on the provider's own checkout
  /// (`WajubSession.startClientSession`).
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

/// A card payment on the provider's own checkout.
///
/// Open [hostedUrl] in the system browser, then call
/// `WajubSession.completeClientSession` with [id] when the payer returns.
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

  /// What `WajubSession.completeClientSession` takes.
  final String id;
  final String provider;

  /// The provider's reference.
  final String? reference;

  /// In the provider's own units.
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

/// What `WajubSession.startClientSession` may take besides the channel.
class ClientSessionOptions {
  const ClientSessionOptions({
    this.email,
    this.name,
    this.returnUrl,
    this.restart = false,
    this.billing = const {},
  });

  /// Required when the payment has no customer email.
  final String? email;
  final String? name;

  /// Where the provider's page sends the payer back after paying.
  final String? returnUrl;

  /// Start again when the provider's checkout has expired.
  final bool restart;

  /// The other contact or billing fields the card payment asks for
  /// ([SdkChannelConfig.requiredFields]).
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

  /// By channel slug.
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

  /// For a channel that groups several operators (`cm.mobile`): the
  /// operator the payer picked (`mtn`).
  final String? operator;
}

class CancelResult {
  const CancelResult({this.redirectUrl});

  final String? redirectUrl;
}

/// The payment's status, as `WajubSession.status()` reads it.
class PaymentStatusUpdate {
  const PaymentStatusUpdate({required this.status, this.reference, this.errorCode, this.payerMessage});

  /// `pending`, `processing`, `succeeded`…; null when Wajub did not say.
  final String? status;

  /// Wajub's payment id (`trx_…`), not your reference.
  final String? reference;

  /// Why the last attempt was refused, while the payment is back at `pending`.
  final String? errorCode;

  /// A message for the payer, in English.
  final String? payerMessage;

  factory PaymentStatusUpdate.fromJson(Map<String, dynamic> json) {
    final fields = readMap(json['transaction']) ?? json;
    return PaymentStatusUpdate(
      status: readText(fields['status'])?.toLowerCase(),
      reference: readString(fields['reference']),
      errorCode: readText(fields['error_code']),
      payerMessage: readText(fields['payer_message']),
    );
  }
}

/// The answer to a confirmation step (`WajubSession.verifyStep`).
class StepVerifyResult {
  const StepVerifyResult({
    required this.success,
    this.transaction,
    this.attemptsRemaining,
    this.errorCode,
    this.errorMessage,
    this.action,
    this.next,
  });

  final bool success;

  /// On success without [next]: its `status` decides (`succeeded` is paid;
  /// it may still be `processing`).
  final SessionTransaction? transaction;

  /// On success, when the provider asks for another step: its action
  /// (`confirm_otp`, `redirect`…).
  final String? action;

  /// That next step: [PaymentRequiresAction] with its `step` and `stepId`
  /// (or the page to open), or [PaymentFailed] with `unsupported_action`
  /// when the SDK cannot perform it.
  final PaymentResult? next;
  final int? attemptsRemaining;

  /// `invalid_otp`, `otp_expired`, `max_attempts_exceeded`, …
  final String? errorCode;

  /// Wajub's own message, in English.
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
      action: readText(json['action']),
    );
  }

  /// This answer with the [next] step it asks for.
  StepVerifyResult withNext(PaymentResult next) => StepVerifyResult(
        success: success,
        transaction: transaction,
        attemptsRemaining: attemptsRemaining,
        errorCode: errorCode,
        errorMessage: errorMessage,
        action: action,
        next: next,
      );
}
