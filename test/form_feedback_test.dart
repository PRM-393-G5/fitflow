import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/form_feedback.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

void main() {
  group('CueStabilizer', () {
    test('holds a cue before a non-urgent change', () {
      final cue = CueStabilizer(holdUs: 900000);
      expect(cue.update('Giữ nhịp đều', CueTone.info, 0), isTrue);
      expect(cue.update('Đẩy lên', CueTone.good, 300000), isFalse);
      expect(cue.cue, 'Giữ nhịp đều');
      expect(cue.update('Đẩy lên', CueTone.good, 900000), isTrue);
      expect(cue.cue, 'Đẩy lên');
    });

    test('a warning replaces a calm cue at once', () {
      final cue = CueStabilizer();
      cue.update('Giữ nhịp đều', CueTone.info, 0);
      expect(cue.update('Giữ gót chân chạm sàn', CueTone.warn, 10000), isTrue);
      expect(cue.tone, CueTone.warn);
    });

    test('one warning does not flicker into another', () {
      final cue = CueStabilizer();
      cue.update('Giữ thân ổn định', CueTone.warn, 0);
      expect(cue.update('Dồn đều lực hai chân', CueTone.warn, 100000), isFalse);
      expect(cue.cue, 'Giữ thân ổn định');
    });
  });

  group('LiveFeedback', () {
    SquatAnalysis analysis({
      required bool visible,
      SquatPhase phase = SquatPhase.descending,
      String cue = 'Hạ ngực thấp hơn',
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
        final lost = analysis(visible: false, cue: 'Lùi ra để thấy cánh tay');
        expect(feedback.update(lost, frame * 125000).changed, isFalse);
      }
      expect(feedback.cue.cue, 'Hạ ngực thấp hơn');
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
      feedback.update(at('Rep chuẩn!', CueTone.good), 0);
      expect(
        feedback.update(at('Đừng để hông xệ', CueTone.warn), 500000).say,
        isNull,
      );
      // Fixed at once, but the stabilizer still shows the warning.
      final good = at('Tốt lắm, giữ nguyên', CueTone.good);
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
        cue: 'Lùi ra để thấy cánh tay',
      );
      expect(feedback.update(gone, 1200000).changed, isTrue);
      expect(feedback.cue.cue, 'Lùi ra để thấy cánh tay');
    });
  });

  group('FormVoiceCoach', () {
    String? say(
      FormVoiceCoach coach, {
      int count = 0,
      bool timed = false,
      String cue = 'Giữ nhịp đều',
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
          cue: 'Rep sau: xuống sâu hơn',
          tip: 'xuống sâu hơn',
          atMs: 3000,
        ),
        '2. xuống sâu hơn',
      );
    });

    test('a next-rep tip is not repeated while resting at the top', () {
      final coach = FormVoiceCoach();
      expect(
        say(coach, count: 1, tip: 'giữ gót chạm sàn', atMs: 0),
        '1. giữ gót chạm sàn',
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
      say(coach, count: 1, tip: 'siết bụng, giữ hông thẳng', atMs: 0);
      expect(
        say(
          coach,
          count: 1,
          cue: 'Đừng để hông xệ',
          tone: CueTone.warn,
          atMs: 2000,
        ),
        'Đừng để hông xệ',
      );
    });

    test('says a warning once, then waits before repeating it', () {
      final coach = FormVoiceCoach();
      const warn = 'Giữ gót chân chạm sàn';
      expect(say(coach, cue: warn, tone: CueTone.warn, atMs: 0), warn);
      expect(say(coach, cue: warn, tone: CueTone.warn, atMs: 2000), isNull);
      expect(say(coach, cue: warn, tone: CueTone.warn, atMs: 6500), warn);
    });

    test('never talks over itself except for a count', () {
      final coach = FormVoiceCoach();
      expect(
        say(coach, cue: 'Giữ thân ổn định', tone: CueTone.warn, atMs: 0),
        isNotNull,
      );
      expect(
        say(coach, cue: 'Dồn đều lực hai chân', tone: CueTone.warn, atMs: 500),
        isNull,
      );
      expect(say(coach, count: 1, atMs: 600), '1');
    });

    test('stays quiet for calm and praising cues', () {
      final coach = FormVoiceCoach();
      expect(
        say(coach, cue: 'Rep chuẩn!', tone: CueTone.good, atMs: 0),
        isNull,
      );
      expect(say(coach, cue: 'Giữ nhịp đều', atMs: 2000), isNull);
    });

    test('announces a hold start and every 10 seconds', () {
      final coach = FormVoiceCoach();
      final said = [
        for (var second = 1; second <= 25; second++)
          say(coach, count: second, timed: true, atMs: second * 1000),
      ].nonNulls;
      expect(said, ['Bắt đầu tính giờ', '10 giây', '20 giây']);
    });
  });
}
