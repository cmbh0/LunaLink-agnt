import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_models.dart';

class AiClient {
  final AiServiceConfig config;
  AiClient(this.config);

  Uri get resolvedUri {
    final base = config.endpoint.trim();
    if (base.isEmpty) throw StateError('API Base URL 未填写');
    switch (config.apiMode) {
      case AiApiMode.openAiChat:
        return Uri.parse(base.endsWith('/chat/completions') ? base : '$base/chat/completions');
      case AiApiMode.responses:
        return Uri.parse(base.endsWith('/responses') ? base : '$base/responses');
      case AiApiMode.messages:
        return Uri.parse(base);
    }
  }

  Future<String> sendChat(List<Map<String, String>> messages) async {
    switch (config.apiMode) {
      case AiApiMode.openAiChat:
        return _openAiCompatible(messages);
      case AiApiMode.responses:
        return _openAiResponses(messages);
      case AiApiMode.messages:
        return _genericMessages(messages);
    }
  }

  Stream<String> streamChat(List<Map<String, String>> messages) async* {
    switch (config.apiMode) {
      case AiApiMode.openAiChat:
        yield* _streamChatCompletions(resolvedUri, messages);
        return;
      case AiApiMode.messages:
        yield* _streamChatCompletions(resolvedUri, messages);
        return;
      case AiApiMode.responses:
        yield* _streamResponses(resolvedUri, messages);
        return;
    }
  }

  Future<String> _openAiCompatible(List<Map<String, String>> messages) async {
    final res = await http
        .post(resolvedUri, headers: _headers(), body: jsonEncode(_chatBody(messages, stream: false)))
        .timeout(const Duration(seconds: 75));
    _ensureOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _messageText(data['choices']?[0]?['message']) ?? data['choices']?[0]?['text'] as String? ?? res.body;
  }

  Future<String> _openAiResponses(List<Map<String, String>> messages) async {
    final res = await http
        .post(resolvedUri, headers: _headers(), body: jsonEncode(_responsesBody(messages, stream: false)))
        .timeout(const Duration(seconds: 75));
    _ensureOk(res);
    return _responsesText(jsonDecode(res.body)) ?? res.body;
  }

  Future<String> _genericMessages(List<Map<String, String>> messages) async {
    final res = await http
        .post(resolvedUri, headers: _headers(), body: jsonEncode(_chatBody(messages, stream: false)))
        .timeout(const Duration(seconds: 75));
    _ensureOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _messageText(data['choices']?[0]?['message']) ?? data['message'] as String? ?? data['text'] as String? ?? res.body;
  }

  Stream<String> _streamChatCompletions(Uri uri, List<Map<String, String>> messages) async* {
    final client = http.Client();
    var emitted = false;
    try {
      final req = http.Request('POST', uri)
        ..headers.addAll(_headers())
        ..body = jsonEncode(_chatBody(messages, stream: true));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = await res.stream.bytesToString().timeout(const Duration(seconds: 12));
        throw StateError('AI HTTP ${res.statusCode}: $body');
      }
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 90), onTimeout: (sink) => sink.close());
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') break;
        final text = _chatStreamDelta(payload);
        if (text != null && text.isNotEmpty) {
          emitted = true;
          yield text;
        }
      }
      if (!emitted) throw StateError('AI 已连接，但没有返回任何可渲染内容。请检查接口模式、模型 ID 或服务端是否支持 SSE。');
    } finally {
      client.close();
    }
  }

  Stream<String> _streamResponses(Uri uri, List<Map<String, String>> messages) async* {
    final client = http.Client();
    var emitted = false;
    try {
      final req = http.Request('POST', uri)
        ..headers.addAll(_headers())
        ..body = jsonEncode(_responsesBody(messages, stream: true));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = await res.stream.bytesToString().timeout(const Duration(seconds: 12));
        throw StateError('AI HTTP ${res.statusCode}: $body');
      }
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 90), onTimeout: (sink) => sink.close());
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') break;
        final text = _responsesStreamDelta(payload);
        if (text != null && text.isNotEmpty) {
          emitted = true;
          yield text;
        }
      }
      if (!emitted) throw StateError('Responses SSE 未返回任何文本增量。请尝试关闭流式输出或切换为 OpenAI 兼容模式。');
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _chatBody(List<Map<String, String>> messages, {required bool stream}) => {
        'model': config.model,
        'messages': messages,
        'temperature': config.temperature,
        'max_tokens': config.maxTokens,
        if (stream) 'stream': true,
      };

  Map<String, dynamic> _responsesBody(List<Map<String, String>> messages, {required bool stream}) => {
        'model': config.model,
        'input': messages.map((m) => {'role': m['role'], 'content': m['content']}).toList(),
        'temperature': config.temperature,
        'max_output_tokens': config.maxTokens,
        if (stream) 'stream': true,
      };

  String? _chatStreamDelta(String payload) {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final delta = data['choices']?[0]?['delta'];
    return _messageText(delta) ?? data['choices']?[0]?['text'] as String?;
  }

  String? _responsesStreamDelta(String payload) {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final type = data['type']?.toString() ?? '';
    if (type == 'response.output_text.delta' || type == 'response.refusal.delta') return data['delta']?.toString();
    if (type == 'response.reasoning_summary_text.delta' || type == 'response.reasoning_text.delta') {
      final d = data['delta']?.toString();
      return d == null ? null : '<thinking>$d</thinking>';
    }
    return _responsesText(data);
  }

  String? _responsesText(dynamic decoded) {
    if (decoded is! Map) return null;
    final outputText = decoded['output_text'];
    if (outputText is String && outputText.isNotEmpty) return outputText;
    final output = decoded['output'];
    if (output is! List) return null;
    final parts = <String>[];
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is List) {
        for (final c in content) {
          if (c is Map) {
            final text = c['text'] ?? c['content'];
            if (text is String && text.isNotEmpty) parts.add(text);
          }
        }
      }
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  String? _messageText(dynamic message) {
    if (message is! Map) return null;
    final parts = <String>[];
    final reasoning = message['reasoning_content'] ?? message['reasoning'] ?? message['thinking'];
    if (reasoning is String && reasoning.isNotEmpty) parts.add('<thinking>$reasoning</thinking>');
    final content = message['content'];
    if (content is String) parts.add(content);
    if (content is List) {
      for (final c in content) {
        if (c is Map) {
          final text = c['text'] ?? c['content'];
          if (text is String) parts.add(text);
        }
      }
    }
    return parts.isEmpty ? null : parts.join('');
  }

  Future<List<String>> fetchModels() async {
    final base = config.endpoint.trim().replaceAll(RegExp(r'/(chat/completions|responses)\$'), '');
    if (base.isEmpty) throw StateError('API Base URL 未填写');
    final uri = Uri.parse(base.endsWith('/models') ? base : '$base/models');
    final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 30));
    _ensureOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = data['data'];
    if (raw is List) return raw.map((e) => e is Map ? e['id']?.toString() : e.toString()).whereType<String>().where((e) => e.isNotEmpty).toList();
    return const [];
  }

  Map<String, String> _headers() => {'Content-Type': 'application/json', if (config.apiKey.isNotEmpty) 'Authorization': 'Bearer ${config.apiKey}', ...config.headers};

  void _ensureOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('AI HTTP ${res.statusCode}: ${res.body}');
  }
}

class AgentSystemPrompt {
  static String build({required bool hasGitHub, required String permissionMode}) => '''
你是 LunaLink Agent，一个运行在 Android 上的 AI 编码助手。

## 工作模式
- MTC：只沟通需求、架构、UI/UX、风险、任务拆解。默认不发起工具调用。
- Code：可以生成工具调用、文件变更、GitHub 操作和终端执行计划。

## 可用工具
你可以通过以下格式发起工具调用，应用会根据用户授权策略执行：
<tool>{"tool":"工具名","arguments":{...}}</tool>

### 服务器工具（需要已连接 SSH 服务器）
- list_files：列出目录文件：`{"path":"/home/user"}`
- read_file：读取文件内容：`{"path":"/home/user/main.dart"}`
- write_file：写入文件（高风险，会生成 .bak）：`{"path":"/path","content":"..."}`
- ssh_exec：执行终端命令（高风险）：`{"command":"ls -la"}`

${hasGitHub ? '''### GitHub 工具（已配置 Token）
用户已知晓风险并授权你在批准策略范围内管理仓库。可用能力：
- github_get_repo：获取仓库信息：`{"owner":"user","repo":"repo"}`
- github_create_or_update_file：创建/更新文件并提交：`{"owner":"user","repo":"repo","path":"file.txt","content":"...","message":"commit msg","branch":"main"}`
- github_dispatch_workflow：触发 Actions 工作流：`{"owner":"user","repo":"repo","workflow":"ci.yml","ref":"main","inputs":{"build_mode":"release"}}`
- github_list_runs：查看构建记录：`{"owner":"user","repo":"repo","per_page":5}`
''' : '### GitHub 工具：未配置 Token，不可用。\n'}

## 文件变更
<file_change>{"path":"/path/file","oldText":"原文","newText":"新内容"}</file_change>

## 规则
- 当前授权策略：$permissionMode
- 写文件、执行命令、GitHub 写操作属于高风险操作，除非用户开启自动批准，否则只生成待批准卡片。
- 使用 Markdown 回复。
- 如果模型有思考内容，可放在 <thinking>...</thinking> 中。
- 返回清晰计划、风险、diff 摘要和可回滚说明。
''';
}
