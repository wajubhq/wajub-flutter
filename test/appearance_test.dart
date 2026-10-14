import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wajub_mobile/src/appearance/appearance.dart';
import 'package:wajub_mobile/src/appearance/appearance_resolver.dart';
import 'package:wajub_mobile/src/appearance/wajub_theme.dart';
import 'package:wajub_mobile/src/models/models.dart';

import 'support/fixtures.dart';

/// `DEFAULT_PALETTES` of the spec's types.ts, as the web checkout's tokens.
const _defaultPalettes = {
  Brightness.light: {
    'primary': '#2563EB',
    'primaryPressed': '#1D4ED8',
    'onPrimary': '#FFFFFF',
    'background': '#FFFFFF',
    'surfaceRaised': '#FFFFFF',
    'surfaceMuted': '#F5F5F5',
    'selectedBackground': '#EFF6FF',
    'text': '#171717',
    'textSecondary': '#525252',
    'textPlaceholder': '#737373',
    'textDisabled': '#A3A3A3',
    'link': '#2563EB',
    'inputBackground': '#FFFFFF',
    'inputBorder': '#E5E5E5',
    'borderStrong': '#D4D4D4',
    'focusRing': '#3B82F6',
    'danger': '#B91C1C',
    'dangerBorder': '#EF4444',
    'dangerBackground': '#FEF2F2',
    'success': '#15803D',
    'successBackground': '#F0FDF4',
    'warning': '#B45309',
    'warningBackground': '#FFFBEB',
    'disabledBackground': '#F5F5F5',
  },
  Brightness.dark: {
    'primary': '#3B82F6',
    'primaryPressed': '#60A5FA',
    'onPrimary': '#0A0A0A',
    'background': '#0A0A0A',
    'surfaceRaised': '#171717',
    'surfaceMuted': '#262626',
    'selectedBackground': '#172554',
    'text': '#FAFAFA',
    'textSecondary': '#A3A3A3',
    'textPlaceholder': '#8A8A8A',
    'textDisabled': '#525252',
    'link': '#60A5FA',
    'inputBackground': '#0A0A0A',
    'inputBorder': '#404040',
    'borderStrong': '#525252',
    'focusRing': '#60A5FA',
    'danger': '#F87171',
    'dangerBorder': '#F87171',
    'dangerBackground': '#450A0A',
    'success': '#4ADE80',
    'successBackground': '#052E16',
    'warning': '#FBBF24',
    'warningBackground': '#451A03',
    'disabledBackground': '#262626',
  },
};

Color hex(String value) => AppearanceResolver.parseColor(value)!;

Branding brandingOf(String fixture) => SessionData.fromJson(fixtureBody(fixture)).merchantBranding;

WajubThemeData resolve({
  Appearance? appearance,
  Branding? branding,
  Brightness platform = Brightness.light,
  ThemeData? hostTheme,
}) =>
    AppearanceResolver.resolve(
      appearance: appearance,
      branding: branding,
      platformBrightness: platform,
      hostTheme: hostTheme,
    );

void main() {
  test('AP-01 parses the appearance object', () {
    final appearance = Appearance.fromMap({
      'theme': 'night',
      'colorScheme': 'dark',
      'inherit': true,
      'variables': {
        'colorPrimary': '#0F766E',
        'colorBackground': '#FFFFFF',
        'colorText': '#111827',
        'colorTextSecondary': '#4B5563',
        'colorTextPlaceholder': '#9CA3AF',
        'colorDanger': '#DC2626',
        'colorSuccess': '#16A34A',
        'fontFamily': 'Poppins, sans-serif',
        'fontSizeBase': '18px',
        'fontWeightNormal': '400',
        'fontWeightMedium': 500,
        'fontWeightBold': 'bold',
        'spacingUnit': '5px',
        'borderRadius': '0.75rem',
        'spacingGridRow': '20px',
        'spacingGridColumn': '10',
        'colorUnknown': '#000000',
      },
      'primaryColor': '#7c3aed',
      'secondaryColor': '#F0FDFA',
      'backgroundColor': '#0f172a',
      'fontFamily': 'Inter',
      'borderRadius': '6px',
      'buttonTextColor': '#f8fafc',
      'inputBackgroundColor': '#1e293b',
      'inputBorderColor': '#334155',
      'textMutedColor': '#94a3b8',
      'successColor': '#22C55E',
      'errorColor': '#EF4444',
      'shadow': 'high',
      'labels': 'floating',
      'disableAnimations': true,
      'rules': {
        '.Input': {'border': '1px solid red'}
      },
      'somethingElse': 42,
    });

    expect(appearance.theme, 'night');
    expect(appearance.colorScheme, 'dark');
    expect(appearance.inherit, isTrue);
    expect(appearance.primaryColor, '#7c3aed');
    expect(appearance.secondaryColor, '#F0FDFA');
    expect(appearance.backgroundColor, '#0f172a');
    expect(appearance.fontFamily, 'Inter');
    expect(appearance.borderRadius, '6px');
    expect(appearance.buttonTextColor, '#f8fafc');
    expect(appearance.inputBackgroundColor, '#1e293b');
    expect(appearance.inputBorderColor, '#334155');
    expect(appearance.textMutedColor, '#94a3b8');
    expect(appearance.successColor, '#22C55E');
    expect(appearance.errorColor, '#EF4444');
    expect(appearance.shadow, 'high');
    expect(appearance.labels, 'floating');
    expect(appearance.disableAnimations, isTrue);
    final variables = appearance.variables!;
    expect(variables.colorPrimary, '#0F766E');
    expect(variables.colorBackground, '#FFFFFF');
    expect(variables.colorText, '#111827');
    expect(variables.colorTextSecondary, '#4B5563');
    expect(variables.colorTextPlaceholder, '#9CA3AF');
    expect(variables.colorDanger, '#DC2626');
    expect(variables.colorSuccess, '#16A34A');
    expect(variables.fontFamily, 'Poppins, sans-serif');
    expect(variables.fontSizeBase, '18px');
    expect(variables.fontWeightNormal, '400');
    expect(variables.fontWeightMedium, '500');
    expect(variables.fontWeightBold, 'bold');
    expect(variables.spacingUnit, '5px');
    expect(variables.borderRadius, '0.75rem');
    expect(variables.spacingGridRow, '20px');
    expect(variables.spacingGridColumn, '10');

    final resolved = resolve(appearance: Appearance(variables: variables));
    expect(resolved.colors.primary, hex('#0F766E'));
    expect(resolved.fontFamily, 'Poppins');
    expect(resolved.fontSizeBase, 18);
    expect(resolved.fontWeightMedium, FontWeight.w500);
    expect(resolved.fontWeightBold, FontWeight.w700);
    expect(resolved.spacingUnit, 5);
    expect(resolved.radius, 12);
    expect(resolved.gapRow, 20);
    expect(resolved.gapColumn, 10);

    // Values of the wrong type or outside Wajub.js's choices are dropped.
    final wrong = Appearance.fromMap({
      'theme': 5,
      'colorScheme': 'sepia',
      'inherit': 'yes',
      'variables': 'nope',
      'primaryColor': 12,
      'shadow': 'huge',
      'labels': 'inside',
      'disableAnimations': 1,
    });
    expect(wrong.theme, isNull);
    expect(wrong.colorScheme, isNull);
    expect(wrong.inherit, isFalse);
    expect(wrong.variables, isNull);
    expect(wrong.primaryColor, isNull);
    expect(wrong.shadow, isNull);
    expect(wrong.labels, isNull);
    expect(wrong.disableAnimations, isFalse);

    // Values that do not parse are ignored, never an error: the next source
    // (here the default palette) fills the token.
    final unparsable = resolve(
      appearance: const Appearance(
        primaryColor: 'red',
        backgroundColor: 'oklch(0.7 0.1 200)',
        borderRadius: '-4px',
        variables: AppearanceVariables(
          colorText: 'rgb(300, 0, 0)',
          fontSizeBase: 'big',
          fontWeightBold: 'heavy',
          spacingUnit: 'NaNpx',
        ),
      ),
    );
    expect(unparsable, resolve());

    expect(AppearanceResolver.parseColor('#abc'), const Color(0xFFAABBCC));
    expect(AppearanceResolver.parseColor('#0F766E'), const Color(0xFF0F766E));
    expect(AppearanceResolver.parseColor('#0f766e80'), const Color(0x800F766E));
    expect(AppearanceResolver.parseColor('RGB(15, 118, 110)'), const Color(0xFF0F766E));
    expect(AppearanceResolver.parseColor('rgba(0, 0, 255, 0.5)'), const Color(0x800000FF));
    for (final bad in ['red', 'oklch(0.7 0.1 200)', '#12', '#12345', 'rgb(1, 2)', 'rgba(0, 0, 0, 2)', '']) {
      expect(AppearanceResolver.parseColor(bad), isNull, reason: bad);
    }
    expect(AppearanceResolver.parseLength('8px'), 8);
    expect(AppearanceResolver.parseLength('8'), 8);
    expect(AppearanceResolver.parseLength('0.5rem'), 8);
    for (final bad in ['-2px', 'abc', '1e400px', 'NaN']) {
      expect(AppearanceResolver.parseLength(bad), isNull, reason: bad);
    }
    expect(AppearanceResolver.parseFontWeight('normal'), FontWeight.w400);
    expect(AppearanceResolver.parseFontWeight('bold'), FontWeight.w700);
    expect(AppearanceResolver.parseFontWeight('600'), FontWeight.w600);
    expect(AppearanceResolver.parseFontWeight(500), FontWeight.w500);
    expect(AppearanceResolver.parseFontWeight('heavy'), isNull);
  });

  test('AP-02 resolves token precedence', () {
    final branding = brandingOf('session-cm-aggregate.json');
    final host = ThemeData(
      colorScheme: const ColorScheme.light(primary: Color(0xFF333333)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    );

    WajubThemeData chain({bool variables = true, bool legacy = true, bool preset = true, bool inherit = true}) =>
        resolve(
          appearance: Appearance(
            theme: preset ? 'stripe' : null,
            inherit: inherit,
            primaryColor: legacy ? '#222222' : null,
            borderRadius: legacy ? '6px' : null,
            variables: variables ? const AppearanceVariables(colorPrimary: '#111111', borderRadius: '2px') : null,
          ),
          branding: branding,
          hostTheme: host,
        );

    // variables > legacy keys > preset > inherited > merchant branding > default palette
    expect(chain().colors.primary, hex('#111111'));
    expect(chain().radius, 2);
    expect(chain(variables: false).colors.primary, hex('#222222'));
    expect(chain(variables: false).radius, 6);
    expect(chain(variables: false, legacy: false).colors.primary, hex('#0570de'));
    expect(chain(variables: false, legacy: false).radius, 4);
    final inherited = chain(variables: false, legacy: false, preset: false);
    expect(inherited.colors.primary, hex('#333333'));
    expect(inherited.radius, 10);
    final merchant = chain(variables: false, legacy: false, preset: false, inherit: false);
    expect(merchant.colors.primary, hex('#0F766E'));
    expect(merchant.radius, 12);
    final defaults = resolve(appearance: const Appearance());
    expect(defaults.colors.primary, hex('#2563EB'));
    expect(defaults.radius, 8);

    // The host's own text colours and fonts win over the merchant's too.
    final textMuted = resolve(
      appearance: const Appearance(textMutedColor: '#374151', fontFamily: 'Roboto Slab'),
      branding: branding,
    );
    expect(textMuted.colors.textSecondary, hex('#374151'));
    expect(textMuted.fontFamily, 'Roboto Slab');
    expect(resolve(branding: branding).colors.textSecondary, hex('#6B7280'));
    expect(resolve(branding: branding).fontFamily, 'Poppins');

    // The inputs take the host's background before the merchant's input colour.
    final hostBackground = resolve(
      appearance: const Appearance(variables: AppearanceVariables(colorBackground: '#FFFBEB')),
      branding: branding,
    );
    expect(hostBackground.colors.background, hex('#FFFBEB'));
    expect(hostBackground.colors.inputBackground, hex('#FFFBEB'));
  });

  test('AP-03 resolves the colour scheme', () {
    final branding = brandingOf('session-cm-aggregate.json');
    expect(branding.appearanceMode, 'light');
    Brightness? requested(Appearance? appearance, {Branding? branding, ThemeData? host}) =>
        AppearanceResolver.requestedBrightness(appearance: appearance, branding: branding, hostTheme: host);

    // 1. colorScheme, else the scheme theme names, else the preset's.
    expect(requested(const Appearance(colorScheme: 'dark', theme: 'light'), branding: branding), Brightness.dark);
    expect(requested(const Appearance(theme: 'dark'), branding: branding), Brightness.dark);
    expect(requested(const Appearance(theme: 'night'), branding: branding), Brightness.dark);
    expect(requested(const Appearance(theme: 'system'), branding: branding), isNull);
    expect(requested(const Appearance(colorScheme: 'auto'), branding: branding), isNull);
    // 2. the host app's scheme, with inherit.
    final darkHost = ThemeData(brightness: Brightness.dark);
    expect(requested(const Appearance(inherit: true), branding: branding, host: darkHost), Brightness.dark);
    expect(requested(const Appearance(theme: 'stripe', inherit: true), host: darkHost), Brightness.dark);
    // 3. the merchant's appearance_mode light or dark; system means no preference.
    expect(requested(null, branding: branding), Brightness.light);
    expect(requested(null, branding: const Branding(appearanceMode: 'dark')), Brightness.dark);
    expect(requested(null, branding: const Branding(appearanceMode: 'system')), isNull);
    // 4. auto.
    expect(requested(null), isNull);

    // auto follows the phone; a merchant's light beats the phone's dark,
    // an explicit auto does not.
    expect(resolve(platform: Brightness.dark).brightness, Brightness.dark);
    expect(resolve(platform: Brightness.dark).colors, WajubColors.dark);
    expect(resolve(platform: Brightness.light).brightness, Brightness.light);
    expect(resolve(branding: branding, platform: Brightness.dark).brightness, Brightness.light);
    expect(
      resolve(appearance: const Appearance(colorScheme: 'auto'), branding: branding, platform: Brightness.dark)
          .brightness,
      Brightness.dark,
    );
  });

  test('AP-04 uses the default palettes', () {
    final branding = brandingOf('session-ci-xof-wallets.json');
    for (final brightness in Brightness.values) {
      final expected = {for (final entry in _defaultPalettes[brightness]!.entries) entry.key: hex(entry.value)};
      expect(WajubColors.of(brightness).asMap(), expected);
      expect(resolve(branding: branding, platform: brightness).colors.asMap(), expected, reason: '$brightness');
      expect(resolve(platform: brightness).colors.asMap(), expected, reason: '$brightness, no branding');
    }

    final shape = resolve(branding: branding);
    expect(shape.radius, 8);
    expect(shape.inputHeight, 44);
    expect(shape.fontFamily, 'Inter');
    expect(shape.fontSizeBase, 16);
    expect(shape.fontSizeLabel, 14);
    expect(shape.fontSizeHint, 13);
    expect(shape.fontWeightNormal, FontWeight.w400);
    expect(shape.fontWeightMedium, FontWeight.w500);
    expect(shape.fontWeightBold, FontWeight.w600);
    expect(shape.spacingUnit, 4);
    expect(shape.focusRingWidth, 2);
    expect(shape.disabledOpacity, 0.5);
    expect(shape.animationDuration, const Duration(milliseconds: 250));
  });

  test('AP-05 applies merchant branding', () {
    final branding = brandingOf('session-cm-aggregate.json');
    expect(branding.whiteLabel, isTrue);

    final light = resolve(branding: branding, platform: Brightness.dark);
    expect(light.brightness, Brightness.light, reason: 'appearance_mode: light');
    expect(light.colors.primary, hex('#0F766E'));
    expect(light.colors.onPrimary, hex('#FFFFFF'));
    expect(light.colors.background, hex('#FFFFFF'));
    expect(light.colors.surfaceMuted, hex('#F0FDFA'));
    expect(light.colors.textSecondary, hex('#6B7280'));
    expect(light.colors.inputBackground, hex('#FFFFFF'));
    expect(light.colors.inputBorder, hex('#D1D5DB'));
    expect(light.colors.success, hex('#16A34A'));
    expect(light.colors.danger, hex('#DC2626'));
    expect(light.colors.focusRing, hex('#0F766E'), reason: 'the primary also draws the focus ring');
    expect(light.colors.link, hex('#0F766E'));
    expect(light.radius, 12);
    expect(light.fontFamily, 'Poppins');
    expect(light.fontWeightBold, FontWeight.w600, reason: 'font_weight_heading: 600 (an integer)');
    expect(light.fontWeightNormal, FontWeight.w400, reason: 'font_weight_body: "400" (a string)');
    expect(light.elevation, 1, reason: 'shadow: low');
    expect(light.scrimOpacity, 0.4);
    expect(light.separatorColor, hex('#E5E7EB'));

    // custom_css is never read.
    final withCss = Map<String, dynamic>.from(fixtureBody('session-cm-aggregate.json')['branding'] as Map)
      ..['custom_css'] = 'body { color: red !important; }';
    expect(resolve(branding: Branding.fromJson(withCss)), resolve(branding: branding));

    // A merchant primary under 3:1 on the background gives way to the default,
    // and its button text with it.
    final pale = resolve(branding: const Branding(primaryColor: '#FFFF00', buttonTextColor: '#000000'));
    expect(pale.colors.primary, hex('#2563EB'));
    expect(pale.colors.onPrimary, hex('#FFFFFF'));

    // The button text, when unset, is white or near-black, whichever reads.
    expect(resolve(appearance: const Appearance(primaryColor: '#FACC15')).colors.onPrimary, hex('#0A0A0A'));
    expect(resolve(appearance: const Appearance(primaryColor: '#7C3AED')).colors.onPrimary, hex('#FFFFFF'));

    // The merchant's light design does not reach a dark sheet.
    final dark = resolve(appearance: const Appearance(colorScheme: 'dark'), branding: branding);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colors.background, hex('#0A0A0A'));
    expect(dark.colors.surfaceMuted, hex('#262626'));
    expect(dark.colors.textSecondary, hex('#A3A3A3'));
    expect(dark.colors.inputBorder, hex('#404040'));
    expect(dark.colors.inputBackground, hex('#0A0A0A'));
    expect(dark.separatorColor, isNull);
    expect(dark.colors.primary, hex('#0F766E'), reason: 'still 3:1 on the dark background');

    // …unless the merchant designed it for the dark scheme.
    const darkDesign = Branding(appearanceMode: 'dark', backgroundColor: '#111827', inputBorderColor: '#374151');
    final designedDark = resolve(branding: darkDesign);
    expect(designedDark.brightness, Brightness.dark);
    expect(designedDark.colors.background, hex('#111827'));
    expect(designedDark.colors.inputBackground, hex('#111827'));
    expect(designedDark.colors.inputBorder, hex('#374151'));
    expect(resolve(appearance: const Appearance(colorScheme: 'light'), branding: darkDesign).colors.background,
        hex('#FFFFFF'));

    // Radius tokens, the cap, the compact density.
    expect(resolve(branding: const Branding(borderRadius: 'lg')).radius, 12);
    expect(resolve(branding: const Branding(borderRadius: 'none')).radius, 0);
    expect(resolve(branding: const Branding(borderRadius: '40px')).radius, WajubThemeData.maxRadius);
    final compact = resolve(branding: const Branding(density: 'compact'));
    expect(compact.spacingUnit, 3);
    expect(compact.gapRow, 12);
  });

  test('AP-06 applies presets', () {
    expect(AppearanceResolver.presets.keys, unorderedEquals(['stripe', 'night', 'flat', 'none']));
    final stripe = AppearanceResolver.presets['stripe']!;
    expect(stripe.primaryColor, '#0570de');
    expect(stripe.borderRadius, '4px');
    expect(stripe.fontFamily, "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif");
    expect(stripe.shadow, 'low');
    final night = AppearanceResolver.presets['night']!;
    expect(night.colorScheme, 'dark');
    expect(night.primaryColor, '#7c3aed');
    expect(night.backgroundColor, '#0f172a');
    expect(night.buttonTextColor, '#f8fafc');
    expect(night.inputBackgroundColor, '#1e293b');
    expect(night.inputBorderColor, '#334155');
    expect(night.textMutedColor, '#94a3b8');
    expect(night.borderRadius, '8px');
    expect(night.shadow, 'none');
    final flat = AppearanceResolver.presets['flat']!;
    expect(flat.shadow, 'none');
    expect(flat.borderRadius, '0');

    final stripeTheme = resolve(appearance: const Appearance(theme: 'stripe'));
    expect(stripeTheme.colors.primary, hex('#0570de'));
    expect(stripeTheme.radius, 4);
    expect(stripeTheme.elevation, 1);
    expect(stripeTheme.fontFamily, isNull, reason: 'the system font stack: the platform font');

    final nightTheme = resolve(appearance: const Appearance(theme: 'night'), platform: Brightness.light);
    expect(nightTheme.brightness, Brightness.dark);
    expect(nightTheme.colors.primary, hex('#7c3aed'));
    expect(nightTheme.colors.background, hex('#0f172a'));
    expect(nightTheme.colors.onPrimary, hex('#f8fafc'));
    expect(nightTheme.colors.inputBackground, hex('#1e293b'));
    expect(nightTheme.colors.inputBorder, hex('#334155'));
    expect(nightTheme.colors.textSecondary, hex('#94a3b8'));
    expect(nightTheme.radius, 8);
    expect(nightTheme.elevation, 0);

    final flatTheme = resolve(appearance: const Appearance(theme: 'flat'));
    expect(flatTheme.elevation, 0);
    expect(flatTheme.radius, 0);

    expect(resolve(appearance: const Appearance(theme: 'none')), resolve());

    // The host's own keys sit on top of its preset.
    expect(
        resolve(appearance: const Appearance(theme: 'night', primaryColor: '#0F766E')).colors.primary, hex('#0F766E'));
  });

  testWidgets('AP-08 inherits the host theme', (tester) async {
    late WajubThemeData inherited;
    late WajubThemeData ignored;
    late WajubThemeData illegible;
    final illegibleTheme = ThemeData(
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFFEF08A),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFFE7E5E4),
        onSurfaceVariant: Color(0xFFD6D3D1),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF6D28D9),
          surface: Color(0xFFFAFAF9),
          onSurface: Color(0xFF1C1917),
          onSurfaceVariant: Color(0xFF57534E),
          outline: Color(0xFFA8A29E),
        ),
        textTheme: const TextTheme(bodyLarge: TextStyle(fontFamily: 'Merriweather')),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
        ),
      ),
      home: Builder(builder: (context) {
        final host = Theme.of(context);
        final platform = MediaQuery.platformBrightnessOf(context);
        inherited = AppearanceResolver.resolve(
          appearance: const Appearance(inherit: true),
          platformBrightness: platform,
          hostTheme: host,
        );
        ignored = AppearanceResolver.resolve(platformBrightness: platform, hostTheme: host);
        illegible = AppearanceResolver.resolve(
          appearance: const Appearance(inherit: true),
          platformBrightness: platform,
          hostTheme: illegibleTheme,
        );
        return const SizedBox();
      }),
    ));

    expect(inherited.brightness, Brightness.light);
    expect(inherited.colors.primary, const Color(0xFF6D28D9));
    expect(inherited.colors.background, const Color(0xFFFAFAF9));
    expect(inherited.colors.text, const Color(0xFF1C1917));
    expect(inherited.colors.textSecondary, const Color(0xFF57534E));
    expect(inherited.colors.inputBorder, const Color(0xFFA8A29E));
    expect(inherited.fontFamily, 'Merriweather');
    expect(inherited.radius, WajubThemeData.maxRadius, reason: 'the host radius 30 is capped at 22');

    // Without inherit the host app's theme is not read.
    expect(ignored, resolve());

    // Values that would not read on the background are dropped.
    expect(illegible.colors.primary, hex('#2563EB'));
    expect(illegible.colors.text, hex('#171717'));
    expect(illegible.colors.textSecondary, hex('#525252'));

    // A dark host makes a dark sheet.
    final darkHost = AppearanceResolver.resolve(
      appearance: const Appearance(inherit: true),
      platformBrightness: Brightness.light,
      hostTheme: ThemeData(colorScheme: const ColorScheme.dark()),
    );
    expect(darkHost.brightness, Brightness.dark);
  });

  testWidgets('the Material theme follows the tokens', (tester) async {
    final data = resolve(branding: brandingOf('session-cm-aggregate.json'));
    final theme = AppearanceResolver.materialTheme(data);
    expect(theme.colorScheme.primary, hex('#0F766E'));
    expect(theme.colorScheme.surface, hex('#FFFFFF'));
    expect(theme.inputDecorationTheme.fillColor, hex('#FFFFFF'));
    expect(theme.bottomSheetTheme.modalBarrierColor, const Color(0xFF000000).withAlpha(102));

    late WajubThemeData read;
    await tester.pumpWidget(WajubTheme(
      data: data,
      child: Builder(builder: (context) {
        read = WajubTheme.of(context);
        return const SizedBox();
      }),
    ));
    expect(read, data);
    await tester.pumpWidget(Builder(builder: (context) {
      read = WajubTheme.of(context);
      return const SizedBox();
    }));
    expect(read, WajubThemeData.light);

    // The sheet's Material widgets draw with it, in both schemes.
    for (final scheme in [theme, AppearanceResolver.materialTheme(WajubThemeData.dark)]) {
      await tester.pumpWidget(MaterialApp(
        theme: scheme,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TextField(decoration: InputDecoration(labelText: 'Phone', hintText: '67 12 34 56 7')),
              FilledButton(onPressed: () {}, child: const Text('Pay')),
              const FilledButton(onPressed: null, child: Text('Pay')),
              OutlinedButton(onPressed: () {}, child: const Text('Close')),
              TextButton(onPressed: () {}, child: const Text('Resend')),
              const LinearProgressIndicator(),
            ],
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      final field = tester.getSize(find.byType(TextField));
      expect(field.height, greaterThanOrEqualTo(44));
    }
  });
}
