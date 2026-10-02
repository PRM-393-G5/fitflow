import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:prm/data/api/api_client.dart';
import 'package:prm/data/api/token_store.dart';
import 'package:prm/data/backend_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';

void main() {
  late SharedPreferences preferences;
  late FakeGoogle google;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    google = FakeGoogle();
  });

  BackendAuthService serviceFor(FakeBackend backend) => BackendAuthService(
    api: backend.api,
    tokens: backend.tokens,
    preferences: preferences,
    google: google,
  );

  test('signs in with the Google token and keeps the session', () async {
    final backend = FakeBackend({'POST /api/auth/google': signInResponse});
    final auth = serviceFor(backend);
    await auth.init();
    final changes = expectLater(
      auth.userChanges,
      emits(
        predicate((user) => (user as dynamic)?.email == 'athlete@example.com'),
      ),
    );

    final user = await auth.signInWithGoogle();

    await changes;
    expect(user.displayName, 'Athlete');
    expect(auth.currentUser, user);
    expect(jsonDecode(backend.requests.single.body), {
      'idToken': 'google-id-token',
    });
    expect(backend.requests.single.headers['Authorization'], isNull);
    expect((await backend.tokens.read())?.refreshToken, 'refresh-1');
  });

  test('restores the signed-in user on the next launch', () async {
    final backend = FakeBackend({'POST /api/auth/google': signInResponse});
    await serviceFor(backend).signInWithGoogle();

    final relaunched = serviceFor(backend);
    await relaunched.init();
    expect(relaunched.currentUser?.email, 'athlete@example.com');
  });

  test('a cached profile without a session counts as signed out', () async {
    final backend = FakeBackend({'POST /api/auth/google': signInResponse});
    await serviceFor(backend).signInWithGoogle();
    await backend.tokens.clear();

    final relaunched = serviceFor(backend);
    await relaunched.init();
    expect(relaunched.currentUser, isNull);
    expect(preferences.getString('auth_user_v1'), isNull);
  });

  test('signing out revokes the session and forgets the user', () async {
    final backend = FakeBackend({
      'POST /api/auth/google': signInResponse,
      'POST /api/auth/logout': (_) => FakeBackend.json(null, 204),
    });
    final auth = serviceFor(backend);
    await auth.init();
    await auth.signInWithGoogle();
    final signedOut = expectLater(auth.userChanges, emits(isNull));

    await auth.signOut();

    await signedOut;
    expect(backend.calls.last, 'POST /api/auth/logout');
    expect(jsonDecode(backend.requests.last.body), {
      'refreshToken': 'refresh-1',
    });
    expect(auth.currentUser, isNull);
    expect(await backend.tokens.read(), isNull);
    expect(google.signOuts, 1);
  });

  test('signing out offline still ends the local session', () async {
    final backend = FakeBackend({
      'POST /api/auth/google': signInResponse,
      'POST /api/auth/logout': (_) => throw http.ClientException('offline'),
    });
    final auth = serviceFor(backend);
    await auth.init();
    await auth.signInWithGoogle();
    await auth.signOut();
    expect(auth.currentUser, isNull);
    expect(await backend.tokens.read(), isNull);
  });

  test('an expired session signs the user out', () async {
    final backend = FakeBackend({
      'POST /api/auth/google': signInResponse,
      'GET /api/me': (_) => FakeBackend.json({}, 401),
      'POST /api/auth/refresh': (_) => FakeBackend.json({}, 401),
    });
    final auth = serviceFor(backend);
    await auth.init();
    await auth.signInWithGoogle();
    final signedOut = expectLater(auth.userChanges, emits(isNull));

    await expectLater(backend.api.get('me'), throwsA(isA<ApiException>()));

    await signedOut;
    expect(auth.currentUser, isNull);
  });

  test('a failed sign-in leaves the user signed out', () async {
    final backend = FakeBackend({
      'POST /api/auth/google': (_) => FakeBackend.json({'message': 'x'}, 401),
    });
    final auth = serviceFor(backend);
    await auth.init();
    await expectLater(auth.signInWithGoogle(), throwsA(isA<ApiException>()));
    expect(auth.currentUser, isNull);
    expect(await backend.tokens.read(), isNull);
  });

  group('review fixes', () {
    test('sign-out ends locally even on a TLS failure', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': signInResponse,
        'POST /api/auth/logout': (_) =>
            throw const HandshakeException('captive portal'),
      });
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();
      await auth.signOut();
      expect(auth.currentUser, isNull);
      expect(await backend.tokens.read(), isNull);
    });

    test('a malformed sign-in answer stores nothing', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': (_) =>
            FakeBackend.json({'accessToken': 'a', 'refreshToken': 'r'}),
      });
      final auth = serviceFor(backend);
      await auth.init();
      await expectLater(auth.signInWithGoogle(), throwsA(isA<ApiException>()));
      expect(await backend.tokens.read(), isNull);
      expect(auth.currentUser, isNull);
    });

    test('expiry is handled without init()', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': signInResponse,
        'GET /api/me': (_) => FakeBackend.json({}, 401),
        'POST /api/auth/refresh': (_) => FakeBackend.json({}, 401),
      });
      final auth = serviceFor(backend);
      await auth.signInWithGoogle();
      final signedOut = expectLater(auth.userChanges, emits(isNull));
      await expectLater(backend.api.get('me'), throwsA(isA<ApiException>()));
      await signedOut;
      expect(auth.currentUser, isNull);
    });

    test('a late expiry event does not sign out a newer session', () async {
      final backend = FakeBackend({'POST /api/auth/google': signInResponse});
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();
      // The event arrives after a new session was already stored.
      await backend.tokens.write(
        const ApiTokens(accessToken: 'new', refreshToken: 'new'),
      );
      backend.api.debugEmitSessionExpired();
      await pumpEventQueue();
      expect(auth.currentUser, isNotNull);
    });

    test('switching accounts revokes the old session first', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': signInResponse,
        'POST /api/auth/logout': (_) => FakeBackend.json(null, 204),
      });
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();
      final events = <Object?>[];
      final sub = auth.userChanges.listen(events.add);

      await auth.signInWithGoogle();
      await pumpEventQueue();
      await sub.cancel();

      expect(backend.calls, [
        'POST /api/auth/google',
        'POST /api/auth/logout',
        'POST /api/auth/google',
      ]);
      expect(events.first, isNull);
      expect(events.last, isNotNull);
    });

    test('init revokes a session that lost its profile', () async {
      final backend = FakeBackend({
        'POST /api/auth/logout': (_) => FakeBackend.json(null, 204),
      });
      await backend.tokens.write(
        const ApiTokens(accessToken: 'a', refreshToken: 'orphan'),
      );
      await serviceFor(backend).init();
      expect(backend.calls, ['POST /api/auth/logout']);
      expect(await backend.tokens.read(), isNull);
    });

    test('disposing during sign-in does not throw', () async {
      final backend = FakeBackend({'POST /api/auth/google': signInResponse});
      final auth = serviceFor(backend);
      await auth.init();
      final signIn = auth.signInWithGoogle();
      auth.dispose();
      await signIn;
    });
  });

  group('account deletion', () {
    test('re-authenticates with Google and deletes through the API', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': signInResponse,
        'DELETE /api/me': (_) => FakeBackend.json(null, 204),
      });
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();
      google.idToken = 'fresh-token';

      final idToken = await auth.reauthenticate();
      await auth.deleteAccount(idToken);

      final request = backend.requests.last;
      expect('${request.method} ${request.url.path}', 'DELETE /api/me');
      expect(request.headers['Authorization'], 'Bearer access-1');
      expect(jsonDecode(request.body), {'idToken': 'fresh-token'});
      expect(auth.currentUser, isNull);
      expect(await backend.tokens.read(), isNull);
    });

    test('finishes locally when the server deleted but then failed', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': signInResponse,
        'DELETE /api/me': (_) => FakeBackend.json({'message': 'x'}, 500),
        'GET /api/me': (_) => FakeBackend.json({'message': 'gone'}, 401),
        'POST /api/auth/refresh': (_) => FakeBackend.json({}, 401),
      });
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();
      await auth.deleteAccount('fresh');
      expect(auth.currentUser, isNull);
    });

    test('a 500 with the account still there is reported', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': signInResponse,
        'DELETE /api/me': (_) => FakeBackend.json({'message': 'x'}, 500),
        'GET /api/me': (_) => FakeBackend.json(apiUser),
      });
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();
      await expectLater(
        auth.deleteAccount('fresh'),
        throwsA(isA<ApiException>()),
      );
      expect(auth.currentUser, isNotNull);
    });

    test('keeps the account usable when the server refuses', () async {
      final backend = FakeBackend({
        'POST /api/auth/google': signInResponse,
        'DELETE /api/me': (_) => FakeBackend.json({'message': 'old'}, 403),
      });
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();

      await expectLater(
        auth.deleteAccount('stale-token'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
      expect(auth.currentUser, isNotNull);
      expect(await backend.tokens.read(), isNotNull);
    });

    test('a cancelled Google prompt deletes nothing', () async {
      final backend = FakeBackend({'POST /api/auth/google': signInResponse});
      final auth = serviceFor(backend);
      await auth.init();
      await auth.signInWithGoogle();
      google.error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      await expectLater(
        auth.reauthenticate(),
        throwsA(isA<GoogleSignInException>()),
      );
      expect(backend.calls, ['POST /api/auth/google']);
    });
  });

  group('describeAuthError', () {
    test('explains Google and API failures', () {
      expect(
        describeAuthError(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        'Sign-in was cancelled.',
      );
      expect(
        describeAuthError(const ApiException(null, 'offline')),
        'Cannot reach the FitFlow server.',
      );
      expect(
        describeAuthError(const ApiException(429, 'slow down')),
        contains('Too many attempts'),
      );
      expect(describeAuthError(StateError('?')), 'Sign-in failed — try again.');
    });
  });
}
