import '../../../domain/models/form_result.dart';
import 'plank_analyzer.dart';
import 'squat_analyzer.dart';

/// The saved form of one analyzed set: what the analyzer recorded, in the
/// app-wide model stored on the set.
FormResult formResultOf(
  FormExercise exercise, {
  required List<RepRecord> records,
  HoldSummary? hold,
}) => FormResult(
  exercise: exercise.name,
  reps: [
    for (final record in records)
      FormRep(
        number: record.number,
        faults: List.of(record.faults),
        firstHalfMs: record.descentMs,
        secondHalfMs: record.ascentMs,
        minKneeAngle: record.minKneeAngle,
      ),
  ],
  hold: hold == null
      ? null
      : FormHold(
          trackedMs: hold.trackedMs,
          goodMs: hold.goodMs,
          sagMs: hold.sagMs,
          pikeMs: hold.pikeMs,
        ),
);

/// The form-check exercise a saved result belongs to, or null for a name
/// this version doesn't know.
FormExercise? formExerciseOf(FormResult result) =>
    FormExercise.values.asNameMap()[result.exercise];
