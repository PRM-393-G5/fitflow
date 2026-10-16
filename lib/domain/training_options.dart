/// Choices shared by onboarding, profile, nutrition and body metrics.
library;

/// Training goals: label shown, value stored (a workout category).
const trainingGoals = [
  (label: 'Build muscle', value: 'Strength'),
  (label: 'Lose fat', value: 'Cardio'),
  (label: 'Stay mobile', value: 'Mobility'),
];

const trainingLevels = ['Beginner', 'Intermediate', 'Advanced'];

/// Activity levels, indexed by `AppController.activityLevel`.
const activityLevels = ['Sedentary', 'Light', 'Moderate', 'Active', 'Athlete'];

/// What a stored goal asks of nutrition — the one mapping from the
/// workout-category value to calorie intent.
enum NutritionIntent { loseFat, buildMuscle, maintain }

NutritionIntent nutritionIntent(String? goal) => switch (goal) {
  'Cardio' => NutritionIntent.loseFat,
  'Strength' => NutritionIntent.buildMuscle,
  _ => NutritionIntent.maintain,
};

/// The label for a stored goal value (or the value itself if unknown).
String goalLabel(String goal) => trainingGoals
    .firstWhere(
      (option) => option.value == goal,
      orElse: () => (label: goal, value: goal),
    )
    .label;

/// The label for an activity level index, clamped to the known range.
String activityLabel(int level) =>
    activityLevels[level.clamp(0, activityLevels.length - 1)];
