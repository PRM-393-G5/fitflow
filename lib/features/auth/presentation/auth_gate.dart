import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../domain/models/app_user.dart';
import '../../navigation/presentation/app_shell.dart';
import 'login_page.dart';

/// Signing in is optional: the welcome/login page shows until the user
/// signs in or chooses to continue without an account. Without an auth
/// service (tests, local-only setups) the app runs local-only.
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
        final signedIn = snapshot.data != null;
        return signedIn || controller.signInSkipped
            ? const AppShell()
            : const LoginPage();
      },
    );
  }
}
