// Builds the Mobile Money tables the package ships
// (assets/wajub/mobile-money.min.json) from the spec's copy that
// sync-spec.sh writes (assets/wajub/mobile-money.json, kept out of the
// published archive): the same tables, without the notes the SDK never
// reads (where each rule comes from, how the web differs, the algorithms in
// prose). Run it after every sync:
//
//   dart run tool/mobile_money_runtime.dart
//
// The Mobile Money tests fail when the shipped copy is not this script's
// output for the synced file.

import 'dart:convert';
import 'dart:io';

/// The synced file, byte for byte the spec's.
const syncedFile = 'assets/wajub/mobile-money.json';

/// What the package ships and reads.
const runtimeFile = 'assets/wajub/mobile-money.min.json';

/// Notes for people, never read by the SDK.
const _notes = {'source', 'errata', 'algorithms', 'dial_code_source', 'source_pattern', 'verified'};

/// [synced] without its notes, as compact JSON.
String runtimeTables(String synced) => '${jsonEncode(_strip(jsonDecode(synced)))}\n';

Object? _strip(Object? value) => switch (value) {
      Map() => {
          for (final entry in value.entries)
            if (!_notes.contains(entry.key)) entry.key as String: _strip(entry.value),
        },
      List() => [for (final item in value) _strip(item)],
      _ => value,
    };

void main() {
  File(runtimeFile).writeAsStringSync(runtimeTables(File(syncedFile).readAsStringSync()));
  stdout.writeln('wrote $runtimeFile');
}
