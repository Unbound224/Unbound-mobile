import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/integrations/file_pending_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('unbound_pending_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File f() => File('${dir.path}/nested/pending.json');

  test('values survive "restart" (a new store instance on the same file)', () async {
    await FilePendingStore(f()).write('a', '1');
    expect(await FilePendingStore(f()).read('a'), '1');
    await FilePendingStore(f()).delete('a');
    expect(await FilePendingStore(f()).read('a'), isNull);
  });

  test('concurrent writes are serialized and none is lost', () async {
    final s = FilePendingStore(f());
    await Future.wait([for (var i = 0; i < 25; i++) s.write('k$i', 'v$i')]);
    for (var i = 0; i < 25; i++) {
      expect(await s.read('k$i'), 'v$i');
    }
  });

  test('a corrupt file reads as empty instead of crashing, and is then repairable', () async {
    f().createSync(recursive: true);
    f().writeAsStringSync('{not json');
    final s = FilePendingStore(f());
    expect(await s.read('x'), isNull);
    await s.write('x', 'ok');
    expect(await FilePendingStore(f()).read('x'), 'ok');
  });

  test('leaves no temp file behind', () async {
    await FilePendingStore(f()).write('a', '1');
    expect(f().parent.listSync().map((e) => e.path.split('/').last), ['pending.json']);
  });

  test('idempotency key is stable across restarts via keyFor', () async {
    final k1 = await keyFor(FilePendingStore(f()), 'create:q_1');
    final k2 = await keyFor(FilePendingStore(f()), 'create:q_1');
    expect(k2, k1);
    expect(await keyFor(FilePendingStore(f()), 'create:q_2'), isNot(k1));
  });
}
