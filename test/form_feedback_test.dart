import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/form_feedback.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

void main() {
  group('CueStabilizer', () {
    test('holds a cue before a non-urgent change', () {
      final cue = CueStabilizer(holdUs: 900000);
      expect(cue.update('Keep a steady pace', CueTone.info, 0), isTrue);
      expect(cue.update('Push up', CueTone.good, 300000), isFalse);
      expect(cue.cue, 'Keep a steady pace');
      expect(cue.update('Push up', CueTone.good, 900000), isTrue);
      expect(cue.cue, 'Push up');
    });

    test('a warning replaces a calm cue at once', () {
      final cue = CueStabilizer();
      cue.update('Keep a steady pace', CueTone.info, 0);
      expect(
        cue.update('Keep your heels on the floor', CueTone.warn, 10000),
        isTrue,
      );
      expect(cue.tone, CueTone.warn);
    });

    test('one warning does not flicker into another', () {
      final cue = CueStabilizer();
      cue.update('Keep your torso steady', CueTone.warn, 0);
      expect(
        cue.update('Spread your weight evenly', CueTone.warn, 100000),
        isFalse,
      );
      expect(cue.cue, 'Keep your torso steady');
    });
  });

  group('LiveFeedback', () {
    SquatAnalysis analysis({
      required bool visible,
      SquatPhase phase = SquatPhase.descending,
      String cue = 'Lower your chest more',
    }) => SquatAnalysis(
      phase: phase,
      repetitions: 2,
      score: visible ? 100 : 0,
      cue: cue,
      bodyVisible: visible,
    );

    test('holds the screen through a dropout the analyzer rides out', () {
      final feedback = LiveFeedback(timed: false);
      feedback.update(analysis(visible: true), 0);
      // 8 lost frames at 8 fps: a full second, still mid-rep.
      for (var frame = 1; frame <= 8; frame++) {
        final lost = analysis(
          visible: false,
          cue: 'Step back so your arms are in view',
        );
        expect(feedback.update(lost, frame * 125000).changed, isFalse);
      }
      expect(feedback.cue.cue, 'Lower your chest more');
    });

    test('a warning fixed while still held on screen is not said', () {
      final feedback = LiveFeedback(timed: false);
      SquatAnalysis at(String cue, CueTone tone) => SquatAnalysis(
        phase: SquatPhase.standing,
        repetitions: 1,
        score: 100,
        cue: cue,
        tone: tone,
        bodyVisible: true,
      );
      // The count is said; the warning half a second later must wait.
      feedback.update(at('Great rep!', CueTone.good), 0);
      expect(
        feedback
            .update(at('Keep your hips from sagging', CueTone.warn), 500000)
            .say,
        isNull,
      );
      // Fixed at once, but the stabilizer still shows the warning.
      final good = at('Great, hold it', CueTone.good);
      for (final us in [1600000, 1700000]) {
        expect(feedback.update(good, us).say, isNull);
      }
    });

    test('shows the loss once the analyzer gives up the rep', () {
      final feedback = LiveFeedback(timed: false);
      feedback.update(analysis(visible: true), 0);
      final gone = analysis(
        visible: false,
        phase: SquatPhase.findingBody,
        cue: 'Step back so your arms are in view',
      );
      expect(feedback.update(gone, 1200000).changed, isTrue);
      expect(feedback.cue.cue, 'Step back so your arms are in view');
    });
  });

  group('FormVoiceCoach', () {
    String? say(
      FormVoiceCoach coach, {
      int count = 0,
      bool timed = false,
      String cue = 'Keep a steady pace',
      CueTone tone = CueTone.info,
      String? tip,
      required int atMs,
    }) => coach.next(
      count: count,
      timed: timed,
      cue: cue,
      tone: tone,
      tip: tip,
      nowUs: atMs * 1000,
    );

    test('counts reps and carries the fix for the next one', () {
      final coach = FormVoiceCoach();
      expect(say(coach, count: 1, atMs: 0), '1');
      expect(
        say(
          coach,
          count: 2,
          cue: 'Next rep: go deeper',
          tip: 'go deeper',
          atMs: 3000,
        ),
        '2. go deeper',
      );
    });

    test('a next-rep tip is not repeated while resting at the top', () {
      final coach = FormVoiceCoach();
      expect(
        say(coach, count: 1, tip: 'keep your heels down', atMs: 0),
        '1. keep your heels down',
      );
      // Tips are info-toned (see betweenRepsCue), so never re-said alone.
      final tip = betweenRepsCue(
        const RepRecord(
          number: 1,
          descentMs: 0,
          ascentMs: 0,
          faults: ['heelsUp'],
        ),
      );
      expect(tip.tone, isNot(CueTone.warn));
      for (final atMs in [7000, 14000, 21000]) {
        expect(
          say(
            coach,
            count: 1,
            cue: tip.cue,
            tone: tip.tone,
            tip: tip.tip,
            atMs: atMs,
          ),
          isNull,
        );
      }
    });

    test('a real warning while resting after a faulty rep is said', () {
      final coach = FormVoiceCoach();
      say(
        coach,
        count: 1,
        tip: 'brace your core, keep your hips level',
        atMs: 0,
      );
      expect(
        say(
          coach,
          count: 1,
          cue: 'Keep your hips from sagging',
          tone: CueTone.warn,
          atMs: 2000,
        ),
        'Keep your hips from sagging',
      );
    });

    test('says a warning once, then waits before repeating it', () {
      final coach = FormVoiceCoach();
      const warn = 'Keep your heels on the floor';
      expect(say(coach, cue: warn, tone: CueTone.warn, atMs: 0), warn);
      expect(say(coach, cue: warn, tone: CueTone.warn, atMs: 2000), isNull);
      expect(say(coach, cue: warn, tone: CueTone.warn, atMs: 6500), warn);
    });

    test('never talks over itself except for a count', () {
      final coach = FormVoiceCoach();
      expect(
        say(coach, cue: 'Keep your torso steady', tone: CueTone.warn, atMs: 0),
        isNotNull,
      );
      expect(
        say(
          coach,
          cue: 'Spread your weight evenly',
          tone: CueTone.warn,
          atMs: 500,
        ),
        isNull,
      );
      expect(say(coach, count: 1, atMs: 600), '1');
    });

    test('stays quiet for calm and praising cues', () {
      final coach = FormVoiceCoach();
      expect(
        say(coach, cue: 'Great rep!', tone: CueTone.good, atMs: 0),
        isNull,
      );
      expect(say(coach, cue: 'Keep a steady pace', atMs: 2000), isNull);
    });

    test('announces a hold start and every 10 seconds', () {
      final coach = FormVoiceCoach();
      final said = [
        for (var second = 1; second <= 25; second++)
          say(coach, count: second, timed: true, atMs: second * 1000),
      ].nonNulls;
      expect(said, ['Timer started', '10 seconds', '20 seconds']);
    });
  });

  test('the AI coach reads press tempo as press up, then lower', () {
    const rep = RepRecord(
      number: 1,
      descentMs: 500,
      ascentMs: 2000,
      faults: [],
    );
    final press = AiFormReviewPrompt.user(
      exercise: FormExercise.shoulderPress.label,
      reps: const [rep],
    );
    expect(press, contains('"pressUpMs":500'));
    expect(press, contains('"lowerMs":2000'));
    expect(press, isNot(contains('descentMs')));
    final squat = AiFormReviewPrompt.user(
      exercise: FormExercise.squat.label,
      reps: const [rep],
    );
    expect(squat, contains('"descentMs":500'));
  });
}
