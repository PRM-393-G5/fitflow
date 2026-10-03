import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/sync_merge.dart';

void main() {
  test('mergeDocs: remote wins, tombstones drop local copies', () {
    final result = SyncMerge.mergeDocs(
      [
        {'id': 'shared', 'v': 'local'},
        {'id': 'local-only', 'v': 1},
        {'id': 'deleted-remotely', 'v': 1},
      ],
      [
        {'id': 'shared', 'v': 'remote'},
        {'id': 'remote-only', 'v': 2},
        {'id': 'deleted-remotely', 'deleted': true},
      ],
    );
    final byId = {for (final doc in result.merged) doc['id']: doc};
    expect(byId.keys, unorderedEquals(['shared', 'local-only', 'remote-only']));
    expect(byId['shared']!['v'], 'remote');
    expect(result.toUpload.map((doc) => doc['id']), ['local-only']);
  });

  test('mergeDocs uploads nothing when the server has everything', () {
    final result = SyncMerge.mergeDocs(
      [
        {'id': 'a'},
      ],
      [
        {'id': 'a'},
      ],
    );
    expect(result.toUpload, isEmpty);
  });
}
