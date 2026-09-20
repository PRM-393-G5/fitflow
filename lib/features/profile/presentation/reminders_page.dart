import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_card.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _timeLabel(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Workout reminders'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FTileGroup(
              children: [
                FTile(
                  prefix: const Icon(FLucideIcons.bell),
                  title: const Text('Enable reminders'),
                  subtitle: const Text('Get nudged on your training days'),
                  suffix: FSwitch(
                    value: controller.reminderEnabled,
                    onChange: (value) async {
                      final granted = await controller.setReminder(
                        enabled: value,
                      );
                      if (!granted && context.mounted) {
                        showFToast(
                          context: context,
                          title: const Text('Notifications are blocked'),
                          description: const Text(
                            'Allow notifications for FitFlow in system '
                            'settings to get reminders.',
                          ),
                          suffixBuilder: (context, entry) => FButton(
                            size: .sm,
                            mainAxisSize: .min,
                            onPress: () {
                              entry.dismiss();
                              openAppSettings();
                            },
                            child: const Text('Settings'),
                          ),
                        );
                      }
                    },
                  ),
                ),
                FTile(
                  prefix: const Icon(FLucideIcons.clock),
                  title: const Text('Time'),
                  suffix: Text(_timeLabel(controller.reminderMinutes)),
                  onPress: !controller.reminderEnabled
                      ? null
                      : () async {
                          var picked = FTime(
                            controller.reminderMinutes ~/ 60,
                            controller.reminderMinutes % 60,
                          );
                          final minutes = await showAppDialog<int>(
                            context: context,
                            title: 'Reminder time',
                            body: Center(
                              child: FTimePicker(
                                control: .managed(
                                  initial: picked,
                                  onChange: (time) => picked = time,
                                ),
                                hour24: true,
                              ),
                            ),
                            actions: [
                              FButton(
                                variant: .ghost,
                                onPress: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              FButton(
                                onPress: () => Navigator.pop(
                                  context,
                                  picked.hour * 60 + picked.minute,
                                ),
                                child: const Text('Save'),
                              ),
                            ],
                          );
                          if (minutes != null) {
                            controller.setReminder(minutes: minutes);
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Days', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: List.generate(
                      7,
                      (index) => FButton(
                        variant: controller.reminderDays.contains(index + 1)
                            ? .primary
                            : .outline,
                        size: .sm,
                        mainAxisSize: .min,
                        onPress: !controller.reminderEnabled
                            ? null
                            : () => controller.toggleReminderDay(index + 1),
                        child: Text(_dayLabels[index]),
                      ),
                    ),
                  ),
                  if (controller.reminderEnabled &&
                      controller.reminderDays.isEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Pick at least one day — no reminders are scheduled.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.theme.colors.destructive),
                    ),
                  ],
                  if (controller.reminderEnabled &&
                      controller.schedule.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FButton(
                      variant: .ghost,
                      size: .sm,
                      mainAxisSize: .min,
                      prefix: const Icon(FLucideIcons.calendarDays),
                      onPress: () => controller.setReminder(
                        days: {
                          for (final day in controller.schedule.keys)
                            if (controller.scheduledWorkout(day) != null) day,
                        },
                      ),
                      child: const Text('Match my weekly schedule'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
