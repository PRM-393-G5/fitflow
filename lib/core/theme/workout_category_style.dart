import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Icon and colour per workout category, shared by every place that shows
/// a plan so Strength, Cardio and Mobility read the same everywhere.
const workoutCategoryIcons = {
  'Strength': FLucideIcons.dumbbell,
  'Cardio': FLucideIcons.flame,
  'Mobility': FLucideIcons.activity,
};

const workoutCategoryColors = {
  'Strength': Color(0xFF3B82F6),
  'Cardio': Color(0xFFF97316),
  'Mobility': Color(0xFF22C55E),
};

/// Custom categories fall back to a dumbbell.
IconData workoutCategoryIcon(String? category) =>
    workoutCategoryIcons[category] ?? FLucideIcons.dumbbell;

/// Custom categories fall back to [fallback] (the theme's primary).
Color workoutCategoryColor(String? category, Color fallback) =>
    workoutCategoryColors[category] ?? fallback;
