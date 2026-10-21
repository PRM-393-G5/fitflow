import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prm/domain/form_trend.dart';
import 'package:prm/domain/models/exercise.dart';
import 'package:prm/domain/models/form_result.dart';
import 'package:prm/domain/models/workout_session.dart';
import 'package:prm/features/progress/presentation/progress_page.dart';
import 'package:prm/features/progress/presentation/session_detail_page.dart';
import 'package:prm/features/squat_form/domain/form_record.dart';
import 'package:prm/features/squat_form/domain/shoulder_press_analyzer.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

import 'progress_pages_test.dart' show pumpPage;
import 'support/form_simulator.dart';

/// A squat set judged by the camera: [clean] of [reps] reps without faults.
FormResult squatForm(int clean, int reps, {String fault = 'heelsUp'}) =>
    FormResult(
      exercise: 'squat',
      reps: [
        for (var i = 1; i <= reps; i++)
          FormRep(number: i, faults: i <= clean ? const [] : [fault]),
      ],
    );

/// A session [daysAgo] with one exercise whose sets carry [forms].
WorkoutSession formSession(
  int daysAgo,
  List<FormResult?> forms, {
  String name = 'Bodyweight Squat',
}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo, 9);
  return WorkoutSession(
    id: 'form-$daysAgo-$name',
    workoutId: 'w1',
    workoutName: 'Legs',
    startedAt: day.subtract(const Duration(minutes: 30)),
    completedAt: day,
    completedSets: forms.length,
    volumeKg: 0,
    exercises: [
      Exercise(
        id: name,
        name: name,
        muscleGroup: 'Legs',
        sets: forms.length,
        reps: 5,
        performedSets: [
          for (final form in forms) SetEntry(amount: 5, form: form),
        ],
      ),
    ],
  );
}

void main() {
  group('saved form', () {
    test('round-trips through the synced JSON', () {
      const form = FormResult(
        exercise: 'squat',
        reps: [
          FormRep(number: 1, faults: [], firstHalfMs: 900, secondHalfMs: 700),
          FormRep(number: 2, faults: ['heelsUp'], minKneeAngle: 82),
        ],
      );
      const set = SetEntry(amount: 2, weightKg: 10, form: form);
      final back = SetEntry.fromJson(
        jsonDecode(jsonEncode(set.toJson())) as Map<String, dynamic>,
      );
      expect(back.form!.reps, hasLength(2));
      expect(back.form!.reps.first.firstHalfMs, 900);
      expect(back.form!.reps.last.faults, ['heelsUp']);
      expect(back.form!.reps.last.minKneeAngle, 82);
      expect(back.form!.quality, .5);
    });

    test('a malformed verdict is dropped, not the whole set', () {
      final set = SetEntry.fromJson({
        'amount': 8,
        'form': {'reps': 'not a list'},
      });
      expect(set.amount, 8);
      expect(set.form, isNull);
    });

    test('sets saved before forms existed still load', () {
      final set = SetEntry.fromJson({'amount': 8, 'weightKg': 20});
      expect(set.form, isNull);
      expect(set.toJson().containsKey('form'), isFalse);
    });

    test('a plank hold is judged by its good-form time', () {
      const form = FormResult(
        exercise: 'plank',
        hold: FormHold(trackedMs: 20000, goodMs: 15000, sagMs: 5000),
      );
      final back = FormResult.fromJson(
        jsonDecode(jsonEncode(form.toJson())) as Map<String, dynamic>,
      );
      expect(back.quality, .75);
      expect(back.faults, ['hipSag']);
    });

    test('an analyzed set maps onto the saved model', () {
      final analyzer = ShoulderPressAnalyzer();
      replay(
        analyzer,
        simulate(
          ShoulderPressMovement(elbowTopDeg: 140),
          camera: const SimCamera(
            azimuthDeg: 0,
            scale: .6,
            floorY: 1.35,
            distanceM: 2,
          ),
        ),
      );
      final form = formResultOf(
        FormExercise.shoulderPress,
        records: analyzer.repRecords,
      );
      expect(form.exercise, 'shoulderPress');
      expect(form.reps, hasLength(5));
      expect(form.quality, 0);
      expect(formExerciseOf(form), FormExercise.shoulderPress);
    });
  });

  group('form trend', () {
    test('ignores sets without a camera verdict', () {
      expect(
        FormTrend.of([
          formSession(0, [null, null]),
        ]),
        isEmpty,
      );
    });

    test('per exercise, oldest set first, newest exercise first', () {
      final trends = FormTrend.of([
        formSession(3, [squatForm(2, 5)]),
        formSession(2, [squatForm(5, 5)]),
        formSession(1, [
          const FormResult(
            exercise: 'plank',
            hold: FormHold(trackedMs: 10000, goodMs: 10000),
          ),
        ], name: 'Plank'),
      ]);
      expect(trends.map((t) => t.exercise), ['plank', 'squat']);
      expect(trends.last.qualities, [.4, 1]);
      expect(trends.last.latest, 1);
      // Too few sets to call a direction yet.
      expect(trends.last.direction, isNull);
    });

    test('compares the last three sets with the three before', () {
      FormTrendDirection? direction(List<int> cleanOfFive) => FormTrend.of([
        for (final (i, clean) in cleanOfFive.indexed)
          formSession(cleanOfFive.length - i, [squatForm(clean, 5)]),
      ]).single.direction;

      expect(direction([1, 1, 2, 4, 5, 5]), FormTrendDirection.improving);
      expect(direction([5, 5, 4, 2, 1, 1]), FormTrendDirection.slipping);
      expect(direction([3, 4, 3, 3, 4, 3]), FormTrendDirection.steady);
    });

    test('keeps the last ten sets and names the most common fault', () {
      final trend = FormTrend.of([
        for (var day = 14; day >= 1; day--)
          formSession(day, [
            squatForm(3, 5, fault: day > 10 ? 'forwardLean' : 'heelsUp'),
          ]),
      ]).single;
      expect(trend.qualities, hasLength(FormTrend.window));
      // The older lean faults fell out of the window.
      expect(trend.topFault, 'heelsUp');
    });
  });

  group('pages', () {
    testWidgets('progress shows form quality per exercise', (tester) async {
      await pumpPage(
        tester,
        const FScaffold(child: ProgressPage()),
        sessions: [
          for (var day = 6; day >= 1; day--)
            formSession(day, [squatForm(day > 3 ? 1 : 5, 5)]),
        ],
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('form-trend-squat')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Form quality'), findsOneWidget);
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Improving'), findsOneWidget);
      expect(find.text('Most common: Heels lifted'), findsOneWidget);
    });

    testWidgets('progress has no form section without camera sets', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const FScaffold(child: ProgressPage()),
        sessions: [
          formSession(1, [null]),
        ],
      );
      expect(find.text('Form quality'), findsNothing);
    });

    testWidgets('a session reopens the per-rep review of its sets', (
      tester,
    ) async {
      final session = formSession(1, [squatForm(4, 5), null]);
      await pumpPage(
        tester,
        SessionDetailPage(session: session),
        sessions: [session],
      );
      expect(find.textContaining('Form: 4/5 clean reps'), findsOneWidget);
      await tester.tap(find.byKey(const Key('session-exercise-0')));
      await tester.pumpAndSettle();
      expect(find.text('Set 1 · 4/5 clean reps'), findsOneWidget);
      expect(find.text('Heels lifted'), findsOneWidget);
      expect(find.text('Clean rep'), findsNWidgets(4));
      await tester.tap(find.byKey(const Key('session-form-done')));
      await tester.pumpAndSettle();
    });
  });
}
