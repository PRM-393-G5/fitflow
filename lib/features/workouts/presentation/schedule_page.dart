import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly schedule')),
      body: SafeArea(
        child: ResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Assign a plan to each day. Home shows today\u2019s pick.',
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Column(
                  children: [
                    for (var weekday = 1; weekday <= 7; weekday++) ...[
                      if (weekday > 1) const Divider(height: 1),
                      ListTile(
                        title: Text(_dayNames[weekday - 1]),
                        trailing: DropdownButton<String?>(
                          value: controller.schedule[weekday],
                          hint: const Text('Rest'),
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem<String?>(
                              child: Text('Rest'),
                            ),
                            ...controller.workouts.map(
                              (workout) => DropdownMenuItem<String?>(
                                value: workout.id,
                                child: Text(workout.name),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              controller.setScheduleDay(weekday, value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
