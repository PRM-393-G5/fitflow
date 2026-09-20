import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

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
                    onChange: (value) => controller.setReminder(enabled: value),
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
                            : () {
                                final days = {...controller.reminderDays};
                                controller.reminderDays.contains(index + 1)
                                    ? days.remove(index + 1)
                                    : days.add(index + 1);
                                controller.setReminder(days: days);
                              },
                        child: Text(_dayLabels[index]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
