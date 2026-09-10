import 'package:flutter_test/flutter_test.dart';
import 'package:prm/features/squat_form/domain/adaptive_inference_scheduler.dart';

void main() {
  test('never schedules outside 12-20 Hz', () {
    final scheduler = AdaptiveInferenceScheduler();
    scheduler.recordLatency(const Duration(milliseconds: 20));
    expect(scheduler.targetHz, 20);
    scheduler.recordLatency(const Duration(milliseconds: 300));
    for (var i = 0; i < 20; i++) {
      scheduler.recordLatency(const Duration(milliseconds: 300));
    }
    expect(scheduler.targetHz, 12);
  });

  test('uses monotonic timestamps to prevent a backlog', () {
    final scheduler = AdaptiveInferenceScheduler(
      mode: SquatPerformanceMode.quality,
    );
    expect(scheduler.shouldStart(0), isTrue);
    scheduler.markStarted(0);
    expect(scheduler.shouldStart(49000), isFalse);
    expect(scheduler.shouldStart(50000), isTrue);
  });

  test('fixed modes select their expected budgets', () {
    final scheduler = AdaptiveInferenceScheduler();
    scheduler.mode = SquatPerformanceMode.performance;
    expect(scheduler.targetHz, 12);
    scheduler.mode = SquatPerformanceMode.balanced;
    expect(scheduler.targetHz, 15);
    scheduler.mode = SquatPerformanceMode.quality;
    expect(scheduler.targetHz, 20);
  });
}
