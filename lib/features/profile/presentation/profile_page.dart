import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../workouts/presentation/schedule_page.dart';
import 'reminders_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.auth?.currentUser;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.theme.colors;
    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profile & settings', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Column(
              children: [
                user?.photoURL == null
                    ? FAvatar.raw(
                        size: 88,
                        child: const Icon(FLucideIcons.user, size: 36),
                      )
                    : FAvatar(image: NetworkImage(user!.photoURL!), size: 88),
                const SizedBox(height: AppSpacing.md),
                Text(
                  user?.displayName ?? 'FitFlow Athlete',
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? 'Your preferences stay on this device.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FTileGroup(
            children: [
              FSelectMenuTile<ThemeMode>.fromMap(
                const {
                  'System': ThemeMode.system,
                  'Light': ThemeMode.light,
                  'Dark': ThemeMode.dark,
                },
                prefix: const Icon(FLucideIcons.sunMoon),
                title: const Text('Theme'),
                selectControl: .managedRadio(
                  initial: controller.themeMode,
                  onChange: (values) {
                    if (values.isNotEmpty) {
                      controller.setThemeMode(values.first);
                    }
                  },
                ),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.ruler),
                title: const Text('Metric units'),
                subtitle: Text(
                  controller.useMetric ? 'Kilograms (kg)' : 'Pounds (lb)',
                ),
                suffix: FSwitch(
                  value: controller.useMetric,
                  onChange: controller.setMetric,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FTileGroup(
            children: [
              FTile(
                prefix: const Icon(FLucideIcons.bell),
                title: const Text('Workout reminders'),
                subtitle: const Text('Time and training days'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RemindersPage(),
                  ),
                ),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.calendarDays),
                title: const Text('Weekly schedule'),
                subtitle: const Text('Assign a plan to each day'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SchedulePage()),
                ),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.upload),
                title: const Text('Export data'),
                subtitle: const Text('Workouts, sessions, and metrics as JSON'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => _showExport(context, controller.exportJson()),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FTileGroup(
            children: [
              FTile(
                variant: .destructive,
                prefix: const Icon(FLucideIcons.logOut),
                title: const Text('Sign out'),
                subtitle: Text(user?.email ?? 'Not signed in'),
                onPress: () => controller.auth?.signOut(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showExport(BuildContext context, String json) {
    showAppDialog<void>(
      context: context,
      title: 'Export data',
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: SelectableText(
            json,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      actions: [
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FButton(
          onPress: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (context.mounted) {
              showFToast(context: context, title: const Text('Export copied.'));
            }
          },
          prefix: const Icon(FLucideIcons.copy),
          child: const Text('Copy'),
        ),
      ],
    );
  }
}
