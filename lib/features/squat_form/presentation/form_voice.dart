import 'package:flutter_tts/flutter_tts.dart';

/// Speaks form-check cues aloud.
abstract interface class FormVoice {
  Future<void> speak(String text);
  Future<void> stop();
}

/// Device text-to-speech in Vietnamese. Fails silently: a phone without a
/// TTS engine or a Vietnamese voice must never break the form check, and
/// reading Vietnamese cues with another language's voice is worse than
/// silence.
class TtsFormVoice implements FormVoice {
  /// How long a failed setup waits before trying again. The Android engine
  /// may still be binding on a cold start, so one failure must not silence
  /// the whole session.
  static const retryAfter = Duration(seconds: 10);

  FlutterTts? _tts;
  Future<bool>? _ready;
  DateTime? _failedAt;

  Future<bool> _init() async {
    try {
      final tts = _tts ??= FlutterTts();
      if (await tts.isLanguageAvailable('vi-VN') != true) return false;
      await tts.setLanguage('vi-VN');
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
    if (!await _ensureReady()) return;
    try {
      // The newest cue matters most: cut off anything still being said
      // instead of queueing behind it (iOS queues by default).
      await _tts!.stop();
      await _tts!.speak(text);
    } catch (_) {
      // A transient engine error drops this cue.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
