import 'dart:convert';
import 'dart:math';

import 'body_metrics.dart';
import 'training_options.dart';

/// One suggested food item inside a meal.
class MealItem {
  const MealItem({
    required this.name,
    required this.kcal,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
  });

  final String name;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  Map<String, Object> toJson() => {
    'name': name,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
  };

  MealItem copyWith({
    int? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) => MealItem(
    name: name,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
  );

  /// Throws [FormatException] when [json] has no usable name.
  factory MealItem.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String) throw const FormatException('Meal item has no name');
    return MealItem(
      name: name,
      kcal: _num(json['kcal'])?.toInt() ?? 0,
      proteinG: _num(json['proteinG'])?.toDouble() ?? 0,
      carbsG: _num(json['carbsG'])?.toDouble() ?? 0,
      fatG: _num(json['fatG'])?.toDouble() ?? 0,
    );
  }
}

num? _num(Object? value) => value is num && value.isFinite ? value : null;

List<Object?> _list(Object? value) => value is List ? value : const [];

/// A labeled meal (Breakfast, Lunch, ...) holding suggested items.
class Meal {
  const Meal({required this.label, required this.items});

  final String label;
  final List<MealItem> items;

  int get kcal => items.fold(0, (sum, item) => sum + item.kcal);
  double get proteinG => items.fold(0, (sum, item) => sum + item.proteinG);
  double get carbsG => items.fold(0, (sum, item) => sum + item.carbsG);
  double get fatG => items.fold(0, (sum, item) => sum + item.fatG);

  /// This meal resized to [target] kcal — a portion edit. Items and
  /// macros scale proportionally; a zero-kcal meal puts [target] on its
  /// first item.
  Meal withKcal(int target) {
    if (items.isEmpty) return this;
    final total = kcal;
    if (total <= 0) {
      return Meal(
        label: label,
        items: [
          items.first.copyWith(kcal: target),
          ...items.skip(1),
        ],
      );
    }
    final factor = target / total;
    final scaled = [
      for (final item in items)
        item.copyWith(
          kcal: (item.kcal * factor).round(),
          proteinG: item.proteinG * factor,
          carbsG: item.carbsG * factor,
          fatG: item.fatG * factor,
        ),
    ];
    // Absorb rounding drift so the meal totals exactly [target].
    final drift = target - scaled.fold<int>(0, (sum, item) => sum + item.kcal);
    final last = scaled.last.kcal + drift;
    scaled[scaled.length - 1] = scaled.last.copyWith(kcal: last < 0 ? 0 : last);
    return Meal(label: label, items: scaled);
  }

  Map<String, Object> toJson() => {
    'label': label,
    'items': items.map((item) => item.toJson()).toList(),
  };

  /// Malformed items are dropped; throws [FormatException] when the
  /// label is missing.
  factory Meal.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    if (label is! String) throw const FormatException('Meal has no label');
    final items = <MealItem>[];
    for (final item in _list(json['items'])) {
      if (item is! Map<String, dynamic>) continue;
      try {
        items.add(MealItem.fromJson(item));
      } on FormatException {
        // Skip the broken item, keep the rest of the meal.
      }
    }
    return Meal(label: label, items: items);
  }
}

/// An AI-suggested day menu plus the target it was generated against.
class MealPlan {
  const MealPlan({
    required this.date,
    required this.targetKcal,
    required this.meals,
    this.note = '',
    this.proteinG,
    this.goal,
  });

  final DateTime date;
  final int targetKcal;
  final List<Meal> meals;
  final String note;

  /// What the plan was generated for besides kcal — the protein target
  /// and the stored goal; null in plans saved before they were recorded
  /// (those only know their kcal).
  final int? proteinG;
  final String? goal;

  /// This plan, recording the [targets] and [goal] it was generated for.
  MealPlan forTargets(DailyTargets targets, String? goal) => MealPlan(
    date: date,
    targetKcal: targetKcal,
    meals: meals,
    note: note,
    proteinG: targets.proteinG,
    goal: goal,
  );

  /// Whether following this menu would now go well under the safe
  /// minimum for [targets] ([DailyTargets.safetyMinKcal]) — e.g. a deficit
  /// menu once a safety rule removed the deficit. Such a menu is not
  /// shown; smaller drifts (a weigh-in moves the minimum a few kcal) only
  /// flag it ([outdatedFor]).
  bool unsafeFor(DailyTargets targets) =>
      totalKcal < targets.safetyMinKcal * (1 - unsafeTolerance);

  /// Share under the safety minimum still treated as the same menu.
  static const unsafeTolerance = 0.05;

  /// Whether today's [targets] or [goal] differ from what this plan was
  /// generated for.
  bool outdatedFor(DailyTargets targets, String? goal) {
    if (targetKcal != targets.kcal) return true;
    if (proteinG == null) return false;
    return proteinG != targets.proteinG || this.goal != goal;
  }

  int get totalKcal => meals.fold(0, (sum, meal) => sum + meal.kcal);

  bool get isToday => isOn(DateTime.now());

  bool isOn(DateTime day) =>
      date.year == day.year && date.month == day.month && date.day == day.day;

  Map<String, Object> toJson() => {
    'date': date.toIso8601String(),
    'targetKcal': targetKcal,
    'meals': meals.map((meal) => meal.toJson()).toList(),
    'note': note,
    'proteinG': ?proteinG,
    'goal': ?goal,
  };

  /// Throws [FormatException] when the date is missing or malformed.
  factory MealPlan.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    if (date is! String) throw const FormatException('Plan has no date');
    final note = json['note'];
    return MealPlan(
      date: DateTime.parse(date),
      targetKcal: _num(json['targetKcal'])?.toInt() ?? 0,
      meals: [
        for (final item in _list(json['meals']))
          if (item is Map<String, dynamic>) Meal.fromJson(item),
      ],
      note: note is String ? note : '',
      proteinG: _num(json['proteinG'])?.toInt(),
      goal: json['goal'] is String ? json['goal'] as String : null,
    );
  }
}

/// What the nutrition page persists under `meal_plan_v1`: today's plan
/// plus the generator settings (so they survive restarts, and are wiped
/// with the rest of the user's data on account changes).
class MealPlanCache {
  const MealPlanCache({this.plan, this.preferences = '', this.mealCount = 3});

  final MealPlan? plan;
  final String preferences;

  /// 3 meals, or 4 (3 + snack).
  final int mealCount;

  MealPlanCache withPlan(MealPlan? plan) =>
      MealPlanCache(plan: plan, preferences: preferences, mealCount: mealCount);

  MealPlanCache copyWith({String? preferences, int? mealCount}) =>
      MealPlanCache(
        plan: plan,
        preferences: preferences ?? this.preferences,
        mealCount: mealCount ?? this.mealCount,
      );

  Map<String, Object?> toJson() => {
    'version': 2,
    'plan': plan?.toJson(),
    'preferences': preferences,
    'mealCount': mealCount,
  };

  /// Never throws: corrupt data degrades to defaults. Also reads the
  /// legacy format, where the key held a bare [MealPlan].
  static MealPlanCache decode(String? raw) {
    if (raw == null) return const MealPlanCache();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const MealPlanCache();
      if (json.containsKey('meals')) {
        return MealPlanCache(plan: MealPlan.fromJson(json));
      }
      final plan = json['plan'];
      final preferences = json['preferences'];
      return MealPlanCache(
        plan: plan is Map<String, dynamic> ? _tryPlan(plan) : null,
        preferences: preferences is String ? preferences : '',
        mealCount: json['mealCount'] == 4 ? 4 : 3,
      );
    } on FormatException {
      return const MealPlanCache();
    }
  }

  static MealPlan? _tryPlan(Map<String, dynamic> json) {
    try {
      return MealPlan.fromJson(json);
    } on FormatException {
      return null;
    }
  }
}

/// The fixed meal slots a day's log is grouped into, in display order.
const mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

/// Bucket for logged meals whose label is not one of [mealTypes]
/// (entries logged before meals had a slot).
const otherMealType = 'Other';

/// The slot a meal logged at [time] most likely belongs to.
String defaultMealType(DateTime time) {
  final minutes = time.hour * 60 + time.minute;
  if (minutes < 11 * 60) return 'Breakfast';
  if (minutes < 15 * 60) return 'Lunch';
  if (minutes < 18 * 60) return 'Snack';
  return 'Dinner';
}

/// [meal]'s slot: its label when that is a known type (case-insensitive),
/// else [otherMealType].
String mealTypeOf(Meal meal) {
  final label = meal.label.trim().toLowerCase();
  for (final type in mealTypes) {
    if (type.toLowerCase() == label) return type;
  }
  return otherMealType;
}

/// One logged meal — the unit synced to the backend (`meals` docs).
/// The id is `yyyy-mm-dd:<entry>`: the day it was eaten, then a unique
/// entry part (microseconds when logged), so entries sort by time.
/// Immutable: an edit makes a new entry with the same id, so sync can
/// tell local changes apart by identity.
class FoodEntry {
  const FoodEntry(this.id, this.meal);

  final String id;
  final Meal meal;

  /// `yyyy-mm-dd` the meal was eaten on.
  String get day => id.substring(0, 10);

  static final _idPattern = RegExp(r'^\d{4}-\d{2}-\d{2}:[A-Za-z0-9_-]{1,64}$');

  static bool isId(String id) => _idPattern.hasMatch(id);

  Map<String, Object> toJson() => {'id': id, ...meal.toJson()};

  /// Throws [FormatException] for a bad id or a meal without dishes.
  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || !isId(id)) {
      throw const FormatException('Food entry has no yyyy-mm-dd:<entry> id');
    }
    final meal = Meal.fromJson(json);
    if (meal.items.isEmpty) {
      throw const FormatException('Food entry has no dishes');
    }
    return FoodEntry(id, meal);
  }
}

/// Meals logged per calendar day, kept for the last [keepDays] days on
/// the device (the backend keeps the full history).
class FoodLog {
  FoodLog([Map<String, List<FoodEntry>>? days]) : days = days ?? {};

  /// Groups [entries] by day, each day in logging order.
  factory FoodLog.fromEntries(Iterable<FoodEntry> entries) {
    final days = <String, List<FoodEntry>>{};
    for (final entry in entries) {
      days.putIfAbsent(entry.day, () => []).add(entry);
    }
    return FoodLog({
      for (final MapEntry(:key, :value) in days.entries)
        key: List.unmodifiable(value..sort((a, b) => a.id.compareTo(b.id))),
    });
  }

  static const keepDays = 30;

  /// `yyyy-mm-dd` → that day's entries, oldest first.
  final Map<String, List<FoodEntry>> days;

  static final _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static bool isDayKey(String key) => _dayPattern.hasMatch(key);

  Iterable<FoodEntry> get entries => days.values.expand((day) => day);

  List<FoodEntry> entriesOn(DateTime day) => days[dayKey(day)] ?? const [];

  List<Meal> mealsOn(DateTime day) => [
    for (final entry in entriesOn(day)) entry.meal,
  ];

  /// Logs [meal] on [day]; the entry id comes from [now] (default: the
  /// current time), made unique within the day.
  FoodEntry add(DateTime day, Meal meal, {DateTime? now}) {
    final key = dayKey(day);
    final existing = days[key] ?? const [];
    final micros = (now ?? DateTime.now()).microsecondsSinceEpoch;
    var id = '$key:$micros';
    for (var n = 1; existing.any((entry) => entry.id == id); n++) {
      id = '$key:$micros-$n';
    }
    final entry = FoodEntry(id, meal);
    days[key] = List.unmodifiable([...existing, entry]);
    return entry;
  }

  /// Replaces entry [id]'s meal; null (and no change) when it is gone.
  FoodEntry? replace(String id, Meal meal) {
    final key = id.substring(0, 10);
    final entries = days[key];
    final index = entries?.indexWhere((entry) => entry.id == id) ?? -1;
    if (index < 0) return null;
    final entry = FoodEntry(id, meal);
    days[key] = List.unmodifiable([...entries!]..[index] = entry);
    return entry;
  }

  /// Removes entry [id]; null (and no change) when it is gone.
  FoodEntry? remove(String id) {
    final key = id.substring(0, 10);
    final entries = days[key];
    final index = entries?.indexWhere((entry) => entry.id == id) ?? -1;
    if (index < 0) return null;
    final removed = entries![index];
    final left = [...entries]..removeAt(index);
    if (left.isEmpty) {
      days.remove(key);
    } else {
      days[key] = List.unmodifiable(left);
    }
    return removed;
  }

  /// First calendar day kept on the device for [now].
  static DateTime oldestKeptDay(DateTime now) =>
      DateTime(now.year, now.month, now.day - (keepDays - 1));

  /// [oldestKeptDay] as a `yyyy-mm-dd` key.
  static String oldestKept(DateTime now) => dayKey(oldestKeptDay(now));

  /// Drops days older than the last [keepDays] days ending at [now] —
  /// locally only; the backend keeps them.
  void prune(DateTime now) {
    final cutoff = oldestKept(now);
    // yyyy-mm-dd keys sort chronologically as strings.
    days.removeWhere(
      (key, entries) => key.compareTo(cutoff) < 0 || entries.isEmpty,
    );
  }

  /// Total kcal and macros of [meals].
  static ({int kcal, double proteinG, double carbsG, double fatG}) totals(
    Iterable<Meal> meals,
  ) => (
    kcal: meals.fold(0, (sum, meal) => sum + meal.kcal),
    proteinG: meals.fold(0, (sum, meal) => sum + meal.proteinG),
    carbsG: meals.fold(0, (sum, meal) => sum + meal.carbsG),
    fatG: meals.fold(0, (sum, meal) => sum + meal.fatG),
  );

  Map<String, Object> toJson() => {
    'version': 3,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  /// Whether [raw] is already the current (v3, per-entry) format.
  static bool isCurrentFormat(String raw) {
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> && json['entries'] is List;
    } on FormatException {
      return false;
    }
  }

  /// Never throws: malformed entries (or meals without dishes) are
  /// dropped. Also reads the older device-only formats —
  /// `{days: {day: [meal…]}}` (v2) and the single-day `{date, meals}`.
  /// Their meals get ids `day:0-<nonce>-<index>`: sorted before newer
  /// entries and in logging order, and unique per device ([nonce], random
  /// by default) so two devices' old logs never collide on sync. Callers
  /// persist the result right away so the ids stay stable.
  static FoodLog decode(String? raw, {String? nonce}) {
    if (raw == null) return FoodLog();
    final entries = <FoodEntry>[];
    final legacyNonce = nonce ?? _nonce();
    void legacyDay(String key, Object? meals) {
      for (final (index, meal) in _meals(meals).indexed) {
        if (meal.items.isEmpty) continue;
        final order = index.toString().padLeft(4, '0');
        entries.add(FoodEntry('$key:0-$legacyNonce-$order', meal));
      }
    }

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return FoodLog();
      if (json['entries'] case final List list) {
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          try {
            entries.add(FoodEntry.fromJson(item));
          } on FormatException {
            // Skip the broken entry.
          }
        }
      } else if (json['date'] case final String date) {
        legacyDay(dayKey(DateTime.parse(date)), json['meals']);
      } else if (json['days'] case final Map<String, dynamic> days) {
        for (final MapEntry(:key, :value) in days.entries) {
          if (isDayKey(key)) legacyDay(key, value);
        }
      }
    } on FormatException {
      // Unreadable log — start fresh.
    }
    return FoodLog.fromEntries(entries);
  }

  static final _random = Random();

  static String _nonce() => [
    for (var i = 0; i < 8; i++)
      'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
  ].join();

  static List<Meal> _meals(Object? value) {
    final meals = <Meal>[];
    for (final item in _list(value)) {
      if (item is! Map<String, dynamic>) continue;
      try {
        meals.add(Meal.fromJson(item));
      } on FormatException {
        // Skip the broken entry.
      }
    }
    return meals;
  }
}

/// Why a daily target was held back from the goal's usual adjustment.
enum TargetLimit {
  /// BMI under 19.5: the safety minimum (maintenance at 18.5, WHO
  /// underweight, easing to the floor at 19.5) shrank or removed the
  /// deficit — continuously, so it never jumps at the cutoff.
  underweight,

  /// The deficit stops at the minimum intake (a smaller deficit —
  /// shrinking to nothing as maintenance nears the minimum).
  floor,

  /// The target was raised above estimated maintenance: it is under the
  /// minimum intake, so the target is held at the minimum (whatever the
  /// goal, and whatever the BMI) — and there is no deficit.
  lowMaintenance,
}

/// Which side of maintenance a target is on, as actually applied.
enum TargetPhase { deficit, maintenance, surplus }

/// A day's calorie and macro targets. [phase] is the adjustment actually
/// applied; [limit] says why a safety rule changed it, if one did.
typedef DailyTargets = ({
  int kcal,
  int proteinG,
  int fatG,
  int carbsG,
  TargetPhase phase,
  TargetLimit? limit,

  /// The least a day may total and still be safe, whatever the goal:
  /// maintenance below BMI 18.5, easing linearly to the floor at 19.5,
  /// and the floor above. [kcal] is never below it. A saved menu well
  /// under it is not shown ([MealPlan.unsafeFor]).
  int safetyMinKcal,

  /// The range a newly suggested menu must total: ±10% of [kcal], never
  /// under [safetyMinKcal]; it always contains [kcal]. See
  /// [AiMealParser.parse].
  int minMenuKcal,
  int maxMenuKcal,
});

/// Calorie and macro targets from TDEE, the goal and the body profile,
/// with safety rules for groups a generic deficit is wrong for.
///
/// - Lose fat: 15% under TDEE, at most 500 kcal (about 0.5 kg a week);
///   build muscle: 10% over, at most 300 kcal; otherwise maintenance.
///   A percentage scales with the person — a flat −400 kcal is over 20%
///   for a small woman and 11% for a large man.
/// - No targets at all under 18: Mifflin-St Jeor and these rules are for
///   adults, and growth needs vary.
/// - No deficit with BMI under 18.5 (WHO underweight), tapering in from
///   BMI 19.5 so a 0.1 kg weigh-in never swings the target.
/// - No target goes below 1,200 kcal for women or 1,500 kcal for men (the
///   usual minimum without medical supervision; below it nutrient needs
///   are hard to meet). A deficit stops there, shrinking continuously as
///   maintenance nears it, so nothing jumps; an estimated maintenance
///   below it holds the target at the minimum.
/// - Protein per kg (ISSN; Morton et al. 2018; Helms et al. 2014): 1.2 g
///   at maintenance, 1.6 g in a surplus, and in a deficit rising from
///   1.2 g to 1.8 g at [fullDeficitKcal] or more — more than when
///   building, to keep muscle. Above BMI 25 it counts the weight at BMI
///   25, not total weight.
/// - Nothing is clamped beyond these rules (no upper cap: a big
///   athlete's surplus stays a surplus). Fat is 25% of calories; carbs
///   fill the rest.
abstract final class NutritionTargets {
  /// The lowest daily target FitFlow sets without medical supervision.
  static int floorKcal({required bool isMale}) => isMale ? 1500 : 1200;

  /// Deficit from which protein is at the full 1.8 g/kg.
  static const fullDeficitKcal = 300;

  /// BMI above [BodyMetrics.underweightBmi] over which a deficit tapers
  /// in.
  static const underweightTaperBmi = 1.0;

  /// Today's targets. Adults only ([BodyMetrics.adultFormulasApply]):
  /// Mifflin-St Jeor and these rules are for adults, and growth needs
  /// vary — calling this for a minor is a bug ([ArgumentError]).
  static DailyTargets daily({
    required double tdee,
    required String? goal,
    required double weightKg,
    required double heightCm,
    required int age,
    required bool isMale,
  }) {
    if (!BodyMetrics.adultFormulasApply(age)) {
      throw ArgumentError.value(age, 'age', 'No calorie targets under 18');
    }
    final bmi = BodyMetrics.bmi(weightKg: weightKg, heightCm: heightCm);
    final intent = nutritionIntent(goal);
    final goalTarget =
        tdee +
        switch (intent) {
          NutritionIntent.loseFat => -min(tdee * 0.15, 500.0),
          NutritionIntent.buildMuscle => min(tdee * 0.10, 300.0),
          NutritionIntent.maintain => 0.0,
        };
    final floor = floorKcal(isMale: isMale);
    // The least a day may total and still be safe: maintenance below BMI
    // 18.5, easing linearly to the floor at 19.5, the floor above. The
    // target is built never to go under it, so a low BMI tapers the
    // deficit by itself and the target always sits in the menu range.
    final taper = ((bmi - BodyMetrics.underweightBmi) / underweightTaperBmi)
        .clamp(0.0, 1.0);
    final safetyMin = floor + (1 - taper) * max(0.0, tdee - floor);
    final kcal = max(goalTarget, safetyMin);
    final target = kcal.round();

    // Why the safety minimum raised the goal's target, if it did.
    final limit = safetyMin <= goalTarget
        ? null
        : kcal > tdee
        ? TargetLimit.lowMaintenance
        : taper < 1
        ? TargetLimit.underweight
        : TargetLimit.floor;
    // Lifting a low estimate to the floor is not a surplus the goal asked
    // for: only Build muscle makes one.
    final phase = intent == NutritionIntent.buildMuscle && kcal > tdee
        ? TargetPhase.surplus
        : kcal < tdee
        ? TargetPhase.deficit
        : TargetPhase.maintenance;

    final perKg = switch (phase) {
      TargetPhase.deficit =>
        1.2 + 0.6 * min((tdee - kcal) / fullDeficitKcal, 1),
      TargetPhase.surplus => 1.6,
      TargetPhase.maintenance => 1.2,
    };
    final referenceKg = bmi > BodyMetrics.overweightBmi
        ? BodyMetrics.overweightBmi * pow(heightCm / 100, 2)
        : weightKg;
    final protein = (referenceKg * perKg).round();
    final safety = safetyMin.round();
    return (
      kcal: target,
      proteinG: protein,
      fatG: fatG(target),
      carbsG: carbsG(targetKcal: target, proteinG: protein),
      phase: phase,
      limit: limit,
      safetyMinKcal: safety,
      // target ≥ safety, so the target is always inside this range.
      minMenuKcal: max((target * 0.9).round(), safety),
      maxMenuKcal: (target * 1.1).round(),
    );
  }

  /// Fat at 25% of target calories (9 kcal/g).
  static int fatG(int targetKcal) => (targetKcal * 0.25 / 9).round();

  /// Carbs fill the remainder after protein and fat (4 kcal/g).
  static int carbsG({required int targetKcal, required int proteinG}) =>
      max(0, ((targetKcal - proteinG * 4 - fatG(targetKcal) * 9) / 4).round());
}

/// Prompt contract for AI meal suggestions.
abstract final class AiMealPrompt {
  static const system = '''
You are a nutritionist generating a day meal plan as JSON. Rules:
- Split the day into exactly the requested meals, following the kcal
  split given in the request.
- Total calories within +/-10% of the target.
- Every item carries realistic kcal and macro estimates (grams).
- Use common, recognizable dish names in English.
- note is one short sentence of advice for the user's goal.''';

  static const schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'meals': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'items': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                  'kcal': {'type': 'integer'},
                  'proteinG': {'type': 'number'},
                  'carbsG': {'type': 'number'},
                  'fatG': {'type': 'number'},
                },
                'required': ['name', 'kcal', 'proteinG', 'carbsG', 'fatG'],
                'additionalProperties': false,
              },
            },
          },
          'required': ['label', 'items'],
          'additionalProperties': false,
        },
      },
      'totalKcal': {'type': 'integer'},
      'note': {'type': 'string'},
    },
    'required': ['meals', 'totalKcal', 'note'],
    'additionalProperties': false,
  };

  /// Percent of the day's kcal per meal; always sums to 100.
  static Map<String, int> split(int meals) => meals >= 4
      ? const {'Breakfast': 25, 'Lunch': 35, 'Dinner': 30, 'Snack': 10}
      : const {'Breakfast': 30, 'Lunch': 40, 'Dinner': 30};

  /// The goal as the model should read it: the label ("Lose fat"), not
  /// the stored workout category ("Cardio"), which reads as endurance
  /// training; and when a safety rule held the target at maintenance,
  /// maintenance — never the fat-loss goal that was picked.
  static String? goalText(String? goal, DailyTargets targets) {
    if (goal == null) return null;
    // Fat loss that a low BMI or a low maintenance held back reads as
    // maintenance — the same reasons the card explains — and so does fat
    // loss with no deficit left. Every other goal keeps its label.
    final heldBack =
        targets.limit == TargetLimit.underweight ||
        targets.limit == TargetLimit.lowMaintenance ||
        targets.phase != TargetPhase.deficit;
    if (nutritionIntent(goal) == NutritionIntent.loseFat && heldBack) {
      return 'eat enough to maintain weight — no meaningful calorie deficit';
    }
    return goalLabel(goal);
  }

  /// The request for a day menu meeting [targets]. [retryNote] says why a
  /// previous menu was rejected.
  static String user({
    required DailyTargets targets,
    required int meals,
    String? goal,
    String? preferences,
    String? retryNote,
  }) {
    final targetKcal = targets.kcal;
    final proteinG = targets.proteinG;
    final buffer = StringBuffer(
      'Create a day meal plan.\nTarget: $targetKcal kcal, ~$proteinG g '
      'protein, $meals meals',
    );
    final shares = split(meals).entries
        .map(
          (entry) =>
              '${entry.key} ${entry.value}% '
              '(~${(targetKcal * entry.value / 100).round()} kcal)',
        )
        .join(', ');
    buffer.write('\nSplit: $shares');
    final goalText = AiMealPrompt.goalText(goal, targets);
    if (goalText != null) buffer.write('\nUser goal: $goalText');
    // When the safety minimum cuts into the system prompt's −10% leeway,
    // state the minimum the parser enforces.
    if (targets.minMenuKcal > (targetKcal * 0.9).round()) {
      buffer.write(
        '\nMinimum: the day must total at least ${targets.minMenuKcal} kcal '
        '— do not go below it.',
      );
    }
    if (retryNote != null) buffer.write('\n$retryNote');

    if (preferences != null && preferences.isNotEmpty) {
      buffer.write('\nPreferences/restrictions: $preferences');
    }
    return buffer.toString();
  }
}

/// Prompt contract for AI food-photo analysis.
abstract final class AiFoodPhotoPrompt {
  static const system = '''
You are a nutritionist identifying dishes in a food photo. Rules:
- List every distinct dish/food item you can see.
- Estimate kcal and macros per item from visible portion size.
- Be honest about uncertainty — note mentions portion assumptions.
- Use common dish names in English.''';

  static const schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'dishes': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'kcal': {'type': 'integer'},
            'proteinG': {'type': 'number'},
            'carbsG': {'type': 'number'},
            'fatG': {'type': 'number'},
          },
          'required': ['name', 'kcal', 'proteinG', 'carbsG', 'fatG'],
          'additionalProperties': false,
        },
      },
      'note': {'type': 'string'},
    },
    'required': ['dishes', 'note'],
    'additionalProperties': false,
  };

  static const user =
      'Identify every dish in this photo and estimate kcal and macros '
      'per item.';
}

/// Sanitizes AI meal-plan JSON into a [MealPlan] — numbers clamped,
/// empty meals dropped. Throws [FormatException] when nothing usable
/// remains.
abstract final class AiMealParser {
  /// Largest share by which a menu's portions are rescaled; see [parse].
  static const maxScale = 0.25;

  /// Parses the photo-analysis response into detected dishes plus the
  /// model's caveat note. Throws [FormatException] when nothing was
  /// identified.
  static ({Meal meal, String note}) parsePhoto(Map<String, dynamic> json) {
    final items = [
      for (final item in _list(json['dishes']))
        if (item is Map<String, dynamic>) _item(item),
    ];
    if (items.isEmpty) {
      throw const FormatException('No dishes identified');
    }
    return (
      meal: Meal(label: 'Detected dishes', items: items),
      note: _text(json['note'], ''),
    );
  }

  /// A menu totalling under [minKcal] or over [maxKcal] has its portions
  /// scaled (kcal and macros, via [Meal.withKcal]) to total [targetKcal]
  /// — models miss sums — with rounding drift put on the last meal, so the
  /// total is exact. Scaling is capped at ±[maxScale] so portions still
  /// match their dish names; a menu further off is rejected
  /// ([FormatException]) for a retry. See [DailyTargets.minMenuKcal].
  static MealPlan parse(
    Map<String, dynamic> json, {
    required int targetKcal,
    int? minKcal,
    int? maxKcal,
  }) {
    // A dish may be as big as the day (big targets have big meals), but
    // no bigger; at least the 1,500 kcal photo cap.
    final itemCap = max(_itemKcalCap, targetKcal);
    final meals = [
      for (final (index, item) in _list(json['meals']).indexed)
        if (item is Map<String, dynamic>)
          _meal(item, 'Meal ${index + 1}', itemCap),
    ].where((meal) => meal.items.isNotEmpty).toList();
    if (meals.isEmpty) {
      throw const FormatException('AI plan has no meals');
    }
    final total = _total(meals);
    final outOfRange =
        (minKcal != null && total < minKcal) ||
        (maxKcal != null && total > maxKcal);
    final factor = total <= 0 ? 0.0 : targetKcal / total;
    if (outOfRange && (factor < 1 - maxScale || factor > 1 + maxScale)) {
      throw FormatException(
        'AI plan totals $total kcal, too far from $targetKcal to rescale',
      );
    }
    if (outOfRange) {
      for (final (index, meal) in meals.indexed) {
        meals[index] = meal.withKcal((meal.kcal * factor).round());
      }
      // Per-meal rounding can leave the total a few kcal off — under a
      // minimum equal to the target. The last meal takes the difference.
      final drift = targetKcal - _total(meals);
      meals.last = meals.last.withKcal(max(0, meals.last.kcal + drift));
    }
    return MealPlan(
      date: DateTime.now(),
      targetKcal: targetKcal,
      meals: meals,
      note: _text(json['note'], ''),
    );
  }

  /// Sanity caps on one AI-estimated dish, before any rescaling: kcal,
  /// and grams of each macro, both scaled with the day for big targets.
  static const _itemKcalCap = 1500;
  static const _itemGramsCap = 300.0;

  static int _total(List<Meal> meals) =>
      meals.fold(0, (sum, meal) => sum + meal.kcal);

  static Meal _meal(
    Map<String, dynamic> json,
    String fallbackLabel,
    int itemCap,
  ) => Meal(
    label: _text(json['label'], fallbackLabel),
    items: [
      for (final item in _list(json['items']))
        if (item is Map<String, dynamic>) _item(item, itemCap),
    ],
  );

  /// One AI item with nonsense clamped away: kcal up to [kcalCap], each
  /// macro up to 300 g scaled by the same factor (photos keep 300 g).
  static MealItem _item(
    Map<String, dynamic> json, [
    int kcalCap = _itemKcalCap,
  ]) {
    final gramsCap = _itemGramsCap * kcalCap / _itemKcalCap;
    return MealItem(
      name: _text(json['name'], 'Item'),
      kcal: _clampInt(json['kcal'], 0, kcalCap, 0),
      proteinG: _clampDouble(json['proteinG'], 0, gramsCap, 0),
      carbsG: _clampDouble(json['carbsG'], 0, gramsCap, 0),
      fatG: _clampDouble(json['fatG'], 0, gramsCap, 0),
    );
  }

  static String _text(Object? value, String fallback) {
    if (value is! String) return fallback;
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }

  static int _clampInt(Object? value, int min, int max, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) return fallback;
    return parsed.clamp(min, max);
  }

  static double _clampDouble(
    Object? value,
    double min,
    double max,
    double fallback,
  ) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed.clamp(min, max);
  }
}
