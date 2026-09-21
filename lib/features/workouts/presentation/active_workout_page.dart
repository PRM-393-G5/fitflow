import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/personal_records.dart';
import '../../../domain/progression.dart';
import 'weight_units.dart';

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({
    required this.workout,
    required this.controller,
    this.clock = DateTime.now,
    super.key,
  });

  final Workout workout;
  final AppController controller;

  /// Time source for the session and timers; tests inject a fake clock.
  final DateTime Function() clock;

  @override
  State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage> {
  static const _maxReps = 1000;
  static const _maxSeconds = 3600;

  late final DateTime _startedAt;
  int _exerciseIndex = 0;
  int _setIndex = 0;

  /// Every planned set is logged; only Finish (or Undo) remains.
  bool _done = false;
  final _entries = <int, List<SetEntry>>{};

  /// Logged (exercise, set) positions in order, for "Undo last set".
  final _log = <(int, int)>[];

  // Timers keep end times rather than counting ticks, so they stay correct
  // when the app is backgrounded and ticks are suspended.
  DateTime? _restEndsAt;
  DateTime? _holdEndsAt;
  int _holdTarget = 0;
  double _holdWeightKg = 0;
  Timer? _ticker;
  int _shownSeconds = -1;

  bool _dialogOpen = false;
  bool _saving = false;
  String? _amountError;
  String? _weightError;

  // The prefilled weight as shown, so an untouched field stores the exact
  // kg value instead of a rounded lb round-trip.
  String _prefillWeightText = '';
  double _prefillWeightKg = 0;

  /// Last-session hints per exercise index; drive the prefill of each
  /// exercise's first set.
  late final Map<int, ProgressionHint> _hints;

  final _amountCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  List<Exercise> get _exercises => widget.workout.exercises;
  Exercise get _exercise => _exercises[_exerciseIndex];
  int get _totalSets =>
      _exercises.fold(0, (sum, item) => sum + (item.sets > 0 ? item.sets : 0));
  int get _completedSets => _log.length;
  double get _progress => _totalSets == 0 ? 0 : _completedSets / _totalSets;
  bool get _metric => widget.controller.useMetric;
  bool get _resting => _restEndsAt != null;
  bool get _holding => _holdEndsAt != null;

  int _secondsUntil(DateTime? end) {
    if (end == null) return 0;
    final ms = end.difference(widget.clock()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _startedAt = widget.clock();
    // 2.5 kg, or 5 lb through the same conversion the form uses.
    final step = _metric
        ? Progression.metricStepKg
        : WeightUnits.toKg(5, false);
    _hints = {
      for (final (index, exercise) in _exercises.indexed)
        index: ?Progression.forExercise(
          widget.controller.sessions,
          exercise,
          weightStepKg: step,
          maxAmount: exercise.isTimed ? _maxSeconds : _maxReps,
          maxWeightKg: WeightUnits.maxKg,
        ),
    };
    final first = _exercises.indexWhere((item) => item.sets > 0);
    if (first >= 0) {
      _exerciseIndex = first;
      _prefill();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amountCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  /// Prefill inputs from [entry], else the last logged set of this
  /// exercise, else the last session's suggestion, else the plan.
  void _prefill([SetEntry? entry]) {
    final logged = _entries[_exerciseIndex];
    final hint = _hints[_exerciseIndex];
    final last =
        entry ??
        (logged != null && logged.isNotEmpty
            ? logged.last
            : hint == null
            ? null
            : SetEntry(amount: hint.amount, weightKg: hint.weightKg));
    _amountCtrl.text =
        '${last?.amount ?? (_exercise.isTimed ? _exercise.durationSeconds : _exercise.reps)}';
    _prefillWeightKg = last?.weightKg ?? _exercise.weightKg;
    _prefillWeightText = WeightUnits.format(_prefillWeightKg, _metric);
    _weightCtrl.text = _prefillWeightText;
    _amountError = null;
    _weightError = null;
  }

  /// Validates the inputs; null (with field errors shown) when invalid.
  SetEntry? _readEntry() {
    final amount = int.tryParse(_amountCtrl.text.trim());
    final weightText = _weightCtrl.text.trim();
    final weight = weightText.isEmpty
        ? 0.0
        : WeightUnits.parseDecimal(weightText);
    final timed = _exercise.isTimed;
    final maxAmount = timed ? _maxSeconds : _maxReps;
    setState(() {
      _amountError = amount == null || amount < 1
          ? (timed ? 'Enter at least 1 second' : 'Enter at least 1 rep')
          : amount > maxAmount
          ? (timed ? 'Max $maxAmount seconds' : 'Max $maxAmount reps')
          : null;
      _weightError = weight == null || weight < 0
          ? 'Enter 0 or more'
          : weight > WeightUnits.maxInput(_metric)
          ? 'Max ${WeightUnits.maxLabel(_metric)}'
          : null;
    });
    if (_amountError != null || _weightError != null) return null;
    return SetEntry(
      amount: amount!,
      weightKg: weightText == _prefillWeightText
          ? _prefillWeightKg
          : WeightUnits.toKg(weight!, _metric),
    );
  }

  (int, int)? _nextPosition() {
    if (_setIndex + 1 < _exercise.sets) return (_exerciseIndex, _setIndex + 1);
    for (var index = _exerciseIndex + 1; index < _exercises.length; index++) {
      if (_exercises[index].sets > 0) return (index, 0);
    }
    return null;
  }

  void _completeSet() {
    if (_done || _resting || _holding || _saving || _dialogOpen) return;
    final entry = _readEntry();
    if (entry != null) _logSet(entry);
  }

  /// Records [entry] for the current set and moves to the next one right
  /// away; the rest timer then runs in front of it. [finishing] skips the
  /// rest timer and the auto-finish when the caller is already finishing.
  void _logSet(SetEntry entry, {bool finishing = false}) {
    final rest = _exercise.restSeconds;
    setState(() {
      (_entries[_exerciseIndex] ??= []).add(entry);
      _log.add((_exerciseIndex, _setIndex));
      final next = _nextPosition();
      if (next == null) {
        _done = true;
      } else {
        _exerciseIndex = next.$1;
        _setIndex = next.$2;
        _prefill();
      }
    });
    if (finishing) return;
    if (_done) {
      _finish();
    } else if (rest > 0) {
      _restEndsAt = widget.clock().add(Duration(seconds: rest));
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _shownSeconds = -1;
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _tick();
  }

  void _tick() {
    // Frozen behind a dialog or while saving: a hold ending now would log a
    // set (and could open a second Finish dialog) mid-save.
    if (!mounted || _dialogOpen || _saving) return;
    if (_resting && _secondsUntil(_restEndsAt) == 0) {
      _alert();
      _skipRest();
      return;
    }
    if (_holding && _secondsUntil(_holdEndsAt) == 0) {
      _alert();
      _endHold(early: false);
      return;
    }
    final seconds = _secondsUntil(_restEndsAt ?? _holdEndsAt);
    if (seconds != _shownSeconds) setState(() => _shownSeconds = seconds);
  }

  void _alert() {
    unawaited(HapticFeedback.heavyImpact());
    unawaited(SystemSound.play(SystemSoundType.alert));
  }

  void _skipRest() {
    _ticker?.cancel();
    setState(() => _restEndsAt = null);
  }

  void _startHold() {
    if (_done || _resting || _holding || _saving || _dialogOpen) return;
    final entry = _readEntry();
    if (entry == null) return;
    setState(() {
      _holdTarget = entry.amount;
      _holdWeightKg = entry.weightKg;
      _holdEndsAt = widget.clock().add(Duration(seconds: entry.amount));
    });
    _startTicker();
  }

  /// Logs the hold — the full target, or the seconds held when ended early.
  void _endHold({required bool early, bool finishing = false}) {
    // A tick and a tap (or Finish) can race to end the same hold.
    if (!_holding) return;
    final remaining = _secondsUntil(_holdEndsAt);
    _ticker?.cancel();
    final held = early ? _holdTarget - remaining : _holdTarget;
    setState(() => _holdEndsAt = null);
    _logSet(
      SetEntry(amount: held < 1 ? 1 : held, weightKg: _holdWeightKg),
      finishing: finishing,
    );
  }

  void _cancelHold() {
    _ticker?.cancel();
    setState(() => _holdEndsAt = null);
  }

  void _undo() {
    if (_log.isEmpty || _saving || _dialogOpen) return;
    _ticker?.cancel();
    setState(() {
      final (exercise, set) = _log.removeLast();
      final removed = _entries[exercise]!.removeLast();
      _restEndsAt = null;
      _holdEndsAt = null;
      _done = false;
      _exerciseIndex = exercise;
      _setIndex = set;
      _prefill(removed);
    });
  }

  /// Runs [show] with the rest/hold countdown frozen, so it can't advance
  /// (or open another dialog) behind it; resumes with the time left.
  Future<T> _whilePaused<T>(Future<T> Function() show) async {
    _dialogOpen = true;
    final paused = widget.clock();
    _ticker?.cancel();
    try {
      return await show();
    } finally {
      _dialogOpen = false;
      if (mounted) {
        final pausedFor = widget.clock().difference(paused);
        _restEndsAt = _restEndsAt?.add(pausedFor);
        _holdEndsAt = _holdEndsAt?.add(pausedFor);
        if (_resting || _holding) _startTicker();
      }
    }
  }

  Future<void> _finish() async {
    if (_dialogOpen || _saving) return;
    // A hold in progress counts as a set: it is logged with the seconds
    // held so far once the user confirms (the dialog freezes it).
    final sets = _completedSets + (_holding ? 1 : 0);
    if (sets == 0) {
      final discard = await _confirm(
        'Discard workout?',
        'No sets are completed yet, so there is nothing to save.',
        'Discard workout',
      );
      if (discard && mounted) Navigator.pop(context);
      return;
    }
    final confirmed = await _confirm(
      'Finish workout?',
      _holding
          ? 'Your $sets sets, including the hold in progress, will be saved '
                'to Progress.'
          : 'Your $sets completed sets will be saved to Progress.',
      'Finish',
    );
    if (!confirmed || !mounted) return;
    _endHold(early: true, finishing: true);
    await _save();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final completedAt = widget.clock();
    final performed = [
      for (final (index, exercise) in _exercises.indexed)
        if (_entries[index]?.isNotEmpty ?? false)
          exercise.copyWith(performedSets: List.of(_entries[index]!)),
    ];
    final volume = performed.fold<double>(
      0,
      (sum, item) => sum + item.performedVolumeKg,
    );
    final newRecords = PersonalRecords.newRecords(
      widget.controller.sessions,
      performed,
    );
    try {
      await widget.controller.addSession(
        WorkoutSession(
          id: completedAt.microsecondsSinceEpoch.toString(),
          workoutId: widget.workout.id,
          workoutName: widget.workout.name,
          startedAt: _startedAt,
          completedAt: completedAt,
          completedSets: _completedSets,
          volumeKg: volume,
          exercises: performed,
        ),
      );
    } catch (e) {
      debugPrint('Saving session failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      showFToast(
        context: context,
        title: const Text('Could not save the workout. Try again.'),
      );
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context)..popUntil((route) => route.isFirst);
    if (newRecords.isNotEmpty && navigator.mounted) {
      showFToast(
        context: navigator.context,
        title: Text(
          'New PR: ${newRecords.map((item) => item.name).join(', ')}',
        ),
      );
    }
  }

  Future<bool> _confirm(String title, String message, String action) =>
      _whilePaused(
        () async =>
            await showAppDialog<bool>(
              context: context,
              title: title,
              body: Text(message),
              actions: [
                FButton(
                  variant: .ghost,
                  onPress: () => Navigator.pop(context, false),
                  child: const Text('Keep going'),
                ),
                FButton(
                  onPress: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ) ??
            false,
      );

  Future<void> _cancel() async {
    if (_dialogOpen || _saving) return;
    if (_completedSets == 0) {
      Navigator.pop(context);
      return;
    }
    final confirmed = await _confirm(
      'Cancel workout?',
      'This active workout will not be saved.',
      'Cancel workout',
    );
    if (confirmed && mounted) Navigator.pop(context);
  }

  String _clock(int seconds) => seconds < 60
      ? '$seconds'
      : '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_totalSets == 0) return _buildEmpty(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _cancel();
      },
      child: FScaffold(
        header: FHeader.nested(
          title: const Text('Active workout'),
          prefixes: [
            FHeaderAction(icon: const Icon(FLucideIcons.x), onPress: _cancel),
          ],
          suffixes: [
            FButton(
              key: const Key('finish-header'),
              variant: .ghost,
              size: .sm,
              onPress: _saving ? null : _finish,
              child: const Text('Finish'),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      label: '${(_progress * 100).round()} percent complete',
                      child: FDeterminateProgress(value: _progress),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('$_completedSets of $_totalSets sets'),
                    const Spacer(),
                    if (_holding)
                      ..._buildHold(context)
                    else if (_resting)
                      ..._buildRest(context)
                    else if (_done)
                      ..._buildDone(context)
                    else
                      ..._buildSet(context),
                    if (_log.isNotEmpty && !_holding) ...[
                      const SizedBox(height: AppSpacing.sm),
                      FButton(
                        key: const Key('undo-set'),
                        variant: .ghost,
                        onPress: _saving ? null : _undo,
                        prefix: const Icon(FLucideIcons.undo2),
                        child: const Text('Undo last set'),
                      ),
                    ],
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) => FScaffold(
    header: FHeader.nested(
      title: const Text('Active workout'),
      prefixes: [
        FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
      ],
    ),
    child: const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'This workout has no exercises yet. Add some before starting.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  Widget _bigNumber(BuildContext context, int seconds) => Text(
    _clock(seconds),
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.displayLarge
        ?.copyWith(fontWeight: FontWeight.bold),
  );

  List<Widget> _buildRest(BuildContext context) => [
    Icon(FLucideIcons.timer, size: 72, color: context.theme.colors.primary),
    Text(
      'Rest',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    _bigNumber(context, _secondsUntil(_restEndsAt)),
    const SizedBox(height: AppSpacing.md),
    Text(
      'Up next: ${_exercise.name}',
      key: const Key('up-next'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    Text(
      'Set ${_setIndex + 1} of ${_exercise.sets} • ${_exercise.prescription}',
      textAlign: TextAlign.center,
      style: TextStyle(color: context.theme.colors.mutedForeground),
    ),
    const SizedBox(height: AppSpacing.lg),
    FButton(
      key: const Key('skip-rest'),
      variant: .outline,
      onPress: _skipRest,
      child: const Text('Skip rest'),
    ),
  ];

  List<Widget> _buildHold(BuildContext context) => [
    Text(
      _exercise.name,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    Text(
      'Hold',
      textAlign: TextAlign.center,
      style: TextStyle(color: context.theme.colors.mutedForeground),
    ),
    _bigNumber(context, _secondsUntil(_holdEndsAt)),
    const SizedBox(height: AppSpacing.lg),
    FButton(
      key: const Key('end-hold'),
      onPress: () => _endHold(early: true),
      prefix: const Icon(FLucideIcons.check),
      child: const Text('End hold and log'),
    ),
    const SizedBox(height: AppSpacing.sm),
    FButton(
      variant: .ghost,
      onPress: _cancelHold,
      child: const Text('Cancel hold'),
    ),
  ];

  List<Widget> _buildDone(BuildContext context) => [
    Icon(
      FLucideIcons.circleCheckBig,
      size: 72,
      color: context.theme.colors.primary,
    ),
    const SizedBox(height: AppSpacing.sm),
    Text(
      'All sets complete',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    const SizedBox(height: AppSpacing.lg),
    FButton(
      key: const Key('finish-workout'),
      onPress: _saving ? null : _finish,
      prefix: const Icon(FLucideIcons.flag),
      child: const Text('Finish workout'),
    ),
  ];

  String _weightLabel(double kg) =>
      '${WeightUnits.format(kg, _metric)} ${WeightUnits.label(_metric)}';

  /// "3 × 10 @ 12 kg", "10, 8, 7 reps @ 12 kg",
  /// "10 @ 12 kg, 8 @ bodyweight".
  String _lastSetsLabel(List<SetEntry> sets) {
    final timed = _exercise.isTimed;
    String amount(int value) => timed ? '${value}s' : '$value';
    final weight = sets.first.weightKg;
    // Compared as shown, so lb conversion noise doesn't split equal sets.
    final shown = WeightUnits.format(weight, _metric);
    final sameWeight = sets.every(
      (set) => WeightUnits.format(set.weightKg, _metric) == shown,
    );
    if (!sameWeight) {
      return [
        for (final set in sets)
          '${amount(set.amount)} @ '
              '${set.weightKg > 0 ? _weightLabel(set.weightKg) : 'bodyweight'}',
      ].join(', ');
    }
    final load = weight > 0 ? ' @ ${_weightLabel(weight)}' : '';
    if (sets.every((set) => set.amount == sets.first.amount)) {
      return '${sets.length} × ${amount(sets.first.amount)}$load';
    }
    final amounts = sets.map((set) => amount(set.amount)).join(', ');
    return timed ? '$amounts$load' : '$amounts reps$load';
  }

  String _stepUpLabel(ProgressionHint hint) {
    if (_exercise.isTimed) {
      return 'You held every set last time — try ${hint.amount}s today.';
    }
    final target = hint.weightKg > 0
        ? _weightLabel(hint.weightKg)
        : '${hint.amount} reps';
    return 'You hit every rep last time — try $target today.';
  }

  List<Widget> _buildHint(BuildContext context, ProgressionHint hint) => [
    const SizedBox(height: AppSpacing.xs),
    Text(
      'Last time: ${_lastSetsLabel(hint.lastSets)}',
      key: const Key('last-time'),
      textAlign: TextAlign.center,
      style: TextStyle(color: context.theme.colors.mutedForeground),
    ),
    if (hint.stepUp) ...[
      const SizedBox(height: AppSpacing.xs),
      Text(
        _stepUpLabel(hint),
        key: const Key('step-up'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.theme.colors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ];

  List<Widget> _buildSet(BuildContext context) => [
    Text(
      'Exercise ${_exerciseIndex + 1} of ${_exercises.length}',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppSpacing.sm),
    Text(
      _exercise.name,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: AppSpacing.md),
    Text(
      'Set ${_setIndex + 1} of ${_exercise.sets}',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    if (_hints[_exerciseIndex] case final hint?) ..._buildHint(context, hint),
    const SizedBox(height: AppSpacing.md),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FTextField(
            key: const Key('set-amount'),
            control: .managed(controller: _amountCtrl),
            keyboardType: TextInputType.number,
            label: Text(_exercise.isTimed ? 'Seconds' : 'Reps'),
            error: _amountError == null ? null : Text(_amountError!),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FTextField(
            key: const Key('set-weight'),
            control: .managed(controller: _weightCtrl),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text('Weight (${WeightUnits.label(_metric)})'),
            error: _weightError == null ? null : Text(_weightError!),
          ),
        ),
      ],
    ),
    const SizedBox(height: AppSpacing.xl),
    if (_exercise.isTimed) ...[
      FButton(
        key: const Key('start-hold'),
        onPress: _startHold,
        prefix: const Icon(FLucideIcons.play),
        child: const Text('Start hold'),
      ),
      const SizedBox(height: AppSpacing.sm),
      FButton(
        key: const Key('complete-set'),
        variant: .outline,
        onPress: _completeSet,
        prefix: const Icon(FLucideIcons.check),
        child: const Text('Log set'),
      ),
    ] else
      FButton(
        key: const Key('complete-set'),
        onPress: _completeSet,
        prefix: const Icon(FLucideIcons.check),
        child: const Text('Complete set'),
      ),
  ];
}
