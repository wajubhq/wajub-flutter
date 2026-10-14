import 'dart:convert';
import 'dart:io';

/// The spec's fixtures, synced into test/fixtures by sync-spec.sh.
const fixturesDir = 'test/fixtures';

/// Every fixture file name (`session-cm-aggregate.json`…), vectors excluded.
List<String> fixtureNames() => Directory(fixturesDir)
    .listSync()
    .whereType<File>()
    .map((f) => f.uri.pathSegments.last)
    .where((name) => name.endsWith('.json') && name != 'mobile-money.vectors.json')
    .toList()
  ..sort();

/// The whole envelope: `request`, `http_status`, `body` (or a realtime
/// event's `event`, `channel`, `data`).
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('$fixturesDir/$name').readAsStringSync()) as Map<String, dynamic>;

/// What the API answered.
Map<String, dynamic> fixtureBody(String name) => Map<String, dynamic>.from(fixture(name)['body'] as Map);

/// The HTTP status the API answered with.
int fixtureStatus(String name) => fixture(name)['http_status'] as int;

/// The body the scenario sent, when it sent one.
Map<String, dynamic>? fixtureRequestBody(String name) {
  final body = (fixture(name)['request'] as Map?)?['body'];
  return body is Map ? Map<String, dynamic>.from(body) : null;
}

/// The Mobile Money test vectors.
Map<String, dynamic> vectors() =>
    jsonDecode(File('$fixturesDir/mobile-money.vectors.json').readAsStringSync()) as Map<String, dynamic>;
