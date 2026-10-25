import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../domain/load_math.dart';
import '../../../domain/models/active_workout_draft.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/form_result.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/personal_records.dart';
import '../../../domain/progression.dart';
import '../../squat_form/domain/squat_analyzer.dart';
import '../../squat_form/domain/hands_free_session.dart';
import '../../squat_form/presentation/squat_form_check_page.dart';
import 'set_input.dart';
import 'weight_units.dart';

/// Opens the camera form check for one set; resolves to the counted reps
/// (or hold seconds) with the camera's form verdict, or null when nothing
/// was counted.
typedef FormCheckLauncher = Future<FormSetOutcome?> Function(
  BuildContext context,
  FormExercise exercise,
);

/// Opens the camera hands-free for [plan]; resolves to each finished set's
/// count and verdict, in plan order, or null when closed with none.
typedef HandsFreeLauncher = Future<List<FormSetOutcome>?> Function(
  BuildContext context,
  List<PlannedSet> plan,
);

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({
    required this.workout,
    required this.controller,
    this.initialDraft,
    this.clock = DateTime.now,
    this.launchFormCheck,
    this.launchHandsFree,
    super.key,
  });

  final Workout workout;
  final AppController controller;

  /// Optional in-progress draft to restore; if omitted, a matching draft
  /// on [controller.activeDraft] for [workout.id] is restored automatically.
  final ActiveWorkoutDraft? initialDraft;

  /// Time source for the session and timers; tests inject a fake clock.
  final DateTime Function() clock;

  /// Replaces the camera page; tests inject a fake count.
  final FormCheckLauncher? launchFormCheck;

  /// Replaces the hands-free camera page; tests inject fake sets.
  final HandsFreeLauncher? launchHandsFree;

  @override
  State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage> {
  static const _maxReps = SetInput.maxReps;
  static const _maxSeconds = SetInput.maxSeconds;
  static const _maxSets = 20;

  late final DateTime _startedAt;
  late List<Exercise> _exercises;
  int _exerciseIndex = 0;
  int _setIndex = 0;

  /// Every planned set is logged; only Finish (or Undo / Add set) remains.
  bool _done = false;

  /// The camera's verdict for the set it just counted, logged with that
  /// set (see [_logSet]).
  ({int exercise, int set, int amount, FormResult form})? _pendingForm;
  final _entries = <int, List<SetEntry>>{};

  /// Logged (exercise, set) positions in order, for "Undo last set".
  final _log = <(int, int)>[];

  /// Exercises skipped by the user during this workout (e.g. machine busy).
  final _skipped = <int>{};

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

  /// Heaviest load per exercise (see [_loadKey]) for the typo guard:
  /// history first, raised by loads confirmed in this session so Undo or
  /// a second entry of the exercise doesn't ask again.
  late final Map<String, double> _bestKg;

  final _amountCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  Exercise get _exercise => _exercises[_exerciseIndex];
  int _loggedSetsFor(int index) => _entries[index]?.length ?? 0;

  int get _totalSets {
    var total = 0;
    for (final (index, item) in _exercises.indexed) {
      if (_skipped.contains(index)) {
        total += _loggedSetsFor(index);
      } else if (item.sets > 0) {
        total += item.sets;
      }
    }
    return total;
  }

  int get _completedSets => _log.length;
  double get _progress => _totalSets == 0 ? 0 : _completedSets / _totalSets;
  bool get _metric => widget.controller.useMetric;
  bool get _resting => _restEndsAt != null;
  bool get _holding => _holdEndsAt != null;

  bool get _canSkipExercise {
    if (_completedSets > 0) return true;
    for (var i = 0; i < _exercises.length; i++) {
      if (i != _exerciseIndex &&
          !_skipped.contains(i) &&
          _loggedSetsFor(i) < _exercises[i].sets) {
        return true;
      }
    }
    return false;
  }

  int _secondsUntil(DateTime? end) {
    if (end == null) return 0;
    final ms = end.difference(widget.clock()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    // Any edit away from the camera's count overrides it: the verdict no
    // longer describes the set, even if the user types the number back.
    _amountCtrl.addListener(() {
      final pending = _pendingForm;
      if (pending != null && _amountCtrl.text != '${pending.amount}') {
        _pendingForm = null;
      }
    });
    final storedDraft = widget.controller.activeDraft;
    final draft = widget.initialDraft ??
        (storedDraft != null && storedDraft.workout.id == widget.workout.id
            ? storedDraft
            : null);

    if (draft != null && draft.workout.exercises.isNotEmpty) {
      _exercises = List.of(draft.workout.exercises);
      _startedAt = draft.startedAt;
      _exerciseIndex = draft.exerciseIndex.clamp(0, _exercises.length - 1);
      _setIndex = draft.setIndex;
      _done = draft.done;
      for (final MapEntry(:key, :value) in draft.entries.entries) {
        if (key >= 0 && key < _exercises.length && value.isNotEmpty) {
          _entries[key] = List.of(value);
        }
      }
      _log.addAll(draft.log);
      _skipped.addAll(draft.skippedExercises);
      final next = _nextPosition();
      if (next == null) {
        _done = true;
      } else if (!_done) {
        _exerciseIndex = next.$1;
        _setIndex = next.$2;
      }
    } else {
      _exercises = List.of(widget.workout.exercises);
      _startedAt = widget.clock();
      final first = _exercises.indexWhere((item) => item.sets > 0);
      if (first >= 0) {
        _exerciseIndex = first;
      }
    }

    _hints = {
      for (final (index, exercise) in _exercises.indexed)
        index: ?Progression.forExercise(
          widget.controller.sessions,
          exercise,
          category: widget.workout.category,
          metric: _metric,
          now: _startedAt,
          maxAmount: exercise.isTimed ? _maxSeconds : _maxReps,
          maxWeightKg: WeightUnits.maxKg,
        ),
    };
    _bestKg = {
      for (final exercise in _exercises)
        _loadKey(exercise): PersonalRecords.heaviestLoad(
          widget.controller.sessions,
          exercise.name,
          timed: exercise.isTimed,
        ),
    };
    if (_exercises.isNotEmpty) {
      _prefill();
    }
    if (draft?.restEndsAt case final restEndsAt?
        when !_done && _secondsUntil(restEndsAt) > 0) {
      _restEndsAt = restEndsAt;
      _startTicker();
    }
  }

  @override
  void didUpdateWidget(covariant ActiveWorkoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workout != widget.workout) {
      _exercises = List.of(widget.workout.exercises);
      _exerciseIndex = 0;
      _setIndex = 0;
      _done = false;
      _entries.clear();
      _log.clear();
      _skipped.clear();
      if (_exercises.isNotEmpty) _prefill();
    }
  }

  void _persistDraft() {
    final hasExtraSets = _exercises.length == widget.workout.exercises.length &&
        [
          for (var i = 0; i < _exercises.length; i++)
            _exercises[i].sets != widget.workout.exercises[i].sets,
        ].any((changed) => changed);
    if (_log.isEmpty && _skipped.isEmpty && !hasExtraSets) {
      unawaited(widget.controller.clearActiveDraft());
      return;
    }
    unawaited(
      widget.controller.saveActiveDraft(
        ActiveWorkoutDraft(
          workout: widget.workout.copyWith(exercises: List.of(_exercises)),
          startedAt: _startedAt,
          exerciseIndex: _exerciseIndex,
          setIndex: _setIndex,
          done: _done,
          entries: {
            for (final MapEntry(:key, :value) in _entries.entries)
              if (value.isNotEmpty) key: List.of(value),
          },
          log: List.of(_log),
          skippedExercises: Set.of(_skipped),
          restEndsAt: _restEndsAt,
        ),
      ),
    );
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
    final amount = SetInput.amount(_amountCtrl.text, timed: _exercise.isTimed);
    final weight = SetInput.weight(
      _weightCtrl.text,
      metric: _metric,
      prefillText: _prefillWeightText,
      prefillKg: _prefillWeightKg,
    );
    setState(() {
      _amountError = amount.error;
      _weightError = weight.error;
    });
    if (amount.value == null || weight.kg == null) return null;
    return SetEntry(amount: amount.value!, weightKg: weight.kg!);
  }

  (int, int)? _nextPosition() {
    final currentLogged = _loggedSetsFor(_exerciseIndex);
    if (!_skipped.contains(_exerciseIndex) && currentLogged < _exercise.sets) {
      return (_exerciseIndex, currentLogged);
    }
    for (var offset = 1; offset < _exercises.length; offset++) {
      final index = (_exerciseIndex + offset) % _exercises.length;
      if (_skipped.contains(index)) continue;
      final logged = _loggedSetsFor(index);
      if (logged < _exercises[index].sets) return (index, logged);
    }
    return null;
  }

  void _addSet() {
    if (_exercise.sets >= _maxSets || _saving || _dialogOpen) return;
    _ticker?.cancel();
    _pendingForm = null;
    setState(() {
      _restEndsAt = null;
      _holdEndsAt = null;
      _skipped.remove(_exerciseIndex);
      _exercises[_exerciseIndex] = _exercise.copyWith(sets: _exercise.sets + 1);
      _setIndex = _loggedSetsFor(_exerciseIndex);
      _done = false;
      _prefill();
    });
    _persistDraft();
  }

  void _skipExercise() {
    if (!_canSkipExercise || _saving || _dialogOpen) return;
    _ticker?.cancel();
    _pendingForm = null;
    setState(() {
      _restEndsAt = null;
      _holdEndsAt = null;
      _skipped.add(_exerciseIndex);
      final next = _nextPosition();
      if (next == null) {
        _done = true;
      } else {
        _done = false;
        _exerciseIndex = next.$1;
        _setIndex = next.$2;
        _prefill();
      }
    });
    _persistDraft();
    if (_done && _completedSets > 0) _finish();
  }

  void _switchExercise(int index) {
    if (index < 0 || index >= _exercises.length || _saving || _dialogOpen) {
      return;
    }
    _ticker?.cancel();
    _pendingForm = null;
    setState(() {
      _restEndsAt = null;
      _holdEndsAt = null;
      _skipped.remove(index);
      final logged = _loggedSetsFor(index);
      if (logged >= _exercises[index].sets &&
          _exercises[index].sets < _maxSets) {
        _exercises[index] = _exercises[index].copyWith(
          sets: _exercises[index].sets + 1,
        );
      }
      _exerciseIndex = index;
      _setIndex = _loggedSetsFor(index).clamp(0, _exercises[index].sets - 1);
      _done = _loggedSetsFor(index) >= _exercises[index].sets;
      _prefill();
    });
    _persistDraft();
  }

  Future<void> _pickExercise() async {
    if (_exercises.length < 2 || _saving || _dialogOpen) return;
    final colors = context.theme.colors;
    final chosen = await _whilePaused(
      () => showAppDialog<int>(
        context: context,
        title: 'Switch exercise',
        body: FTileGroup(
          children: [
            for (final (index, item) in _exercises.indexed)
              FTile(
                key: Key('pick-exercise-$index'),
                title: Text(item.name),
                subtitle: Text(_exerciseStatusLabel(index)),
                suffix: index == _exerciseIndex && !_done
                    ? Icon(FLucideIcons.play, color: colors.primary)
                    : _loggedSetsFor(index) >= item.sets &&
                          !_skipped.contains(index)
                    ? Icon(FLucideIcons.check, color: colors.primary)
                    : null,
                onPress: () => Navigator.pop(context, index),
              ),
          ],
        ),
        actions: [
          FButton(
            variant: .ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (chosen != null && mounted) _switchExercise(chosen);
  }

  String _exerciseStatusLabel(int index) {
    final item = _exercises[index];
    final logged = _loggedSetsFor(index);
    if (_skipped.contains(index)) {
      return logged > 0
          ? 'Skipped ($logged/${item.sets} sets done) • Tap to resume'
          : 'Skipped • Tap to resume';
    }
    if (logged >= item.sets) {
      return item.sets < _maxSets
          ? 'Done ($logged/${item.sets} sets) • Tap to add set'
          : 'Done ($logged/${item.sets} sets)';
    }
    return '$logged of ${item.sets} sets • ${item.muscleGroup}';
  }

  Future<void> _completeSet() async {
    if (_done || _resting || _holding || _saving || _dialogOpen) return;
    final entry = _readEntry();
    if (entry == null || !await _loadConfirmed(entry.weightKg)) return;
    if (mounted) _logSet(entry);
  }

  /// Exercises match across entries of a workout by name and kind.
  static String _loadKey(Exercise exercise) =>
      '${exercise.name.trim().toLowerCase()}|${exercise.isTimed}';

  /// Loads far above anything logged for this exercise are likely typos
  /// (600 for 60; see [LoadMath.looksMistyped]) and need a confirmation.
  /// The best is history plus every set of the exercise logged so far in
  /// this workout, so a first-ever session is guarded from its first set.
  /// A weight the app filled in itself (the suggestion) is never asked.
  Future<bool> _loadConfirmed(double kg) async {
    if (_weightCtrl.text.trim() == _prefillWeightText) return true;
    final key = _loadKey(_exercise);
    var best = _bestKg[key] ?? 0;
    for (final MapEntry(key: index, value: sets) in _entries.entries) {
      if (_loadKey(_exercises[index]) != key) continue;
      for (final set in sets) {
        best = math.max(best, set.weightKg);
      }
    }
    if (!LoadMath.looksMistyped(kg, best)) return true;
    final confirmed = await _whilePaused(
      () async =>
          await showAppDialog<bool>(
            context: context,
            title: 'Log ${_weightLabel(kg)}?',
            body: Text(
              'That is far above your best of ${_weightLabel(best)} on '
              '${_exercise.name}. Check for a typo before logging it.',
            ),
            actions: [
              FButton(
                key: const Key('fix-heavy-set'),
                variant: .ghost,
                onPress: () => Navigator.pop(context, false),
                child: const Text('Fix it'),
              ),
              FButton(
                key: const Key('confirm-heavy-set'),
                onPress: () => Navigator.pop(context, true),
                child: const Text('Log it'),
              ),
            ],
          ) ??
          false,
    );
    if (confirmed) _bestKg[key] = math.max(best, kg);
    return confirmed;
  }

  /// Records [entry] for the current set and moves to the next one right
  /// away; the rest timer then runs in front of it. [finishing] skips the
  /// rest timer and the auto-finish when the caller is already finishing.
  void _logSet(SetEntry entry, {bool finishing = false}) {
    final rest = _exercise.restSeconds;
    // The camera's verdict belongs to this set only if it's the set it
    // counted, logged with the count it gave.
    final pending = _pendingForm;
    _pendingForm = null;
    if (pending != null &&
        pending.exercise == _exerciseIndex &&
        pending.set == _setIndex &&
        pending.amount == entry.amount) {
      entry = entry.withForm(pending.form);
    }
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
    if (finishing) {
      _persistDraft();
      return;
    }
    if (_done) {
      _persistDraft();
      _finish();
    } else if (rest > 0) {
      _restEndsAt = widget.clock().add(Duration(seconds: rest));
      _persistDraft();
      _startTicker();
    } else {
      _persistDraft();
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
    _persistDraft();
  }

  Future<void> _startHold() async {
    if (_done || _resting || _holding || _saving || _dialogOpen) return;
    final entry = _readEntry();
    if (entry == null || !await _loadConfirmed(entry.weightKg)) return;
    if (!mounted) return;
    // A timer hold is a new hold the camera never saw.
    _pendingForm = null;
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

  /// Counts the current set with the camera and logs it with that count
  /// and the weight in the field, as "Complete set" would: the user lifts,
  /// the camera counts, the set is done. Undo puts the count back to fix.
  /// If the set can't be logged as is (an invalid weight, a heavy load
  /// they don't confirm), the count stays in the field to log by hand.
  Future<void> _checkForm(FormExercise exercise) async {
    if (_done || _resting || _holding || _saving || _dialogOpen) return;
    final launch =
        widget.launchFormCheck ??
        (context, exercise) => Navigator.of(context).push<FormSetOutcome>(
          MaterialPageRoute(
            builder: (_) => SquatFormCheckPage(
              controller: widget.controller,
              forSet: exercise,
            ),
          ),
        );
    final outcome = await _whilePaused(() => launch(context, exercise));
    if (outcome == null || outcome.amount < 1 || !mounted) return;
    final timed = _exercise.isTimed;
    final amount = outcome.amount.clamp(1, timed ? _maxSeconds : _maxReps);
    setState(() {
      _amountCtrl.text = '$amount';
      _amountError = null;
    });
    // This run replaces any earlier one; a verdict only goes with the
    // count it describes, so a clamped count carries none.
    _pendingForm = switch (outcome.form) {
      final form? when amount == outcome.amount => (
        exercise: _exerciseIndex,
        set: _setIndex,
        amount: amount,
        form: form,
      ),
      _ => null,
    };
    final before = _completedSets;
    await _completeSet();
    if (!mounted) return;
    final logged = _completedSets > before;
    showFToast(
      context: context,
      title: Text(
        logged
            ? timed
                  ? 'Logged a ${amount}s hold from the camera. Undo to fix it.'
                  : 'Logged $amount reps from the camera. Undo to fix it.'
            : timed
            ? 'Held ${amount}s — log the set to save it.'
            : 'Counted $amount reps — complete the set to save it.',
      ),
    );
  }

  int _plannedTarget(int index) {
    final exercise = _exercises[index];
    if (index == _exerciseIndex) {
      final typed = SetInput.amount(
        _amountCtrl.text,
        timed: exercise.isTimed,
      ).value;
      if (typed != null) return typed;
    }
    final logged = _entries[index];
    if (logged != null && logged.isNotEmpty) return logged.last.amount;
    return _hints[index]?.amount ??
        (exercise.isTimed ? exercise.durationSeconds : exercise.reps);
  }

  /// The sets the camera can run back to back from here: the rest of this
  /// exercise, then each following unfinished one it can count (wrapping
  /// around when the user switched order), up to the first it can't.
  List<PlannedSet> _handsFreePlan() {
    final plan = <PlannedSet>[];
    for (var offset = 0; offset < _exercises.length; offset++) {
      final index = (_exerciseIndex + offset) % _exercises.length;
      if (_skipped.contains(index)) continue;
      final exercise = _exercises[index];
      final startSet = offset == 0 ? _setIndex : _loggedSetsFor(index);
      if (startSet >= exercise.sets) continue;
      final kind = FormExercise.match(exercise.name, timed: exercise.isTimed);
      if (kind == null) break;
      final target = _plannedTarget(index);
      for (var set = startSet; set < exercise.sets; set++) {
        plan.add(
          PlannedSet(
            exercise: kind,
            name: exercise.name,
            target: target < 1 ? 1 : target,
            restSeconds: exercise.restSeconds,
            setNumber: set + 1,
            sets: exercise.sets,
          ),
        );
      }
    }
    return plan;
  }

  /// Runs the camera sets from here without a tap, then logs each set it
  /// finished with the weight the workout would have suggested for it.
  Future<void> _handsFree() async {
    if (_done || _resting || _holding || _saving || _dialogOpen) return;
    final first = _readEntry();
    if (first == null || !await _loadConfirmed(first.weightKg)) return;
    if (!mounted) return;
    final plan = _handsFreePlan();
    if (plan.length < 2) return;
    final launch =
        widget.launchHandsFree ??
        (context, plan) => Navigator.of(context).push<List<FormSetOutcome>>(
          MaterialPageRoute(
            builder: (_) =>
                SquatFormCheckPage(controller: widget.controller, plan: plan),
          ),
        );
    final outcomes = await _whilePaused(() => launch(context, plan));
    if (outcomes == null || outcomes.isEmpty || !mounted) return;
    var logged = 0;
    for (final (index, outcome) in outcomes.indexed) {
      if (_done || outcome.amount < 1) break;
      final amount = outcome.amount.clamp(
        1,
        _exercise.isTimed ? _maxSeconds : _maxReps,
      );
      setState(() {
        _amountCtrl.text = '$amount';
        _amountError = null;
      });
      _pendingForm = switch (outcome.form) {
        final form? when amount == outcome.amount => (
          exercise: _exerciseIndex,
          set: _setIndex,
          amount: amount,
          form: form,
        ),
        _ => null,
      };
      // Each set is prefilled (weight included) as it comes up, exactly
      // as when logged by hand; an unusable weight stops here for the
      // user to fix and log the rest themselves.
      final entry = _readEntry();
      if (entry == null) break;
      // The camera already rested between sets: only the last one starts
      // a rest here (or finishes the workout).
      _logSet(entry, finishing: index < outcomes.length - 1);
      logged++;
    }
    if (!mounted || logged == 0) return;
    showFToast(
      context: context,
      title: Text(
        'Logged $logged ${logged == 1 ? 'set' : 'sets'} hands-free. '
        'Undo to fix one.',
      ),
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
      _skipped.remove(exercise);
      _restEndsAt = null;
      _holdEndsAt = null;
      _done = false;
      _exerciseIndex = exercise;
      _setIndex = set;
      _prefill(removed);
      // Re-logging the same count keeps the camera's verdict.
      _pendingForm = switch (removed.form) {
        final form? => (
          exercise: exercise,
          set: set,
          amount: removed.amount,
          form: form,
        ),
        null => null,
      };
    });
    _persistDraft();
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
      if (discard) {
        await widget.controller.clearActiveDraft();
        if (mounted) Navigator.pop(context);
      }
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
      await widget.controller.clearActiveDraft();
      if (mounted) Navigator.pop(context);
      return;
    }
    final confirmed = await _confirm(
      'Cancel workout?',
      'This active workout will not be saved.',
      'Cancel workout',
    );
    if (confirmed) {
      await widget.controller.clearActiveDraft();
      if (mounted) Navigator.pop(context);
    }
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
    if (_exercise.sets < _maxSets) ...[
      const SizedBox(height: AppSpacing.sm),
      FButton(
        key: const Key('add-set'),
        variant: .outline,
        onPress: _saving ? null : _addSet,
        prefix: const Icon(FLucideIcons.plus),
        child: Text('Add set to ${_exercise.name}'),
      ),
    ],
    if (_exercises.length > 1) ...[
      const SizedBox(height: AppSpacing.sm),
      FButton(
        key: const Key('switch-exercise'),
        variant: .ghost,
        onPress: _saving ? null : _pickExercise,
        prefix: const Icon(FLucideIcons.listOrdered),
        child: const Text('Switch exercise'),
      ),
    ],
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

  /// "Last time", or "Last 12-rep session" when alternating plans put a
  /// session with another target after the one the hint follows.
  String _lastLabel(ProgressionHint hint) {
    if (!hint.otherTargetSince) return 'Last time';
    final target = _exercise.isTimed
        ? '${_exercise.durationSeconds}s'
        : '${_exercise.reps}-rep';
    return 'Last $target session';
  }

  /// What today's suggestion is and why; null when there is nothing to
  /// add to "Last time" (mobility and cardio work).
  String? _hintLabel(ProgressionHint hint) {
    final timed = _exercise.isTimed;
    final amount = timed ? '${hint.amount}s' : '${hint.amount} reps';
    final load = hint.weightKg > 0 ? _weightLabel(hint.weightKg) : null;
    return switch (hint.reason) {
      ProgressionReason.stepUp when timed =>
        'You held every set last time — try ${hint.amount}s today.',
      ProgressionReason.stepUp when load == null =>
        'You hit every rep last time — try $amount today.',
      ProgressionReason.stepUp =>
        'Top of the rep range twice in a row — try $load today.',
      ProgressionReason.building =>
        'Same weight — aim for $amount per set, then it goes up.',
      ProgressionReason.repeat =>
        'Match the plan first: ${load == null ? amount : '$amount @ $load'}.',
      ProgressionReason.deload =>
        'Missed reps three times in a row — reset to $load and build back.',
      ProgressionReason.comeback =>
        'First time in ${hint.weeksAway} weeks — start lighter at $load.',
      ProgressionReason.newTarget =>
        'New target — ${load == null ? amount : '$amount @ $load'} '
            'matches last time\'s effort.',
      ProgressionReason.capped when timed =>
        'Strong hold — try a harder variation to keep progressing.',
      ProgressionReason.capped when load == null =>
        'Plenty of reps — try a harder variation or add weight.',
      ProgressionReason.capped => 'Keep $load and own every rep.',
      ProgressionReason.maintain => null,
    };
  }

  List<Widget> _buildHint(BuildContext context, ProgressionHint hint) => [
    const SizedBox(height: AppSpacing.xs),
    Text(
      '${_lastLabel(hint)}: ${_lastSetsLabel(hint.lastSets)}',
      key: const Key('last-time'),
      textAlign: TextAlign.center,
      style: TextStyle(color: context.theme.colors.mutedForeground),
    ),
    if (_hintLabel(hint) case final label?) ...[
      const SizedBox(height: AppSpacing.xs),
      Text(
        label,
        key: Key(hint.stepUp ? 'step-up' : 'progression-hint'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: hint.stepUp
              ? context.theme.colors.primary
              : context.theme.colors.mutedForeground,
          fontWeight: hint.stepUp ? FontWeight.w600 : null,
        ),
      ),
    ],
  ];

  List<Widget> _buildSet(BuildContext context) => [
    if (_exercises.length > 1)
      Center(
        child: FButton(
          key: const Key('switch-exercise'),
          variant: .ghost,
          size: .sm,
          mainAxisSize: .min,
          onPress: _saving ? null : _pickExercise,
          suffix: const Icon(FLucideIcons.chevronDown, size: 16),
          child: Text('Exercise ${_exerciseIndex + 1} of ${_exercises.length}'),
        ),
      )
    else
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
    if (FormExercise.match(_exercise.name, timed: _exercise.isTimed)
        case final exercise?) ...[
      const SizedBox(height: AppSpacing.sm),
      FButton(
        key: const Key('form-check-set'),
        variant: .ghost,
        onPress: () => _checkForm(exercise),
        prefix: const Icon(FLucideIcons.accessibility),
        child: Text(
          _exercise.isTimed ? 'Time hold with camera' : 'Count with camera',
        ),
      ),
      if (_handsFreePlan() case final plan when plan.length > 1)
        FButton(
          key: const Key('hands-free'),
          variant: .outline,
          onPress: _handsFree,
          prefix: const Icon(FLucideIcons.hand),
          child: Text('Hands-free · ${plan.length} sets'),
        ),
    ],
    if (_exercise.sets < _maxSets || _canSkipExercise) ...[
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          if (_exercise.sets < _maxSets)
            FButton(
              key: const Key('add-set'),
              variant: .ghost,
              size: .sm,
              mainAxisSize: .min,
              onPress: _saving ? null : _addSet,
              prefix: const Icon(FLucideIcons.plus, size: 16),
              child: const Text('Add set'),
            ),
          if (_canSkipExercise)
            FButton(
              key: const Key('skip-exercise'),
              variant: .ghost,
              size: .sm,
              mainAxisSize: .min,
              onPress: _saving ? null : _skipExercise,
              prefix: const Icon(FLucideIcons.skipForward, size: 16),
              child: const Text('Skip exercise'),
            ),
        ],
      ),
    ],
  ];
}
