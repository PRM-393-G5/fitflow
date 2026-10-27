import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'token_store.dart';

/// A failed API call. [statusCode] is null when the server was not reached
/// (offline, DNS, timeout).
class ApiException implements Exception {
  const ApiException(
    this.statusCode,
    this.message, {
    this.error,
    this.timedOut = false,
  });

  final int? statusCode;
  final String message;

  /// The server's `error` reason (e.g. `Unauthorized`), when it sent one.
  final String? error;

  /// The request ran out of time (a network failure, [isNetwork] too).
  final bool timedOut;

  bool get isNetwork => statusCode == null;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

/// JSON client for the FitFlow API. Paths are relative to [baseUrl]
/// (`.../api/`). Authenticated calls send the stored access token; when it
/// has expired (401) the client refreshes the session once and retries.
/// If the refresh token is rejected too, the session is cleared and
/// [onSessionExpired] fires. A refresh that fails for any other reason
/// (offline, 5xx) keeps the session and surfaces the error.
///
/// Create one ApiClient per app and share it: refresh tokens are
/// single-use, so two clients refreshing the same session would race.
///
/// Known limit: if the server spends a refresh token but its answer is
/// lost (timeout mid-response), the next refresh is rejected and the user
/// has to sign in again.
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

  /// [timeout] overrides the client's for slow routes (AI generation).
  Future<dynamic> post(
    String path, {
    Object? body,
    bool auth = true,
    Duration? timeout,
  }) => _send('POST', path, body: body, auth: auth, timeout: timeout);

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
    Duration? timeout,
  }) async {
    final session = auth ? await tokens.read() : null;
    if (auth && session == null) {
      throw const ApiException(401, 'Not signed in');
    }
    var response = await _raw(
      method,
      path,
      body: body,
      accessToken: session?.accessToken,
      timeout: timeout,
    );
    if (session != null && response.statusCode == 401) {
      final renewed = await _refresh(session);
      if (renewed != null) {
        response = await _raw(
          method,
          path,
          body: body,
          accessToken: renewed.accessToken,
          timeout: timeout,
        );
      }
    }
    return _decode(response);
  }

  Future<ApiTokens?>? _refreshing;

  /// Renews the session that just got a 401. Concurrent callers share one
  /// refresh: the server rotates refresh tokens, so a second refresh with
  /// the same token would be rejected. Null when the session is over.
  Future<ApiTokens?> _refresh(ApiTokens stale) {
    return _refreshing ??= _doRefresh(stale)
        .whenComplete(() => _refreshing = null);
  }

  Future<ApiTokens?> _doRefresh(ApiTokens stale) async {
    final current = await tokens.read();
    if (current == null) return null;
    // Another request already renewed the session while ours was in flight.
    if (current.accessToken != stale.accessToken) return current;

    final sent = current.refreshToken;
    final response = await _raw(
      'POST',
      'auth/refresh',
      body: {'refreshToken': sent},
    );
    // Signed out or switched account meanwhile: leave the new state alone.
    Future<bool> stillCurrent() async =>
        (await tokens.read())?.refreshToken == sent;

    // 401 = spent/expired, 400/403 = a token the server will never accept.
    if (const {400, 401, 403}.contains(response.statusCode)) {
      if (await stillCurrent()) {
        await tokens.clear();
        if (!_sessionExpired.isClosed) _sessionExpired.add(null);
      }
      return null;
    }
    final json = _decode(response);
    final accessToken = json is Map ? json['accessToken'] : null;
    final refreshToken = json is Map ? json['refreshToken'] : null;
    if (accessToken is! String || refreshToken is! String) {
      throw ApiException(response.statusCode, 'Malformed server response');
    }
    final renewed = ApiTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    if (!await stillCurrent()) return null;
    await tokens.write(renewed);
    return renewed;
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Object? body,
    String? accessToken,
    Duration? timeout,
  }) async {
    // A leading slash would resolve from the host root and drop `/api/`.
    final relative = path.startsWith('/') ? path.substring(1) : path;
    final request = http.Request(method, baseUrl.resolve(relative))
      ..headers['Accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      // One budget for headers and body together.
      return await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const ApiException(
        null,
        'The server took too long to answer',
        timedOut: true,
      );
    } on SocketException catch (e) {
      throw ApiException(null, 'No connection to the server: ${e.message}');
    } on http.ClientException catch (e) {
      throw ApiException(null, 'No connection to the server: ${e.message}');
    } on TlsException catch (e) {
      // e.g. a captive portal answering instead of the server.
      throw ApiException(null, 'No secure connection to the server: $e');
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
    final error = json is Map ? json['error'] : null;
    throw ApiException(response.statusCode, switch (message) {
      String text => text,
      List list => list.join(', '),
      _ => 'Request failed (${response.statusCode})',
    }, error: error is String ? error : null);
  }

  /// Simulates the server rejecting the session — for tests.
  @visibleForTesting
  void debugEmitSessionExpired() => _sessionExpired.add(null);

  void close() {
    _http.close();
    _sessionExpired.close();
  }
}
