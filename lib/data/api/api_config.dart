import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Where the FitFlow API (PRM-393-G5/fitflow-api) lives.
///
/// `--dart-define=API_BASE_URL=...` wins, then `API_BASE_URL` in the
/// bundled `.env`, then a local default: the Android emulator reaches the
/// host machine at 10.0.2.2, everything else at localhost.
class ApiConfig {
  const ApiConfig._();

  static const _dartDefine = String.fromEnvironment('API_BASE_URL');

  static Uri get baseUrl => resolve(
    dartDefine: _dartDefine,
    dotenvValue: dotenv.isInitialized ? dotenv.maybeGet('API_BASE_URL') : null,
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
  );

  @visibleForTesting
  static Uri resolve({
    required String dartDefine,
    required String? dotenvValue,
    required TargetPlatform platform,
    required bool isWeb,
  }) {
    final configured = dartDefine.isNotEmpty
        ? dartDefine
        : (dotenvValue?.trim().isNotEmpty ?? false)
        ? dotenvValue!.trim()
        : null;
    final raw =
        configured ??
        (!isWeb && platform == TargetPlatform.android
            ? 'http://10.0.2.2:3001/api'
            : 'http://localhost:3001/api');
    // Normalise to a trailing slash so relative paths resolve under /api/.
    return Uri.parse(raw.endsWith('/') ? raw : '$raw/');
  }
}
