import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prm/data/api/api_config.dart';
import 'package:prm/data/api/token_store.dart';
import 'package:prm/features/auth/presentation/login_page.dart';

import 'support/e2e.dart';

void main() {
  e2eTest('signs in with Google and signs out', ($) async {
    await launchApp($);
    expect($(LoginPage), findsOneWidget);

    await signIn($);

    // The API knows the account the app shows.
    final me = await Cloud($).me();
    final email = me['email'] as String;
    if (googleAccount.isNotEmpty) expect(email, googleAccount);
    await openTab($, 'Profile');
    await $(email).scrollTo();
    expect($(email), findsOneWidget);

    final session = await SecureTokenStore().read();
    expect(session, isNotNull);

    await signOut($);
    expect(await SecureTokenStore().read(), isNull);

    // Signing out revoked the session on the server, not only locally.
    final refresh = await http.post(
      ApiConfig.baseUrl.resolve('auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': session!.refreshToken}),
    );
    expect(refresh.statusCode, 401, reason: refresh.body);
  });
}
