import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api/api_client.dart';

/// Client for FitFlow's backend AI endpoints (`/api/ai/*`).
///
/// All OpenAI requests and the `OPENAI_API_KEY` secret live on the
/// `fitflow-api` NestJS server; the mobile app sends prompts/schemas (or
/// domain payloads) to the backend and receives validated JSON back.
/// Requests go through the app's [ApiClient], so they carry the signed-in
/// user's token (refreshed when it expires) and the server can tell who
/// used which AI feature.
class OpenAiService {
  const OpenAiService({this.api});

  /// The client to use; null means [defaultApi].
  final ApiClient? api;

  /// The app's shared client, set once in `main`; pages create
  /// `const OpenAiService()` and use it.
  static ApiClient? defaultApi;

  ApiClient? get _client => api ?? defaultApi;

  static const _dartDefineKey = String.fromEnvironment('OPENAI_API_KEY');
  static const _dartDefineApiUrl = String.fromEnvironment('API_BASE_URL');

  @visibleForTesting
  static bool? debugConfiguredOverride;

  /// Whole-request budget: reasoning + vision calls on the backend can take
  /// up to 90s before headers return.
  static const _timeout = Duration(seconds: 95);

  /// True once the app environment is initialized (or an explicit override
  /// is active). The actual OpenAI key is held by `fitflow-api`.
  static bool get configured =>
      debugConfiguredOverride ??
      (_dartDefineKey.isNotEmpty ||
          _dartDefineApiUrl.isNotEmpty ||
          dotenv.isInitialized);

  /// Sends a structured-output JSON generation request to `POST /api/ai/generate`
  /// on the FitFlow API backend. Throws [OpenAiException] on any failure.
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    required String schemaName,
    String? reasoningEffort,
    List<int>? imageBytes,
  }) => _postJson('ai/generate', {
    'system': system,
    'user': user,
    'schema': schema,
    'schemaName': schemaName,
    'reasoningEffort': ?reasoningEffort,
    if (imageBytes != null) ...{
      'imageBase64': base64Encode(imageBytes),
      'imageMimeType': _imageMime(imageBytes),
    },
  });

  /// Calls `POST /api/ai/workout-plan` on the backend.
  Future<Map<String, dynamic>> generateWorkoutPlan({
    required String request,
    String? level,
    int? durationMinutes,
    String? goal,
  }) => _postJson('ai/workout-plan', {
    'request': request,
    'level': ?level,
    'durationMinutes': ?durationMinutes,
    'goal': ?goal,
  });

  /// Calls `POST /api/ai/meal-plan` on the backend.
  Future<Map<String, dynamic>> generateMealPlan({
    required int targetKcal,
    required int proteinG,
    required int meals,
    String? goal,
    String? preferences,
  }) => _postJson('ai/meal-plan', {
    'targetKcal': targetKcal,
    'proteinG': proteinG,
    'meals': meals,
    'goal': ?goal,
    if (preferences != null && preferences.isNotEmpty)
      'preferences': preferences,
  });

  /// Calls `POST /api/ai/food-photo` on the backend.
  Future<Map<String, dynamic>> analyzeFoodPhoto(List<int> imageBytes) =>
      _postJson('ai/food-photo', {
        'imageBase64': base64Encode(imageBytes),
        'imageMimeType': _imageMime(imageBytes),
      });

  /// Calls `POST /api/ai/form-review` on the backend.
  Future<Map<String, dynamic>> reviewForm({
    required String exercise,
    required List<Map<String, dynamic>> reps,
  }) => _postJson('ai/form-review', {'exercise': exercise, 'reps': reps});

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final client = _client;
    if (!configured || client == null) {
      throw const OpenAiException('not-configured');
    }
    final dynamic decoded;
    try {
      decoded = await client.post(path, body: payload, timeout: _timeout);
    } on ApiException catch (e) {
      debugPrint('Backend AI ${e.statusCode}: ${e.message}');
      throw OpenAiException(errorCodeFor(e));
    } catch (e) {
      // e.g. secure storage failing to read the token.
      debugPrint('Backend AI unexpected: $e');
      throw const OpenAiException('invalid-response');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    throw const OpenAiException('invalid-response');
  }

  /// The [OpenAiException] code for a failed call: the backend's own code
  /// when it sent one, else one derived from the status.
  @visibleForTesting
  static String errorCodeFor(ApiException e) {
    if (e.isNetwork) return e.timedOut ? 'timeout' : 'offline';
    if (_backendCodes.contains(e.message)) return e.message;
    return switch (e.statusCode!) {
      // A success whose body could not be read.
      < 300 => 'invalid-response',
      // The session ended (or never started): only signing in helps.
      401 => 'signed-out',
      403 => 'unauthorized',
      429 => 'rate-limited',
      503 => 'not-configured',
      504 => 'timeout',
      >= 500 => 'server-error',
      final status => 'http-$status',
    };
  }

  static const _backendCodes = {
    'not-configured',
    'refused',
    'rate-limited',
    'unauthorized',
    'server-error',
    'too-long',
    'invalid-response',
    'timeout',
    'offline',
  };
}

/// Sniffs PNG/WebP magic bytes; everything else is sent as JPEG.
String _imageMime(List<int> bytes) {
  if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return 'image/png';
  }
  if (bytes.length > 12 && bytes[8] == 0x57 && bytes[9] == 0x45) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

class OpenAiException implements Exception {
  const OpenAiException(this.code);

  final String code;

  String get message => switch (code) {
    'not-configured' => 'OpenAI API key is not configured on the server.',
    'refused' => 'The AI declined that request — try rephrasing it.',
    'rate-limited' => 'Rate limit reached — try again later.',
    'unauthorized' => 'The OpenAI API key was rejected — check the key.',
    'server-error' => 'The AI service is having trouble — try again shortly.',
    'too-long' => 'The AI response was cut off — try a simpler request.',
    'invalid-response' => 'The AI returned an unexpected answer — try again.',
    'timeout' => 'Request timed out — try again.',
    'offline' => 'Could not reach the FitFlow API server.',
    'signed-out' => 'Your session has ended — sign in again to use AI.',
    _ => 'Could not generate ($code) — try again.',
  };

  @override
  String toString() => 'OpenAiException($code)';
}
