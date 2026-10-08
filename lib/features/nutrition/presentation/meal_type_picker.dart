import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/meal_plan.dart';

IconData mealIcon(String label) => switch (label.toLowerCase()) {
  'breakfast' => FLucideIcons.sunrise,
  'lunch' => FLucideIcons.sun,
  'dinner' => FLucideIcons.moon,
  'snack' => FLucideIcons.apple,
  _ => FLucideIcons.utensils,
};

/// Breakfast / Lunch / Dinner / Snack segmented choice.
class MealTypePicker extends StatelessWidget {
  const MealTypePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    spacing: AppSpacing.xs,
    children: [
      for (final type in mealTypes)
        Expanded(
          child: FButton(
            key: Key('meal-type-$type'),
            variant: type == selected ? .primary : .outline,
            size: .sm,
            style: const .delta(
              contentStyle: .delta(
                padding: .add(EdgeInsets.symmetric(horizontal: -6)),
              ),
            ),
            onPress: () => onChanged(type),
            child: Flexible(
              child: FittedBox(
                fit: .scaleDown,
                child: Text(type, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ),
        ),
    ],
  );
}
