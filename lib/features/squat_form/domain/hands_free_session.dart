import 'squat_analyzer.dart';

/// One set for the camera to run hands-free.
class PlannedSet {
  const PlannedSet({
    required this.exercise,
    required this.name,
    required this.target,
    required this.restSeconds,
    required this.setNumber,
    required this.sets,
  });

  final FormExercise exercise;

  /// The plan's name for it ("Hammer Curl"), as the user knows it.
  final String name;

  /// Reps to do, or seconds to hold for a plank.
  final int target;

  /// Rest after this set before the next one.
  final int restSeconds;

  /// 1-based set number within its exercise, of [sets].
  final int setNumber;
  final int sets;

  bool get timed => exercise == FormExercise.plank;
}

enum HandsFreeStage { active, resting, done }

/// What the page does after a step: bank the set it just finished, start
/// a fresh analyzer for the next one, say something.
class HandsFreeStep {
  const HandsFreeStep({
    this.say,
    this.setEnded = false,
    this.nextSet = false,
    this.finished = false,
  });

  static const none = HandsFreeStep();

  final String? say;

  /// The set in progress is over: bank the analyzer's result now, before
  /// anything resets it.
  final bool setEnded;

  /// The next set starts: a fresh analyzer for [HandsFreeSession.current].
  final bool nextSet;

  /// Every planned set is done.
  final bool finished;
}

/// Runs a list of camera sets without a tap: a set ends when its target
/// is reached or the user stops (no new rep for a while), then a spoken
/// rest counts down and the next set starts, switching exercise when the
/// plan does. Pure logic, fed analyzed frames and clock ticks.
class HandsFreeSession {
  HandsFreeSession(this.plan) : assert(plan.isNotEmpty);

  final List<PlannedSet> plan;

  /// No new rep for this long after at least one ends the set early: the
  /// user stopped short of the target (or walked off to rest).
  static const idleEndUs = 8000000;

  /// A hold that stopped growing for this long is over.
  static const holdIdleEndUs = 4000000;

  /// Rests at least this long get a "10 seconds left" call.
  static const _warnRestSeconds = 20;

  int _index = 0;
  HandsFreeStage _stage = HandsFreeStage.active;
  int _lastCount = 0;
  int? _lastProgressUs;
  int? _restEndsUs;
  int? _pausedAtUs;
  bool _warned = false;

  /// Each finished set's count, in plan order.
  final counts = <int>[];

  HandsFreeStage get stage => _stage;
  int get index => _index;
  PlannedSet get current => plan[_index];

  /// The set after [current], if any.
  PlannedSet? get upcoming =>
      _index + 1 < plan.length ? plan[_index + 1] : null;

  /// Whole seconds of rest left (0 when not resting).
  int restLeft(int nowUs) {
    final ends = _restEndsUs;
    if (_stage != HandsFreeStage.resting || ends == null) return 0;
    final at = _pausedAtUs ?? nowUs;
    final left = ends - at;
    return left <= 0 ? 0 : (left + 999999) ~/ 1000000;
  }

  /// Freezes the idle and rest timers while the camera is paused or closed.
  void pause(int nowUs) {
    _pausedAtUs ??= nowUs;
  }

  /// Resumes after [pause], shifting the rest deadline by the time paused
  /// and giving the active set a fresh idle window to step back into frame.
  void resume(int nowUs) {
    final pausedAt = _pausedAtUs;
    if (pausedAt == null) return;
    _pausedAtUs = null;
    final gap = nowUs - pausedAt;
    if (gap > 0 && _restEndsUs != null) {
      _restEndsUs = _restEndsUs! + gap;
    }
    if (_lastProgressUs != null && nowUs > _lastProgressUs!) {
      _lastProgressUs = nowUs;
    }
  }

  /// Feeds one analyzed frame of the active set.
  HandsFreeStep onFrame(SquatAnalysis analysis, int nowUs) {
    resume(nowUs);
    if (_stage != HandsFreeStage.active) return HandsFreeStep.none;
    final count = analysis.repetitions;
    if (count > _lastCount) {
      _lastCount = count;
      _lastProgressUs = nowUs;
    }
    if (count >= current.target) return _endSet(nowUs);
    final last = _lastProgressUs;
    final idle = current.timed ? holdIdleEndUs : idleEndUs;
    if (count > 0 && last != null && nowUs - last >= idle) {
      return _endSet(nowUs);
    }
    return HandsFreeStep.none;
  }

  /// Ends the active set now (the user tapped done), keeping its count.
  /// Returns the step to bank it and wrap up; nothing after it runs.
  HandsFreeStep stop(int count) {
    if (_stage != HandsFreeStage.active) {
      _stage = HandsFreeStage.done;
      return const HandsFreeStep(finished: true);
    }
    _stage = HandsFreeStage.done;
    if (count > 0) counts.add(count);
    return HandsFreeStep(setEnded: count > 0, finished: true);
  }

  /// Advances the rest countdown.
  HandsFreeStep tick(int nowUs) {
    final ends = _restEndsUs;
    if (_stage != HandsFreeStage.resting || ends == null || _pausedAtUs != null) {
      return HandsFreeStep.none;
    }
    if (nowUs >= ends) return _startNext();
    if (!_warned &&
        current.restSeconds >= _warnRestSeconds &&
        ends - nowUs <= 10000000) {
      _warned = true;
      return HandsFreeStep(say: 'Còn 10 giây. ${_nextIntro()}');
    }
    return HandsFreeStep.none;
  }

  /// Cuts the rest short and starts the next set.
  HandsFreeStep skipRest() =>
      _stage == HandsFreeStage.resting ? _startNext() : HandsFreeStep.none;

  HandsFreeStep _endSet(int nowUs) {
    counts.add(_lastCount);
    final done = 'Xong set ${current.setNumber}';
    if (upcoming == null) {
      _stage = HandsFreeStage.done;
      return HandsFreeStep(
        say: '$done. Hoàn thành!',
        setEnded: true,
        finished: true,
      );
    }
    final rest = current.restSeconds;
    if (rest <= 0) {
      final next = _startNext();
      return HandsFreeStep(
        say: '$done. ${next.say}',
        setEnded: true,
        nextSet: true,
      );
    }
    _stage = HandsFreeStage.resting;
    _restEndsUs = nowUs + rest * 1000000;
    _warned = false;
    return HandsFreeStep(say: '$done. Nghỉ $rest giây.', setEnded: true);
  }

  HandsFreeStep _startNext() {
    final changed =
        upcoming!.exercise != current.exercise ||
        upcoming!.name != current.name;
    _index++;
    _stage = HandsFreeStage.active;
    _restEndsUs = null;
    _pausedAtUs = null;
    _lastCount = 0;
    _lastProgressUs = null;
    final set = current;
    final unit = set.timed ? 'giây' : 'rep';
    return HandsFreeStep(
      say: changed
          ? 'Bài tiếp theo: ${set.name}, ${set.target} $unit. Bắt đầu.'
          : 'Set ${set.setNumber}, bắt đầu.',
      nextSet: true,
    );
  }

  /// What comes after the rest, for the 10-second call.
  String _nextIntro() {
    final next = upcoming;
    if (next == null) return '';
    return next.exercise != current.exercise || next.name != current.name
        ? 'Tiếp theo: ${next.name}.'
        : 'Chuẩn bị set ${next.setNumber}.';
  }
}
