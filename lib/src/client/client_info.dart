import 'dart:convert';
import 'dart:ui' show PlatformDispatcher, Size;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../version.dart';
import 'ids.dart';
import 'platform_web.dart' if (dart.library.io) 'platform_io.dart';

/// What the SDK tells the API about the device and itself (spec README §2.2,
/// §2.3): the `X-Wajub-Client` and `Accept-Language` headers, and the device
/// signals sent as `data._client` on every payment, which the API's risk
/// scoring reads.
class ClientInfo {
  const ClientInfo({
    required this.platform,
    required this.osVersion,
    required this.timezone,
    required this.locales,
    required this.screen,
    this.colorDepth = 24,
    required this.fingerprint,
    this.platformUserAgent,
  });

  /// `android` or `ios` (the operating system's name elsewhere).
  final String platform;

  /// The OS release: `15`, `18.1`. Empty when the platform would not tell.
  final String osVersion;

  /// The device's IANA zone: `Africa/Douala`.
  final String timezone;

  /// The device's languages, BCP 47 with region, preferred first.
  final List<String> locales;

  /// `<width>x<height>` of the main display in physical pixels, portrait.
  final String screen;
  final int colorDepth;

  /// Stable for one install: hex SHA-256 of `device:` and a random id kept
  /// in the app's private storage. Never derived from a hardware id.
  final String fingerprint;

  /// The platform's own `User-Agent`, when the SDK may set one.
  final String? platformUserAgent;

  static const _installIdKey = 'wajub_mobile.install_id';
  static Future<ClientInfo>? _current;
  static String? _volatileInstallId;

  /// `wajub-flutter/1.6.0 (android 15)`.
  String get wajubClient => 'wajub-flutter/$wajubSdkVersion ($platform${osVersion.isEmpty ? '' : ' $osVersion'})';

  /// The device's first language: `fr-CM`.
  String get language => locales.isEmpty ? 'en' : locales.first;

  /// `fr-CM, fr;q=0.9, en;q=0.8`: each language with its region, then
  /// without, by decreasing preference.
  String get acceptLanguage {
    final tags = <String>[];
    for (final locale in locales.isEmpty ? const ['en'] : locales) {
      for (final tag in [locale, locale.split('-').first]) {
        if (!tags.contains(tag)) tags.add(tag);
      }
    }
    final parts = <String>[];
    for (var i = 0; i < tags.length && i < 10; i++) {
      parts.add(i == 0 ? tags[i] : '${tags[i]};q=${(10 - i) / 10}');
    }
    return parts.join(', ');
  }

  /// The platform's `User-Agent` followed by [wajubClient], or null where
  /// the platform does not let the SDK set it.
  String? get userAgent => platformUserAgent == null ? null : '$platformUserAgent $wajubClient';

  /// `data._client` of `POST /pay/process`.
  Map<String, Object?> get signals => {
        'timezone': timezone,
        'language': language,
        'screen': screen,
        'color_depth': colorDepth,
        'fingerprint': fingerprint,
        'client': wajubClient,
      };

  /// This device's info, read once per process.
  static Future<ClientInfo> current() => _current ??= _read();

  /// Forgets what [current] read, as a restart of the app would.
  @visibleForTesting
  static void reset() {
    _current = null;
    _volatileInstallId = null;
  }

  /// The install fingerprint: the same for every [ClientInfo] of one install,
  /// across restarts, as long as the app's storage is kept.
  static Future<String> installFingerprint() async {
    final id = await _installId();
    return sha256.convert(utf8.encode('device:$id')).toString();
  }

  static Future<String> _installId() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_installIdKey);
      if (stored != null && stored.isNotEmpty) return stored;
      final created = uuidV4();
      await preferences.setString(_installIdKey, created);
      return created;
    } catch (_) {
      // No storage plugin (a test, an unsupported platform): an id for this
      // run only, which the API reads as a new device.
      return _volatileInstallId ??= uuidV4();
    }
  }

  static Future<ClientInfo> _read() async {
    final dispatcher = PlatformDispatcher.instance;
    final results = await Future.wait([_osVersion(), _timezone(), installFingerprint()]);
    return ClientInfo(
      platform: _platformName(),
      osVersion: results[0],
      timezone: results[1],
      locales: [for (final locale in dispatcher.locales) locale.toLanguageTag()],
      screen: _screen(dispatcher),
      fingerprint: results[2],
      platformUserAgent: _userAgent(),
    );
  }

  static String _platformName() => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          final other => other.name.toLowerCase(),
        };

  static Future<String> _osVersion() async {
    if (kIsWeb) return '';
    try {
      final plugin = DeviceInfoPlugin();
      return switch (defaultTargetPlatform) {
        TargetPlatform.android => (await plugin.androidInfo).version.release,
        TargetPlatform.iOS => (await plugin.iosInfo).systemVersion,
        _ => '',
      };
    } catch (_) {
      return '';
    }
  }

  static Future<String> _timezone() async {
    try {
      // flutter_timezone 4 answers the identifier, 5 a TimezoneInfo carrying
      // it: both are allowed, Flutter 3.24 can only resolve 4.
      final Object zone = await FlutterTimezone.getLocalTimezone();
      return zone is String ? zone : (zone as dynamic).identifier as String;
    } catch (_) {
      // Without the plugin only the abbreviation is known (`WAT`).
      return DateTime.now().timeZoneName;
    }
  }

  static String _screen(PlatformDispatcher dispatcher) {
    final size = dispatcher.displays.isNotEmpty
        ? dispatcher.displays.first.size
        : (dispatcher.implicitView?.physicalSize ?? Size.zero);
    final short = size.shortestSide.round();
    final long = size.longestSide.round();
    return '${short}x$long';
  }

  static String? _userAgent() {
    try {
      return defaultUserAgent();
    } catch (_) {
      return null;
    }
  }
}
