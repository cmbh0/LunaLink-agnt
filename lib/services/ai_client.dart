import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_models.dart';

class AiClient {
  final AiServiceConfig config;
  AiClient(this.config);

  Future<String> sendChat(List<Map<String, String>> messages) async {
    switch (config.provider) {
      case AiProviderType.openai:
      case AiProviderType.rest:
        return _openAiCompatible(messages);
      case AiProviderType.gemini:
        return _gemini(messages);
      case AiProviderType.claude:
        return _claude(messages);
    }
  }

  Future<String> _openAiCompatible(List<Map<String, String>> messages) async {
    final uri = Uri.parse(config.endpoint.endsWith('/chat/completions') ? config.endpoint : '${config.endpoint}/chat/completions');
    final res = await http.post(uri, headers: _headers(), body: jsonEncode({'model': config.model, 'messages': messages, 'temperature': 0.2}));
    _ensureOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['choices']?[0]?['message']?['content'] as String? ?? res.body;
  }

  Future<String> _gemini(List<Map<String, String>> messages) async {
    final text = messages.map((m) => '${m['role']}: ${m['content']}').join('\n');
    final base = config.endpoint.isEmpty ? 'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent' : config.endpoint;
    final uri = Uri.parse(base).replace(queryParameters: {'key': config.apiKey});
    final res = await http.post(uri, headers: {'Content-Type': 'application/json', ...config.headers}, body: jsonEncode({'contents': [{'parts': [{'text': text}]}]}));
    _ensureOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? res.body;
  }

  Future<String> _claude(List<Map<String, String>> messages) async {
    final uri = Uri.parse(config.endpoint.isEmpty ? 'https://api.anthropic.com/v1/messages' : config.endpoint);
    final system = messages.where((m) => m['role'] == 'system').map((m) => m['content']).join('\n');
    final msgs = messages.where((m) => m['role'] != 'system').map((m) => {'role': m['role'] == 'assistant' ? 'assistant' : 'user', 'content': m['content']}).toList();
    final res = await http.post(uri, headers: {'Content-Type': 'application/json', 'x-api-key': config.apiKey, 'anthropic-version': '2023-06-01', ...config.headers}, body: jsonEncode({'model': config.model, 'max_tokens': 4096, 'system': system, 'messages': msgs}));
    _ensureOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['content']?[0]?['text'] as String? ?? res.body;
  }

  Map<String, String> _headers() => {'Content-Type': 'application/json', if (config.apiKey.isNotEmpty) 'Authorization': 'Bearer ${config.apiKey}', ...config.headers};
  void _ensureOk(http.Response res) { if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('AI HTTP ${res.statusCode}: ${res.body}'); }
}

class AgentSystemPrompt {
  static const text = '''
你是 LunaLink Agent，工作方式对齐 Trae/Codex CLI。
你可以提出工具调用，但写文件、删除文件、执行终端命令必须等待用户授权。
你必须返回清晰的计划、风险、diff 摘要和可回滚记录。
可用工具语义参考：read_file/list_files/apply_file/delete_file/make_directory/grep_code/grep_context/ssh_exec/sftp_read/sftp_write。
文件修改优先生成结构化 FileChangeRecord，等待用户保存或拒绝。
''';
}