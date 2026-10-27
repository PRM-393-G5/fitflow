import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/app/app_controller.dart';
import 'package:prm/app/app_scope.dart';
import 'package:prm/core/theme/app_theme.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/workout.dart';
import 'package:prm/features/workouts/presentation/schedule_page.dart';

import 'gym_ux_test.dart' show makeController;

Workout _plan(String id, String name, String exercise, int minutes) => Workout(
  id: id,
  name: name,
  duration: Duration(minutes: minutes),
  level: 'Intermediate',
  category: 'Strength',
  description: '',
  exercises: [
    Exercise(id: '$id-1', name: exercise, muscleGroup: '', sets: 3, reps: 10),
  ],
);

void main() {
  testWidgets('shows each day in full and sums up the week', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await makeController(
      saved: [
        _plan('legs', 'Lower Body Strength', 'Goblet Squat', 45),
        _plan('arms', 'Arm Day Express', 'Biceps Curl', 25),
      ],
    );
    controller.setScheduleDay(1, 'legs');
    controller.setScheduleDay(2, AppController.restDay);
    controller.setScheduleDay(3, 'arms');

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.toApproximateMaterialTheme(),
          builder: (context, child) =>
              FTheme(data: AppTheme.light, child: child!),
          home: const SchedulePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Full plan names, no truncated grid cells.
    expect(find.text('Lower Body Strength'), findsOneWidget);
    expect(find.text('Arm Day Express'), findsOneWidget);
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Not planned'), findsNWidgets(4));

    // 2 plans, 70 minutes, 1 rest day; legs and arms only.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1 h 10 min'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Covers: Arms, Legs'), findsOneWidget);
    expect(
      find.text('No day for Chest, Back, Shoulders, Core yet'),
      findsOneWidget,
    );

    // Monday becomes a rest day from the sheet.
    await tester.tap(find.byKey(const Key('schedule-day-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-rest')));
    await tester.pumpAndSettle();
    expect(controller.isRestDay(1), isTrue);
    expect(find.text('Lower Body Strength'), findsNothing);
    expect(find.text('Rest day'), findsNWidgets(2));
    expect(find.text('25 min'), findsOneWidget);
  });
}
