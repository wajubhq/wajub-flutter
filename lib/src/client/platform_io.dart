import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// An HTTP client that gives up connecting after [connectTimeout].
http.Client createHttpClient(Duration connectTimeout) => IOClient(HttpClient()..connectionTimeout = connectTimeout);

/// The platform's own `User-Agent` (`Dart/3.9 (dart:io)`), which the SDK
/// suffixes with its `X-Wajub-Client`.
String? defaultUserAgent() {
  final client = HttpClient();
  try {
    return client.userAgent;
  } finally {
    client.close(force: true);
  }
}
