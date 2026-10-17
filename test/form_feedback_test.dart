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
          tone: CueTone.warn,
          tip: 'xuống sâu hơn',
          atMs: 3000,
        ),
        '2. xuống sâu hơn',
      );
      // The tip was just said with the count; the cue isn't repeated.
      expect(
        say(
          coach,
          count: 2,
          cue: 'Rep sau: xuống sâu hơn',
          tone: CueTone.warn,
          atMs: 5000,
        ),
        isNull,
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
