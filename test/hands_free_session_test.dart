import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/hands_free_session.dart';
import 'package:prm/features/squat_form/domain/squat_analyzer.dart';

SquatAnalysis frame(int reps) => SquatAnalysis(
  phase: SquatPhase.standing,
  repetitions: reps,
  score: 100,
  cue: '',
  bodyVisible: true,
);

const curl1 = PlannedSet(
  exercise: FormExercise.curl,
  name: 'Dumbbell Curl',
  target: 3,
  restSeconds: 30,
  setNumber: 1,
  sets: 2,
);
const curl2 = PlannedSet(
  exercise: FormExercise.curl,
  name: 'Dumbbell Curl',
  target: 3,
  restSeconds: 30,
  setNumber: 2,
  sets: 2,
);
const dip1 = PlannedSet(
  exercise: FormExercise.dip,
  name: 'Bench Dip',
  target: 10,
  restSeconds: 0,
  setNumber: 1,
  sets: 1,
);

int s(double seconds) => (seconds * 1000000).round();

void main() {
  test('reaching the target ends the set and starts the rest', () {
    final session = HandsFreeSession([curl1, curl2]);
    expect(session.onFrame(frame(2), s(1)).setEnded, isFalse);
    final end = session.onFrame(frame(3), s(2));
    expect(end.setEnded, isTrue);
    expect(end.say, 'Xong set 1. Nghỉ 30 giây.');
    expect(session.stage, HandsFreeStage.resting);
    expect(session.counts, [3]);
    expect(session.restLeft(s(2)), 30);
    expect(session.restLeft(s(31.5)), 1);
    // Frames during the rest are ignored.
    expect(session.onFrame(frame(5), s(3)), same(HandsFreeStep.none));
  });

  test('the rest calls the last 10 seconds, then starts the next set', () {
    final session = HandsFreeSession([curl1, curl2])..onFrame(frame(3), s(0));
    expect(session.tick(s(15)).say, isNull);
    expect(session.tick(s(21)).say, 'Còn 10 giây. Chuẩn bị set 2.');
    expect(session.tick(s(22)).say, isNull);
    final next = session.tick(s(30));
    expect(next.nextSet, isTrue);
    expect(next.say, 'Set 2, bắt đầu.');
    expect(session.stage, HandsFreeStage.active);
    expect(session.current, curl2);
  });

  test('a new exercise is announced, and a zero rest goes straight on', () {
    final session = HandsFreeSession([curl2, dip1, curl1]);
    session.onFrame(frame(3), s(0));
    final next = session.skipRest();
    expect(next.nextSet, isTrue);
    expect(next.say, 'Bài tiếp theo: Bench Dip, 10 rep. Bắt đầu.');
    // The dip has no rest: its end starts the next set at once.
    final end = session.onFrame(frame(10), s(5));
    expect(end.setEnded, isTrue);
    expect(end.nextSet, isTrue);
    expect(
      end.say,
      'Xong set 1. Bài tiếp theo: Dumbbell Curl, 3 rep. Bắt đầu.',
    );
    expect(session.current, curl1);
  });

  test('stopping short ends the set after a while without a rep', () {
    final session = HandsFreeSession([curl1, curl2]);
    session.onFrame(frame(0), s(0));
    // Nothing counted yet: waiting for the user, never ends.
    expect(session.onFrame(frame(0), s(60)).setEnded, isFalse);
    session.onFrame(frame(2), s(61));
    expect(session.onFrame(frame(2), s(68)).setEnded, isFalse);
    expect(session.onFrame(frame(2), s(69)).setEnded, isTrue);
    expect(session.counts, [2]);
  });

  test('a plank ends at its target or shortly after the hold stops', () {
    const plank = PlannedSet(
      exercise: FormExercise.plank,
      name: 'Plank',
      target: 30,
      restSeconds: 20,
      setNumber: 1,
      sets: 2,
    );
    final short = HandsFreeSession([plank, plank]);
    short.onFrame(frame(12), s(12));
    expect(short.onFrame(frame(12), s(15.9)).setEnded, isFalse);
    expect(short.onFrame(frame(12), s(16)).setEnded, isTrue);
    final full = HandsFreeSession([plank, plank]);
    expect(full.onFrame(frame(30), s(30)).setEnded, isTrue);
  });

  test('the last set finishes the plan', () {
    final session = HandsFreeSession([curl2]);
    final end = session.onFrame(frame(3), s(3));
    expect(end.finished, isTrue);
    expect(end.say, 'Xong set 2. Hoàn thành!');
    expect(session.stage, HandsFreeStage.done);
  });

  test('done mid-set keeps what was counted; mid-rest keeps the sets', () {
    final active = HandsFreeSession([curl1, curl2]);
    active.onFrame(frame(2), s(1));
    final stop = active.stop(2);
    expect(stop.setEnded, isTrue);
    expect(stop.finished, isTrue);
    expect(active.counts, [2]);

    final empty = HandsFreeSession([curl1]);
    expect(empty.stop(0).setEnded, isFalse);
    expect(empty.counts, isEmpty);

    final resting = HandsFreeSession([curl1, curl2])..onFrame(frame(3), s(0));
    final done = resting.stop(0);
    expect(done.setEnded, isFalse);
    expect(done.finished, isTrue);
    expect(resting.counts, [3]);
  });
}
