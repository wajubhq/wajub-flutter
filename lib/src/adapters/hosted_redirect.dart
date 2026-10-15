import 'package:url_launcher/url_launcher.dart';

/// Opens a provider's page in the system browser.
class HostedRedirect {
  HostedRedirect._();

  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
