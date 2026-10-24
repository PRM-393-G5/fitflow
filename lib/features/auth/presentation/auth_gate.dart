import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../domain/models/app_user.dart';
import '../../navigation/presentation/app_shell.dart';
import 'login_page.dart';

/// FitFlow requires an account: the login page shows until the user signs
/// in, and again when the session ends. Without an auth service (widget
/// tests only) the gate is skipped.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AppUser?>? _signOuts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AppScope.of(context).auth;
    if (_signOuts != null || auth == null) return;
    // When a session ends (sign-out, expiry, account deletion), close the
    // pages pushed over the shell too — they would otherwise stay on top
    // of the login page with no account to save to. Only on that
    // transition, so later routes over the login page are left alone.
    var signedIn = auth.currentUser != null;
    _signOuts = auth.userChanges.listen((user) {
      final wasSignedIn = signedIn;
      signedIn = user != null;
      if (wasSignedIn && !signedIn && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _signOuts?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    if (auth == null) return const AppShell();
    // The service knows the restored session synchronously, and its
    // stream only reports later changes — so start from currentUser
    // instead of waiting for a first event.
    return StreamBuilder<AppUser?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) =>
          snapshot.data != null ? const AppShell() : const LoginPage(),
    );
  }
}
