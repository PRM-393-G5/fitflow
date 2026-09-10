import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../workouts/presentation/schedule_page.dart';
import 'reminders_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile & settings',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.lg),
          const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'FitFlow Athlete',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('Your preferences stay on this device.'),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Theme'),
                  trailing: DropdownButton<ThemeMode>(
                    value: controller.themeMode,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) {
                      if (value != null) controller.setThemeMode(value);
                    },
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('System'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.straighten),
                  title: const Text('Metric units'),
                  subtitle: Text(
                    controller.useMetric ? 'Kilograms (kg)' : 'Pounds (lb)',
                  ),
                  value: controller.useMetric,
                  onChanged: controller.setMetric,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Workout reminders'),
                  subtitle: const Text('Time and training days'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RemindersPage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Weekly schedule'),
                  subtitle: const Text('Assign a plan to each day'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SchedulePage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Export data'),
                  subtitle: const Text(
                    'Workouts, sessions, and metrics as JSON',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showExport(context, controller.exportJson()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Private by design'),
              subtitle: const Text(
                'No account, backend, or cloud sync is used.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExport(BuildContext context, String json) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export data'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Export copied.')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}
