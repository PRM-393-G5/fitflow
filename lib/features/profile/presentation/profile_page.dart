import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/formatting.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../data/api/api_client.dart';
import '../../../data/backend_auth_service.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/training_options.dart';
import '../../auth/presentation/login_page.dart';
import '../../metrics/presentation/body_metrics_page.dart';
import '../../workouts/presentation/schedule_page.dart';
import '../../workouts/presentation/weight_units.dart';
import 'reminders_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.auth?.currentUser;
    final textTheme = Theme.of(context).textTheme;
    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile',
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ProfileCard(controller: controller, user: user),
          const _SectionLabel('Training'),
          FTileGroup(
            children: [
              FTile(
                key: const Key('profile-goal'),
                prefix: const Icon(FLucideIcons.target),
                title: const Text('Goal & level'),
                subtitle: Text(
                  [
                    controller.goal == null
                        ? 'No goal set'
                        : goalLabel(controller.goal!),
                    ?controller.level,
                  ].join(' · '),
                ),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => _editGoal(context, controller),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.calendarDays),
                title: const Text('Weekly schedule'),
                subtitle: Text(_scheduleSummary(controller)),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SchedulePage()),
                ),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.bell),
                title: const Text('Workout reminders'),
                subtitle: Text(_reminderSummary(controller)),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RemindersPage(),
                  ),
                ),
              ),
            ],
          ),
          const _SectionLabel('Preferences'),
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
          const _SectionLabel('Data'),
          FTileGroup(
            children: [
              if (user != null) _syncTile(controller),
              FTile(
                prefix: const Icon(FLucideIcons.upload),
                title: const Text('Export data'),
                subtitle: const Text('Back up everything as a JSON file'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => _showExport(context, controller.exportJson()),
              ),
              FTile(
                prefix: const Icon(FLucideIcons.download),
                title: const Text('Import data'),
                subtitle: const Text('Restore a FitFlow JSON backup'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => _showImport(context),
              ),
            ],
          ),
          const _SectionLabel('Account'),
          _AccountSection(controller: controller, user: user),
        ],
      ),
    );
  }

  /// Sync status; rebuilt every minute so "5 min ago" stays true.
  static FTile _syncTile(AppController controller) => FTile(
    key: const Key('profile-sync'),
    prefix: controller.syncing
        ? const FCircularProgress()
        : const Icon(FLucideIcons.refreshCw),
    title: const Text('Sync'),
    subtitle: _Ticking(
      every: const Duration(minutes: 1),
      builder: (_) => Text(_syncSummary(controller)),
    ),
    onPress: controller.syncing ? null : controller.sync,
  );

  /// "5 workout days · Mon, Wed, Thu, Fri, Sat", or a hint when empty.
  static String _scheduleSummary(AppController controller) {
    final days = [
      for (var day = 1; day <= 7; day++)
        if (controller.scheduledWorkout(day) != null) day,
    ];
    if (days.isEmpty) return 'No plan assigned yet';
    final names = days.map((day) => weekdayNames[day - 1]).join(', ');
    return '${days.length} workout ${days.length == 1 ? 'day' : 'days'} · '
        '$names';
  }

  /// "18:00 · Mon, Wed, Fri", or "Off".
  static String _reminderSummary(AppController controller) {
    if (!controller.reminderEnabled) return 'Off';
    final time = clockLabel(controller.reminderMinutes);
    final days = (controller.reminderDays.toList()..sort())
        .map((day) => weekdayNames[day - 1])
        .join(', ');
    return days.isEmpty ? time : '$time · $days';
  }

  static String _syncSummary(AppController controller) {
    if (controller.syncing) return 'Syncing…';
    if (controller.lastSyncFailed) return "Couldn't sync — tap to retry";
    final at = controller.lastSyncedAt;
    return at == null ? 'Tap to sync now' : 'Synced ${ago(at)}';
  }

  /// "just now", "5 min ago", "3 h ago", else the date (with the year
  /// when it is not this year).
  @visibleForTesting
  static String ago(DateTime time, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final elapsed = today.difference(time);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
    final day =
        '${time.day.toString().padLeft(2, '0')}/'
        '${time.month.toString().padLeft(2, '0')}';
    return time.year == today.year ? 'on $day' : 'on $day/${time.year}';
  }

  Future<void> _editGoal(BuildContext context, AppController controller) async {
    final picked = await showFDialog<({String goal, String level})>(
      context: context,
      builder: (context, style, animation) => _GoalDialog(
        style: style,
        animation: animation,
        goal: controller.goal,
        level: controller.level,
        // No calorie targets under 18.
        calorieTargets: BodyMetrics.adultFormulasApply(controller.age),
      ),
    );
    if (picked == null) return;
    await controller.setGoal(goal: picked.goal, level: picked.level);
  }

  void _showExport(BuildContext context, String json) {
    showAppDialog<void>(
      context: context,
      title: 'Export data',
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          // A preview only — large histories would stall a full render.
          child: Text(
            json.length > 4000 ? '${json.substring(0, 4000)}\n…' : json,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      actions: [
        FButton(
          onPress: () async {
            final now = DateTime.now();
            final stamp =
                '${now.year}${now.month.toString().padLeft(2, '0')}'
                '${now.day.toString().padLeft(2, '0')}';
            await SharePlus.instance.share(
              ShareParams(
                files: [
                  XFile.fromData(
                    utf8.encode(json),
                    mimeType: 'application/json',
                    name: 'fitflow-backup-$stamp.json',
                  ),
                ],
                fileNameOverrides: ['fitflow-backup-$stamp.json'],
              ),
            );
          },
          prefix: const Icon(FLucideIcons.share2),
          child: const Text('Save or share file'),
        ),
        FButton(
          variant: .outline,
          onPress: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (context.mounted) {
              showFToast(context: context, title: const Text('Export copied.'));
            }
          },
          prefix: const Icon(FLucideIcons.copy),
          child: const Text('Copy'),
        ),
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _showImport(BuildContext context) {
    showFDialog<void>(
      context: context,
      builder: (context, style, animation) =>
          _ImportDialog(style: style, animation: animation),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.style, required this.animation});

  final FDialogStyle style;
  final Animation<double> animation;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (mounted && data?.text != null) _input.text = data!.text!;
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await AppScope.of(context).importJson(_input.text);
      if (!mounted) return;
      Navigator.pop(context);
      showFToast(context: context, title: Text('Imported $count records.'));
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Import failed — $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FDialog(
    style: widget.style,
    animation: widget.animation,
    builder: (context, style) => AppDialogContent(
      title: 'Import data',
      style: style,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste the contents of a FitFlow export. Entries merge with '
            'your current data; profile and schedule are replaced.',
          ),
          const SizedBox(height: AppSpacing.sm),
          FTextField(
            control: .managed(controller: _input),
            minLines: 4,
            maxLines: 8,
            hint: '{ "app": "FitFlow", … }',
            error: _error == null ? null : Text(_error!),
          ),
        ],
      ),
      actions: [
        FButton(onPress: _busy ? null : _import, child: const Text('Import')),
        FButton(
          variant: .outline,
          onPress: _busy ? null : _paste,
          prefix: const Icon(FLucideIcons.clipboardPaste),
          child: const Text('Paste from clipboard'),
        ),
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.controller, required this.user});

  final AppController controller;
  final AppUser? user;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async =>
      await showAppDialog<bool>(
        context: context,
        title: title,
        body: Text(body),
        actions: [
          FButton(
            variant: .destructive,
            onPress: () => Navigator.pop(context, true),
            child: Text(action),
          ),
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ) ??
      false;

  Future<void> _signOut(BuildContext context) async {
    if (await controller.signOut()) return;
    if (!context.mounted) return;
    final force = await _confirm(
      context,
      title: 'Unsynced changes',
      body:
          'Some changes have not reached the cloud yet (you may be offline). '
          'Signing out now will lose them.',
      action: 'Sign out anyway',
    );
    if (force) await controller.signOut(force: true);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete account?',
      body:
          'This permanently deletes your FitFlow account and all synced '
          'data (sessions, plans, weights, profile). This cannot be undone.',
      action: 'Delete account',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await controller.deleteAccount();
      if (context.mounted) {
        showFToast(context: context, title: const Text('Account deleted.'));
      }
    } on GoogleSignInException catch (e) {
      // Cancelled the confirmation login: nothing was deleted.
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete the account'),
          description: Text(describeAuthError(e)),
        );
      }
    } catch (e) {
      debugPrint('Delete account failed: $e');
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete the account'),
          description: Text(describeDeleteError(e)),
        );
      }
    }
  }

  Future<void> _clearLocal(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete all data?',
      body:
          'This removes every session, custom plan, weight entry and your '
          'profile from this device. Export a backup first if unsure.',
      action: 'Delete data',
    );
    if (confirmed) await controller.clearLocalData();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = user != null;
    // The destructive action sits apart from the everyday ones.
    final danger = signedIn
        ? FTile(
            key: const Key('profile-delete-account'),
            variant: .destructive,
            prefix: const Icon(FLucideIcons.userX),
            title: const Text('Delete account'),
            subtitle: const Text('Remove your account and cloud data'),
            onPress: () => _deleteAccount(context),
          )
        : FTile(
            variant: .destructive,
            prefix: const Icon(FLucideIcons.trash2),
            title: const Text('Delete data on this device'),
            onPress: () => _clearLocal(context),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (signedIn || controller.auth != null) ...[
          FTileGroup(
            children: [
              if (signedIn)
                FTile(
                  key: const Key('profile-sign-out'),
                  prefix: const Icon(FLucideIcons.logOut),
                  title: const Text('Sign out'),
                  onPress: () => _signOut(context),
                )
              else
                FTile(
                  prefix: const Icon(FLucideIcons.logIn),
                  title: const Text('Sign in with Google'),
                  subtitle: const Text('Back up and sync across devices'),
                  suffix: const Icon(FLucideIcons.chevronRight),
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginPage(popOnSuccess: true),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        FTileGroup(children: [danger]),
      ],
    );
  }
}

/// Rebuilds [builder] every [every] (for relative times).
class _Ticking extends StatefulWidget {
  const _Ticking({required this.every, required this.builder});

  final Duration every;
  final WidgetBuilder builder;

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.every, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Small heading above a settings group.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: AppSpacing.lg,
      bottom: AppSpacing.sm,
      left: AppSpacing.xs,
    ),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.theme.colors.mutedForeground,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// Who is signed in plus the body profile at a glance; opens Body
/// metrics to edit it.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.controller, required this.user});

  final AppController controller;
  final AppUser? user;

  /// "172 cm · 22 y · 72.5 kg · Moderate", or null with nothing set.
  String? _bodySummary() {
    final weights = controller.weightEntries;
    final parts = [
      if (controller.heightCm case final height?)
        '${WeightUnits.formatNumber(height.toDouble())} cm',
      if (controller.age case final age?) '$age y',
      if (weights.isNotEmpty)
        '${WeightUnits.format(weights.last.weightKg, controller.useMetric)} '
            '${WeightUnits.label(controller.useMetric)}',
    ];
    if (parts.isEmpty) return null;
    return [...parts, activityLabel(controller.activityLevel)].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    final body = _bodySummary();
    final user = this.user;
    return FTappable(
      key: const Key('profile-card'),
      semanticsLabel:
          '${user?.displayName ?? 'FitFlow Athlete'}. '
          '${body ?? 'Add your body profile'}. Open body metrics',
      onPress: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const BodyMetricsPage())),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                user?.photoUrl == null
                    ? FAvatar.raw(
                        size: 56,
                        child: const Icon(FLucideIcons.user, size: 26),
                      )
                    : FAvatar(image: NetworkImage(user!.photoUrl!), size: 56),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'FitFlow Athlete',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        user?.email ?? 'Guest · data stays on this device',
                        style: muted,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      FLucideIcons.activity,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        body ?? 'Add height, age and weight',
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    Icon(
                      FLucideIcons.chevronRight,
                      size: 18,
                      color: colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks the training goal and level in place; pops both, or null.
class _GoalDialog extends StatefulWidget {
  const _GoalDialog({
    required this.style,
    required this.animation,
    required this.goal,
    required this.level,
    required this.calorieTargets,
  });

  final FDialogStyle style;
  final Animation<double> animation;
  final String? goal;
  final String? level;
  final bool calorieTargets;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late String? _goal = widget.goal;
  late String? _level = widget.level;

  FTile _option(String label, bool selected, VoidCallback onPress) => FTile(
    title: Text(label),
    suffix: selected
        ? Icon(FLucideIcons.check, color: context.theme.colors.primary)
        : null,
    onPress: onPress,
  );

  @override
  Widget build(BuildContext context) => FDialog(
    style: widget.style,
    animation: widget.animation,
    builder: (context, style) => AppDialogContent(
      title: 'Goal & level',
      style: style,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.calorieTargets
                ? 'Plans, suggestions and calorie targets follow these.'
                : 'Plans and suggestions follow these.',
          ),
          const SizedBox(height: AppSpacing.md),
          FTileGroup(
            label: const Text('Goal'),
            children: [
              for (final option in trainingGoals)
                _option(
                  option.label,
                  _goal == option.value,
                  () => setState(() => _goal = option.value),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FTileGroup(
            label: const Text('Level'),
            children: [
              for (final level in trainingLevels)
                _option(
                  level,
                  _level == level,
                  () => setState(() => _level = level),
                ),
            ],
          ),
        ],
      ),
      actions: [
        FButton(
          key: const Key('goal-save'),
          onPress: _goal == null || _level == null
              ? null
              : () => Navigator.pop(context, (goal: _goal!, level: _level!)),
          child: const Text('Save'),
        ),
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// A user-facing reason why account deletion failed.
@visibleForTesting
String describeDeleteError(Object error) {
  if (error is ApiException && !error.isNetwork) {
    if (error.statusCode == 403) {
      return error.message.contains('does not match')
          ? 'Choose the same Google account you signed in with.'
          : 'Confirm with Google again, then retry right away.';
    }
    if (error.statusCode == 429) {
      return 'Too many attempts — try again in a minute.';
    }
    return 'The server could not delete the account — try again later.';
  }
  return 'Check your connection and try again.';
}
