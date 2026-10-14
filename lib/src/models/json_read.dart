// Lenient readers for /pay/* JSON. The API mixes types the strict casts did
// not expect — `branding.white_label` is a bool, `overlay_intensity` an int,
// some amounts arrive as numeric strings — and one `as String?` on such a
// value threw on every loadSession. These accept what the API sends and fall
// back instead of throwing.

String? readString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return null;
}

/// [readString], with an empty or blank string read as absent.
String? readText(Object? value) {
  final text = readString(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

double? readDouble(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) {
    final number = double.tryParse(value.trim());
    return number != null && number.isFinite ? number : null;
  }
  return null;
}

/// A number the payload cannot do without (`transaction.amount`): anything
/// that does not read as one is a [FormatException], not a silent 0.
double requireDouble(Object? value, String name) {
  final number = readDouble(value);
  if (number == null) throw FormatException('$name is not a number', value);
  return number;
}

int? readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value.trim()) ?? readDouble(value)?.toInt();
  return null;
}

bool? readBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
      case '':
        return false;
    }
  }
  return null;
}

List<String> readStringList(Object? value) {
  if (value is! List) return const [];
  return value.map(readString).whereType<String>().toList();
}

Map<String, dynamic>? readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return null;
}

List<Map<String, dynamic>> readMapList(Object? value) {
  if (value is! List) return const [];
  return value.map(readMap).whereType<Map<String, dynamic>>().toList();
}
