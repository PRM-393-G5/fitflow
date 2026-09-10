import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    required this.icon,
    required this.value,
    required this.label,
    super.key,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );
}
