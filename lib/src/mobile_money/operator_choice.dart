import '../models/models.dart';
import 'mobile_money_data.dart';

/// One operator the payer can pick in the Mobile Money form: a member of an
/// aggregate (`cm.mobile` → `mtn`), or an operator channel of its own
/// (`ci.wave` → `wave`).
class OperatorChoice {
  const OperatorChoice({
    required this.id,
    required this.label,
    required this.name,
    this.logo,
    this.logoPng,
    required this.channelSlug,
    required this.configSlug,
    this.viaAggregate = false,
    required this.badge,
    this.operatorIndependent = false,
  });

  /// `mtn`, `wave`, `eu`: the aggregate member's `operator`, or the
  /// channel's slug after the dot.
  final String id;

  /// What the picker shows: the operator's brand label from the data file,
  /// else [name].
  final String label;

  /// The name the API gives it: the member's `name`, or the channel's name in
  /// the sheet's language.
  final String name;

  /// An `https` URL, else null (the [badge] stands in).
  final String? logo;

  /// The PNG of the same logo, drawn when [logo] does not load.
  final String? logoPng;

  /// The `channel` of `POST /pay/process`: the aggregate's slug for one of
  /// its members, the channel's own slug otherwise.
  final String channelSlug;

  /// The raw slug sdk-config is keyed by: the member's (`cm.mtn`) or the
  /// channel's.
  final String configSlug;

  /// Paid through an aggregate: the request may name the operator.
  final bool viaAggregate;

  /// The operator's brand, else the data file's fallback.
  final OperatorBrand badge;

  /// Takes any number: never an `operator_mismatch`.
  final bool operatorIndependent;
}

/// A channel the Mobile Money form pays through (`mobile_money`, `mobile`).
bool isMobileMoneyChannel(SessionChannel channel) =>
    const {'mobile_money', 'mobile'}.contains(channel.type.toLowerCase());

/// The countries of the Mobile Money channels, upper case, in API order.
List<String> mobileMoneyCountries(Iterable<SessionChannel> channels) {
  final countries = <String>[];
  for (final channel in channels.where(isMobileMoneyChannel)) {
    for (final country in channel.countries) {
      final code = country.toUpperCase();
      if (!countries.contains(code)) countries.add(code);
    }
  }
  return countries;
}

/// The country the form opens on: [requested] when a Mobile
/// Money channel covers it, else [geoCountry] when one covers it, else the
/// first country of the first Mobile Money channel. Null without one.
String? defaultMobileMoneyCountry(Iterable<SessionChannel> channels, {String? requested, String? geoCountry}) {
  final mobile = channels.where(isMobileMoneyChannel).toList();
  bool covered(String? country) =>
      country != null &&
      country.isNotEmpty &&
      mobile.any((c) => c.countries.isEmpty || c.countries.any((cc) => cc.toUpperCase() == country.toUpperCase()));

  if (covered(requested)) return requested!.toUpperCase();
  if (covered(geoCountry)) return geoCountry!.toUpperCase();
  final countries = mobileMoneyCountries(mobile);
  return countries.isEmpty ? null : countries.first;
}

/// The operators the payer can pick for [country], from each
/// Mobile Money channel that covers it, in API order: one per member of an
/// aggregate, one for any other channel. A repeated id keeps the first.
/// [language] (`fr` or `en`) names a channel by `name.fr` or `name`.
List<OperatorChoice> operatorChoices(
  Iterable<SessionChannel> channels,
  String country,
  MobileMoneyData data, {
  required String language,
}) {
  final code = country.toUpperCase();
  final choices = <OperatorChoice>[];

  void add({
    required String id,
    required String name,
    required String? logo,
    required String? logoPng,
    required String channelSlug,
    required String configSlug,
    required bool viaAggregate,
  }) {
    if (id.isEmpty || choices.any((c) => c.id == id)) return;
    final brand = data.operators[id]?.brand;
    choices.add(OperatorChoice(
      id: id,
      label: brand?.label ?? name,
      name: name,
      logo: _httpsUrl(logo),
      logoPng: _httpsUrl(logoPng),
      channelSlug: channelSlug,
      configSlug: configSlug,
      viaAggregate: viaAggregate,
      badge: brand ?? data.fallbackBrand,
      operatorIndependent: data.isOperatorIndependent(id),
    ));
  }

  for (final channel in channels.where(isMobileMoneyChannel)) {
    if (channel.countries.isNotEmpty && !channel.countries.any((c) => c.toUpperCase() == code)) continue;
    if (channel.isAggregate) {
      for (final member in channel.operators) {
        add(
          id: member.operator.toLowerCase(),
          name: member.name,
          logo: member.logo,
          logoPng: member.logoPng,
          channelSlug: channel.slug,
          configSlug: member.slug,
          viaAggregate: true,
        );
      }
    } else {
      add(
        id: _afterDot(channel.slug).toLowerCase(),
        name: channel.localizedName(language),
        logo: channel.logo,
        logoPng: channel.logoPng,
        channelSlug: channel.slug,
        configSlug: channel.slug,
        viaAggregate: false,
      );
    }
  }
  return choices;
}

String _afterDot(String slug) {
  final dot = slug.indexOf('.');
  return dot < 0 ? slug : slug.substring(dot + 1);
}

String? _httpsUrl(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? url : null;
}
