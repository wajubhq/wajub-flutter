import 'package:http/http.dart' as http;

/// Browsers bound the connection themselves.
http.Client createHttpClient(Duration connectTimeout) => http.Client();

/// Browsers do not let a page set `User-Agent`.
String? defaultUserAgent() => null;
