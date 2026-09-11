import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../navigation/presentation/app_shell.dart';
import 'login_page.dart';

/// Gates the whole app behind Google sign-in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    if (auth == null) {
      return const Scaffold(
        body: Center(child: Text('Sign-in is unavailable.')),
      );
    }
    return StreamBuilder<User?>(
      stream: auth.userChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            auth.currentUser == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == null ? const LoginPage() : const AppShell();
      },
    );
  }
}
