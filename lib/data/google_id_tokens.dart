import 'package:google_sign_in/google_sign_in.dart';

/// Gets Google ID tokens for the API to verify. An interface so the auth
/// service can be tested without the Google Sign-In plugin.
abstract interface class GoogleIdTokens {
  /// Shows the Google account picker and returns a fresh ID token.
  /// Throws [GoogleSignInException] when cancelled or unavailable.
  Future<String> signIn();

  /// Forgets the chosen Google account on this device.
  Future<void> signOut();
}

/// Google Sign-In plugin implementation. The web client ID is the
/// `serverClientId`, so the token's audience is what the API accepts
/// (`GOOGLE_CLIENT_IDS` in fitflow-api).
class GoogleSignInIdTokens implements GoogleIdTokens {
  GoogleSignInIdTokens({GoogleSignIn? google})
    : _google = google ?? GoogleSignIn.instance;

  static const serverClientId =
      '578747595727-nftl7og0f8q21va0hdhohd6subqn2iiv.apps.googleusercontent.com';

  final GoogleSignIn _google;
  Future<void>? _initialized;

  Future<void> _ensureInitialized() async {
    try {
      await (_initialized ??= _google.initialize(
        serverClientId: serverClientId,
      ));
    } catch (_) {
      // Let the next attempt retry instead of replaying the cached failure.
      _initialized = null;
      rethrow;
    }
  }

  @override
  Future<String> signIn() async {
    await _ensureInitialized();
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Google did not return an ID token.',
      );
    }
    return idToken;
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await _google.signOut();
  }
}
