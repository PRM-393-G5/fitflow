import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/app_user.dart';
import 'api/api_client.dart';
import 'api/token_store.dart';
import 'google_id_tokens.dart';

/// Sign-in against the FitFlow API: Google gives
/// an ID token, the API verifies it and returns its own session.
///
/// The profile is cached in SharedPreferences so [currentUser] is known
/// synchronously at startup; the session tokens live in [TokenStore].
class BackendAuthService {
  BackendAuthService({
    required this._api,
    required this._tokens,
    required this._preferences,
    required this._google,
  }) {
    _expiry = _api.onSessionExpired.listen((_) => _onSessionExpired());
  }

  static const _userKey = 'auth_user_v1';

  final ApiClient _api;
  final TokenStore _tokens;
  final SharedPreferences _preferences;
  final GoogleIdTokens _google;

  final _changes = StreamController<AppUser?>.broadcast();
  late final StreamSubscription<void> _expiry;
  AppUser? _user;

  /// Emits on every sign-in and sign-out (including an expired session).
  Stream<AppUser?> get userChanges => _changes.stream;
  AppUser? get currentUser => _user;

  /// Restores the previous session. A cached profile without tokens (or
  /// tokens without a profile) counts as signed out.
  Future<void> init() async {
    final session = await _tokens.read();
    final cached = _readCachedUser();
    if (session != null && cached != null) {
      _user = cached;
    } else {
      // Half a session is unusable; revoke what the server still knows.
      if (session != null) await _revoke(session);
      await _forget();
    }
  }

  /// Signs in with Google. Signing in while another account is signed in
  /// ends that session first, so listeners always see a sign-out between
  /// two accounts.
  Future<AppUser> signInWithGoogle() async {
    final idToken = await _google.signIn();
    if (_user != null || await _tokens.read() != null) await signOut();
    final json = await _api.post(
      'auth/google',
      body: {'idToken': idToken},
      auth: false,
    );
    // Parse everything before storing anything: a malformed answer must
    // not leave tokens behind without a user.
    final ApiTokens tokens;
    final AppUser user;
    try {
      final map = json as Map<String, dynamic>;
      tokens = ApiTokens(
        accessToken: map['accessToken'] as String,
        refreshToken: map['refreshToken'] as String,
      );
      user = AppUser.fromJson(map['user'] as Map<String, dynamic>);
    } on TypeError {
      throw const ApiException(200, 'Malformed sign-in response');
    }
    await _tokens.write(tokens);
    await _remember(user);
    return user;
  }

  /// Ends the session on the server (best effort — offline it simply
  /// expires) and on this device.
  Future<void> signOut() async {
    final session = await _tokens.read();
    if (session != null) await _revoke(session);
    try {
      await _google.signOut();
    } catch (_) {
      // The API session is what matters — always end it.
    }
    await _forget(notify: true);
  }

  /// A fresh Google ID token proving the user is present — the API only
  /// deletes an account with one issued within the last few minutes.
  Future<String> reauthenticate() => _google.signIn();

  /// Deletes the account and all its cloud data (the API does both), then
  /// signs out locally. [idToken] comes from [reauthenticate]. Throws
  /// [ApiException] without signing out when the server refuses or is
  /// unreachable, so the account stays intact and usable.
  Future<void> deleteAccount(String idToken) async {
    try {
      await _api.delete('me', body: {'idToken': idToken});
    } on ApiException catch (e) {
      // The server may have deleted the account and then failed (or the
      // answer got lost): if the account is gone, finish locally.
      final ambiguous = e.statusCode == 401 || (e.statusCode ?? 0) >= 500;
      if (!ambiguous || !await _accountGone()) rethrow;
    }
    try {
      await _google.signOut();
    } catch (_) {}
    await _forget(notify: true);
  }

  Future<bool> _accountGone() async {
    try {
      await _api.get('me');
      return false;
    } on ApiException catch (e) {
      return e.isUnauthorized;
    }
  }

  /// Revokes [session] on the server; failures (offline, TLS, …) are
  /// ignored — the session then simply expires.
  Future<void> _revoke(ApiTokens session) async {
    try {
      await _api.post(
        'auth/logout',
        body: {'refreshToken': session.refreshToken},
        auth: false,
      );
    } catch (e) {
      debugPrint('Logout request failed: $e');
    }
  }

  /// ApiClient already cleared the rejected session. Forget the user only
  /// if no new session was created before this event arrived.
  Future<void> _onSessionExpired() async {
    if (await _tokens.read() != null) return;
    await _forget(notify: true);
  }

  AppUser? _readCachedUser() {
    final raw = _preferences.getString(_userKey);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(AppUser user) async {
    await _preferences.setString(_userKey, jsonEncode(user.toJson()));
    _user = user;
    if (!_changes.isClosed) _changes.add(user);
  }

  Future<void> _forget({bool notify = false}) async {
    await _tokens.clear();
    await _preferences.remove(_userKey);
    final hadUser = _user != null;
    _user = null;
    if (notify && hadUser && !_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    _expiry.cancel();
    _changes.close();
  }
}

/// A short user-facing message for a sign-in failure.
String describeAuthError(Object error) {
  if (error is GoogleSignInException) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Sign-in was cancelled.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is not configured for this build.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google sign-in is unavailable on this device.',
      _ => 'Google sign-in failed — try again.',
    };
  }
  if (error is ApiException) {
    if (error.isNetwork) return 'Cannot reach the FitFlow server.';
    return switch (error.statusCode) {
      401 || 403 => 'Google could not confirm this account — try again.',
      429 => 'Too many attempts — try again in a minute.',
      503 => 'Sign-in is temporarily unavailable — try again later.',
      _ => 'Sign-in failed (${error.statusCode}) — try again.',
    };
  }
  return 'Sign-in failed — try again.';
}
