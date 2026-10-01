import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/app_user.dart';
import 'api/api_client.dart';
import 'api/token_store.dart';
import 'google_id_tokens.dart';

/// Sign-in against the FitFlow API (replaces Firebase Auth): Google gives
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
  });

  static const _userKey = 'auth_user_v1';

  final ApiClient _api;
  final TokenStore _tokens;
  final SharedPreferences _preferences;
  final GoogleIdTokens _google;

  final _changes = StreamController<AppUser?>.broadcast();
  StreamSubscription<void>? _expiry;
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
      await _forget();
    }
    _expiry ??= _api.onSessionExpired.listen((_) => _forget(notify: true));
  }

  Future<AppUser> signInWithGoogle() async {
    final idToken = await _google.signIn();
    final json = await _api.post(
      'auth/google',
      body: {'idToken': idToken},
      auth: false,
    ) as Map<String, dynamic>;
    await _tokens.write(
      ApiTokens(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      ),
    );
    final user = AppUser.fromJson(json['user'] as Map<String, dynamic>);
    await _remember(user);
    return user;
  }

  /// Ends the session on the server (best effort — offline it simply
  /// expires) and on this device.
  Future<void> signOut() async {
    final session = await _tokens.read();
    if (session != null) {
      try {
        await _api.post(
          'auth/logout',
          body: {'refreshToken': session.refreshToken},
          auth: false,
        );
      } on ApiException catch (e) {
        debugPrint('Logout request failed: $e');
      }
    }
    try {
      await _google.signOut();
    } catch (_) {
      // The API session is what matters — always end it.
    }
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
    _changes.add(user);
  }

  Future<void> _forget({bool notify = false}) async {
    await _tokens.clear();
    await _preferences.remove(_userKey);
    final hadUser = _user != null;
    _user = null;
    if (notify && hadUser) _changes.add(null);
  }

  void dispose() {
    _expiry?.cancel();
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
