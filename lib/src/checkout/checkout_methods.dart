import '../mapper/payment_mapper.dart';
import '../mobile_money/operator_choice.dart';
import '../models/models.dart';
import '../models/sdk_flavor.dart';

/// The families the sheet reports with its states (`method`).
enum MethodFamily {
  mobileMoney('mobile_money'),
  card('card'),
  wallet('wallet');

  const MethodFamily(this.wireName);

  final String wireName;
}

/// How the card channel is paid on mobile.
enum CardFlavour {
  /// The card provider's own checkout.
  clientSession,

  /// Stripe's native card field.
  stripe,

  /// A PSP page in the browser, after the contact fields it needs.
  hostedRedirect,

  /// The sandbox test-card form.
  sandboxForm,
}

/// The card flavour for an sdk-config `card` entry, first match wins:
/// client session, Stripe, hosted redirect, sandbox form; null hides card.
CardFlavour? cardFlavour(SdkChannelConfig? config, {required bool sandbox}) {
  if (config == null || !config.available) return null;
  if (config.clientSession) return CardFlavour.clientSession;
  if (config.sdk == SdkFlavor.stripeElements) {
    return config.publishableKey == null ? null : CardFlavour.stripe;
  }
  if (config.sdk == SdkFlavor.hostedRedirect) return CardFlavour.hostedRedirect;
  if (config.sdk == SdkFlavor.form && sandbox) return CardFlavour.sandboxForm;
  return null;
}

/// The contact and billing fields a card provider's page may ask the payer
/// for; any other `required_fields` only a web component can produce.
List<String> hostedCardRequiredFields(SdkChannelConfig? config) =>
    (config?.requiredFields ?? const []).where(PaymentMapper.hostedCardFields.contains).toList();

/// One entry of the method list.
class CheckoutMethod {
  const CheckoutMethod({
    required this.family,
    required this.channels,
    this.config,
    this.cardFlavour,
    this.limit,
  });

  final MethodFamily family;

  /// Mobile Money: every Mobile Money channel the payer can use; card and
  /// wallets: their channel.
  final List<SessionChannel> channels;

  /// Card and wallets: the channel's sdk-config entry.
  final SdkChannelConfig? config;
  final CardFlavour? cardFlavour;

  /// Set when the amount is outside the channel's limits: the method shows
  /// disabled with it.
  final MethodLimit? limit;

  bool get enabled => limit == null;
  SessionChannel get channel => channels.first;
}

/// A channel's `min_amount` or `max_amount` the amount falls outside.
class MethodLimit {
  const MethodLimit({required this.minimum, required this.amount, required this.currency});

  /// `true`: under the minimum; `false`: over the maximum.
  final bool minimum;
  final double amount;
  final String currency;
}

/// What the method list offers: Mobile Money (all its
/// channels in one form), the card when sdk-config names a flavour this SDK
/// can draw, and one-tap wallets — in the API's order. Anything else is not
/// shown. [config] is null when `GET /pay/sdk-config` failed: Mobile Money
/// still works.
List<CheckoutMethod> buildMethods(SessionData session, SdkConfig? config) {
  final amount = session.transaction.payableAmount;
  final sandbox = session.transaction.sandbox;
  final methods = <CheckoutMethod>[];
  final mobile = <SessionChannel>[];
  MethodLimit? mobileLimit;
  var mobileIndex = -1;

  for (final channel in session.channels) {
    final type = channel.type.toLowerCase();
    if (isMobileMoneyChannel(channel)) {
      if (!_mobileMoneyAvailable(channel, config)) continue;
      if (mobileIndex < 0) {
        // Its place in the list: completed with every channel below.
        mobileIndex = methods.length;
        methods.add(const CheckoutMethod(family: MethodFamily.mobileMoney, channels: []));
      }
      final limit = _limit(channel, amount, session.transaction.currency);
      if (limit == null) {
        mobile.add(channel);
      } else {
        mobileLimit ??= limit;
      }
    } else if (type == 'card') {
      final entry = config?.channels[channel.slug];
      final flavour = cardFlavour(entry, sandbox: sandbox);
      if (flavour == null) continue;
      methods.add(CheckoutMethod(
        family: MethodFamily.card,
        channels: [channel],
        config: entry,
        cardFlavour: flavour,
        limit: _limit(channel, amount, session.transaction.currency),
      ));
    } else if (PaymentMapper.isRedirectWalletChannel(channel, config?.channels[channel.slug])) {
      methods.add(CheckoutMethod(
        family: MethodFamily.wallet,
        channels: [channel],
        config: config?.channels[channel.slug],
        limit: _limit(channel, amount, session.transaction.currency),
      ));
    }
  }
  if (mobileIndex >= 0) {
    methods[mobileIndex] = CheckoutMethod(
      family: MethodFamily.mobileMoney,
      channels: mobile,
      limit: mobile.isEmpty ? mobileLimit : null,
    );
  }
  return methods;
}

/// sdk-config is looked up by the session's slug: an aggregate (`cm.mobile`)
/// uses its own entry, else — an older answer — its members' (`cm.mtn`,
/// `cm.orange`). A Mobile Money channel without any entry (a failed
/// sdk-config, or an older sandbox answer) is a form asking for the phone;
/// `available: false` hides it.
bool _mobileMoneyAvailable(SessionChannel channel, SdkConfig? config) {
  if (config == null) return true;
  final own = config.channels[channel.slug];
  if (own != null) return own.available;
  if (!channel.isAggregate) return true;
  final members =
      channel.operators.map((member) => config.channels[member.slug]).whereType<SdkChannelConfig>().toList();
  return members.isEmpty || members.any((entry) => entry.available);
}

/// [amount] is the payment's total; a channel with a total of its own (its
/// fee included) is compared with that one.
MethodLimit? _limit(SessionChannel channel, double amount, String currency) {
  amount = channel.amountTotal ?? amount;
  final min = channel.minAmount;
  final max = channel.maxAmount;
  if (min != null && amount < min) return MethodLimit(minimum: true, amount: min, currency: currency);
  if (max != null && amount > max) return MethodLimit(minimum: false, amount: max, currency: currency);
  return null;
}

/// The currencies written without decimals.
const _zeroDecimal = {
  'XAF', 'XOF', 'XPF', 'GNF', 'RWF', 'UGX', 'KMF', 'DJF', 'BIF', 'JPY', 'KRW', 'VND', 'CLP', 'PYG', 'VUV', //
};

/// `25 000 XAF` in French, `25,000 XAF` in English; two decimals for the
/// currencies that have them (`49,90 EUR`).
String formatAmount(double amount, String currency, String language) {
  final decimals = _zeroDecimal.contains(currency.toUpperCase()) ? 0 : 2;
  final fixed = amount.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts.first.replaceFirst('-', '');
  final group = language == 'fr' ? ' ' : ',';
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(group);
    grouped.write(whole[i]);
  }
  final sign = amount < 0 ? '-' : '';
  final fraction = decimals == 0 ? '' : '${language == 'fr' ? ',' : '.'}${parts.last}';
  return '$sign$grouped$fraction ${currency.toUpperCase()}'.trim();
}
