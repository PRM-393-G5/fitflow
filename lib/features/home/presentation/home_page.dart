import 'package:clock/clock.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/layout/responsive_content.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/workout_stats.dart';
import '../../squat_form/presentation/squat_form_check_page.dart';
import '../../../domain/models/active_workout_draft.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';
import '../../workouts/presentation/active_workout_page.dart';
import '../../workouts/presentation/schedule_page.dart';
import '../../workouts/presentation/workout_detail_page.dart';
import '../../../core/widgets/app_card.dart';
import 'home_nutrition_section.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenNutrition});

  /// Switches the shell to the Nutrition tab; null outside the shell.
  final VoidCallback? onOpenNutrition;

  /// "Good morning" before noon, "Good afternoon" until 6 pm, then
  /// "Good evening".
  static String greeting(DateTime time) => time.hour < 12
      ? 'Good morning'
      : time.hour < 18
      ? 'Good afternoon'
      : 'Good evening';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Home stays built in the shell's IndexedStack, so a resume past
  /// midnight must rebuild it for "today" (meals, done, rest) to move on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final now = clock.now();
    final today = controller.suggestedWorkout();
    final restDay = controller.isRestDay(now.weekday);
    final streak = WorkoutStats.weeklyStreak(
      controller.sessions,
      controller.weeklyGoal,
      now: now,
    );
    // The goal chip and the minutes chip count the same sessions.
    final week = WorkoutStats.thisWeek(controller.sessions, now: now);
    final weekMinutes = WorkoutStats.totalMinutes(week);
    final dayStart = DateTime(now.year, now.month, now.day);
    WorkoutSession? doneToday;
    for (final session in controller.sessions) {
      // A camera form check is not today's planned workout.
      if (session.workoutId == WorkoutStats.formCheckId) continue;
      if (!session.completedAt.isBefore(dayStart)) {
        doneToday = session;
        break;
      }
    }
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final fromSchedule = controller.plannedDays > 0;
    void openSchedule() => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SchedulePage()));

    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            HomePage.greeting(now),
            style: textTheme.titleMedium?.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          Text(
            'Fuel your day',
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (controller.activeDraft case final draft?) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              key: const Key('resume-workout-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FLucideIcons.play, color: colors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Workout in progress: ${draft.workout.name}',
                          style: textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${draft.completedSets} of ${draft.totalSets} sets logged',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      FButton(
                        key: const Key('resume-workout'),
                        size: .sm,
                        mainAxisSize: .min,
                        onPress: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ActiveWorkoutPage(
                              workout: draft.workout,
                              controller: controller,
                              initialDraft: draft,
                            ),
                          ),
                        ),
                        prefix: const Icon(FLucideIcons.play, size: 16),
                        child: const Text('Resume'),
                      ),
                      FButton(
                        key: const Key('discard-active-draft'),
                        variant: .ghost,
                        size: .sm,
                        mainAxisSize: .min,
                        onPress: () =>
                            _confirmDiscardDraft(context, controller, draft),
                        child: const Text('Discard'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          HomeNutritionSection(onOpenNutrition: widget.onOpenNutrition),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'Training',
            action: FTappable(
              onPress: openSchedule,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  FLucideIcons.calendarDays,
                  size: 20,
                  color: colors.mutedForeground,
                  semanticLabel: 'Edit weekly schedule',
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _TrainingCard(
            today: today,
            restDay: restDay,
            doneToday: doneToday,
            stats: [
              _Stat(
                key: const Key('home-weekly-goal'),
                value: '${week.length}/${controller.weeklyGoal}',
                label: 'this week',
                highlight: week.length >= controller.weeklyGoal,
                // The goal is the schedule's training days when there is
                // one, so the stat opens the schedule, not the picker.
                onPress: fromSchedule
                    ? openSchedule
                    : () => _pickWeeklyGoal(context, controller),
              ),
              _Stat(
                key: const Key('home-streak'),
                value: '${streak.current}',
                label: 'week streak',
              ),
              _Stat(
                key: const Key('home-minutes'),
                value: '${weekMinutes}m',
                label: 'active',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FTileGroup(
            children: [
              FTile(
                key: const Key('open-squat-form-check-home'),
                prefix: Icon(FLucideIcons.accessibility, color: colors.primary),
                title: const Text('AI Form Check'),
                subtitle: const Text('Live feedback on your form'),
                suffix: const Icon(FLucideIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SquatFormCheckPage(controller: controller),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDiscardDraft(
    BuildContext context,
    AppController controller,
    ActiveWorkoutDraft draft,
  ) async {
    if (draft.completedSets == 0) {
      await controller.clearActiveDraft();
      return;
    }
    final sets = draft.completedSets;
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Discard workout?',
      body: Text(
        'Your $sets logged ${sets == 1 ? 'set' : 'sets'} for '
        '${draft.workout.name} will not be saved.',
      ),
      actions: [
        FButton(
          variant: .ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('Keep'),
        ),
        FButton(
          key: const Key('confirm-discard-draft'),
          variant: .destructive,
          onPress: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
      ],
    );
    if (confirmed == true) {
      await controller.clearActiveDraft();
    }
  }

  void _pickWeeklyGoal(BuildContext context, AppController controller) {
    showAppDialog<void>(
      context: context,
      title: 'Weekly goal',
      body: FTileGroup(
        children: [
          for (final value in List.generate(7, (index) => index + 1))
            FTile(
              title: Text('$value workouts per week'),
              onPress: () {
                controller.setWeeklyGoal(value);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

/// Today's training in one row: what is planned (or done, or rest) and
/// a Start button. Tapping the text opens the plan's details.
class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.today,
    required this.restDay,
    required this.doneToday,
    required this.stats,
  });

  final Workout? today;
  final bool restDay;
  final WorkoutSession? doneToday;

  /// The week's numbers, shown in one row under today's plan.
  final List<Widget> stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    final workout = today;
    final done = doneToday;

    final (icon, title, subtitle, titleKey) = done != null
        ? (
            FLucideIcons.circleCheckBig,
            'Done today',
            '${done.workoutName} • ${done.completedSets} sets • '
                '${done.durationMinutes} min',
            const Key('home-done-today'),
          )
        : restDay
        ? (
            FLucideIcons.moon,
            'Rest day',
            'Recovery is part of the plan.',
            const Key('home-rest-day'),
          )
        : workout == null
        ? (FLucideIcons.activity, 'No plan available', null, null)
        : (
            FLucideIcons.activity,
            workout.name,
            '${workout.duration.inMinutes} min • ${workout.level}',
            null,
          );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: titleKey,
          style: textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );

    final canStart = done == null && !restDay && workout != null;
    // The icon is decoration: with large text it gives its room to the
    // plan's name and Start.
    final showIcon = MediaQuery.textScalerOf(context).scale(1) <= 1.5;
    final todayRow = Row(
      children: [
        if (showIcon) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          // Rest days link nowhere; otherwise the plan's details — after
          // today's workout, to train it again.
          child: workout == null || (restDay && done == null)
              ? text
              : FTappable(
                  key: const Key('home-view-details'),
                  // Read as one node: the plan (or what was done) and
                  // what tapping does.
                  semanticsLabel:
                      '${[title, ?subtitle].join(', ')}. '
                      '${done == null ? 'View details' : 'Train again'}',
                  excludeSemantics: true,
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkoutDetailPage(workout: workout),
                    ),
                  ),
                  // Start already reads as the action; the chevron only
                  // marks the text as tappable when Start is absent.
                  child: canStart
                      ? text
                      : Row(
                          children: [
                            Expanded(child: text),
                            Icon(
                              FLucideIcons.chevronRight,
                              size: 16,
                              color: colors.mutedForeground,
                            ),
                          ],
                        ),
                ),
        ),
        if (canStart) ...[
          const SizedBox(width: AppSpacing.sm),
          FButton(
            key: const Key('home-quick-start'),
            // Secondary: Log meal is Home's one primary action.
            variant: .secondary,
            size: .sm,
            mainAxisSize: .min,
            onPress: workout.totalSets == 0
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ActiveWorkoutPage(
                        workout: workout,
                        controller: AppScope.of(context),
                      ),
                    ),
                  ),
            prefix: const Icon(FLucideIcons.play, size: 16),
            child: const Text('Start'),
          ),
        ],
      ],
    );

    return AppCard(
      key: const Key('home-training'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          todayRow,
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, thickness: 1, color: colors.border),
          const SizedBox(height: AppSpacing.md),
          Row(children: [for (final stat in stats) Expanded(child: stat)]),
        ],
      ),
    );
  }
}

/// One of the week's numbers: the value over a short label. Tappable
/// when [onPress] is set, which a chevron after the label shows.
class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.value,
    required this.label,
    this.highlight = false,
    this.onPress,
  });

  final String value;
  final String label;

  /// Drawn in the primary color, e.g. once the weekly goal is reached.
  final bool highlight;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final stat = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlight ? colors.primary : null,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ),
            if (onPress != null)
              Icon(
                FLucideIcons.chevronRight,
                size: 12,
                color: colors.mutedForeground,
              ),
          ],
        ),
      ],
    );
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      button: onPress != null,
      onTap: onPress,
      child: onPress == null
          ? stat
          : FTappable(
              onPress: onPress,
              // A 48dp touch target, taller than the two lines of text.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(alignment: Alignment.centerLeft, child: stat),
              ),
            ),
    );
  }
}
