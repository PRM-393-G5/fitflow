import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/data/api/api_client.dart';
import 'package:prm/data/backend_auth_service.dart';
import 'package:prm/data/local_workout_repository.dart';
import 'package:prm/features/auth/presentation/auth_gate.dart';
import 'package:prm/features/auth/presentation/login_page.dart';
import 'package:prm/features/navigation/presentation/app_shell.dart';
import 'package:prm/features/profile/presentation/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';

void main() {
  Future<(AppController, BackendAuthService)> app(
    Map<String, Object> stored, {
    FakeBackend? backend,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final preferences = await SharedPreferences.getInstance();
    backend ??= FakeBackend({});
    final auth = BackendAuthService(
      api: backend.api,
      tokens: backend.tokens,
      preferences: preferences,
      google: FakeGoogle(),
    );
    await auth.init();
    final controller = AppController(
      LocalWorkoutRepository(preferences, templates: const []),
      preferences,
      auth: auth,
    );
    await controller.load();
    return (controller, auth);
  }

  Future<AppController> signedOutApp(Map<String, Object> stored) async =>
      (await app(stored)).$1;

  Future<void> pumpGate(WidgetTester tester, AppController controller) async {
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: AppTheme.light,
            child: FToaster(child: child!),
          ),
          home: const AuthGate(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a fresh install shows the sign-in page, not a spinner', (
    tester,
  ) async {
    await pumpGate(tester, await signedOutApp({}));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(FCircularProgress), findsNothing);
  });

  testWidgets('there is no way in without an account', (tester) async {
    // A device that used the old guest mode stays at the sign-in page.
    await pumpGate(tester, await signedOutApp({'sign_in_skipped_v1': true}));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.textContaining('without an account'), findsNothing);
  });

  testWidgets('signing out closes pages pushed over the app', (tester) async {
    final (controller, auth) = await app(
      {},
      backend: FakeBackend({
        'POST /api/auth/google': signInResponse,
      }, fallback: (_) => FakeBackend.json({})),
    );
    await auth.signInWithGoogle();
    await pumpGate(tester, controller);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Text('pushed page')),
    );
    await tester.pumpAndSettle();
    expect(find.text('pushed page'), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();

    expect(find.text('pushed page'), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('routes over the login page survive app updates', (tester) async {
    final controller = await signedOutApp({});
    await pumpGate(tester, controller);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(builder: (_) => const Text('over login')),
        );
    await tester.pumpAndSettle();

    await controller.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(find.text('over login'), findsOneWidget);
  });

  test('delete errors explain a wrong Google account', () {
    expect(
      describeDeleteError(
        const ApiException(403, 'Google account does not match'),
      ),
      contains('same Google account'),
    );
    expect(
      describeDeleteError(const ApiException(null, 'offline')),
      contains('connection'),
    );
  });
}
