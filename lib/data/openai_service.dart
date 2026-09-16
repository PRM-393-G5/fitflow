import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  static const _model = 'gpt-4o-mini';

  /// Vision + reasoning model used for photo analysis. Rejects
  /// `temperature` — omit it when calling with this model.
  static const visionModel = 'gpt-6-luna';
  static const _timeout = Duration(seconds: 30);

  static bool get configured => _apiKey.isNotEmpty;

  /// Chat completions with strict JSON-schema output; returns the decoded
  /// response object. Throws [OpenAiException] on any failure.
  /// [imageBytes] attaches a JPEG photo for vision-capable models.
  /// Reasoning models (e.g. gpt-6-luna) reject `temperature` — pass
  /// `null` to omit it, and [reasoningEffort] to control thinking cost.
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    required String schemaName,
    String? model,
    double? temperature = 0.8,
    String? reasoningEffort,
    List<int>? imageBytes,
    int maxTokens = 1500,
  }) async {
    if (!configured) throw const OpenAiException('not-configured');
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'))
          .timeout(_timeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey')
        ..set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(
        jsonEncode({
          'model': model ?? _model,
          'max_completion_tokens': maxTokens,
          'temperature': ?temperature,
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
                              'data:image/jpeg;base64,${base64Encode(imageBytes)}',
                        },
                      },
                    ],
            },
          ],
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': schemaName,
              'strict': true,
              'schema': schema,
            },
          },
        }),
      );
      final response = await request.close().timeout(_timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      if (response.statusCode == 429) {
        throw const OpenAiException('rate-limited');
      }
      if (response.statusCode != 200) {
        throw OpenAiException('http-${response.statusCode}');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List?;
      final message = choices == null || choices.isEmpty
          ? null
          : choices.first['message'] as Map<String, dynamic>?;
      if (message?['refusal'] != null) {
        throw const OpenAiException('refused');
      }
      final content = message?['content'] as String?;
      if (content == null) throw const OpenAiException('invalid-response');
      return jsonDecode(content) as Map<String, dynamic>;
    } on OpenAiException {
      rethrow;
    } on TimeoutException {
      throw const OpenAiException('timeout');
    } on SocketException {
      throw const OpenAiException('offline');
    } on FormatException {
      throw const OpenAiException('invalid-response');
    } finally {
      client.close();
    }
  }
}

class OpenAiException implements Exception {
  const OpenAiException(this.code);

  final String code;

  String get message => switch (code) {
    'not-configured' => 'OpenAI API key is not configured.',
    'refused' => 'The AI declined that request — try rephrasing it.',
    'rate-limited' => 'Rate limit reached — try again later.',
    'timeout' => 'Request timed out — try again.',
    'offline' => 'No network connection.',
    _ => 'Could not generate — try again.',
  };

  @override
  String toString() => 'OpenAiException($code)';
}
