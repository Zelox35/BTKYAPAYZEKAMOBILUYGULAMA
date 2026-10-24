import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class OllamaService {
  final http.Client _client = http.Client();

  Future<List<OllamaModel>> fetchModels(String baseUrl) async {
    final response = await _client
        .get(_endpoint(baseUrl, '/api/tags'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Sunucu HTTP ${response.statusCode} döndürdü.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['models'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((model) {
          final name = model['name'] as String?;
          if (name == null) return null;
          final capabilities = (model['capabilities'] as List<dynamic>? ?? [])
              .whereType<String>();
          return OllamaModel(
            name: name,
            supportsThinking: capabilities.contains('thinking'),
          );
        })
        .whereType<OllamaModel>()
        .toList();
  }

  Stream<OllamaChatDelta> chat({
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    required bool enableThinking,
  }) async* {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
    };
    if (enableThinking) body['think'] = true;

    final request = http.Request('POST', _endpoint(baseUrl, '/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      var detail = body;
      try {
        detail =
            (jsonDecode(body) as Map<String, dynamic>)['error'] as String? ??
            body;
      } catch (_) {}
      throw Exception('HTTP ${response.statusCode}: $detail');
    }

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(minutes: 3))) {
      if (line.trim().isEmpty) continue;
      final event = jsonDecode(line) as Map<String, dynamic>;
      if (event['error'] case final String error) {
        throw Exception(error);
      }
      final message = event['message'] as Map<String, dynamic>? ?? {};
      yield OllamaChatDelta(
        thinking: message['thinking'] as String? ?? '',
        content: message['content'] as String? ?? '',
        done: event['done'] as bool? ?? false,
      );
      if (event['done'] == true) break;
    }
  }

  void dispose() {
    _client.close();
  }

  Uri _endpoint(String baseUrl, String path) {
    final base = Uri.parse(baseUrl.trim());
    if ((base.scheme != 'http' && base.scheme != 'https') ||
        base.host.isEmpty) {
      throw const FormatException('Geçerli bir HTTP/HTTPS adresi girin.');
    }
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(path: '$basePath$path', query: null, fragment: null);
  }
}

class OllamaChatDelta {
  const OllamaChatDelta({
    required this.thinking,
    required this.content,
    required this.done,
  });

  final String thinking;
  final String content;
  final bool done;
}

class OllamaModel {
  const OllamaModel({required this.name, required this.supportsThinking});

  final String name;
  final bool supportsThinking;
}
