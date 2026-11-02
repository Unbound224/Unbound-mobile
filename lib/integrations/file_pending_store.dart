import 'dart:convert';
import 'dart:io';

import '../flows/ports.dart';

/// Durable [PendingStore] backed by one JSON file with atomic replace. Holds idempotency keys and
/// in-flight ids (not secrets), so a crash or restart resumes the SAME operation. Writes are
/// serialized; a corrupt file is treated as empty rather than crashing the app.
class FilePendingStore implements PendingStore {
  FilePendingStore(this.file);
  final File file;
  Future<void> _tail = Future<void>.value();

  Map<String, String> _read() {
    if (!file.existsSync()) {
      return {};
    }
    try {
      final j = jsonDecode(file.readAsStringSync());
      if (j is Map<String, Object?>) {
        return {
          for (final e in j.entries)
            if (e.value is String) e.key: e.value! as String,
        };
      }
    } on FormatException {
      // fall through: treat as empty
    }
    return {};
  }

  Future<T> _locked<T>(Future<T> Function() f) {
    final run = _tail.then((_) => f());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  void _write(Map<String, String> m) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(m), flush: true);
    tmp.renameSync(file.path);
  }

  @override
  Future<String?> read(String key) => _locked(() async => _read()[key]);

  @override
  Future<void> write(String key, String value) =>
      _locked(() async => _write(_read()..[key] = value));

  @override
  Future<void> delete(String key) =>
      _locked(() async => _write(_read()..remove(key)));
}
