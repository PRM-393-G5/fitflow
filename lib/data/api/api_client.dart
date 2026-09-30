import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'token_store.dart';

/// A failed API call. [statusCode] is null when the server was not reached
/// (offline, DNS, timeout).
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.error});

  final int? statusCode;
  final String message;

  /// The server's `error` reason (e.g. `Unauthorized`), when it sent one.
  final String? error;

  bool get isNetwork => statusCode == null;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

/// JSON client for the FitFlow API. Paths are relative to [baseUrl]
/// (`.../api/`). Authenticated calls send the stored access token; when it
/// has expired (401) the client refreshes the session once and retries.
/// If the refresh token is rejected too, the session is cleared and
/// [onSessionExpired] fires.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final TokenStore tokens;
  final Duration timeout;
  final http.Client _http;

  final _sessionExpired = StreamController<void>.broadcast();

  /// Fires when the server no longer accepts this device's session.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  Future<dynamic> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);

  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);

  Future<dynamic> put(String path, {Object? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<dynamic> delete(String path, {Object? body, bool auth = true}) =>
      _send('DELETE', path, body: body, auth: auth);

  /// Sends one request; returns the decoded JSON body (null when empty).
  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    required bool auth,
  }) async {
    final session = auth ? await tokens.read() : null;
    if (auth && session == null) {
      throw const ApiException(401, 'Not signed in');
    }
    final response = await _raw(
      method,
      path,
      body: body,
      accessToken: session?.accessToken,
    );
    return _decode(response);
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Object? body,
    String? accessToken,
  }) async {
    final request = http.Request(method, baseUrl.resolve(path))
      ..headers['Accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(null, 'The server took too long to answer');
    } on SocketException catch (e) {
      throw ApiException(null, 'No connection to the server: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException(null, 'No connection to the server: ${e.message}');
    }
  }

  dynamic _decode(http.Response response) {
    final text = response.body;
    dynamic json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        if (response.statusCode < 400) {
          throw ApiException(response.statusCode, 'Malformed server response');
        }
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return json;
    final message = json is Map ? json['message'] : null;
    throw ApiException(response.statusCode, switch (message) {
      String text => text,
      List list => list.join(', '),
      _ => 'Request failed (${response.statusCode})',
    }, error: json is Map ? json['error'] as String? : null);
  }

  void close() {
    _http.close();
    _sessionExpired.close();
  }
}
