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

double? readDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int? readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.toInt();
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
