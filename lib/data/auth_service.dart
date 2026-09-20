import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _google = GoogleSignIn.instance;

  Future<void>? _initialized;

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> _ensureInitialized() async {
    try {
      await (_initialized ??= _google.initialize(
        serverClientId: '578747595727-nftl7og0f8q21va0hdhohd6subqn2iiv.apps.googleusercontent.com',
      ));
    } catch (_) {
      // Let the next attempt retry instead of replaying the cached failure.
      _initialized = null;
      rethrow;
    }
  }

  Future<AuthCredential> _googleCredential() async {
    await _ensureInitialized();
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google did not return an ID token.',
      );
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  Future<void> signInWithGoogle() async {
    await _auth.signInWithCredential(await _googleCredential());
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // The Firebase session is what gates sync — always end it.
    }
    await _auth.signOut();
  }

  /// Confirms the signed-in user with a fresh Google login — Firebase
  /// requires a recent login before deleting the account.
  Future<void> reauthenticate() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reauthenticateWithCredential(await _googleCredential());
  }

  /// Deletes the Firebase account; call [reauthenticate] first.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
    try {
      await _google.signOut();
    } catch (_) {}
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
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'network-request-failed' => 'No network connection.',
      'user-disabled' => 'This account has been disabled.',
      'too-many-requests' => 'Too many attempts — try again later.',
      _ => 'Sign-in failed (${error.code}) — try again.',
    };
  }
  return 'Sign-in failed — try again.';
}
