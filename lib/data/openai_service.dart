import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api/api_config.dart';

/// Client for FitFlow's backend AI endpoints (`/api/ai/*`).
///
/// All OpenAI requests and the `OPENAI_API_KEY` secret live on the
/// `fitflow-api` NestJS server; the mobile app sends prompts/schemas (or
/// domain payloads) to the backend and receives validated JSON back.
class OpenAiService {
  const OpenAiService({this.baseUrl});

  final Uri? baseUrl;

  Uri get _resolvedBaseUrl => baseUrl ?? ApiConfig.baseUrl;

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

  /// Queries `GET /api/ai/status` on the backend to check whether the server
  /// has `OPENAI_API_KEY` configured.
  Future<bool> checkServerStatus() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(_resolvedBaseUrl.resolve('ai/status'));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> && decoded['configured'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

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
    if (!configured) throw const OpenAiException('not-configured');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await _request(
        client,
        uri: _resolvedBaseUrl.resolve(path),
        payload: payload,
      ).timeout(_timeout);
    } on OpenAiException {
      rethrow;
    } on TimeoutException {
      debugPrint('Backend AI timeout');
      throw const OpenAiException('timeout');
    } on SocketException catch (e) {
      debugPrint('Backend AI socket: $e');
      throw const OpenAiException('offline');
    } on HandshakeException catch (e) {
      debugPrint('Backend AI TLS: $e');
      throw const OpenAiException('offline');
    } on HttpException catch (e) {
      debugPrint('Backend AI http: $e');
      throw const OpenAiException('offline');
    } catch (e) {
      debugPrint('Backend AI unexpected: $e');
      throw const OpenAiException('invalid-response');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _request(
    HttpClient client, {
    required Uri uri,
    required Map<String, dynamic> payload,
  }) async {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      final code = _extractErrorCode(body, response.statusCode);
      throw OpenAiException(code);
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const OpenAiException('invalid-response');
    } on FormatException {
      throw const OpenAiException('invalid-response');
    }
  }

  String _extractErrorCode(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'];
        if (msg is String && msg.isNotEmpty) {
          if (const {
            'not-configured',
            'refused',
            'rate-limited',
            'unauthorized',
            'server-error',
            'too-long',
            'invalid-response',
            'timeout',
            'offline',
          }.contains(msg)) {
            return msg;
          }
        }
      }
    } catch (_) {
      // Fall through to status-code mapping.
    }
    if (statusCode == 429) return 'rate-limited';
    if (statusCode == 503) return 'not-configured';
    if (statusCode == 504) return 'timeout';
    if (statusCode == 401 || statusCode == 403) return 'unauthorized';
    if (statusCode >= 500) return 'server-error';
    return 'http-$statusCode';
  }
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
    _ => 'Could not generate ($code) — try again.',
  };

  @override
  String toString() => 'OpenAiException($code)';
}
