import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prm/data/api/api_client.dart';
import 'package:prm/data/api/token_store.dart';
import 'package:prm/data/google_id_tokens.dart';

/// Google stand-in returning a fixed ID token.
class FakeGoogle implements GoogleIdTokens {
  FakeGoogle([this.idToken = 'google-id-token']);

  String idToken;
  Object? error;
  int signIns = 0;
  int signOuts = 0;

  @override
  Future<String> signIn() async {
    signIns++;
    if (error != null) throw error!;
    return idToken;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

/// A scripted API: [handlers] map "METHOD /path" to a response; every
/// request is recorded in [requests].
class FakeBackend {
  FakeBackend(this.handlers);

  final Map<String, http.Response Function(http.Request)> handlers;
  final requests = <http.Request>[];
  final tokens = MemoryTokenStore();

  late final api = ApiClient(
    baseUrl: Uri.parse('http://api.test/api/'),
    tokens: tokens,
    httpClient: MockClient((request) async {
      requests.add(request);
      final handler = handlers['${request.method} ${request.url.path}'];
      return handler?.call(request) ?? json({'message': 'not found'}, 404);
    }),
  );

  /// Stores a session so authenticated calls carry a bearer token.
  Future<void> signIn() => tokens.write(
    const ApiTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
  );

  List<String> get calls =>
      requests.map((r) => '${r.method} ${r.url.path}').toList();

  static http.Response json(Object? body, [int status = 200]) => http.Response(
    body == null ? '' : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

const apiUser = {
  'id': '6710a1b2c3d4e5f601234567',
  'email': 'athlete@example.com',
  'name': 'Athlete',
  'photoUrl': null,
};

http.Response signInResponse(http.Request _) => FakeBackend.json({
  'accessToken': 'access-1',
  'expiresIn': 900,
  'refreshToken': 'refresh-1',
  'user': apiUser,
});
