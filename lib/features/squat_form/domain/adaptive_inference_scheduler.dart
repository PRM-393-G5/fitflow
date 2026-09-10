import 'dart:math' as math;

enum SquatPerformanceMode { auto, performance, balanced, quality }

class AdaptiveInferenceScheduler {
  AdaptiveInferenceScheduler({
    this.mode = SquatPerformanceMode.auto,
    this.minHz = 12,
    this.maxHz = 20,
    this.latencyAlpha = .2,
  });

  SquatPerformanceMode mode;
  final double minHz;
  final double maxHz;
  final double latencyAlpha;
  double? _latencyMs;
  int _lastStartUs = -1000000;

  double get latencyMs => _latencyMs ?? 0;
  double get targetHz {
    if (mode == SquatPerformanceMode.performance) return minHz;
    if (mode == SquatPerformanceMode.balanced) return 15;
    if (mode == SquatPerformanceMode.quality) return maxHz;
    final latency = _latencyMs ?? 55;
    // Leave headroom for camera/UI work instead of saturating the ML thread.
    return (1000 / math.max(50, latency * 1.45)).clamp(minHz, maxHz);
  }

  bool shouldStart(int nowUs) => nowUs - _lastStartUs >= 1000000 / targetHz;

  void markStarted(int nowUs) => _lastStartUs = nowUs;

  void recordLatency(Duration elapsed) {
    final sample = elapsed.inMicroseconds / 1000;
    _latencyMs = _latencyMs == null
        ? sample
        : _latencyMs! + latencyAlpha * (sample - _latencyMs!);
  }

  void reset() {
    _latencyMs = null;
    _lastStartUs = -1000000;
  }
}
