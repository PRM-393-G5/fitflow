import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Minimal OpenAI chat-completions client. The key comes from a bundled
/// `.env` (`OPENAI_API_KEY=...`, gitignored) or `--dart-define` — either
/// way it ships inside the app binary, so pair it with a spending limit
/// on the OpenAI dashboard.
class OpenAiService {
  const OpenAiService();

  static const _dartDefineKey = String.fromEnvironment('OPENAI_API_KEY');
  static String get _apiKey => _dartDefineKey.isNotEmpty
      ? _dartDefineKey
      : (dotenv.isInitialized ? dotenv.maybeGet('OPENAI_API_KEY') ?? '' : '');

  /// gpt-6-luna: reasoning model with vision + structured output — it
  /// rejects `temperature`, and reasoning tokens share the completion
  /// budget, so a low cap truncates the JSON mid-output (hence 8000).
  static const _model = 'gpt-6-luna';

  /// Whole-request budget: the reasoning model sends no headers until it
  /// has finished thinking, so a short per-step timeout trips spuriously.
  static const _timeout = Duration(seconds: 90);

  static bool get configured => _apiKey.isNotEmpty;

  /// Chat completions with strict JSON-schema output; returns the decoded
  /// response object. Throws [OpenAiException] on any failure.
  /// [imageBytes] attaches a JPEG photo; [reasoningEffort] tunes the
  /// model's thinking cost.
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    required String schemaName,
    String? reasoningEffort,
    List<int>? imageBytes,
  }) async {
    if (!configured) throw const OpenAiException('not-configured');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await _request(
        client,
        system: system,
        user: user,
        schema: schema,
        schemaName: schemaName,
        reasoningEffort: reasoningEffort,
        imageBytes: imageBytes,
      ).timeout(_timeout);
    } on OpenAiException {
      rethrow;
    } on TimeoutException {
      debugPrint('OpenAI timeout');
      throw const OpenAiException('timeout');
    } on SocketException catch (e) {
      debugPrint('OpenAI socket: $e');
      throw const OpenAiException('offline');
    } on HandshakeException catch (e) {
      debugPrint('OpenAI TLS: $e');
      throw const OpenAiException('offline');
    } on HttpException catch (e) {
      debugPrint('OpenAI http: $e');
      throw const OpenAiException('offline');
    } catch (e) {
      // FormatException on bad JSON, TypeError on unexpected shapes —
      // any other decode failure is an invalid response.
      debugPrint('OpenAI unexpected: $e');
      throw const OpenAiException('invalid-response');
    } finally {
      // force: abort an in-flight request on timeout instead of letting it
      // run (and bill) in the background.
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _request(
    HttpClient client, {
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    required String schemaName,
    String? reasoningEffort,
    List<int>? imageBytes,
  }) async {
    final request = await client.postUrl(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey')
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        'model': _model,
        'max_completion_tokens': 8000,
        'reasoning_effort': ?reasoningEffort,
        'messages': [
          {'role': 'system', 'content': system},
          {
            'role': 'user',
            'content': imageBytes == null
                ? user
                : [
                    {'type': 'text', 'text': user},
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url':
                            'data:${_imageMime(imageBytes)};base64,${base64Encode(imageBytes)}',
                      },
                    },
                  ],
          },
        ],
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': schemaName, 'strict': true, 'schema': schema},
        },
      }),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 429) {
      throw const OpenAiException('rate-limited');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const OpenAiException('unauthorized');
    }
    if (response.statusCode >= 500) {
      throw const OpenAiException('server-error');
    }
    if (response.statusCode != 200) {
      debugPrint(
        'OpenAI ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 400))}',
      );
      throw OpenAiException('http-${response.statusCode}');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    final choice = choices == null || choices.isEmpty
        ? null
        : choices.first as Map<String, dynamic>;
    if (choice?['finish_reason'] == 'length') {
      throw const OpenAiException('too-long');
    }
    final message = choice?['message'] as Map<String, dynamic>?;
    if (message?['refusal'] != null) {
      throw const OpenAiException('refused');
    }
    final raw = message?['content'];
    final content = raw is String
        ? raw
        : raw is List
        ? [
            for (final part in raw)
              if (part is Map && part['text'] is String) part['text'] as String,
          ].join()
        : null;
    if (content == null || content.isEmpty) {
      debugPrint(
        'OpenAI no content: ${body.substring(0, body.length.clamp(0, 500))}',
      );
      throw const OpenAiException('invalid-response');
    }
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } on FormatException {
      debugPrint(
        'OpenAI content not JSON: '
        '${content.substring(0, content.length.clamp(0, 500))}',
      );
      throw const OpenAiException('invalid-response');
    }
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
    'not-configured' => 'OpenAI API key is not configured.',
    'refused' => 'The AI declined that request — try rephrasing it.',
    'rate-limited' => 'Rate limit reached — try again later.',
    'unauthorized' => 'The OpenAI API key was rejected — check the key.',
    'server-error' => 'OpenAI is having trouble — try again shortly.',
    'too-long' => 'The AI response was cut off — try a simpler request.',
    'invalid-response' => 'The AI returned an unexpected answer — try again.',
    'timeout' => 'Request timed out — try again.',
    'offline' => 'No network connection.',
    _ => 'Could not generate ($code) — try again.',
  };

  @override
  String toString() => 'OpenAiException($code)';
}
