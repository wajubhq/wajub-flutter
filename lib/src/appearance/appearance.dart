/// Wajub.js's variables (`appearance.variables`), under the same names, so a
/// merchant styles the web Components and this sheet with one object.
///
/// Values are strings as in Wajub.js: colours `#rgb`, `#rrggbb`,
/// `#rrggbbaa`, `rgb()`, `rgba()`; lengths `"8px"`, `"8"`, `"0.5rem"`; font
/// weights `"400"`…`"700"`, `"normal"`, `"bold"`. A value that does not parse
/// is ignored, never an error.
class AppearanceVariables {
  const AppearanceVariables({
    this.colorPrimary,
    this.colorBackground,
    this.colorText,
    this.colorTextSecondary,
    this.colorTextPlaceholder,
    this.colorDanger,
    this.colorSuccess,
    this.fontFamily,
    this.fontSizeBase,
    this.fontWeightNormal,
    this.fontWeightMedium,
    this.fontWeightBold,
    this.spacingUnit,
    this.borderRadius,
    this.spacingGridRow,
    this.spacingGridColumn,
  });

  /// The Pay button, the selected operator, the focus ring, links.
  final String? colorPrimary;

  /// The sheet's surface; also the inputs' when `inputBackgroundColor` is unset.
  final String? colorBackground;

  /// Main text and typed values.
  final String? colorText;

  /// Labels, hints, secondary lines.
  final String? colorTextSecondary;

  /// Placeholders.
  final String? colorTextPlaceholder;

  /// Field errors and the failure screen.
  final String? colorDanger;

  /// The success screen.
  final String? colorSuccess;

  /// A CSS font stack: the first family is used, the platform's font when it
  /// names a system or generic family.
  final String? fontFamily;

  /// Input text; labels and hints are smaller. Inputs never go below 16.
  final String? fontSizeBase;
  final String? fontWeightNormal;
  final String? fontWeightMedium;
  final String? fontWeightBold;

  /// The base of every padding and gap.
  final String? spacingUnit;

  /// Inputs, buttons, list boxes; capped at 22.
  final String? borderRadius;

  /// The vertical gap between fields.
  final String? spacingGridRow;

  /// The horizontal gap between side-by-side fields.
  final String? spacingGridColumn;

  /// Wajub.js's `variables` object as a map: unknown keys and values that are
  /// neither strings nor (for lengths and weights) numbers are ignored.
  factory AppearanceVariables.fromMap(Map<String, Object?> map) => AppearanceVariables(
        colorPrimary: _string(map['colorPrimary']),
        colorBackground: _string(map['colorBackground']),
        colorText: _string(map['colorText']),
        colorTextSecondary: _string(map['colorTextSecondary']),
        colorTextPlaceholder: _string(map['colorTextPlaceholder']),
        colorDanger: _string(map['colorDanger']),
        colorSuccess: _string(map['colorSuccess']),
        fontFamily: _string(map['fontFamily']),
        fontSizeBase: _length(map['fontSizeBase']),
        fontWeightNormal: _length(map['fontWeightNormal']),
        fontWeightMedium: _length(map['fontWeightMedium']),
        fontWeightBold: _length(map['fontWeightBold']),
        spacingUnit: _length(map['spacingUnit']),
        borderRadius: _length(map['borderRadius']),
        spacingGridRow: _length(map['spacingGridRow']),
        spacingGridColumn: _length(map['spacingGridColumn']),
      );
}

/// How the sheet looks: Wajub.js 1.8's `AppearanceConfig`, key for key, so
/// the object a merchant gives the web Components styles this sheet the same
/// way. It sits on top of the merchant's own branding (the session's
/// `branding`), which fills what it leaves out.
///
/// ```dart
/// const Appearance(theme: 'night', variables: AppearanceVariables(colorPrimary: '#0F766E'))
/// ```
class Appearance {
  const Appearance({
    this.theme,
    this.colorScheme,
    this.inherit = false,
    this.variables,
    this.primaryColor,
    this.secondaryColor,
    this.backgroundColor,
    this.fontFamily,
    this.borderRadius,
    this.buttonTextColor,
    this.inputBackgroundColor,
    this.inputBorderColor,
    this.textMutedColor,
    this.successColor,
    this.errorColor,
    this.shadow,
    this.labels,
    this.disableAnimations = false,
  });

  /// `light`, `dark`, `auto`, `system` (= `auto`) name the colour scheme when
  /// [colorScheme] is absent; `stripe`, `night`, `flat`, `none` are Wajub.js's
  /// presets.
  final String? theme;

  /// `light`, `dark` or `auto` (follows the phone, live).
  final String? colorScheme;

  /// Take the host app's theme (`Theme.of(context)`) where this object and
  /// the variables leave a token unset. Read values are kept only when they
  /// stay legible.
  final bool inherit;
  final AppearanceVariables? variables;

  /// Wajub.js's top-level keys. [primaryColor], [backgroundColor],
  /// [textMutedColor], [errorColor], [successColor], [fontFamily] and
  /// [borderRadius] feed the same tokens as their [variables], which win.
  final String? primaryColor;

  /// The summary panel behind the amount.
  final String? secondaryColor;
  final String? backgroundColor;
  final String? fontFamily;
  final String? borderRadius;

  /// Text on the Pay button. Unset, white or near-black, whichever reads
  /// better on the primary colour.
  final String? buttonTextColor;
  final String? inputBackgroundColor;
  final String? inputBorderColor;
  final String? textMutedColor;
  final String? successColor;
  final String? errorColor;

  /// The sheet's elevation: `none`, `low`, `high`.
  final String? shadow;

  /// `above` (default) or `floating`.
  final String? labels;

  /// No pulse on the loader and no cross-fades. The phone's own
  /// reduced-motion setting does the same.
  final bool disableAnimations;

  /// Wajub.js's appearance object as a map (for instance the JSON a web and
  /// a mobile checkout share). Key names are Wajub.js's; unknown keys,
  /// `rules` (CSS selectors, web only) and values of the wrong type are
  /// ignored.
  factory Appearance.fromMap(Map<String, Object?> map) {
    final variables = map['variables'];
    return Appearance(
      theme: _oneOf(map['theme'], const {'light', 'dark', 'auto', 'system', 'stripe', 'night', 'flat', 'none'}),
      colorScheme: _oneOf(map['colorScheme'], const {'light', 'dark', 'auto'}),
      inherit: map['inherit'] is bool ? map['inherit'] as bool : false,
      variables: variables is Map ? AppearanceVariables.fromMap(variables.map((k, v) => MapEntry('$k', v))) : null,
      primaryColor: _string(map['primaryColor']),
      secondaryColor: _string(map['secondaryColor']),
      backgroundColor: _string(map['backgroundColor']),
      fontFamily: _string(map['fontFamily']),
      borderRadius: _length(map['borderRadius']),
      buttonTextColor: _string(map['buttonTextColor']),
      inputBackgroundColor: _string(map['inputBackgroundColor']),
      inputBorderColor: _string(map['inputBorderColor']),
      textMutedColor: _string(map['textMutedColor']),
      successColor: _string(map['successColor']),
      errorColor: _string(map['errorColor']),
      shadow: _oneOf(map['shadow'], const {'none', 'low', 'high'}),
      labels: _oneOf(map['labels'], const {'above', 'floating'}),
      disableAnimations: map['disableAnimations'] is bool ? map['disableAnimations'] as bool : false,
    );
  }
}

String? _string(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

/// A length or a weight: a string, or a number read as pixels (`8` = `"8"`).
String? _length(Object? value) {
  if (value is num) return value.isFinite ? (value == value.roundToDouble() ? '${value.round()}' : '$value') : null;
  return _string(value);
}

String? _oneOf(Object? value, Set<String> allowed) {
  final text = _string(value)?.toLowerCase();
  return allowed.contains(text) ? text : null;
}
