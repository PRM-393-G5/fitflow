import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/navigation/presentation/app_shell.dart';
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
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: controller.themeMode,
        home: const AppShell(),
      ),
    ),
  );
}
