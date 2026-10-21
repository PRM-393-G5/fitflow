/// One rep as the camera form check judged it.
class FormRep {
  const FormRep({
    required this.number,
    required this.faults,
    this.firstHalfMs = 0,
    this.secondHalfMs = 0,
    this.minKneeAngle,
  });

  final int number;

  /// Fault codes (see `faultTips`); empty for a clean rep.
  final List<String> faults;

  /// The rep's first and second half, in the order it moves: down then up
  /// for a squat or push-up, up then down for a press. 0 when not timed.
  final int firstHalfMs;
  final int secondHalfMs;

  /// Deepest knee angle, squats only.
  final double? minKneeAngle;

  bool get clean => faults.isEmpty;

  Map<String, Object> toJson() => {
    'number': number,
    'faults': faults,
    'firstHalfMs': firstHalfMs,
    'secondHalfMs': secondHalfMs,
    'minKneeAngle': ?minKneeAngle,
  };

  factory FormRep.fromJson(Map<String, dynamic> json) => FormRep(
    number: (json['number'] as num).toInt(),
    faults: [for (final fault in json['faults'] as List? ?? const []) '$fault'],
    firstHalfMs: (json['firstHalfMs'] as num?)?.toInt() ?? 0,
    secondHalfMs: (json['secondHalfMs'] as num?)?.toInt() ?? 0,
    minKneeAngle: (json['minKneeAngle'] as num?)?.toDouble(),
  );
}

/// Where a plank hold's time went.
class FormHold {
  const FormHold({
    required this.trackedMs,
    required this.goodMs,
    this.sagMs = 0,
    this.pikeMs = 0,
  });

  final int trackedMs;
  final int goodMs;
  final int sagMs;
  final int pikeMs;

  Map<String, Object> toJson() => {
    'trackedMs': trackedMs,
    'goodMs': goodMs,
    'sagMs': sagMs,
    'pikeMs': pikeMs,
  };

  factory FormHold.fromJson(Map<String, dynamic> json) => FormHold(
    trackedMs: (json['trackedMs'] as num).toInt(),
    goodMs: (json['goodMs'] as num).toInt(),
    sagMs: (json['sagMs'] as num?)?.toInt() ?? 0,
    pikeMs: (json['pikeMs'] as num?)?.toInt() ?? 0,
  );
}

/// What the camera form check recorded for one set: per-rep verdicts, or a
/// hold breakdown for a plank. Saved on the set so progress can show form
/// quality over time.
class FormResult {
  const FormResult({required this.exercise, this.reps = const [], this.hold});

  /// The form-check exercise (`FormExercise.name`, e.g. `squat`).
  final String exercise;
  final List<FormRep> reps;
  final FormHold? hold;

  /// Share of the set in good form: clean reps, or good-form hold time.
  /// Null when nothing was judged.
  double? get quality {
    final hold = this.hold;
    if (hold != null) {
      return hold.trackedMs > 0 ? hold.goodMs / hold.trackedMs : null;
    }
    if (reps.isEmpty) return null;
    return reps.where((rep) => rep.clean).length / reps.length;
  }

  /// Every fault occurrence across the set's reps; for a plank, the hip
  /// faults that held for a second or more.
  Iterable<String> get faults sync* {
    for (final rep in reps) {
      yield* rep.faults;
    }
    final hold = this.hold;
    if (hold == null) return;
    if (hold.sagMs >= 1000) yield 'hipSag';
    if (hold.pikeMs >= 1000) yield 'hipPike';
  }

  Map<String, Object> toJson() => {
    'exercise': exercise,
    'reps': [for (final rep in reps) rep.toJson()],
    'hold': ?hold?.toJson(),
  };

  /// [json] as a result, or null when it's missing or malformed: the
  /// verdict is extra, and a bad one (synced as free-form JSON) must not
  /// lose the whole session it sits in.
  static FormResult? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return FormResult.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  factory FormResult.fromJson(Map<String, dynamic> json) => FormResult(
    exercise: json['exercise'] as String,
    reps: [
      for (final rep in json['reps'] as List? ?? const [])
        FormRep.fromJson(rep as Map<String, dynamic>),
    ],
    hold: json['hold'] == null
        ? null
        : FormHold.fromJson(json['hold'] as Map<String, dynamic>),
  );
}
