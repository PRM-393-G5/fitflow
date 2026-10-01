import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prm/data/api/api_client.dart';
import 'package:prm/data/api/token_store.dart';

const session = ApiTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

ApiClient clientWith(
  MockClientHandler handler, {
  ApiTokens? tokens = session,
}) => ApiClient(
  baseUrl: Uri.parse('http://api.test/api/'),
  tokens: MemoryTokenStore(tokens),
  httpClient: MockClient(handler),
);

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('sends JSON with the bearer token under the API prefix', () async {
    late http.Request seen;
    final client = clientWith((request) async {
      seen = request;
      return jsonResponse({'ok': true});
    });

    final result = await client.put('me/meta', body: {'updatedAt': 1});

    expect(result, {'ok': true});
    expect(seen.method, 'PUT');
    expect(seen.url.toString(), 'http://api.test/api/me/meta');
    expect(seen.headers['Authorization'], 'Bearer access-1');
    expect(seen.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(seen.body), {'updatedAt': 1});
  });

  test('a leading slash keeps the API prefix', () async {
    late http.Request seen;
    final client = clientWith((request) async {
      seen = request;
      return jsonResponse({});
    });
    await client.get('/me');
    expect(seen.url.path, '/api/me');
  });

  test('a non-string error field does not crash decoding', () async {
    final client = clientWith(
      (_) async => jsonResponse({'message': 'x', 'error': 42}, 409),
    );
    await expectLater(
      client.get('me'),
      throwsA(isA<ApiException>().having((e) => e.error, 'error', isNull)),
    );
  });

  test('public calls send no token, and work signed out', () async {
    late http.Request seen;
    final client = clientWith((request) async {
      seen = request;
      return jsonResponse([]);
    }, tokens: null);

    expect(await client.get('templates', auth: false), isEmpty);
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('authenticated calls fail fast when signed out', () async {
    final client = clientWith(
      (_) async => fail('no request expected'),
      tokens: null,
    );
    await expectLater(
      client.get('me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
  });

  test('204 responses decode to null', () async {
    final client = clientWith((_) async => http.Response('', 204));
    expect(await client.delete('me/docs/sessions/s1'), isNull);
  });

  test('maps the API error body to ApiException', () async {
    final client = clientWith(
      (_) async => jsonResponse({
        'statusCode': 400,
        'error': 'Bad Request',
        'message': ['idToken must be a jwt string', 'other'],
      }, 400),
    );
    await expectLater(
      client.post('auth/google', body: {}, auth: false),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.error, 'error', 'Bad Request')
            .having(
              (e) => e.message,
              'message',
              'idToken must be a jwt string, other',
            ),
      ),
    );
  });

  test('non-JSON error pages still become ApiException', () async {
    final client = clientWith(
      (_) async => http.Response('<html>502</html>', 502),
    );
    await expectLater(
      client.get('templates', auth: false),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 502)),
    );
  });

  test('connection failures are network errors', () async {
    final client = clientWith(
      (_) async => throw const SocketException('Connection refused'),
    );
    await expectLater(
      client.get('templates', auth: false),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)),
    );
  });

  test('a hung server times out as a network error', () async {
    final client = ApiClient(
      baseUrl: Uri.parse('http://api.test/api/'),
      tokens: MemoryTokenStore(),
      httpClient: MockClient(
        (_) => Future.delayed(
          const Duration(seconds: 1),
          () => http.Response('', 200),
        ),
      ),
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      client.get('templates', auth: false),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)),
    );
  });

  group('session refresh', () {
    /// A fake API: `me` needs `Bearer <valid>`; `auth/refresh` rotates.
    ({ApiClient client, MemoryTokenStore store, List<String> calls}) fakeApi({
      required String valid,
      String acceptedRefresh = 'refresh-1',
      int refreshStatus = 200,
      Object? refreshBody,
      Future<void> Function()? beforeRefreshAnswer,
    }) {
      final calls = <String>[];
      final store = MemoryTokenStore(session);
      final client = ApiClient(
        baseUrl: Uri.parse('http://api.test/api/'),
        tokens: store,
        httpClient: MockClient((request) async {
          final path = request.url.path;
          calls.add(path);
          if (path == '/api/auth/refresh') {
            await beforeRefreshAnswer?.call();
            final body = jsonDecode(request.body) as Map;
            if (refreshStatus != 200 ||
                body['refreshToken'] != acceptedRefresh) {
              return jsonResponse({
                'message': 'no',
              }, refreshStatus == 200 ? 401 : refreshStatus);
            }
            return jsonResponse(
              refreshBody ??
                  {
                    'accessToken': 'access-2',
                    'expiresIn': 900,
                    'refreshToken': 'refresh-2',
                  },
            );
          }
          final ok = request.headers['Authorization'] == 'Bearer $valid';
          return ok ? jsonResponse({'id': 'u1'}) : jsonResponse({}, 401);
        }),
      );
      return (client: client, store: store, calls: calls);
    }

    test('renews an expired access token and retries once', () async {
      final api = fakeApi(valid: 'access-2');
      expect(await api.client.get('me'), {'id': 'u1'});
      expect(api.calls, ['/api/me', '/api/auth/refresh', '/api/me']);
      expect((await api.store.read())?.refreshToken, 'refresh-2');
    });

    test('concurrent 401s share a single refresh', () async {
      final api = fakeApi(valid: 'access-2');
      final results = await Future.wait(
        List.generate(3, (_) => api.client.get('me')),
      );
      expect(results, everyElement({'id': 'u1'}));
      expect(
        api.calls.where((call) => call == '/api/auth/refresh'),
        hasLength(1),
      );
    });

    test('a rejected refresh token ends the session', () async {
      final api = fakeApi(valid: 'access-2', acceptedRefresh: 'other');
      final expired = expectLater(api.client.onSessionExpired, emits(null));
      await expectLater(
        api.client.get('me'),
        throwsA(
          isA<ApiException>().having((e) => e.isUnauthorized, '401', true),
        ),
      );
      await expired;
      expect(await api.store.read(), isNull);
    });

    test('a refresh that fails otherwise keeps the session', () async {
      final api = fakeApi(valid: 'access-2', refreshStatus: 503);
      await expectLater(
        api.client.get('me'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
      expect((await api.store.read())?.refreshToken, 'refresh-1');
    });

    test('a malformed (400) or forbidden (403) refresh also ends it', () async {
      for (final status in [400, 403]) {
        final api = fakeApi(valid: 'access-2', refreshStatus: status);
        await expectLater(api.client.get('me'), throwsA(isA<ApiException>()));
        expect(await api.store.read(), isNull, reason: 'status $status');
      }
    });

    test('a malformed refresh answer is an ApiException', () async {
      final api = fakeApi(valid: 'access-2', refreshBody: {'accessToken': 1});
      await expectLater(
        api.client.get('me'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Malformed'),
          ),
        ),
      );
      expect((await api.store.read())?.refreshToken, 'refresh-1');
    });

    test('signing out during a refresh is not undone', () async {
      late MemoryTokenStore store;
      final api = fakeApi(
        valid: 'access-2',
        beforeRefreshAnswer: () => store.clear(),
      );
      store = api.store;
      await expectLater(api.client.get('me'), throwsA(isA<ApiException>()));
      expect(await api.store.read(), isNull);
    });

    test('a rejected refresh does not wipe a newer sign-in', () async {
      late MemoryTokenStore store;
      const other = ApiTokens(
        accessToken: 'b-access',
        refreshToken: 'b-refresh',
      );
      final api = fakeApi(
        valid: 'access-2',
        acceptedRefresh: 'nope',
        beforeRefreshAnswer: () => store.write(other),
      );
      store = api.store;
      await expectLater(api.client.get('me'), throwsA(isA<ApiException>()));
      expect((await api.store.read())?.refreshToken, 'b-refresh');
    });

    test('closing during a refresh does not throw', () async {
      late ApiClient client;
      final api = fakeApi(
        valid: 'access-2',
        acceptedRefresh: 'nope',
        beforeRefreshAnswer: () async => client.close(),
      );
      client = api.client;
      await expectLater(api.client.get('me'), throwsA(isA<ApiException>()));
    });
  });
}
