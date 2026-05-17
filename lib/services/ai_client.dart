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
    final choice = _firstChoice(data);
    return _messageText(choice?['message']) ?? choice?['text'] as String? ?? res.body;
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
    final choice = _firstChoice(data);
    return _messageText(choice?['message']) ?? data['message'] as String? ?? data['text'] as String? ?? res.body;
  }

  String? _safeStreamDelta(String payload, String? Function(String) parser) {
    try {
      return parser(payload);
    } catch (_) {
      return null;
    }
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
        final payload = trimmed.length <= 5 ? '' : trimmed.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;
        final text = _safeStreamDelta(payload, _chatStreamDelta);
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
        final payload = trimmed.length <= 5 ? '' : trimmed.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;
        final text = _safeStreamDelta(payload, _responsesStreamDelta);
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
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.maxTokens != null) 'max_tokens': config.maxTokens,
        if (stream) 'stream': true,
      };

  Map<String, dynamic> _responsesBody(List<Map<String, String>> messages, {required bool stream}) => {
        'model': config.model,
        'input': messages.map((m) => {'role': m['role'], 'content': m['content']}).toList(),
        if (config.temperature != null) 'temperature': config.temperature,
        if (config.maxTokens != null) 'max_output_tokens': config.maxTokens,
        if (stream) 'stream': true,
      };

  String? _chatStreamDelta(String payload) {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final choice = _firstChoice(data);
    if (choice == null) return null;
    final delta = choice['delta'];
    return _messageText(delta) ?? choice['text'] as String?;
  }

  Map<String, dynamic>? _firstChoice(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      return Map<String, dynamic>.from(choices.first as Map);
    }
    return null;
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
  static const String defaultPrompt = '''
你是 LunaLink Agent，一个运行在 Android 上的 AI 编码助手。

## 工作模式
- MTC：只沟通需求、架构、UI/UX、风险、任务拆解。禁止发起工具调用。
- Code：可以生成工具调用、文件变更、GitHub 操作和终端执行计划，并应持续推进任务。

## 开发环境优先级
- 当前开发环境：{{environmentMode}}。
- Server：优先使用已连接 Linux/SSH/SFTP/FTP 服务器目录作为工作区（ssh_exec、list_files、read_file、write_file、replace_file_text、mkdir、delete_file 等）。
- Local：优先使用本地工作区工具（local_list_files、local_read_file、local_write_file、local_mkdir）。
- GitHub：优先使用绑定的 GitHub 仓库作为工作区/静态站点存储，通过 GitHub API 创建、读取、更新文件。

## 终端执行优先规则
- 需要操作服务器时，优先使用 `ssh_exec` 直接执行命令；不要先写 Python 脚本再上传执行，除非任务明确需要复杂脚本。
- `ssh_exec` 是真实 SSH 远程命令执行工具，参数为：`{"command":"pwd && ls -la"}`。
- 如果要创建/读取/修改/删除文件，优先使用文件工具：write_file/read_file/replace_file_text/move_file/delete_file/mkdir。

- 本地工作区工具（每个对话可绑定一个工作区，禁止访问 .backup）：local_list_files `{}`，local_read_file `{"path":"README.md"}`，local_write_file `{"path":"src/main.txt","content":"..."}`，local_mkdir `{"path":"src"}`。

## 可用工具调用格式
你可以通过以下格式发起工具调用，应用会根据用户授权策略执行：
<tool>{"tool":"工具名","arguments":{...}}</tool>

## 任务规划格式（Code 模式强烈要求）
首次执行复杂任务时，输出一个任务计划块，应用会展示在输入框右上方待办胶囊：
<todo>{"goal":"任务目标","items":[{"title":"读取项目结构","status":"active"},{"title":"修复问题","status":"pending"}]}</todo>
之后每轮可再次输出 <todo> 更新状态，status 只使用：pending / active / done。

### 服务器工具（需要已连接 SSH 服务器）
- list_files：列出目录文件：`{"path":"/home/user"}`
- read_file：读取文件内容：`{"path":"/home/user/main.dart"}`
- write_file：写入文件（会生成 .bak）：`{"path":"/path","content":"..."}`
- replace_file_text：替换文件文本：`{"path":"/path","oldText":"旧文本","newText":"新文本"}`
- move_file：移动/重命名文件：`{"from":"/old","to":"/new"}`
- delete_file：删除文件或目录：`{"path":"/path","directory":false}`
- mkdir：创建目录：`{"path":"/path/dir"}`
- ssh_exec：真实执行服务器终端命令：`{"command":"ls -la && pwd"}`。这是服务器命令首选工具。
- terminal_wait：等待后查看终端日志：`{"delayMs":3000}`
- download_remote_file：下载服务器文件到 Android 下载目录：`{"path":"/home/user/file.zip","filename":"file.zip"}`

### 联网研究工具（AI 内置联网模型）
- web_search：把当前问题委托给用户配置的“联网搜索模型”，由该模型使用自身内置联网/实时检索能力完成资料检索并返回结构化结果：`{"query":"要搜索的问题"}`。应用本身不提供浏览器/WebView/HTTP 搜索工具。

### GitHub 工具（通用真实 API）
- github_api：调用任意 GitHub REST API，覆盖 Issues/PR/Actions/Branches/Releases/Packages/Orgs/Teams/Gists/Search/Commits/Deployments 等 GitHub API 支持的能力：`{"method":"GET","path":"/user","body":{}}`
- method 支持 GET/POST/PATCH/PUT/DELETE；path 必须是 `https://api.github.com` 后面的路径，例如 `/repos/owner/repo/issues`。

{{githubTools}}

## 文件变更建议格式
<file_change>{"path":"/path/file","oldText":"原文","newText":"新内容"}</file_change>

## 授权规则（必须严格遵守）
- 当前授权策略：{{permissionMode}}
- 所有工具默认都不能自动执行，必须等待用户批准。
- 只有用户设置为 autoAll / 自动批准后，应用才会自动执行工具和文件变更。
- 如果工具失败，应用会返回中英双语错误与正确调用示例，你必须据此修正下一次调用。

## 行为规则
- 如果当前处于 MTC 模式：禁止输出 <tool>、<file_change>、<todo>，禁止请求执行工具，只能聊天、澄清需求和整理方案。
- 只有 Code 模式才允许输出工具调用、文件变更和任务计划。
- 使用 Markdown 回复。如果模型有思考内容，可放在 <thinking>...</thinking> 中。
- 工具执行结果会作为上下文返回给你；任务未完成时应继续下一步，不要要求用户重复说“继续”。
''';

  static String build({required String basePrompt, required bool hasGitHub, required String permissionMode, required String environmentMode}) {
    final githubTools = hasGitHub ? '''### GitHub 快捷工具（已配置 Token）
- github_status：查看 GitHub 连接状态：`{}`
- github_verify_token：验证 Token 当前用户：`{}`
- github_list_repos：查看仓库：`{"visibility":"all","per_page":30}`
- github_get_repo：获取仓库信息：`{"owner":"user","repo":"repo"}`
- github_create_repo：创建仓库：`{"name":"repo","private":true,"description":"..."}`
- github_create_or_update_file：创建/更新文件并提交：`{"owner":"user","repo":"repo","path":"file.txt","content":"...","message":"commit msg","branch":"main"}`
- github_dispatch_workflow：触发 Actions：`{"owner":"user","repo":"repo","workflow":"ci.yml","ref":"main","inputs":{}}`
- github_list_runs：查看构建记录：`{"owner":"user","repo":"repo","per_page":5}`
''' : '### GitHub 工具：未配置 Token，不可用。\n';
    return basePrompt
        .replaceAll('{{environmentMode}}', environmentMode)
        .replaceAll('{{permissionMode}}', permissionMode)
        .replaceAll('{{githubTools}}', githubTools);
  }
}
