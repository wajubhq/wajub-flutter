import 'package:flutter/material.dart';

import '../models/models.dart';
import 'appearance.dart';
import 'wajub_theme.dart';

/// Turns the host's [Appearance], the merchant's [Branding] and, with
/// `inherit`, the host app's [ThemeData] into the tokens the sheet draws with.
///
/// For each token the first value found wins, in this order: the
/// appearance's `variables`, its top-level keys, its preset, the host app's
/// theme, the merchant's branding, the default palette of the colour scheme.
abstract final class AppearanceResolver {
  /// The presets, value for value.
  static const presets = <String, Appearance>{
    'stripe': Appearance(
      primaryColor: '#0570de',
      borderRadius: '4px',
      fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
      shadow: 'low',
    ),
    'night': Appearance(
      colorScheme: 'dark',
      primaryColor: '#7c3aed',
      backgroundColor: '#0f172a',
      buttonTextColor: '#f8fafc',
      inputBackgroundColor: '#1e293b',
      inputBorderColor: '#334155',
      textMutedColor: '#94a3b8',
      borderRadius: '8px',
      shadow: 'none',
    ),
    'flat': Appearance(shadow: 'none', borderRadius: '0'),
    'none': Appearance(),
  };

  /// The scheme the sheet must use, or null for `auto` (follow the phone,
  /// live): the appearance's `colorScheme`, else the scheme its `theme` names
  /// (`light`, `dark`, `auto`, `system`), else its preset's (`night` is dark);
  /// then, with `inherit`, the host app's; then the merchant's
  /// `appearance_mode` when it is `light` or `dark`.
  static Brightness? requestedBrightness({Appearance? appearance, Branding? branding, ThemeData? hostTheme}) {
    final explicit = _scheme(appearance?.colorScheme) ??
        _scheme(appearance?.theme) ??
        _scheme(presets[appearance?.theme]?.colorScheme);
    if (explicit != null) return explicit == _Scheme.auto ? null : _brightness(explicit);
    if (appearance?.inherit == true && hostTheme != null) return hostTheme.brightness;
    return switch (branding?.appearanceMode) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => null,
    };
  }

  /// Resolves every token. [platformBrightness] is the phone's scheme, used
  /// when the scheme is `auto`; [hostTheme] is read only when the appearance
  /// says `inherit: true`; [reduceMotion] is the phone's reduced-motion
  /// setting (`MediaQuery.disableAnimationsOf`).
  static WajubThemeData resolve({
    Appearance? appearance,
    Branding? branding,
    required Brightness platformBrightness,
    ThemeData? hostTheme,
    bool reduceMotion = false,
  }) {
    final inherited = appearance?.inherit == true ? hostTheme : null;
    final brightness =
        requestedBrightness(appearance: appearance, branding: branding, hostTheme: inherited) ?? platformBrightness;
    final palette = WajubColors.of(brightness);

    final variables = _Layer.variables(appearance?.variables);
    final legacy = _Layer.legacy(appearance);
    final preset = _Layer.legacy(presets[appearance?.theme]);
    final host = inherited != null ? _Layer.inherited(inherited) : const _Layer();
    final merchant = branding != null ? _Layer.branding(branding, brightness) : const _Layer();
    final layers = [variables, legacy, preset, host, merchant];
    T? first<T>(T? Function(_Layer layer) token) {
      for (final layer in layers) {
        final value = token(layer);
        if (value != null) return value;
      }
      return null;
    }

    final background = first((l) => l.background) ?? palette.background;

    // The host app's colours and the merchant's primary are kept only when
    // they stay legible on the background; anything else falls through to
    // the next layer.
    bool legible(Color? color, double ratio) => color != null && contrastRatio(color, background) >= ratio;
    final primary = variables.primary ??
        legacy.primary ??
        preset.primary ??
        (legible(host.primary, 3) ? host.primary : null) ??
        (legible(merchant.primary, 3) ? merchant.primary : null) ??
        palette.primary;
    final text = variables.text ?? (legible(host.text, 4.5) ? host.text : null) ?? palette.text;
    final textSecondary = variables.textSecondary ??
        legacy.textSecondary ??
        preset.textSecondary ??
        (legible(host.textSecondary, 4.5) ? host.textSecondary : null) ??
        merchant.textSecondary ??
        palette.textSecondary;

    // The merchant's button text goes with the merchant's own primary: on any
    // other (the host's, or the default after the contrast guard) the text
    // is picked to read on it.
    final onPrimary = legacy.onPrimary ??
        preset.onPrimary ??
        (primary == merchant.primary ? merchant.onPrimary : null) ??
        (primary == palette.primary ? palette.onPrimary : _readableOn(primary));

    // The inputs take the host's input colour, else the host's background,
    // and only then the merchant's: the host's look sits on top.
    final inputBackground = legacy.inputBackground ??
        preset.inputBackground ??
        variables.background ??
        legacy.background ??
        preset.background ??
        host.background ??
        merchant.inputBackground ??
        merchant.background ??
        palette.inputBackground;
    final surfaceMuted = first((l) => l.surfaceMuted);

    final colors = _derive(
      palette: palette,
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      background: background,
      surfaceMuted: surfaceMuted,
      text: text,
      textSecondary: textSecondary,
      textPlaceholder: first((l) => l.textPlaceholder) ?? palette.textPlaceholder,
      inputBackground: inputBackground,
      inputBorder: first((l) => l.inputBorder) ?? palette.inputBorder,
      danger: first((l) => l.danger) ?? palette.danger,
      success: first((l) => l.success) ?? palette.success,
    );

    final family = first((l) => l.fontFamily);
    final spacingUnit = first((l) => l.spacingUnit) ?? 4;
    return WajubThemeData(
      brightness: brightness,
      colors: colors,
      radius: _capRadius(first((l) => l.radius) ?? 8),
      fontFamily: family == null ? WajubThemeData.defaultFontFamily : (family.isEmpty ? null : family),
      fontSizeBase: first((l) => l.fontSizeBase) ?? 16,
      fontWeightNormal: first((l) => l.fontWeightNormal) ?? FontWeight.w400,
      fontWeightMedium: first((l) => l.fontWeightMedium) ?? FontWeight.w500,
      fontWeightBold: first((l) => l.fontWeightBold) ?? FontWeight.w600,
      spacingUnit: spacingUnit,
      gapRow: first((l) => l.gapRow),
      gapColumn: first((l) => l.gapColumn),
      elevation: first((l) => l.elevation) ?? 1,
      disableAnimations: (appearance?.disableAnimations ?? false) || reduceMotion,
      labels: appearance?.labels == 'floating' ? 'floating' : 'above',
      scrimOpacity: branding?.overlayIntensity != null ? branding!.overlayIntensity!.clamp(0, 100) / 100 : null,
      separatorColor: merchant.separator,
    );
  }

  /// A Material theme drawn from the tokens, so the sheet's Material widgets
  /// (fields, buttons, radios, progress indicators, the bottom sheet) follow
  /// them.
  static ThemeData materialTheme(WajubThemeData data) {
    final c = data.colors;
    final radius = BorderRadius.circular(data.radius);
    final scheme = ColorScheme(
      brightness: data.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.selectedBackground,
      onPrimaryContainer: c.text,
      secondary: c.primary,
      onSecondary: c.onPrimary,
      error: c.danger,
      onError: _readableOn(c.danger),
      errorContainer: c.dangerBackground,
      onErrorContainer: c.danger,
      surface: c.background,
      onSurface: c.text,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surfaceRaised,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceMuted,
      outline: c.inputBorder,
      outlineVariant: data.dividerColor,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: data.fontFamily);
    final textTheme = _textTheme(base.textTheme.apply(bodyColor: c.text, displayColor: c.text), data);

    WidgetStateProperty<Color?> faded(Color color) =>
        WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? _alpha(color, 0.5) : color);
    final shape = WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius));
    final buttonText = WidgetStatePropertyAll(
      TextStyle(fontFamily: data.fontFamily, fontSize: data.fontSizeBase, fontWeight: data.fontWeightBold),
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color, width: width));
    final lineHeight = data.inputFontSize * 1.5;
    final verticalPadding = ((data.inputHeight - lineHeight) / 2).clamp(8.0, double.infinity);

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: data.dividerColor,
      disabledColor: c.textDisabled,
      hintColor: c.textPlaceholder,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: c.textSecondary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: _alpha(c.primary, 0.25),
        selectionHandleColor: c.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inputBackground,
        isDense: false,
        contentPadding: EdgeInsets.symmetric(horizontal: data.spacingUnit * 3, vertical: verticalPadding),
        border: border(c.inputBorder),
        enabledBorder: border(c.inputBorder),
        focusedBorder: border(c.focusRing, data.focusRingWidth),
        errorBorder: border(c.dangerBorder),
        focusedErrorBorder: border(c.dangerBorder, data.focusRingWidth),
        disabledBorder: border(_alpha(c.inputBorder, data.disabledOpacity)),
        floatingLabelBehavior: data.labels == 'floating' ? FloatingLabelBehavior.auto : FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: c.textSecondary, fontSize: data.fontSizeLabel, fontWeight: data.fontWeightMedium),
        floatingLabelStyle: TextStyle(color: c.textSecondary, fontWeight: data.fontWeightMedium),
        hintStyle: TextStyle(color: c.textPlaceholder, fontSize: data.inputFontSize),
        helperStyle: TextStyle(color: c.textSecondary, fontSize: data.fontSizeHint),
        errorStyle: TextStyle(color: c.danger, fontSize: data.fontSizeHint),
        prefixStyle: TextStyle(color: c.text, fontSize: data.inputFontSize),
        suffixStyle: TextStyle(color: c.textSecondary, fontSize: data.inputFontSize),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return _alpha(c.primary, data.disabledOpacity);
            if (states.contains(WidgetState.pressed)) return c.primaryPressed;
            return c.primary;
          }),
          foregroundColor: faded(c.onPrimary),
          overlayColor: WidgetStatePropertyAll(_alpha(c.onPrimary, 0.08)),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: data.spacingUnit * 4)),
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: faded(c.text),
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.disabled) ? _alpha(c.borderStrong, 0.5) : c.borderStrong,
              )),
          overlayColor: WidgetStatePropertyAll(_alpha(c.text, 0.06)),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: data.spacingUnit * 4)),
          shape: shape,
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontFamily: data.fontFamily, fontSize: data.fontSizeBase, fontWeight: data.fontWeightMedium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: faded(c.link),
          overlayColor: WidgetStatePropertyAll(_alpha(c.link, 0.08)),
          minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
          shape: shape,
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontFamily: data.fontFamily, fontSize: data.fontSizeLabel, fontWeight: data.fontWeightMedium),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: data.dividerColor, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.background,
        modalBackgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: data.elevation,
        modalElevation: data.elevation,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        modalBarrierColor: data.scrimOpacity != null ? _alpha(Colors.black, data.scrimOpacity!) : null,
        dragHandleColor: c.borderStrong,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.primary : c.textSecondary,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
        side: BorderSide(color: c.borderStrong),
      ),
    );
  }

  /// `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb(r, g, b)` and `rgba(r, g, b, a)`,
  /// in any case. Anything else (named colours, `oklch()`, …) is null.
  static Color? parseColor(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    final hex = _hexColor.firstMatch(text);
    if (hex != null) {
      var digits = hex.group(1)!;
      if (digits.length == 3) digits = digits.split('').map((d) => '$d$d').join();
      final alpha = digits.length == 8 ? int.parse(digits.substring(6), radix: 16) : 0xFF;
      return Color((alpha << 24) | int.parse(digits.substring(0, 6), radix: 16));
    }
    final function = _rgbColor.firstMatch(text);
    if (function == null) return null;
    final parts = function.group(1)!.split(',').map((p) => p.trim()).toList();
    if (parts.length != 3 && parts.length != 4) return null;
    final channels = <int>[];
    for (final part in parts.take(3)) {
      final channel = double.tryParse(part);
      if (channel == null || channel < 0 || channel > 255) return null;
      channels.add(channel.round());
    }
    var alpha = 255;
    if (parts.length == 4) {
      final opacity = double.tryParse(parts[3]);
      if (opacity == null || opacity < 0 || opacity > 1) return null;
      alpha = (opacity * 255).round();
    }
    return Color.fromARGB(alpha, channels[0], channels[1], channels[2]);
  }

  /// `"8px"`, `"8"` (pixels, dp on the phone) or `"0.5rem"` (× 16). Negative
  /// and non-finite values are null.
  static double? parseLength(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    final double? length;
    if (text.endsWith('rem')) {
      final rem = double.tryParse(text.substring(0, text.length - 3).trim());
      length = rem == null ? null : rem * 16;
    } else if (text.endsWith('px')) {
      length = double.tryParse(text.substring(0, text.length - 2).trim());
    } else {
      length = double.tryParse(text);
    }
    return length != null && length.isFinite && length >= 0 ? length : null;
  }

  /// `"400"`…`"700"` (any hundred from 100 to 900), `"normal"` (400),
  /// `"bold"` (700), or a number.
  static FontWeight? parseFontWeight(Object? value) {
    final double? weight = switch (value) {
      num number => number.toDouble(),
      String text => switch (text.trim().toLowerCase()) {
          'normal' => 400,
          'bold' => 700,
          final other => double.tryParse(other),
        },
      _ => null,
    };
    if (weight == null || !weight.isFinite || weight < 100 || weight > 900) return null;
    return FontWeight.values[(weight / 100).round() - 1];
  }

  /// WCAG contrast ratio, from 1 to 21.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  static final _hexColor = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$');
  static final _rgbColor = RegExp(r'^rgba?\(([^)]*)\)$');

  /// The tokens derived from the ones a host or merchant sets, so a
  /// custom primary also tints the focus ring, links and the selected row,
  /// and a custom background carries its own raised and muted surfaces.
  static WajubColors _derive({
    required WajubColors palette,
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color background,
    required Color? surfaceMuted,
    required Color text,
    required Color textSecondary,
    required Color textPlaceholder,
    required Color inputBackground,
    required Color inputBorder,
    required Color danger,
    required Color success,
  }) {
    final dark = brightness == Brightness.dark;
    final customPrimary = primary != palette.primary;
    final customBackground = background != palette.background;
    Color tint(Color color, double opacity) => Color.alphaBlend(_alpha(color, opacity), background);
    final muted = surfaceMuted ?? (customBackground ? Color.lerp(background, text, dark ? 0.12 : 0.04)! : null);
    return palette.copyWith(
      primary: primary,
      primaryPressed: customPrimary ? Color.lerp(primary, dark ? Colors.white : Colors.black, dark ? 0.2 : 0.15) : null,
      onPrimary: onPrimary,
      background: background,
      surfaceRaised: customBackground ? (dark ? Color.lerp(background, Colors.white, 0.05) : background) : null,
      surfaceMuted: muted,
      selectedBackground: customPrimary || customBackground ? tint(primary, dark ? 0.2 : 0.08) : null,
      text: text,
      textSecondary: textSecondary,
      textPlaceholder: textPlaceholder,
      link: customPrimary ? primary : null,
      inputBackground: inputBackground,
      inputBorder: inputBorder,
      borderStrong: customBackground ? Color.lerp(background, text, 0.2) : null,
      focusRing: customPrimary ? primary : null,
      danger: danger,
      dangerBorder: danger != palette.danger ? danger : null,
      dangerBackground: danger != palette.danger || customBackground ? tint(danger, dark ? 0.2 : 0.08) : null,
      success: success,
      successBackground: success != palette.success || customBackground ? tint(success, dark ? 0.2 : 0.08) : null,
      warningBackground: customBackground ? tint(palette.warning, dark ? 0.2 : 0.08) : null,
      disabledBackground: muted,
    );
  }

  static TextTheme _textTheme(TextTheme base, WajubThemeData data) {
    final c = data.colors;
    TextStyle? weight(TextStyle? style, FontWeight weight, {double? size, Color? color}) =>
        style?.copyWith(fontWeight: weight, fontSize: size, color: color);
    return base.copyWith(
      displayLarge: weight(base.displayLarge, data.fontWeightBold),
      displayMedium: weight(base.displayMedium, data.fontWeightBold),
      displaySmall: weight(base.displaySmall, data.fontWeightBold),
      headlineLarge: weight(base.headlineLarge, data.fontWeightBold),
      headlineMedium: weight(base.headlineMedium, data.fontWeightBold),
      headlineSmall: weight(base.headlineSmall, data.fontWeightBold),
      titleLarge: weight(base.titleLarge, data.fontWeightBold),
      titleMedium: weight(base.titleMedium, data.fontWeightBold),
      titleSmall: weight(base.titleSmall, data.fontWeightMedium),
      bodyLarge: weight(base.bodyLarge, data.fontWeightNormal, size: data.inputFontSize),
      bodyMedium: weight(base.bodyMedium, data.fontWeightNormal, size: data.fontSizeLabel),
      bodySmall: weight(base.bodySmall, data.fontWeightNormal, size: data.fontSizeHint, color: c.textSecondary),
      labelLarge: weight(base.labelLarge, data.fontWeightBold, size: data.fontSizeBase),
      labelMedium: weight(base.labelMedium, data.fontWeightMedium, size: data.fontSizeLabel),
      labelSmall: weight(base.labelSmall, data.fontWeightMedium, size: data.fontSizeHint, color: c.textSecondary),
    );
  }
}

enum _Scheme { light, dark, auto }

_Scheme? _scheme(String? value) => switch (value?.trim().toLowerCase()) {
      'light' => _Scheme.light,
      'dark' => _Scheme.dark,
      'auto' || 'system' => _Scheme.auto,
      _ => null,
    };

Brightness _brightness(_Scheme scheme) => scheme == _Scheme.dark ? Brightness.dark : Brightness.light;

/// What one source (the variables, the top-level keys, a preset, the host
/// app's theme, the merchant's branding) sets. Null: it leaves the token to
/// the next source.
class _Layer {
  const _Layer({
    this.primary,
    this.onPrimary,
    this.background,
    this.surfaceMuted,
    this.text,
    this.textSecondary,
    this.textPlaceholder,
    this.inputBackground,
    this.inputBorder,
    this.danger,
    this.success,
    this.separator,
    this.fontFamily,
    this.fontSizeBase,
    this.fontWeightNormal,
    this.fontWeightMedium,
    this.fontWeightBold,
    this.spacingUnit,
    this.radius,
    this.gapRow,
    this.gapColumn,
    this.elevation,
  });

  final Color? primary;
  final Color? onPrimary;
  final Color? background;
  final Color? surfaceMuted;
  final Color? text;
  final Color? textSecondary;
  final Color? textPlaceholder;
  final Color? inputBackground;
  final Color? inputBorder;
  final Color? danger;
  final Color? success;
  final Color? separator;

  /// An empty string asks for the platform's font.
  final String? fontFamily;
  final double? fontSizeBase;
  final FontWeight? fontWeightNormal;
  final FontWeight? fontWeightMedium;
  final FontWeight? fontWeightBold;
  final double? spacingUnit;
  final double? radius;
  final double? gapRow;
  final double? gapColumn;
  final double? elevation;

  factory _Layer.variables(AppearanceVariables? v) {
    if (v == null) return const _Layer();
    final parse = AppearanceResolver.parseColor;
    final length = AppearanceResolver.parseLength;
    final fontSize = length(v.fontSizeBase);
    return _Layer(
      primary: parse(v.colorPrimary),
      background: parse(v.colorBackground),
      text: parse(v.colorText),
      textSecondary: parse(v.colorTextSecondary),
      textPlaceholder: parse(v.colorTextPlaceholder),
      danger: parse(v.colorDanger),
      success: parse(v.colorSuccess),
      fontFamily: _fontFamily(v.fontFamily),
      fontSizeBase: fontSize != null && fontSize > 0 ? fontSize : null,
      fontWeightNormal: AppearanceResolver.parseFontWeight(v.fontWeightNormal),
      fontWeightMedium: AppearanceResolver.parseFontWeight(v.fontWeightMedium),
      fontWeightBold: AppearanceResolver.parseFontWeight(v.fontWeightBold),
      spacingUnit: length(v.spacingUnit),
      radius: length(v.borderRadius),
      gapRow: length(v.spacingGridRow),
      gapColumn: length(v.spacingGridColumn),
    );
  }

  /// The top-level keys, of the appearance or of a preset.
  factory _Layer.legacy(Appearance? a) {
    if (a == null) return const _Layer();
    final parse = AppearanceResolver.parseColor;
    return _Layer(
      primary: parse(a.primaryColor),
      onPrimary: parse(a.buttonTextColor),
      background: parse(a.backgroundColor),
      surfaceMuted: parse(a.secondaryColor),
      textSecondary: parse(a.textMutedColor),
      inputBackground: parse(a.inputBackgroundColor),
      inputBorder: parse(a.inputBorderColor),
      danger: parse(a.errorColor),
      success: parse(a.successColor),
      fontFamily: _fontFamily(a.fontFamily),
      radius: AppearanceResolver.parseLength(a.borderRadius),
      elevation: _elevation(a.shadow),
    );
  }

  /// The host app's theme: its colours, font and input radius. The contrast
  /// thresholds are applied by the resolver, against the resolved
  /// background.
  factory _Layer.inherited(ThemeData theme) {
    final border = theme.inputDecorationTheme.border;
    return _Layer(
      primary: theme.colorScheme.primary,
      background: theme.colorScheme.surface,
      text: theme.colorScheme.onSurface,
      textSecondary: theme.colorScheme.onSurfaceVariant,
      inputBorder: theme.colorScheme.outline,
      fontFamily: theme.textTheme.bodyLarge?.fontFamily,
      radius: border is OutlineInputBorder ? border.borderRadius.topLeft.x : null,
    );
  }

  /// The merchant's branding. The background, the summary panel, the muted text,
  /// the inputs and the separator were designed for one scheme (dark when
  /// `appearance_mode` is `dark`, light otherwise) and apply only there.
  factory _Layer.branding(Branding b, Brightness brightness) {
    final parse = AppearanceResolver.parseColor;
    final designedFor = b.appearanceMode == 'dark' ? Brightness.dark : Brightness.light;
    final sameScheme = brightness == designedFor;
    return _Layer(
      primary: parse(b.primaryColor),
      onPrimary: parse(b.buttonTextColor),
      background: sameScheme ? parse(b.backgroundColor) : null,
      surfaceMuted: sameScheme ? parse(b.secondaryColor) : null,
      textSecondary: sameScheme ? parse(b.textMutedColor) : null,
      inputBackground: sameScheme ? parse(b.inputBackgroundColor) : null,
      inputBorder: sameScheme ? parse(b.inputBorderColor) : null,
      separator: sameScheme ? parse(b.separatorColor) : null,
      danger: parse(b.errorColor),
      success: parse(b.successColor),
      fontFamily: _fontFamily(b.font),
      fontWeightBold: AppearanceResolver.parseFontWeight(b.fontWeightHeading),
      fontWeightNormal: AppearanceResolver.parseFontWeight(b.fontWeightBody),
      spacingUnit: b.density == 'compact' ? 3 : null,
      radius: _brandingRadius(b.borderRadius),
      elevation: _elevation(b.shadow),
    );
  }
}

/// The family a CSS stack starts with, without quotes; an empty string when
/// it starts with a system or generic family (the platform's font).
String? _fontFamily(String? stack) {
  if (stack == null) return null;
  for (final raw in stack.split(',')) {
    final family = raw.trim().replaceAll(RegExp('^["\']|["\']\$'), '').trim();
    if (family.isEmpty) continue;
    return _systemFamilies.contains(family.toLowerCase()) ? '' : family;
  }
  return null;
}

const _systemFamilies = {
  '-apple-system',
  'blinkmacsystemfont',
  'system-ui',
  'ui-sans-serif',
  'ui-serif',
  'ui-monospace',
  'ui-rounded',
  'sans-serif',
  'serif',
  'monospace',
  'cursive',
  'fantasy',
  'inherit',
  'initial',
};

double? _elevation(String? shadow) => switch (shadow?.trim().toLowerCase()) {
      'none' => 0,
      'low' => 1,
      'high' => 8,
      _ => null,
    };

/// `"12px"`, `"12"`, or the dashboard's named sizes.
double? _brandingRadius(String? value) => switch (value?.trim().toLowerCase()) {
      'none' => 0,
      'sm' => 4,
      'md' => 8,
      'lg' => 12,
      'xl' => 16,
      final other => AppearanceResolver.parseLength(other),
    };

double _capRadius(double radius) => radius > WajubThemeData.maxRadius ? WajubThemeData.maxRadius : radius;

/// White or near-black, whichever contrasts more with [color].
Color _readableOn(Color color) {
  const white = Color(0xFFFFFFFF);
  const ink = Color(0xFF0A0A0A);
  return AppearanceResolver.contrastRatio(white, color) >= AppearanceResolver.contrastRatio(ink, color) ? white : ink;
}

Color _alpha(Color color, double opacity) => color.withAlpha((opacity * 255).round());
