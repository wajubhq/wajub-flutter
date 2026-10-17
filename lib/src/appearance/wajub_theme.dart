import 'package:flutter/material.dart';

/// The sheet's colour tokens, with Wajub's default light and dark
/// palettes.
@immutable
class WajubColors {
  const WajubColors({
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.background,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.selectedBackground,
    required this.text,
    required this.textSecondary,
    required this.textPlaceholder,
    required this.textDisabled,
    required this.link,
    required this.inputBackground,
    required this.inputBorder,
    required this.borderStrong,
    required this.focusRing,
    required this.danger,
    required this.dangerBorder,
    required this.dangerBackground,
    required this.success,
    required this.successBackground,
    required this.warning,
    required this.warningBackground,
    required this.disabledBackground,
  });

  /// The Pay button, the selected operator, links.
  final Color primary;
  final Color primaryPressed;

  /// Text and icons on [primary].
  final Color onPrimary;

  /// The sheet's surface.
  final Color background;
  final Color surfaceRaised;

  /// The summary panel behind the amount, skeleton blocks.
  final Color surfaceMuted;

  /// The selected operator's row.
  final Color selectedBackground;
  final Color text;
  final Color textSecondary;
  final Color textPlaceholder;
  final Color textDisabled;
  final Color link;
  final Color inputBackground;
  final Color inputBorder;
  final Color borderStrong;
  final Color focusRing;

  /// Field errors and the failure screen.
  final Color danger;
  final Color dangerBorder;
  final Color dangerBackground;

  /// The success screen.
  final Color success;
  final Color successBackground;
  final Color warning;
  final Color warningBackground;
  final Color disabledBackground;

  /// The default light palette.
  static const light = WajubColors(
    primary: Color(0xFF2563EB),
    primaryPressed: Color(0xFF1D4ED8),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F5F5),
    selectedBackground: Color(0xFFEFF6FF),
    text: Color(0xFF171717),
    textSecondary: Color(0xFF525252),
    textPlaceholder: Color(0xFF737373),
    textDisabled: Color(0xFFA3A3A3),
    link: Color(0xFF2563EB),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFE5E5E5),
    borderStrong: Color(0xFFD4D4D4),
    focusRing: Color(0xFF3B82F6),
    danger: Color(0xFFB91C1C),
    dangerBorder: Color(0xFFEF4444),
    dangerBackground: Color(0xFFFEF2F2),
    success: Color(0xFF15803D),
    successBackground: Color(0xFFF0FDF4),
    warning: Color(0xFFB45309),
    warningBackground: Color(0xFFFFFBEB),
    disabledBackground: Color(0xFFF5F5F5),
  );

  /// The default dark palette.
  static const dark = WajubColors(
    primary: Color(0xFF3B82F6),
    primaryPressed: Color(0xFF60A5FA),
    onPrimary: Color(0xFF0A0A0A),
    background: Color(0xFF0A0A0A),
    surfaceRaised: Color(0xFF171717),
    surfaceMuted: Color(0xFF262626),
    selectedBackground: Color(0xFF172554),
    text: Color(0xFFFAFAFA),
    textSecondary: Color(0xFFA3A3A3),
    textPlaceholder: Color(0xFF8A8A8A),
    textDisabled: Color(0xFF525252),
    link: Color(0xFF60A5FA),
    inputBackground: Color(0xFF0A0A0A),
    inputBorder: Color(0xFF404040),
    borderStrong: Color(0xFF525252),
    focusRing: Color(0xFF60A5FA),
    danger: Color(0xFFF87171),
    dangerBorder: Color(0xFFF87171),
    dangerBackground: Color(0xFF450A0A),
    success: Color(0xFF4ADE80),
    successBackground: Color(0xFF052E16),
    warning: Color(0xFFFBBF24),
    warningBackground: Color(0xFF451A03),
    disabledBackground: Color(0xFF262626),
  );

  /// The default palette of [brightness].
  static WajubColors of(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  /// Every token under its name (`primary`, `onPrimary`, …).
  Map<String, Color> asMap() => {
        'primary': primary,
        'primaryPressed': primaryPressed,
        'onPrimary': onPrimary,
        'background': background,
        'surfaceRaised': surfaceRaised,
        'surfaceMuted': surfaceMuted,
        'selectedBackground': selectedBackground,
        'text': text,
        'textSecondary': textSecondary,
        'textPlaceholder': textPlaceholder,
        'textDisabled': textDisabled,
        'link': link,
        'inputBackground': inputBackground,
        'inputBorder': inputBorder,
        'borderStrong': borderStrong,
        'focusRing': focusRing,
        'danger': danger,
        'dangerBorder': dangerBorder,
        'dangerBackground': dangerBackground,
        'success': success,
        'successBackground': successBackground,
        'warning': warning,
        'warningBackground': warningBackground,
        'disabledBackground': disabledBackground,
      };

  WajubColors copyWith({
    Color? primary,
    Color? primaryPressed,
    Color? onPrimary,
    Color? background,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? selectedBackground,
    Color? text,
    Color? textSecondary,
    Color? textPlaceholder,
    Color? textDisabled,
    Color? link,
    Color? inputBackground,
    Color? inputBorder,
    Color? borderStrong,
    Color? focusRing,
    Color? danger,
    Color? dangerBorder,
    Color? dangerBackground,
    Color? success,
    Color? successBackground,
    Color? warning,
    Color? warningBackground,
    Color? disabledBackground,
  }) =>
      WajubColors(
        primary: primary ?? this.primary,
        primaryPressed: primaryPressed ?? this.primaryPressed,
        onPrimary: onPrimary ?? this.onPrimary,
        background: background ?? this.background,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
        selectedBackground: selectedBackground ?? this.selectedBackground,
        text: text ?? this.text,
        textSecondary: textSecondary ?? this.textSecondary,
        textPlaceholder: textPlaceholder ?? this.textPlaceholder,
        textDisabled: textDisabled ?? this.textDisabled,
        link: link ?? this.link,
        inputBackground: inputBackground ?? this.inputBackground,
        inputBorder: inputBorder ?? this.inputBorder,
        borderStrong: borderStrong ?? this.borderStrong,
        focusRing: focusRing ?? this.focusRing,
        danger: danger ?? this.danger,
        dangerBorder: dangerBorder ?? this.dangerBorder,
        dangerBackground: dangerBackground ?? this.dangerBackground,
        success: success ?? this.success,
        successBackground: successBackground ?? this.successBackground,
        warning: warning ?? this.warning,
        warningBackground: warningBackground ?? this.warningBackground,
        disabledBackground: disabledBackground ?? this.disabledBackground,
      );

  @override
  bool operator ==(Object other) =>
      other is WajubColors &&
      _listEquals(asMap().values.toList(growable: false), other.asMap().values.toList(growable: false));

  @override
  int get hashCode => Object.hashAll(asMap().values);
}

/// Everything the sheet draws with, resolved from the host's `Appearance`,
/// the merchant's branding and the defaults (see `AppearanceResolver`).
@immutable
class WajubThemeData {
  const WajubThemeData({
    required this.brightness,
    required this.colors,
    this.radius = 8,
    this.inputHeight = 44,
    this.fontFamily = defaultFontFamily,
    this.fontSizeBase = 16,
    this.fontWeightNormal = FontWeight.w400,
    this.fontWeightMedium = FontWeight.w500,
    this.fontWeightBold = FontWeight.w600,
    this.spacingUnit = 4,
    double? gapRow,
    double? gapColumn,
    this.elevation = 1,
    this.disableAnimations = false,
    this.labels = 'above',
    this.scrimOpacity,
    this.separatorColor,
  })  : gapRow = gapRow ?? spacingUnit * 4,
        gapColumn = gapColumn ?? spacingUnit * 3;

  /// Wajub's default font, used when the app ships it (Flutter falls back to
  /// the platform's font otherwise).
  static const defaultFontFamily = 'Inter';

  /// Half an input's height.
  static const maxRadius = 22.0;

  static const light = WajubThemeData(brightness: Brightness.light, colors: WajubColors.light);
  static const dark = WajubThemeData(brightness: Brightness.dark, colors: WajubColors.dark);

  final Brightness brightness;
  final WajubColors colors;

  /// Inputs, buttons, list boxes. At most [maxRadius].
  final double radius;
  final double inputHeight;

  /// Null: the platform's font.
  final String? fontFamily;

  /// Text typed in inputs, never drawn below 16 there ([inputFontSize]).
  final double fontSizeBase;
  final FontWeight fontWeightNormal;
  final FontWeight fontWeightMedium;
  final FontWeight fontWeightBold;

  /// The base of every padding and gap.
  final double spacingUnit;

  /// The vertical gap between fields.
  final double gapRow;

  /// The horizontal gap between side-by-side fields.
  final double gapColumn;

  /// The sheet's elevation: 0 (`shadow: none`), 1 (`low`), 8 (`high`).
  final double elevation;

  /// No pulse, no cross-fade: the appearance asked for it, or the phone did.
  final bool disableAnimations;

  /// `above` or `floating`.
  final String labels;

  /// The scrim's opacity behind the sheet (the merchant's
  /// `overlay_intensity / 100`); null leaves the platform's.
  final double? scrimOpacity;

  /// The merchant's divider colour, when it set one.
  final Color? separatorColor;

  /// Labels: 14 on a 16 base.
  double get fontSizeLabel => fontSizeBase * 0.875;

  /// Hints and helper lines: 13 on a 16 base.
  double get fontSizeHint => fontSizeBase * 0.8125;

  /// Input text: [fontSizeBase], never below 16 (smaller makes iOS zoom in).
  double get inputFontSize => fontSizeBase < 16 ? 16 : fontSizeBase;

  /// The focus ring's width.
  double get focusRingWidth => 2;

  /// What disabled controls are drawn at.
  double get disabledOpacity => 0.5;

  /// Cross-fades and the loader's pulse; zero when animations are off.
  Duration get animationDuration => disableAnimations ? Duration.zero : const Duration(milliseconds: 250);

  /// Dividers: the merchant's separator, else the input border.
  Color get dividerColor => separatorColor ?? colors.inputBorder;

  bool get isDark => brightness == Brightness.dark;

  WajubThemeData copyWith({
    Brightness? brightness,
    WajubColors? colors,
    double? radius,
    String? fontFamily,
    double? fontSizeBase,
    FontWeight? fontWeightNormal,
    FontWeight? fontWeightMedium,
    FontWeight? fontWeightBold,
    double? spacingUnit,
    double? gapRow,
    double? gapColumn,
    double? elevation,
    bool? disableAnimations,
    String? labels,
    double? scrimOpacity,
    Color? separatorColor,
  }) =>
      WajubThemeData(
        brightness: brightness ?? this.brightness,
        colors: colors ?? this.colors,
        radius: radius ?? this.radius,
        inputHeight: inputHeight,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSizeBase: fontSizeBase ?? this.fontSizeBase,
        fontWeightNormal: fontWeightNormal ?? this.fontWeightNormal,
        fontWeightMedium: fontWeightMedium ?? this.fontWeightMedium,
        fontWeightBold: fontWeightBold ?? this.fontWeightBold,
        spacingUnit: spacingUnit ?? this.spacingUnit,
        gapRow: gapRow ?? this.gapRow,
        gapColumn: gapColumn ?? this.gapColumn,
        elevation: elevation ?? this.elevation,
        disableAnimations: disableAnimations ?? this.disableAnimations,
        labels: labels ?? this.labels,
        scrimOpacity: scrimOpacity ?? this.scrimOpacity,
        separatorColor: separatorColor ?? this.separatorColor,
      );

  @override
  bool operator ==(Object other) =>
      other is WajubThemeData &&
      other.brightness == brightness &&
      other.colors == colors &&
      other.radius == radius &&
      other.inputHeight == inputHeight &&
      other.fontFamily == fontFamily &&
      other.fontSizeBase == fontSizeBase &&
      other.fontWeightNormal == fontWeightNormal &&
      other.fontWeightMedium == fontWeightMedium &&
      other.fontWeightBold == fontWeightBold &&
      other.spacingUnit == spacingUnit &&
      other.gapRow == gapRow &&
      other.gapColumn == gapColumn &&
      other.elevation == elevation &&
      other.disableAnimations == disableAnimations &&
      other.labels == labels &&
      other.scrimOpacity == scrimOpacity &&
      other.separatorColor == separatorColor;

  @override
  int get hashCode => Object.hash(
      brightness,
      colors,
      radius,
      inputHeight,
      fontFamily,
      fontSizeBase,
      fontWeightNormal,
      fontWeightMedium,
      fontWeightBold,
      spacingUnit,
      gapRow,
      gapColumn,
      elevation,
      disableAnimations,
      labels,
      scrimOpacity,
      separatorColor);
}

/// Hands the resolved [WajubThemeData] to the sheet's widgets.
class WajubTheme extends InheritedWidget {
  const WajubTheme({super.key, required this.data, required super.child});

  final WajubThemeData data;

  /// The nearest theme, or the light default when there is none.
  static WajubThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WajubTheme>()?.data ?? WajubThemeData.light;

  @override
  bool updateShouldNotify(WajubTheme oldWidget) => data != oldWidget.data;
}

bool _listEquals(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
