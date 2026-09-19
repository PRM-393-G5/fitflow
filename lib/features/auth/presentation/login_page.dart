import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../app/app_scope.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).auth!.signInWithGoogle();
    } on GoogleSignInException catch (e) {
      // User dismissed the account picker — nothing to report.
      if (e.code != GoogleSignInExceptionCode.canceled && mounted) {
        _showError('$e');
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    showFToast(context: context, title: Text('Sign-in failed: $message'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FScaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FLucideIcons.zap,
                size: 72,
                color: context.theme.colors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'FitFlow',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to start training.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              FButton(
                onPress: _busy ? null : _signIn,
                prefix: _busy
                    ? const FCircularProgress()
                    : const Icon(FLucideIcons.logIn),
                child: const Text('Continue with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
