import 'squat_analyzer.dart';

/// Keeps the live cue readable from across the room: a shown cue stays at
/// least [holdUs], so per-frame flicker never reaches the screen. A form
/// warning still replaces a non-warning at once — corrections can't wait.
class CueStabilizer {
  CueStabilizer({this.holdUs = 900000});

  final int holdUs;
  String? _cue;
  CueTone _tone = CueTone.info;
  int _shownUs = 0;

  String? get cue => _cue;
  CueTone get tone => _tone;

  /// Feeds the analyzer's cue for this frame; returns true when the shown
  /// cue changed.
  bool update(String cue, CueTone tone, int nowUs) {
    if (cue == _cue) {
      _tone = tone;
      return false;
    }
    final urgent = tone == CueTone.warn && _tone != CueTone.warn;
    if (_cue != null && !urgent && nowUs - _shownUs < holdUs) return false;
    _cue = cue;
    _tone = tone;
    _shownUs = nowUs;
    return true;
  }
}

/// Decides what to say aloud. The user is metres away mid-set, so speech
/// carries the essentials only: the rep count (with the fix for the next
/// rep when the last one was faulty), every 10 s of a hold, and form
/// warnings — each warning at most once per [repeatGapUs], and nothing
/// within [minGapUs] of the last utterance unless it is a count.
class FormVoiceCoach {
  FormVoiceCoach({this.minGapUs = 1500000, this.repeatGapUs = 6000000});

  final int minGapUs;
  final int repeatGapUs;
  int _count = 0;
  int? _lastUs;
  final _lastByText = <String, int>{};

  /// The utterance for this frame, or null. [cue] and [tone] are the cue
  /// on screen (after [CueStabilizer]), [tip] the analysis' `nextRepTip`.
  /// [analysisCue] is the analyzer's own cue, which the stabilizer may not
  /// show yet: a count that carries the tip covers it too.
  String? next({
    required int count,
    required bool timed,
    required String cue,
    required CueTone tone,
    String? tip,
    String? analysisCue,
    required int nowUs,
  }) {
    final previous = _count;
    _count = count;
    if (count > previous) {
      if (!timed) {
        if (analysisCue != null) _lastByText[analysisCue] = nowUs;
        return _say(tip == null ? '$count' : '$count. $tip', cue, nowUs);
      }
      if (previous == 0) return _say('Bắt đầu tính giờ', cue, nowUs);
      if (count ~/ 10 > previous ~/ 10) {
        return _say('${count ~/ 10 * 10} giây', cue, nowUs);
      }
    }
    // A next-rep tip is said once, with the count — not again while the
    // user rests at the top.
    if (tone != CueTone.warn || tip != null) return null;
    final lastUs = _lastUs;
    if (lastUs != null && nowUs - lastUs < minGapUs) return null;
    final saidUs = _lastByText[cue];
    if (saidUs != null && nowUs - saidUs < repeatGapUs) return null;
    return _say(cue, cue, nowUs);
  }

  String _say(String text, String cue, int nowUs) {
    _lastUs = nowUs;
    // Only entries within the repeat gap are ever read.
    _lastByText.removeWhere((_, saidUs) => nowUs - saidUs >= repeatGapUs);
    // What was on screen counts as said: a count that already carried the
    // tip must not be followed by the same tip again.
    _lastByText[cue] = nowUs;
    _lastByText[text] = nowUs;
    return text;
  }
}

/// The page's live feedback loop, one per exercise: filters detector
/// glitches, steadies the cue and picks what to say. Kept out of the
/// widget so tests replay exactly what the user sees and hears.
class LiveFeedback {
  LiveFeedback({required this.timed});

  /// Hold exercise (plank): speech marks time instead of counting reps.
  final bool timed;

  /// A body lost for less than this is a detector glitch, not the user
  /// leaving: the last analysis stays on screen instead of flashing
  /// "step back". Longer losses the analyzer itself still rides out (it
  /// keeps the phase, see `dropoutFrames`) are held too, at any frame rate.
  static const glitchUs = 600000;

  final cue = CueStabilizer();
  final _coach = FormVoiceCoach();
  SquatAnalysis? _shown;
  int? _visibleUs;

  /// The analysis on screen.
  SquatAnalysis? get shown => _shown;

  /// Feeds one analyzed frame. Returns whether the screen needs a rebuild
  /// and the utterance to speak, if any.
  ({bool changed, String? say}) update(SquatAnalysis analysis, int nowUs) {
    final shown = _shown;
    if (analysis.bodyVisible) {
      _visibleUs = nowUs;
    } else if (shown != null &&
        shown.bodyVisible &&
        analysis.repetitions == shown.repetitions &&
        (analysis.phase != SquatPhase.findingBody ||
            (_visibleUs != null && nowUs - _visibleUs! < glitchUs))) {
      return (changed: false, say: null);
    }
    final cueChanged = cue.update(analysis.cue, analysis.tone, nowUs);
    _shown = analysis;
    final say = _coach.next(
      count: analysis.repetitions,
      timed: timed,
      cue: cue.cue!,
      tone: cue.tone,
      tip: analysis.nextRepTip,
      analysisCue: analysis.cue,
      nowUs: nowUs,
    );
    final changed =
        shown == null ||
        cueChanged ||
        shown.phase != analysis.phase ||
        shown.repetitions != analysis.repetitions ||
        shown.bodyVisible != analysis.bodyVisible ||
        (shown.score - analysis.score).abs() >= 5;
    return (changed: changed, say: say);
  }
}
