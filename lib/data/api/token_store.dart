import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The API session: a short-lived access token and the refresh token that
/// renews it.
class ApiTokens {
  const ApiTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// Persists the API session between launches.
abstract interface class TokenStore {
  Future<ApiTokens?> read();
  Future<void> write(ApiTokens tokens);
  Future<void> clear();
}

/// Keychain (iOS) / EncryptedSharedPreferences-backed keystore (Android):
/// unlike SharedPreferences, tokens are not readable from a backup or a
/// rooted file dump. Both tokens live under one key so they always change
/// together, and the session is cached in memory after the first read.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'api_session';

  final FlutterSecureStorage _storage;
  ApiTokens? _cached;
  bool _loaded = false;

  @override
  Future<ApiTokens?> read() async {
    if (_loaded) return _cached;
    final raw = await _storage.read(key: _key);
    _cached = _decode(raw);
    _loaded = true;
    return _cached;
  }

  @override
  Future<void> write(ApiTokens tokens) async {
    _cached = tokens;
    _loaded = true;
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
      }),
    );
  }

  @override
  Future<void> clear() async {
    _cached = null;
    _loaded = true;
    await _storage.delete(key: _key);
  }

  static ApiTokens? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      final access = json is Map ? json['accessToken'] : null;
      final refresh = json is Map ? json['refreshToken'] : null;
      if (access is! String || refresh is! String) return null;
      return ApiTokens(accessToken: access, refreshToken: refresh);
    } on FormatException {
      return null;
    }
  }
}

/// Keeps tokens in memory only — for tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._tokens]);

  ApiTokens? _tokens;

  @override
  Future<ApiTokens?> read() async => _tokens;

  @override
  Future<void> write(ApiTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
