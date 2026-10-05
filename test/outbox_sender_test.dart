import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prm/data/outbox_sender.dart';
import 'package:prm/data/sync_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/fake_backend.dart';

OutboxEntry put(String id, {String kind = 'sessions', String owner = 'u1'}) =>
    OutboxEntry(owner: owner, kind: kind, id: id, body: {'id': id});

OutboxEntry del(String id, {String kind = 'sessions'}) =>
    OutboxEntry(owner: 'u1', kind: kind, id: id);

void main() {
  late SyncOutbox outbox;
  String? user = 'u1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    outbox = SyncOutbox(await SharedPreferences.getInstance());
    user = 'u1';
  });

  Future<(OutboxSender, FakeBackend)> senderWith(
    Map<String, http.Response Function(http.Request)> handlers,
  ) async {
    final backend = FakeBackend(handlers);
    await backend.signIn();
    return (
      OutboxSender(outbox, backend.api, currentUserId: () => user),
      backend,
    );
  }

  http.Response ok(http.Request _) => FakeBackend.json(null, 204);

  test('sends in order, batching consecutive saves of one kind', () async {
    await outbox.addAll([
      put('a'),
      put('b'),
      del('c'),
      put('d'),
      put('w', kind: 'workouts'),
    ]);
    final (sender, backend) = await senderWith({
      'PUT /api/me/docs/sessions': ok,
      'DELETE /api/me/docs/sessions/c': ok,
      'PUT /api/me/docs/sessions/d': ok,
      'PUT /api/me/docs/workouts/w': ok,
    });

    expect(await sender.flush(), isTrue);

    expect(backend.calls, [
      'PUT /api/me/docs/sessions',
      'DELETE /api/me/docs/sessions/c',
      'PUT /api/me/docs/sessions/d',
      'PUT /api/me/docs/workouts/w',
    ]);
    expect(jsonDecode(backend.requests.first.body), {
      'docs': [
        {'id': 'a'},
        {'id': 'b'},
      ],
    });
    expect(outbox.isEmpty, isTrue);
  });

  test('keeps writes when offline and resumes later', () async {
    await outbox.addAll([put('a'), del('b')]);
    var online = false;
    final (sender, _) = await senderWith({
      'PUT /api/me/docs/sessions/a': (r) =>
          online ? ok(r) : throw http.ClientException('offline'),
      'DELETE /api/me/docs/sessions/b': ok,
    });

    expect(await sender.flush(), isFalse);
    expect(outbox.entries, hasLength(2));

    online = true;
    expect(await sender.flush(), isTrue);
    expect(outbox.isEmpty, isTrue);
  });

  test('pauses on 5xx but drops writes the server rejects', () async {
    await outbox.addAll([put('bad'), del('x')]);
    final (sender, _) = await senderWith({
      'PUT /api/me/docs/sessions/bad': (_) =>
          FakeBackend.json({'message': 'invalid'}, 400),
      'DELETE /api/me/docs/sessions/x': (_) => FakeBackend.json({}, 503),
    });
    expect(await sender.flush(), isFalse);
    expect(outbox.entries.single.id, 'x');
  });

  test('never sends another account\'s writes, but keeps them', () async {
    await outbox.addAll([put('mine'), put('theirs', owner: 'u2')]);
    final (sender, backend) = await senderWith({
      'PUT /api/me/docs/sessions/mine': ok,
      'PUT /api/me/docs/sessions/theirs': ok,
    });
    expect(await sender.flush(), isTrue);
    expect(backend.calls, ['PUT /api/me/docs/sessions/mine']);
    expect(outbox.entries.single.owner, 'u2');

    user = 'u2'; // that account signs in again later
    expect(await sender.flush(), isTrue);
    expect(outbox.isEmpty, isTrue);
  });

  test(
    'a rejected batch is retried per document; only bad ones drop',
    () async {
      await outbox.addAll([put('a'), put('bad'), put('c')]);
      final (sender, backend) = await senderWith({
        'PUT /api/me/docs/sessions': (_) =>
            FakeBackend.json({'message': 'bad id'}, 400),
        'PUT /api/me/docs/sessions/a': ok,
        'PUT /api/me/docs/sessions/bad': (_) => FakeBackend.json({}, 400),
        'PUT /api/me/docs/sessions/c': ok,
      });
      expect(await sender.flush(), isTrue);
      expect(backend.calls, [
        'PUT /api/me/docs/sessions',
        'PUT /api/me/docs/sessions/a',
        'PUT /api/me/docs/sessions/bad',
        'PUT /api/me/docs/sessions/c',
      ]);
      expect(outbox.isEmpty, isTrue);
    },
  );

  test('a too-large batch (413) is split instead of dropped', () async {
    await outbox.addAll([put('a'), put('b')]);
    final (sender, _) = await senderWith({
      'PUT /api/me/docs/sessions': (_) => FakeBackend.json({}, 413),
      'PUT /api/me/docs/sessions/a': ok,
      'PUT /api/me/docs/sessions/b': ok,
    });
    expect(await sender.flush(), isTrue);
    expect(outbox.isEmpty, isTrue);
  });

  test('408 and 409 are retried later, not dropped', () async {
    for (final status in [408, 409]) {
      await outbox.clear();
      await outbox.add(put('a'));
      final (sender, _) = await senderWith({
        'PUT /api/me/docs/sessions/a': (_) => FakeBackend.json({}, status),
      });
      expect(await sender.flush(), isFalse, reason: '$status');
      expect(outbox.entries, hasLength(1));
    }
  });

  test('stops when the account changes mid-flush', () async {
    await outbox.addAll([put('a'), del('b')]);
    final (sender, backend) = await senderWith({
      'PUT /api/me/docs/sessions/a': (r) {
        user = 'u2';
        return ok(r);
      },
    });
    expect(await sender.flush(), isFalse);
    expect(backend.calls, ['PUT /api/me/docs/sessions/a']);
  });

  test('signed out: nothing to send', () async {
    await outbox.add(put('a'));
    user = null;
    final (sender, backend) = await senderWith({});
    expect(await sender.flush(), isTrue);
    expect(backend.requests, isEmpty);
  });

  test('concurrent flushes share one run', () async {
    await outbox.add(put('a'));
    final (sender, backend) = await senderWith({
      'PUT /api/me/docs/sessions/a': ok,
    });
    await Future.wait([sender.flush(), sender.flush()]);
    expect(backend.requests, hasLength(1));
  });
}
