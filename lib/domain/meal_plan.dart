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

  factory MealItem.fromJson(Map<String, dynamic> json) => MealItem(
    name: json['name'] as String,
    kcal: (json['kcal'] as num?)?.toInt() ?? 0,
    proteinG: (json['proteinG'] as num?)?.toDouble() ?? 0,
    carbsG: (json['carbsG'] as num?)?.toDouble() ?? 0,
    fatG: (json['fatG'] as num?)?.toDouble() ?? 0,
  );
}

/// A labeled meal (Breakfast, Lunch, ...) holding suggested items.
class Meal {
  const Meal({required this.label, required this.items});

  final String label;
  final List<MealItem> items;

  int get kcal => items.fold(0, (sum, item) => sum + item.kcal);

  Map<String, Object> toJson() => {
    'label': label,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    label: json['label'] as String,
    items: [
      for (final item in json['items'] as List? ?? const [])
        MealItem.fromJson(item as Map<String, dynamic>),
    ],
  );
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

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Map<String, Object> toJson() => {
    'date': date.toIso8601String(),
    'targetKcal': targetKcal,
    'meals': meals.map((meal) => meal.toJson()).toList(),
    'note': note,
  };

  factory MealPlan.fromJson(Map<String, dynamic> json) => MealPlan(
    date: DateTime.parse(json['date'] as String),
    targetKcal: (json['targetKcal'] as num?)?.toInt() ?? 0,
    meals: [
      for (final item in json['meals'] as List? ?? const [])
        Meal.fromJson(item as Map<String, dynamic>),
    ],
    note: json['note'] as String? ?? '',
  );
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
- Split the day into the requested meals (Breakfast, Lunch, Dinner,
  Snack) with sensible kcal distribution (breakfast ~25%, lunch ~35%,
  dinner ~30%, snack ~10%).
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
    if (goal != null) buffer.write('\nUser goal: $goal');
    if (preferences != null && preferences.isNotEmpty) {
      buffer.write('\nPreferences/restrictions: $preferences');
    }
    return buffer.toString();
  }
}

/// Sanitizes AI meal-plan JSON into a [MealPlan] — numbers clamped,
/// empty meals dropped. Throws [FormatException] when nothing usable
/// remains.
abstract final class AiMealParser {
  static MealPlan parse(Map<String, dynamic> json, {required int targetKcal}) {
    final meals = [
      for (final (index, item) in (json['meals'] as List? ?? const []).indexed)
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
      for (final item in json['items'] as List? ?? const [])
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
