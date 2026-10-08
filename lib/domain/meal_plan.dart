import 'dart:convert';

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
  });

  final DateTime date;
  final int targetKcal;
  final List<Meal> meals;
  final String note;

  int get totalKcal => meals.fold(0, (sum, meal) => sum + meal.kcal);

  bool get isToday => isOn(DateTime.now());

  bool isOn(DateTime day) =>
      date.year == day.year && date.month == day.month && date.day == day.day;

  Map<String, Object> toJson() => {
    'date': date.toIso8601String(),
    'targetKcal': targetKcal,
    'meals': meals.map((meal) => meal.toJson()).toList(),
    'note': note,
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

/// Logged meals per local calendar day, kept for [keepDays] days.
/// Persisted under `food_log_v1`.
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

/// One day's logged meals — the unit synced to the backend (`foodDays`,
/// id `yyyy-mm-dd`). Immutable: every edit makes a new day, so sync can
/// tell local changes apart by identity.
class FoodDay {
  FoodDay(this.id, Iterable<Meal> meals) : meals = List.unmodifiable(meals);

  final String id;
  final List<Meal> meals;

  Map<String, Object> toJson() => {
    'id': id,
    'meals': [for (final meal in meals) meal.toJson()],
  };

  /// Malformed meals are dropped; throws [FormatException] without a
  /// `yyyy-mm-dd` id.
  factory FoodDay.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || !FoodLog.isDayKey(id)) {
      throw const FormatException('Food day has no yyyy-mm-dd id');
    }
    return FoodDay(id, FoodLog._meals(json['meals']));
  }
}

/// Meals logged per calendar day, kept for the last [keepDays] days on
/// the device (the backend keeps the full history).
class FoodLog {
  FoodLog([Map<String, FoodDay>? days]) : days = days ?? {};

  /// Keeps only non-empty days.
  factory FoodLog.fromDays(Iterable<FoodDay> days) => FoodLog({
    for (final day in days)
      if (day.meals.isNotEmpty) day.id: day,
  });

  static const keepDays = 30;

  /// `yyyy-mm-dd` → that day's meals.
  final Map<String, FoodDay> days;

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static bool isDayKey(String key) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key);

  List<Meal> mealsOn(DateTime day) => days[dayKey(day)]?.meals ?? const [];

  /// Each mutation returns the changed day's key.
  String add(DateTime day, Meal meal) {
    final key = dayKey(day);
    days[key] = FoodDay(key, [...?days[key]?.meals, meal]);
    return key;
  }

  String replace(DateTime day, int index, Meal meal) {
    final key = dayKey(day);
    final meals = days[key]?.meals;
    if (meals == null || index < 0 || index >= meals.length) return key;
    days[key] = FoodDay(key, [...meals]..[index] = meal);
    return key;
  }

  String removeAt(DateTime day, int index) {
    final key = dayKey(day);
    final meals = days[key]?.meals;
    if (meals == null || index < 0 || index >= meals.length) return key;
    final left = [...meals]..removeAt(index);
    if (left.isEmpty) {
      days.remove(key);
    } else {
      days[key] = FoodDay(key, left);
    }
    return key;
  }

  /// Drops days older than the last [keepDays] days ending at [now].
  void prune(DateTime now) {
    final cutoff = dayKey(
      DateTime(now.year, now.month, now.day - (keepDays - 1)),
    );
    // yyyy-mm-dd keys sort chronologically as strings.
    days.removeWhere(
      (key, day) => key.compareTo(cutoff) < 0 || day.meals.isEmpty,
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
    'version': 2,
    'days': {
      for (final entry in days.entries)
        entry.key: [for (final meal in entry.value.meals) meal.toJson()],
    },
  };

  /// Never throws: malformed days or meals are dropped. Also reads the
  /// legacy single-day format (`{date, meals}`).
  static FoodLog decode(String? raw) {
    final log = FoodLog();
    if (raw == null) return log;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return log;
      final legacyDate = json['date'];
      if (legacyDate is String) {
        final key = dayKey(DateTime.parse(legacyDate));
        log.days[key] = FoodDay(key, _meals(json['meals']));
      } else if (json['days'] case final Map<String, dynamic> days) {
        for (final entry in days.entries) {
          if (!isDayKey(entry.key)) continue;
          log.days[entry.key] = FoodDay(entry.key, _meals(entry.value));
        }
      }
    } on FormatException {
      // Unreadable log — start fresh.
    }
    log.days.removeWhere((_, day) => day.meals.isEmpty);
    return log;
  }

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

/// Calorie and macro targets derived from TDEE and the onboarding goal.
abstract final class NutritionTargets {
  /// Goal-based adjustment on top of maintenance calories.
  /// Strength = lean surplus, Cardio = fat-loss deficit, Mobility = maintain.
  static int targetKcal({required double tdee, required String? goal}) {
    final delta = switch (goal) {
      'Strength' => 300,
      'Cardio' => -400,
      _ => 0,
    };
    return (tdee + delta).clamp(1200, 5000).round();
  }

  /// Protein per kg of body weight by goal.
  static int proteinG({required double weightKg, required String? goal}) {
    final factor = switch (goal) {
      'Strength' => 1.8,
      'Cardio' => 1.4,
      _ => 1.2,
    };
    return (weightKg * factor).round();
  }

  /// Fat at 25% of target calories (9 kcal/g).
  static int fatG(int targetKcal) => (targetKcal * 0.25 / 9).round();

  /// Carbs fill the remainder after protein and fat (4 kcal/g).
  static int carbsG({required int targetKcal, required int proteinG}) =>
      ((targetKcal - proteinG * 4 - fatG(targetKcal) * 9) / 4)
          .clamp(0, 1000)
          .round();
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

  static String user({
    required int targetKcal,
    required int proteinG,
    required int meals,
    String? goal,
    String? preferences,
  }) {
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
    if (goal != null) buffer.write('\nUser goal: $goal');
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

  static MealPlan parse(Map<String, dynamic> json, {required int targetKcal}) {
    final meals = [
      for (final (index, item) in _list(json['meals']).indexed)
        if (item is Map<String, dynamic>) _meal(item, 'Meal ${index + 1}'),
    ].where((meal) => meal.items.isNotEmpty).toList();
    if (meals.isEmpty) {
      throw const FormatException('AI plan has no meals');
    }
    return MealPlan(
      date: DateTime.now(),
      targetKcal: targetKcal,
      meals: meals,
      note: _text(json['note'], ''),
    );
  }

  static Meal _meal(Map<String, dynamic> json, String fallbackLabel) => Meal(
    label: _text(json['label'], fallbackLabel),
    items: [
      for (final item in _list(json['items']))
        if (item is Map<String, dynamic>) _item(item),
    ],
  );

  static MealItem _item(Map<String, dynamic> json) => MealItem(
    name: _text(json['name'], 'Item'),
    kcal: _clampInt(json['kcal'], 0, 1500, 0),
    proteinG: _clampDouble(json['proteinG'], 0, 300, 0),
    carbsG: _clampDouble(json['carbsG'], 0, 300, 0),
    fatG: _clampDouble(json['fatG'], 0, 300, 0),
  );

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
