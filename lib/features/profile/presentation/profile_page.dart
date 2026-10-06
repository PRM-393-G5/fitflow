import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../data/api/api_client.dart';
import '../../../data/backend_auth_service.dart';
import '../../../domain/models/app_user.dart';
import '../../auth/presentation/login_page.dart';
import '../../onboarding/presentation/onboarding_page.dart';
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
                user?.photoUrl == null
                    ? FAvatar.raw(
                        size: 88,
                        child: const Icon(FLucideIcons.user, size: 36),
                      )
                    : FAvatar(image: NetworkImage(user!.photoUrl!), size: 88),
                const SizedBox(height: AppSpacing.md),
                Text(
                  user?.displayName ?? 'FitFlow Athlete',
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? 'Your data stays on this device.',
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
                prefix: const Icon(FLucideIcons.target),
                title: const Text('Training goal'),
                subtitle: Text(
                  [
                    controller.goal ?? 'No goal set',
                    ?controller.level,
                  ].join(' · '),
                ),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OnboardingPage(),
                  ),
                ),
              ),
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
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FTileGroup(
            children: [
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
          const SizedBox(height: AppSpacing.lg),
          _AccountSection(controller: controller, user: user),
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
    return FTileGroup(
      children: [
        if (signedIn) ...[
          FTile(
            prefix: const Icon(FLucideIcons.refreshCw),
            title: const Text('Sync now'),
            subtitle: Text(
              controller.syncing ? 'Syncing…' : 'Backed up to your account',
            ),
            onPress: controller.syncing ? null : controller.sync,
          ),
          FTile(
            prefix: const Icon(FLucideIcons.logOut),
            title: const Text('Sign out'),
            subtitle: Text(user!.email),
            onPress: () => _signOut(context),
          ),
          FTile(
            variant: .destructive,
            prefix: const Icon(FLucideIcons.userX),
            title: const Text('Delete account'),
            subtitle: const Text('Remove your account and cloud data'),
            onPress: () => _deleteAccount(context),
          ),
        ] else ...[
          if (controller.auth != null)
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
          FTile(
            variant: .destructive,
            prefix: const Icon(FLucideIcons.trash2),
            title: const Text('Delete data on this device'),
            onPress: () => _clearLocal(context),
          ),
        ],
      ],
    );
  }
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
