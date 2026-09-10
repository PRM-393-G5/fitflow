import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_session.dart';

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
  Timer? _timer;

  Exercise get _exercise => widget.workout.exercises[_exerciseIndex];
  double get _progress => _completedSets / widget.workout.totalSets;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _completeSet() {
    setState(() {
      _completedSets++;
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
    final volume = widget.workout.exercises.fold<double>(
      0,
      (sum, item) => sum + item.weightKg * item.reps * item.sets,
    );
    await widget.controller.addSession(
      WorkoutSession(
        id: completedAt.microsecondsSinceEpoch.toString(),
        workoutId: widget.workout.id,
        workoutName: widget.workout.name,
        startedAt: _startedAt,
        completedAt: completedAt,
        completedSets: _completedSets,
        volumeKg: volume,
      ),
    );
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
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
                Text(
                  _exercise.isTimed
                      ? '${_exercise.durationSeconds} seconds'
                      : '${_exercise.reps} reps',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall,
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
