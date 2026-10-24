import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../domain/models/app_user.dart';
import '../../navigation/presentation/app_shell.dart';
import 'login_page.dart';

/// FitFlow requires an account: the login page shows until the user signs
/// in, and again when the session ends. Without an auth service (widget
/// tests only) the gate is skipped.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final auth = controller.auth;
    if (auth == null) return const AppShell();
    // The service knows the restored session synchronously, and its
    // stream only reports later changes — so start from currentUser
    // instead of waiting for a first event.
    return StreamBuilder<AppUser?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        return snapshot.data != null ? const AppShell() : const LoginPage();
      },
    );
  }
}
