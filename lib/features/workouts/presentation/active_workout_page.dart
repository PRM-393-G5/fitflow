import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/personal_records.dart';

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({
    required this.workout,
    required this.controller,
    super.key,
  });

  final Workout workout;
  final AppController controller;

  @override
  State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage> {
  late final DateTime _startedAt = DateTime.now();
  int _exerciseIndex = 0;
  int _setIndex = 0;
  int _completedSets = 0;
  int _restRemaining = 0;
  final _performedIndexes = <int>{};
  final _entries = <int, List<SetEntry>>{};
  final _amountCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  Timer? _timer;

  Exercise get _exercise => widget.workout.exercises[_exerciseIndex];
  double get _progress => _completedSets / widget.workout.totalSets;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amountCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  /// Prefill inputs from the last logged set of this exercise, else the plan.
  void _prefill() {
    final logged = _entries[_exerciseIndex];
    final last = logged == null || logged.isEmpty ? null : logged.last;
    _amountCtrl.text =
        '${last?.amount ?? (_exercise.isTimed ? _exercise.durationSeconds : _exercise.reps)}';
    _weightCtrl.text = '${last?.weightKg ?? _exercise.weightKg}';
  }

  void _completeSet() {
    final fallback = _exercise.isTimed
        ? _exercise.durationSeconds
        : _exercise.reps;
    final entry = SetEntry(
      amount: int.tryParse(_amountCtrl.text.trim()) ?? fallback,
      weightKg: double.tryParse(_weightCtrl.text.trim()) ?? _exercise.weightKg,
    );
    setState(() {
      _completedSets++;
      _performedIndexes.add(_exerciseIndex);
      (_entries[_exerciseIndex] ??= []).add(entry);
      _restRemaining = _exercise.restSeconds;
    });
    _startRestTimer();
  }

  void _startRestTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_restRemaining <= 1) {
        _advance();
      } else {
        setState(() => _restRemaining--);
      }
    });
  }

  void _advance() {
    _timer?.cancel();
    setState(() {
      _restRemaining = 0;
      if (_setIndex + 1 < _exercise.sets) {
        _setIndex++;
      } else if (_exerciseIndex + 1 < widget.workout.exercises.length) {
        _exerciseIndex++;
        _setIndex = 0;
      }
      _prefill();
    });
    if (_completedSets >= widget.workout.totalSets) _finish();
  }

  Future<void> _finish() async {
    final confirmed = await _confirm(
      'Finish workout?',
      'Your completed sets will be saved to Progress.',
      'Finish',
    );
    if (!confirmed || !mounted) return;
    final completedAt = DateTime.now();
    final performed = [
      for (final index in _performedIndexes)
        widget.workout.exercises[index].copyWith(
          performedSets: _entries[index] ?? const [],
        ),
    ];
    final volume = performed.fold<double>(
      0,
      (sum, item) => sum + item.performedVolumeKg,
    );
    final newRecords = PersonalRecords.newRecords(
      widget.controller.sessions,
      performed,
    );
    final messenger = ScaffoldMessenger.of(context);
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
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      if (newRecords.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'New PR: ${newRecords.map((item) => item.name).join(', ')}',
            ),
          ),
        );
      }
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep going'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _cancel() async {
    final confirmed = await _confirm(
      'Cancel workout?',
      'This active workout will not be saved.',
      'Cancel workout',
    );
    if (confirmed && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _cancel();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Active workout'),
        leading: IconButton(
          tooltip: 'Cancel workout',
          onPressed: _cancel,
          icon: const Icon(Icons.close),
        ),
        actions: [TextButton(onPressed: _finish, child: const Text('Finish'))],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: '${(_progress * 100).round()} percent complete',
                child: LinearProgressIndicator(value: _progress),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('$_completedSets of ${widget.workout.totalSets} sets'),
              const Spacer(),
              if (_restRemaining > 0) ...[
                Icon(
                  Icons.timer_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                Text(
                  'Rest',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  '$_restRemaining',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  key: const Key('skip-rest'),
                  onPressed: _advance,
                  child: const Text('Skip rest'),
                ),
              ] else ...[
                Text(
                  'Exercise ${_exerciseIndex + 1} of ${widget.workout.exercises.length}',
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
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('set-amount'),
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: _exercise.isTimed ? 'Seconds' : 'Reps',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        key: const Key('set-weight'),
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(labelText: 'Kg'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const Key('complete-set'),
                  onPressed: _completeSet,
                  icon: const Icon(Icons.check),
                  label: const Text('Complete set'),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    ),
  );
}
