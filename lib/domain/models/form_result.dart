/// One rep as the camera form check judged it.
class FormRep {
  const FormRep({
    required this.number,
    required this.faults,
    this.descentMs = 0,
    this.ascentMs = 0,
    this.minKneeAngle,
  });

  final int number;

  /// Fault codes (see `faultTips`); empty for a clean rep.
  final List<String> faults;

  /// First and second half of the rep: down then up for a squat or
  /// push-up, up then down for a press. 0 when not timed.
  final int descentMs;
  final int ascentMs;

  /// Deepest knee angle, squats only.
  final double? minKneeAngle;

  bool get clean => faults.isEmpty;

  Map<String, Object> toJson() => {
    'number': number,
    'faults': faults,
    'descentMs': descentMs,
    'ascentMs': ascentMs,
    'minKneeAngle': ?minKneeAngle,
  };

  factory FormRep.fromJson(Map<String, dynamic> json) => FormRep(
    number: json['number'] as int,
    faults: [for (final fault in json['faults'] as List? ?? const []) '$fault'],
    descentMs: json['descentMs'] as int? ?? 0,
    ascentMs: json['ascentMs'] as int? ?? 0,
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
    trackedMs: json['trackedMs'] as int,
    goodMs: json['goodMs'] as int,
    sagMs: json['sagMs'] as int? ?? 0,
    pikeMs: json['pikeMs'] as int? ?? 0,
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
