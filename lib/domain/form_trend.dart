import 'models/form_result.dart';
import 'models/workout_session.dart';

/// How form quality on one form-check exercise moved across recent sets.
class FormTrend {
  const FormTrend({
    required this.exercise,
    required this.qualities,
    required this.direction,
    this.topFault,
  });

  /// The form-check exercise (`FormExercise.name`).
  final String exercise;

  /// Good-form share (0..1) of each judged set, oldest first, at most
  /// [window] of them.
  final List<double> qualities;

  /// Recent sets against the ones before them; null with too few sets.
  final FormTrendDirection? direction;

  /// The most frequent fault across those sets, if any.
  final String? topFault;

  double get latest => qualities.last;

  /// Sets shown per exercise.
  static const window = 10;

  /// Sets compared on each side for [direction].
  static const _compared = 3;

  /// A change smaller than this (in good-form share) is "steady".
  static const _steadyBand = 0.1;

  /// One trend per exercise that has camera-judged sets, most recently
  /// trained first.
  static List<FormTrend> of(Iterable<WorkoutSession> sessions) {
    final ordered = [...sessions]
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final byExercise = <String, List<FormResult>>{};
    final lastSeen = <String, DateTime>{};
    for (final session in ordered) {
      for (final exercise in session.exercises) {
        for (final set in exercise.performedSets) {
          final form = set.form;
          if (form == null || form.quality == null) continue;
          (byExercise[form.exercise] ??= []).add(form);
          lastSeen[form.exercise] = session.completedAt;
        }
      }
    }
    final trends = [
      for (final MapEntry(key: exercise, value: forms) in byExercise.entries)
        _trend(
          exercise,
          forms.length > window ? forms.sublist(forms.length - window) : forms,
        ),
    ];
    return trends
      ..sort((a, b) => lastSeen[b.exercise]!.compareTo(lastSeen[a.exercise]!));
  }

  static FormTrend _trend(String exercise, List<FormResult> forms) {
    final qualities = [for (final form in forms) form.quality!];
    FormTrendDirection? direction;
    if (qualities.length > _compared) {
      final recent = qualities.sublist(qualities.length - _compared);
      final before = qualities.sublist(
        (qualities.length - 2 * _compared).clamp(0, qualities.length),
        qualities.length - _compared,
      );
      final change = _mean(recent) - _mean(before);
      direction = change > _steadyBand
          ? FormTrendDirection.improving
          : change < -_steadyBand
          ? FormTrendDirection.slipping
          : FormTrendDirection.steady;
    }
    final counts = <String, int>{};
    for (final form in forms) {
      for (final fault in form.faults) {
        counts[fault] = (counts[fault] ?? 0) + 1;
      }
    }
    final topFault = counts.entries.isEmpty
        ? null
        : counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return FormTrend(
      exercise: exercise,
      qualities: qualities,
      direction: direction,
      topFault: topFault,
    );
  }

  static double _mean(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;
}

enum FormTrendDirection { improving, steady, slipping }
