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
}
