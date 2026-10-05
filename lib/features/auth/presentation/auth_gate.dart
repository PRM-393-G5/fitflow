import 'package:forui/forui.dart';
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
    return StreamBuilder<AppUser?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            auth.currentUser == null &&
            !controller.signInSkipped) {
          return const FScaffold(child: Center(child: FCircularProgress()));
        }
        final signedIn = snapshot.data != null;
        return signedIn || controller.signInSkipped
            ? const AppShell()
            : const LoginPage();
      },
    );
  }
}
