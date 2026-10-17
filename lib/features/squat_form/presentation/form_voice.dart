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
  FlutterTts? _tts;
  Future<bool>? _ready;

  Future<bool> _init() async {
    try {
      final tts = _tts = FlutterTts();
      if (await tts.isLanguageAvailable('vi-VN') != true) return false;
      await tts.setLanguage('vi-VN');
      await tts.setSpeechRate(.55);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String text) async {
    if (!await (_ready ??= _init())) return;
    try {
      // Flushes anything still being said: the newest cue matters most.
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
