import 'package:flutter_tts/flutter_tts.dart';

/// Speaks form-check cues aloud.
abstract interface class FormVoice {
  Future<void> speak(String text);
  Future<void> stop();
}

/// Device text-to-speech in English. Fails silently: a phone without a
/// TTS engine or an English voice must never break the form check, and
/// reading English cues with another language's voice is worse than
/// silence.
class TtsFormVoice implements FormVoice {
  /// How long a failed setup waits before trying again. The Android engine
  /// may still be binding on a cold start, so one failure must not silence
  /// the whole session.
  static const retryAfter = Duration(seconds: 10);

  FlutterTts? _tts;
  Future<bool>? _ready;
  DateTime? _failedAt;

  /// Bumped by every speak and stop: a speak still awaiting setup when a
  /// newer speak or a stop arrives is dropped instead of talking late.
  int _generation = 0;

  Future<bool> _init() async {
    try {
      final tts = _tts ??= FlutterTts();
      if (await tts.isLanguageAvailable('en-US') != true) return false;
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(.55);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureReady() async {
    final failedAt = _failedAt;
    if (failedAt != null) {
      if (DateTime.now().difference(failedAt) < retryAfter) return false;
      _failedAt = null;
      _ready = null;
    }
    final ready = await (_ready ??= _init());
    if (!ready) _failedAt = DateTime.now();
    return ready;
  }

  @override
  Future<void> speak(String text) async {
    final generation = ++_generation;
    if (!await _ensureReady() || generation != _generation) return;
    try {
      // The newest cue matters most: cut off anything still being said
      // instead of queueing behind it (iOS queues by default).
      await _tts!.stop();
      if (generation != _generation) return;
      await _tts!.speak(text);
    } catch (_) {
      // A transient engine error drops this cue.
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
