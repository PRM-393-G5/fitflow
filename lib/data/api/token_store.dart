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
/// rooted file dump.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'api_access_token';
  static const _refreshKey = 'api_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<ApiTokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null || refresh == null) return null;
    return ApiTokens(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> write(ApiTokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
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
