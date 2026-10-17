import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

/// A logo from the network, SVG (the API's operator logos are) or bitmap,
/// with [fallback] while it is missing: not loaded yet, not found, or not an
/// image. When [url] cannot be drawn, [fallbackUrl] (the logo's PNG) is
/// tried before [fallback]. Each URL is fetched once per run of the app.
class NetworkLogo extends StatefulWidget {
  const NetworkLogo({
    super.key,
    required this.url,
    this.fallbackUrl,
    required this.width,
    required this.height,
    required this.fallback,
  });

  /// [url] and [fallbackUrl] from a channel's or an operator's `logo` and
  /// `logo_png`; null when it has neither.
  static NetworkLogo? of({
    Key? key,
    required String? logo,
    required String? logoPng,
    required double width,
    required double height,
    required Widget fallback,
  }) {
    final url = logo ?? logoPng;
    if (url == null) return null;
    return NetworkLogo(
      key: key,
      url: url,
      fallbackUrl: url == logoPng ? null : logoPng,
      width: width,
      height: height,
      fallback: fallback,
    );
  }

  final String url;

  /// Tried when [url] does not load or cannot be drawn.
  final String? fallbackUrl;
  final double width;
  final double height;

  /// Drawn while the logo loads, and when it cannot be drawn.
  final Widget fallback;

  static final _cache = <String, Future<Uint8List?>>{};

  /// Forgets the logos fetched so far.
  @visibleForTesting
  static void clearCache() => _cache.clear();

  @override
  State<NetworkLogo> createState() => _NetworkLogoState();
}

class _NetworkLogoState extends State<NetworkLogo> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _fetch(widget.url);
  }

  @override
  void didUpdateWidget(NetworkLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _bytes = _fetch(widget.url);
  }

  static Future<Uint8List?> _fetch(String url) => NetworkLogo._cache.putIfAbsent(url, () async {
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) return response.bodyBytes;
        } catch (_) {
          // Offline, or not a URL: the fallback shows.
        }
        // Not kept: the next sheet tries again.
        NetworkLogo._cache.remove(url);
        return null;
      });

  bool _isSvg(Uint8List bytes) {
    if (Uri.tryParse(widget.url)?.path.toLowerCase().endsWith('.svg') ?? false) return true;
    final head = String.fromCharCodes(bytes.take(256)).trimLeft();
    return head.startsWith('<svg') || (head.startsWith('<?xml') && head.contains('<svg'));
  }

  /// The [fallbackUrl], else the [fallback].
  Widget _failed() {
    final next = widget.fallbackUrl;
    if (next == null) return widget.fallback;
    return NetworkLogo(url: next, width: widget.width, height: widget.height, fallback: widget.fallback);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return snapshot.connectionState == ConnectionState.done ? _failed() : widget.fallback;
          }
          if (_isSvg(bytes)) {
            return SvgPicture.memory(
              bytes,
              width: widget.width,
              height: widget.height,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _failed(),
            );
          }
          return Image.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _failed(),
          );
        },
      );
}
