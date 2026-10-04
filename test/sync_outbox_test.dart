import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/sync_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

OutboxEntry put(String id, [int v = 1, String owner = 'u1']) => OutboxEntry(
  owner: owner,
  kind: 'sessions',
  id: id,
  body: {'id': id, 'v': v},
);

OutboxEntry del(String id, [String owner = 'u1']) =>
    OutboxEntry(owner: owner, kind: 'sessions', id: id);

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test('survives a restart', () async {
    await SyncOutbox(preferences).addAll([put('a'), del('b')]);
    final reloaded = SyncOutbox(preferences);
    expect(reloaded.entries.map((e) => (e.id, e.isDelete)), [
      ('a', false),
      ('b', true),
    ]);
  });

  test('keeps only the latest write per document, at the end', () async {
    final outbox = SyncOutbox(preferences);
    await outbox.add(put('a', 1));
    await outbox.add(put('b'));
    await outbox.add(put('a', 2));
    await outbox.add(del('b'));
    expect(outbox.entries.map((e) => (e.id, e.body?['v'])), [
      ('a', 2),
      ('b', null),
    ]);
  });

  test(
    'removing a delivered write keeps a newer one for the same doc',
    () async {
      final outbox = SyncOutbox(preferences);
      final first = put('a', 1);
      await outbox.add(first);
      await outbox.add(put('a', 2)); // queued while `first` was in flight
      await outbox.remove([first]);
      expect(outbox.entries.single.body?['v'], 2);
    },
  );

  test('keeps accounts apart', () async {
    final outbox = SyncOutbox(preferences);
    await outbox.addAll([put('a', 1, 'u1'), put('a', 1, 'u2')]);
    expect(outbox.pendingFor('u1', 'sessions'), hasLength(1));
    expect(outbox.entries, hasLength(2));
  });

  test('later duplicates in one batch win', () async {
    final outbox = SyncOutbox(preferences);
    await outbox.addAll([put('a', 1), put('a', 2)]);
    expect(outbox.entries.single.body?['v'], 2);
  });

  test('clear empties the stored queue', () async {
    final outbox = SyncOutbox(preferences);
    await outbox.add(put('a'));
    await outbox.clear();
    expect(SyncOutbox(preferences).isEmpty, isTrue);
  });

  test('ignores a corrupt stored queue', () {
    SharedPreferences.setMockInitialValues({'sync_outbox_v1': '{oops'});
    return SharedPreferences.getInstance().then((prefs) {
      expect(SyncOutbox(prefs).isEmpty, isTrue);
    });
  });
}
