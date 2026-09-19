import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_gate.dart';
import 'app_controller.dart';
import 'app_scope.dart';

class WorkoutApp extends StatelessWidget {
  const WorkoutApp({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'FitFlow',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light.toApproximateMaterialTheme(),
        darkTheme: AppTheme.dark.toApproximateMaterialTheme(),
        themeMode: controller.themeMode,
        supportedLocales: FLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...FLocalizations.localizationsDelegates,
        ],
        builder: (context, child) => FTheme(
          data: Theme.brightnessOf(context) == .light
              ? AppTheme.light
              : AppTheme.dark,
          child: FToaster(child: FTooltipGroup(child: child!)),
        ),
        home: const AuthGate(),
      ),
    ),
  );
}
