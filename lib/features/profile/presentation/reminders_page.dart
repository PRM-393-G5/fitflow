import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _timeLabel(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Workout reminders')),
      body: SafeArea(
        child: ResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Enable reminders'),
                  subtitle: const Text('Get nudged on your training days'),
                  value: controller.reminderEnabled,
                  onChanged: (value) => controller.setReminder(enabled: value),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Time'),
                  trailing: Text(_timeLabel(controller.reminderMinutes)),
                  enabled: controller.reminderEnabled,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: controller.reminderMinutes ~/ 60,
                        minute: controller.reminderMinutes % 60,
                      ),
                    );
                    if (picked != null) {
                      controller.setReminder(
                        minutes: picked.hour * 60 + picked.minute,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Days',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: List.generate(
                          7,
                          (index) => FilterChip(
                            label: Text(_dayLabels[index]),
                            selected: controller.reminderDays.contains(
                              index + 1,
                            ),
                            onSelected: !controller.reminderEnabled
                                ? null
                                : (selected) {
                                    final days = {...controller.reminderDays};
                                    selected
                                        ? days.add(index + 1)
                                        : days.remove(index + 1);
                                    controller.setReminder(days: days);
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
