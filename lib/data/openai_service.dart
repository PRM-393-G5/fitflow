import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal OpenAI chat-completions client. The key comes from
/// `--dart-define=OPENAI_API_KEY=...` and ships inside the app binary —
/// pair it with a spending limit on the OpenAI dashboard.
class OpenAiService {
  const OpenAiService();

  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const _model = 'gpt-4o-mini';
  static const _timeout = Duration(seconds: 30);

  static bool get configured => _apiKey.isNotEmpty;

  /// Chat completions with strict JSON-schema output; returns the decoded
  /// response object. Throws [OpenAiException] on any failure.
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    required String schemaName,
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
          'model': _model,
          'temperature': 0.8,
          'max_tokens': 1500,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
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
