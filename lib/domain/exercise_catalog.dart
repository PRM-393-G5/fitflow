import '../features/squat_form/domain/squat_analyzer.dart';
import 'models/workout.dart';
import 'models/workout_session.dart';

/// A standard or user-defined exercise template used for autocomplete in
/// the workout builder so exercise names stay consistent across plans,
/// personal records, progressive overload, and muscle volume tracking.
class CatalogExercise {
  const CatalogExercise({
    required this.name,
    required this.muscleGroup,
    this.isTimed = false,
    this.defaultSets = 3,
    this.defaultReps = 10,
    this.defaultSeconds = 30,
    this.defaultRestSeconds = 60,
  });

  final String name;
  final String muscleGroup;
  final bool isTimed;
  final int defaultSets;
  final int defaultReps;
  final int defaultSeconds;
  final int defaultRestSeconds;

  /// Whether the on-device pose analyzer can count or time this exercise.
  bool get hasCameraCheck => FormExercise.match(name, timed: isTimed) != null;
}

abstract final class ExerciseCatalog {
  /// Standard gym and bodyweight exercises aligned with [MuscleVolume] and
  /// [FormExercise] naming rules.
  static const List<CatalogExercise> standard = [
    // Legs
    CatalogExercise(
      name: 'Bodyweight Squat',
      muscleGroup: 'Legs',
      defaultReps: 12,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Barbell Back Squat',
      muscleGroup: 'Legs',
      defaultSets: 4,
      defaultReps: 8,
      defaultRestSeconds: 90,
    ),
    CatalogExercise(
      name: 'Goblet Squat',
      muscleGroup: 'Legs',
      defaultSets: 4,
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Romanian Deadlift',
      muscleGroup: 'Legs',
      defaultSets: 4,
      defaultReps: 10,
      defaultRestSeconds: 90,
    ),
    CatalogExercise(
      name: 'Conventional Deadlift',
      muscleGroup: 'Legs',
      defaultSets: 3,
      defaultReps: 6,
      defaultRestSeconds: 120,
    ),
    CatalogExercise(
      name: 'Leg Press',
      muscleGroup: 'Legs',
      defaultSets: 4,
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Reverse Lunge',
      muscleGroup: 'Legs',
      defaultReps: 10,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Bulgarian Split Squat',
      muscleGroup: 'Legs',
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Hip Thrust',
      muscleGroup: 'Legs',
      defaultSets: 4,
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Leg Extension',
      muscleGroup: 'Legs',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Lying Leg Curl',
      muscleGroup: 'Legs',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Calf Raise',
      muscleGroup: 'Legs',
      defaultReps: 15,
      defaultRestSeconds: 45,
    ),

    // Chest
    CatalogExercise(
      name: 'Push-up',
      muscleGroup: 'Chest',
      defaultReps: 10,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Barbell Bench Press',
      muscleGroup: 'Chest',
      defaultSets: 4,
      defaultReps: 8,
      defaultRestSeconds: 90,
    ),
    CatalogExercise(
      name: 'Dumbbell Bench Press',
      muscleGroup: 'Chest',
      defaultSets: 4,
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Incline Dumbbell Press',
      muscleGroup: 'Chest',
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Cable Chest Fly',
      muscleGroup: 'Chest',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Pec Deck Fly',
      muscleGroup: 'Chest',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),

    // Back
    CatalogExercise(
      name: 'Dumbbell Row',
      muscleGroup: 'Back',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Barbell Row',
      muscleGroup: 'Back',
      defaultSets: 4,
      defaultReps: 8,
      defaultRestSeconds: 90,
    ),
    CatalogExercise(
      name: 'Lat Pulldown',
      muscleGroup: 'Back',
      defaultSets: 4,
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Pull-up',
      muscleGroup: 'Back',
      defaultReps: 8,
      defaultRestSeconds: 90,
    ),
    CatalogExercise(
      name: 'Seated Cable Row',
      muscleGroup: 'Back',
      defaultReps: 10,
      defaultRestSeconds: 75,
    ),
    CatalogExercise(
      name: 'Face Pull',
      muscleGroup: 'Back',
      defaultReps: 15,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Back Extension',
      muscleGroup: 'Back',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),

    // Shoulders
    CatalogExercise(
      name: 'Shoulder Press',
      muscleGroup: 'Shoulders',
      defaultReps: 10,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Overhead Press',
      muscleGroup: 'Shoulders',
      defaultSets: 4,
      defaultReps: 8,
      defaultRestSeconds: 90,
    ),
    CatalogExercise(
      name: 'Dumbbell Lateral Raise',
      muscleGroup: 'Shoulders',
      defaultReps: 15,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Rear Delt Fly',
      muscleGroup: 'Shoulders',
      defaultReps: 15,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Dumbbell Shrug',
      muscleGroup: 'Shoulders',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),

    // Arms
    CatalogExercise(
      name: 'Biceps Curl',
      muscleGroup: 'Arms',
      defaultReps: 12,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Dumbbell Curl',
      muscleGroup: 'Arms',
      defaultReps: 12,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Hammer Curl',
      muscleGroup: 'Arms',
      defaultReps: 12,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Barbell Curl',
      muscleGroup: 'Arms',
      defaultReps: 10,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Overhead Triceps Extension',
      muscleGroup: 'Arms',
      defaultReps: 12,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Triceps Pushdown',
      muscleGroup: 'Arms',
      defaultReps: 12,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Bench Dip',
      muscleGroup: 'Arms',
      defaultReps: 12,
      defaultRestSeconds: 60,
    ),
    CatalogExercise(
      name: 'Skull Crusher',
      muscleGroup: 'Arms',
      defaultReps: 10,
      defaultRestSeconds: 60,
    ),

    // Core
    CatalogExercise(
      name: 'Plank',
      muscleGroup: 'Core',
      isTimed: true,
      defaultSeconds: 30,
      defaultRestSeconds: 30,
    ),
    CatalogExercise(
      name: 'Side Plank',
      muscleGroup: 'Core',
      isTimed: true,
      defaultSeconds: 30,
      defaultRestSeconds: 30,
    ),
    CatalogExercise(
      name: 'Hanging Leg Raise',
      muscleGroup: 'Core',
      defaultReps: 12,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Cable Crunch',
      muscleGroup: 'Core',
      defaultReps: 15,
      defaultRestSeconds: 45,
    ),
    CatalogExercise(
      name: 'Russian Twist',
      muscleGroup: 'Core',
      defaultReps: 16,
      defaultRestSeconds: 30,
    ),

    // Cardio & Full body
    CatalogExercise(
      name: 'Burpees',
      muscleGroup: 'Full body',
      defaultReps: 10,
      defaultRestSeconds: 30,
    ),
    CatalogExercise(
      name: 'Jumping Jacks',
      muscleGroup: 'Cardio',
      isTimed: true,
      defaultSeconds: 40,
      defaultRestSeconds: 20,
    ),
    CatalogExercise(
      name: 'Mountain Climbers',
      muscleGroup: 'Core',
      isTimed: true,
      defaultSeconds: 30,
      defaultRestSeconds: 20,
    ),
    CatalogExercise(
      name: 'High Knees',
      muscleGroup: 'Cardio',
      isTimed: true,
      defaultSeconds: 40,
      defaultRestSeconds: 20,
    ),
  ];

  /// Returns matching exercises from the standard catalog plus any custom
  /// exercises the user has already saved in [workouts] or logged in [sessions].
  ///
  /// When [query] is empty, exercises in [muscleGroup] are returned first.
  /// When [query] matches the exact name already typed (case-insensitive)
  /// and nothing else, returns matching alternatives or an empty list if
  /// the exact item is the only match.
  static List<CatalogExercise> suggestions({
    String query = '',
    String? muscleGroup,
    Iterable<Workout> workouts = const [],
    Iterable<WorkoutSession> sessions = const [],
    int limit = 8,
  }) {
    final byKey = <String, CatalogExercise>{
      for (final item in standard) item.name.toLowerCase(): item,
    };

    void mergeCustom(
      String name,
      String group, {
      required bool isTimed,
      required int sets,
      required int reps,
      required int seconds,
      required int rest,
    }) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return;
      final key = trimmed.toLowerCase();
      if (byKey.containsKey(key)) return;
      byKey[key] = CatalogExercise(
        name: trimmed,
        muscleGroup: group,
        isTimed: isTimed,
        defaultSets: sets > 0 ? sets : 3,
        defaultReps: reps > 0 ? reps : 10,
        defaultSeconds: seconds > 0 ? seconds : 30,
        defaultRestSeconds: rest >= 0 ? rest : 45,
      );
    }

    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        mergeCustom(
          exercise.name,
          exercise.muscleGroup,
          isTimed: exercise.isTimed,
          sets: exercise.sets,
          reps: exercise.reps,
          seconds: exercise.durationSeconds,
          rest: exercise.restSeconds,
        );
      }
    }
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        mergeCustom(
          exercise.name,
          exercise.muscleGroup,
          isTimed: exercise.isTimed,
          sets: exercise.sets,
          reps: exercise.reps,
          seconds: exercise.durationSeconds,
          rest: exercise.restSeconds,
        );
      }
    }

    final rawTrimmed = query.trim();
    final q = rawTrimmed.toLowerCase();
    final groupLower = muscleGroup?.trim().toLowerCase();

    final matches = <CatalogExercise>[];
    for (final item in byKey.values) {
      final nameLower = item.name.toLowerCase();
      final itemGroupLower = item.muscleGroup.toLowerCase();
      if (q.isEmpty) {
        if (groupLower == null ||
            groupLower == 'full body' ||
            itemGroupLower == groupLower) {
          matches.add(item);
        }
      } else if (item.name != rawTrimmed &&
          (nameLower.contains(q) || itemGroupLower.contains(q))) {
        matches.add(item);
      }
    }

    matches.sort((a, b) {
      final aGroupMatch =
          groupLower != null && a.muscleGroup.toLowerCase() == groupLower;
      final bGroupMatch =
          groupLower != null && b.muscleGroup.toLowerCase() == groupLower;
      if (q.isNotEmpty) {
        final aStarts = a.name.toLowerCase().startsWith(q);
        final bStarts = b.name.toLowerCase().startsWith(q);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
      }
      if (aGroupMatch != bGroupMatch) return aGroupMatch ? -1 : 1;
      if (a.hasCameraCheck != b.hasCameraCheck) {
        return a.hasCameraCheck ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });

    return matches.take(limit).toList();
  }
}
