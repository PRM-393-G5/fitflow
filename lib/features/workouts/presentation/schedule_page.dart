import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Weekly schedule'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assign a plan to each day. Home shows today\u2019s pick.',
            ),
            const SizedBox(height: AppSpacing.md),
            FTileGroup(
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  FSelectMenuTile<String?>.fromMap(
                    {
                      'Rest': null,
                      for (final workout in controller.workouts)
                        workout.name: workout.id,
                    },
                    title: Text(_dayNames[weekday - 1]),
                    selectControl: .managedRadio(
                      initial: controller.schedule[weekday],
                      onChange: (values) => controller.setScheduleDay(
                        weekday,
                        values.isEmpty ? null : values.first,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
