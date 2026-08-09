import 'package:url_launcher/url_launcher.dart';

/// Opens PSP confirmation URLs in the system browser — never an embedded WebView.
class HostedRedirect {
  HostedRedirect._();

  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
