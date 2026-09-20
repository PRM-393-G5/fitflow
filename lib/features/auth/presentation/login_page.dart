import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../app/app_scope.dart';
import '../../../data/auth_service.dart';

class LoginPage extends StatefulWidget {
  /// [popOnSuccess]: pushed from Profile (vs. shown as the welcome gate).
  const LoginPage({this.popOnSuccess = false, super.key});

  final bool popOnSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).auth!.signInWithGoogle();
      if (mounted && widget.popOnSuccess) Navigator.of(context).pop();
    } on GoogleSignInException catch (e) {
      // User dismissed the account picker — nothing to report.
      if (e.code != GoogleSignInExceptionCode.canceled && mounted) {
        _showError(describeAuthError(e));
      }
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      if (mounted) _showError(describeAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    showFToast(context: context, title: Text(message));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FScaffold(
      header: widget.popOnSuccess
          ? FHeader.nested(
              prefixes: [
                FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
              ],
            )
          : null,
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
                'Sign in to back up and sync your training across devices.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Everything works without an account — your data stays on '
                'this device.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FButton(
                onPress: _busy ? null : _signIn,
                prefix: _busy
                    ? const FCircularProgress()
                    : const Icon(FLucideIcons.logIn),
                child: const Text('Continue with Google'),
              ),
              if (!widget.popOnSuccess) ...[
                const SizedBox(height: 12),
                FButton(
                  key: const Key('skip-sign-in'),
                  variant: .ghost,
                  onPress: _busy
                      ? null
                      : () => AppScope.of(context).skipSignIn(),
                  child: const Text('Continue without an account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
