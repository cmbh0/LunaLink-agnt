import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/ai_models.dart';
import '../models/server_models.dart';
import 'ai_client.dart';
import 'json_txt_store.dart';
import 'ssh_service.dart';

class AppState extends ChangeNotifier {
  final ssh = SshService();
  final store = JsonTxtStore();
  late final ChangeJournal journal = ChangeJournal(store);
  final servers = <ServerProfile>[];
  final aiConfigs = <AiServiceConfig>[];
  final messages = <AgentMessage>[];
  final conversations = <ConversationMeta>[];
  final terminalLogs = <String>['LunaLink SSH Terminal ready.'];
  GitHubConfig github = const GitHubConfig();
  String? activeServerId;
  bool autoReconnect = false;
  bool generationActive = false;
  bool cancelRequested = false;
  String? activeAssistantMessageId;
  AgentMode agentMode = AgentMode.mtc;
  ServerInfo? serverInfo;
  String currentPath = '/';
  List<RemoteFileEntry> files = [];
  bool busy = false;
  String conversationId = 'default_conversation';
  ToolPermissionMode permissionMode = ToolPermissionMode.askEveryTime;
  String? selectedAiConfigId;

  AppState() {
    aiConfigs.add(const AiServiceConfig(
      id: 'default-openai',
      name: 'OpenAI Compatible',
      provider: AiProviderType.openai,
      endpoint: 'https://api.openai.com/v1',
      apiKey: '',
      model: 'gpt-4.1',
      thinkingModel: null,
    ));
  }

  Future<void> loadPersistedState() async {
    final convDoc = await store.readMap('memory', 'conversations', fallback: {'items': <dynamic>[]});
    conversations
      ..clear()
      ..addAll((convDoc['items'] as List? ?? []).whereType<Map>().map((e) => ConversationMeta.fromJson(Map<String, dynamic>.from(e))));
    if (conversations.isEmpty) {
      conversations.add(ConversationMeta(id: conversationId, title: '默认话题', updatedAt: DateTime.now()));
      await _saveConversations();
    }
    final serverDoc = await store.readMap('profiles', 'servers', fallback: {'items': <dynamic>[]});
    servers
      ..clear()
      ..addAll((serverDoc['items'] as List? ?? []).whereType<Map>().map((e) => ServerProfile.fromJson(Map<String, dynamic>.from(e))));
    activeServerId = serverDoc['activeServerId'] as String?;
    autoReconnect = serverDoc['autoReconnect'] as bool? ?? false;
    final savedConversationId = convDoc['activeConversationId'] as String?;
    if (savedConversationId != null && conversations.any((e) => e.id == savedConversationId)) {
      conversationId = savedConversationId;
    } else if (conversations.isNotEmpty) {
      conversationId = conversations.first.id;
    }
    await _loadConversationMessages(conversationId);
    final githubDoc = await store.readMap('profiles', 'github', fallback: const {});
    github = GitHubConfig.fromJson(githubDoc);
    final activeAiDoc = await store.readMap('profiles', 'active_ai', fallback: const {});
    selectedAiConfigId = activeAiDoc['id'] as String?;
    final aiDoc = await store.readMap('profiles', 'ai_services', fallback: {'items': <dynamic>[]});
    final aiItems = aiDoc['items'] as List? ?? [];
    if (aiItems.isNotEmpty) {
      aiConfigs
        ..clear()
        ..addAll(aiItems.whereType<Map>().map((e) => AiServiceConfig.fromJson(Map<String, dynamic>.from(e))));
    }
    notifyListeners();
    if (autoReconnect && activeServerId != null && servers.any((e) => e.id == activeServerId)) {
      Future.microtask(() => connect(servers.firstWhere((e) => e.id == activeServerId!), persistAutoReconnect: true));
    }
  }

  Future<void> setAgentMode(AgentMode mode) async {
    agentMode = mode;
    notifyListeners();
  }

  Future<void> newConversation() async {
    conversationId = const Uuid().v4();
    messages.clear();
    conversations.insert(0, ConversationMeta(id: conversationId, title: '新话题 ${conversations.length + 1}', updatedAt: DateTime.now()));
    await _saveConversations();
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    final index = conversations.indexWhere((e) => e.id == id);
    if (index < 0) return;
    conversations.removeAt(index);
    await store.deleteFile('memory', id);
    if (conversationId == id) {
      if (conversations.isEmpty) {
        await newConversation();
        return;
      }
      conversationId = conversations.first.id;
      messages.clear();
    }
    await _saveConversations();
    notifyListeners();
  }

  Future<void> pinConversation(String id) async {
    final index = conversations.indexWhere((e) => e.id == id);
    if (index <= 0) return;
    final item = conversations.removeAt(index);
    conversations.insert(0, item);
    await _saveConversations();
    notifyListeners();
  }

  Future<void> moveConversationUp(String id) async {
    final index = conversations.indexWhere((e) => e.id == id);
    if (index <= 0) return;
    final item = conversations.removeAt(index);
    conversations.insert(index - 1, item);
    await _saveConversations();
    notifyListeners();
  }

  Future<void> switchConversation(String id) async {
    conversationId = id;
    await store.writeMap('memory', 'conversations', {'items': conversations.map((e) => e.toJson()).toList(), 'activeConversationId': conversationId});
    await _loadConversationMessages(id);
    notifyListeners();
  }

  Future<void> _saveConversations() => store.writeMap('memory', 'conversations', {'items': conversations.map((e) => e.toJson()).toList(), 'activeConversationId': conversationId});

  Future<void> _loadConversationMessages(String id) async {
    final doc = await store.readMap('memory', id, fallback: {'events': <dynamic>[]});
    messages
      ..clear()
      ..addAll((doc['events'] as List? ?? []).whereType<Map>().where((e) => e['type'] == 'message').map((e) => AgentMessage(
            id: e['id'] as String? ?? const Uuid().v4(),
            role: e['role'] as String? ?? 'assistant',
            content: e['content'] as String? ?? '',
            createdAt: DateTime.tryParse(e['at'] as String? ?? '') ?? DateTime.now(),
            thinking: e['thinking'] as String?,
            modelLabel: e['modelLabel'] as String?,
          )));
  }

  Future<void> saveGitHubConfig(GitHubConfig config) async {
    github = config;
    await store.writeMap('profiles', 'github', config.toJson());
    notifyListeners();
  }

  Future<void> switchServer(String id) async {
    final profile = servers.firstWhere((e) => e.id == id);
    await connect(profile);
  }

  Future<T> withReconnect<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      if (!autoReconnect || activeServerId == null) rethrow;
      final matches = servers.where((e) => e.id == activeServerId).toList();
      if (matches.isEmpty) rethrow;
      final profile = matches.first;
      await ssh.connect(profile);
      return action();
    }
  }

  Future<void> connect(ServerProfile profile, {bool? persistAutoReconnect}) async {
    busy = true;
    notifyListeners();
    try {
      await ssh.connect(profile);
      activeServerId = profile.id;
      if (persistAutoReconnect != null) autoReconnect = persistAutoReconnect;
      serverInfo = await ssh.readInfo();
      currentPath = profile.rootPath;
      files = await ssh.listDir(currentPath);
      final index = servers.indexWhere((e) => e.id == profile.id);
      if (index >= 0) { servers[index] = profile; } else { servers.add(profile); }
      await _saveServers();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setAutoReconnect(bool value) async {
    autoReconnect = value;
    await _saveServers();
    notifyListeners();
  }

  Future<void> disconnectServer() async {
    autoReconnect = false;
    activeServerId = null;
    serverInfo = null;
    files = [];
    await _saveServers();
    notifyListeners();
  }

  Future<void> _saveServers() => store.writeMap('profiles', 'servers', {'items': servers.map((e) => e.toJson()).toList(), 'activeServerId': activeServerId, 'autoReconnect': autoReconnect});

  Future<void> openDir(String path) async {
    busy = true;
    notifyListeners();
    try {
      currentPath = _normalizeRemote(path);
      files = await ssh.listDir(currentPath);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshFiles() => openDir(currentPath);

  Future<void> createRemoteFile(String name, {bool directory = false}) async {
    final target = _joinRemote(currentPath, name);
    if (directory) {
      await ssh.mkdir(target);
    } else {
      await ssh.writeFile(target, utf8.encode(''));
    }
    await refreshFiles();
  }

  Future<void> renameRemote(RemoteFileEntry entry, String newName) async {
    await ssh.rename(entry.path, _joinRemote(_parentRemote(entry.path), newName));
    await refreshFiles();
  }

  Future<void> uploadLocalFile(String localPath) async {
    final file = File(localPath);
    final target = _joinRemote(currentPath, p.basename(localPath));
    await ssh.writeFile(target, await file.readAsBytes());
    await refreshFiles();
  }

  Future<File> downloadRemoteFile(RemoteFileEntry entry, Directory dir) async {
    final out = File(p.join(dir.path, entry.name));
    await out.writeAsBytes(await ssh.readFile(entry.path));
    return out;
  }
Future<void> runTerminalCommand(String command) async {
    terminalLogs.add('\$ $command');
    notifyListeners();
    final id = const Uuid().v4();
    addAssistantMessage('执行终端命令：`$command`', toolCalls: [ToolCallRecord(id: id, tool: 'ssh_exec', arguments: {'command': command}, status: 'running')]);
    await executeTool(id);
  }

  void clearTerminalLogs() {
    terminalLogs.clear();
    terminalLogs.add('LunaLink SSH Terminal ready.');
    notifyListeners();
  }


  Future<void> deleteRemote(RemoteFileEntry entry) async {
    await ssh.delete(entry.path, directory: entry.isDirectory);
    await refreshFiles();
  }

  Future<void> duplicateRemote(RemoteFileEntry entry, String newName) async {
    if (entry.isDirectory) throw StateError('暂不支持直接复制目录，请使用终端 cp -r。');
    final bytes = await ssh.readFile(entry.path);
    await ssh.writeFile(_joinRemote(_parentRemote(entry.path), newName), bytes);
    await refreshFiles();
  }

  Future<void> chmodRemote(RemoteFileEntry entry, String mode) async {
    await ssh.exec('chmod $mode ${_shellQuote(entry.path)}');
    await refreshFiles();
  }

  String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  Future<void> writeRemoteTextWithBackup(String path, String text) async {
    try {
      final old = await ssh.readFile(path);
      await ssh.writeFile('$path.bak', old);
    } catch (_) {}
    await ssh.writeFile(path, utf8.encode(text));
    await refreshFiles();
  }

  Future<void> restoreBackup(String backupPath) async {
    if (!backupPath.endsWith('.bak')) throw StateError('不是 .bak 备份文件');
    final target = backupPath.substring(0, backupPath.length - 4);
    final bytes = await ssh.readFile(backupPath);
    try {
      final old = await ssh.readFile(target);
      await ssh.writeFile('$target.bak.${DateTime.now().millisecondsSinceEpoch}', old);
    } catch (_) {}
    await ssh.writeFile(target, bytes);
    await refreshFiles();
  }

  void setPermissionMode(ToolPermissionMode mode) {
    permissionMode = mode;
    notifyListeners();
  }

  Future<void> sendAgentTask(String content) async {
    if (generationActive || busy) return;
    busy = true;
    generationActive = true;
    cancelRequested = false;
    notifyListeners();

    addUserMessage(content);
    final cfg = activeAiConfig;
    final modeGuide = agentMode == AgentMode.mtc
        ? '当前是 MTC 方案沟通模式：必须真实回复用户，专注需求澄清、架构方案、UI/UX 设计和风险评估；默认不要执行工具调用，除非用户明确要求查询。'
        : '当前是 Code 编码模式：可提出工具调用和文件变更建议。当前授权策略：${permissionMode.name}。';
    final prompt = '$modeGuide\n当前远程目录：$currentPath\n用户任务：$content';
    final modelLabel = '${cfg.name} · ${cfg.model}';
    final id = addAssistantMessage('', modelLabel: modelLabel);
    activeAssistantMessageId = id;

    try {
      if (cfg.endpoint.trim().isEmpty) throw StateError('未配置 API Base URL。请进入 AI 配置填写接口地址。');
      if (cfg.model.trim().isEmpty) throw StateError('未配置模型 ID。请进入 AI 配置填写模型名称。');
      if (cfg.apiKey.trim().isEmpty) throw StateError('未配置 API Key。请进入 AI 配置填写密钥。');

      final systemPrompt = AgentSystemPrompt.build(hasGitHub: github.isConnected, permissionMode: permissionMode.name);
      final req = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ];

      if (cfg.streamOutput) {
        var raw = '';
        var gotAnyChunk = false;
        await for (final chunk in AiClient(cfg).streamChat(req)) {
          gotAnyChunk = true;
          raw += chunk;
          final parsed = _extractThinkingStreaming(raw);
          updateAssistantMessage(id, parsed.$2, thinking: parsed.$1, modelLabel: modelLabel, persist: false);
          if (cancelRequested) break;
        }
        if (cancelRequested) {
          final parsed = _extractThinkingStreaming(raw);
          updateAssistantMessage(id, raw.isEmpty ? '已取消 AI 输出。' : '${parsed.$2}\n\n_已取消继续输出。_', thinking: parsed.$1, modelLabel: modelLabel);
        } else if (!gotAnyChunk || raw.trim().isEmpty) {
          updateAssistantMessage(id, 'AI 请求完成，但没有收到任何文本内容。请检查接口模式、模型 ID、流式输出兼容性，或关闭“流式输出”后重试。', modelLabel: modelLabel);
        } else {
          final parsed = _extractThinking(raw);
          await _materializeAgentOutput(id, parsed.$2, parsed.$1, modelLabel);
        }
      } else {
        final text = await AiClient(cfg).sendChat(req);
        if (cancelRequested) {
          updateAssistantMessage(id, '已取消 AI 输出。', modelLabel: modelLabel);
        } else if (text.trim().isEmpty) {
          updateAssistantMessage(id, 'AI 请求完成，但响应文本为空。请检查接口模式或模型返回格式。', modelLabel: modelLabel);
        } else {
          final parsed = _extractThinking(text);
          await _materializeAgentOutput(id, parsed.$2, parsed.$1, modelLabel);
        }
      }
    } catch (e) {
      updateAssistantMessage(id, 'AI 请求失败：\n\n```text\n$e\n```', modelLabel: modelLabel);
    } finally {
      busy = false;
      generationActive = false;
      cancelRequested = false;
      activeAssistantMessageId = null;
      notifyListeners();
      await _rewriteMemoryFromMessages();
    }
  }

  void cancelGeneration() {
    cancelRequested = true;
    notifyListeners();
  }

  Future<void> executeTool(String toolCallId) async {
    final found = _findTool(toolCallId);
    if (found == null) return;
    final call = found.$2;
    _replaceTool(toolCallId, ToolCallRecord(id: call.id, tool: call.tool, arguments: call.arguments, status: 'running', output: call.output));
    String output;
    try {
      switch (call.tool) {
        case 'ssh_exec':
          output = await ssh.exec(call.arguments['command'] as String? ?? '');
          terminalLogs.add(output.trim().isEmpty ? '[no output]' : output);
          break;
        case 'list_files':
          final path = call.arguments['path'] as String? ?? currentPath;
          final list = await ssh.listDir(path);
          output = list.map((e) => '${e.isDirectory ? 'd' : '-'} ${e.name} ${e.size}').join('\n');
          break;
        case 'read_file':
          final bytes = await ssh.readFile(call.arguments['path'] as String);
          output = utf8.decode(bytes, allowMalformed: true);
          break;
        case 'write_file':
          await writeRemoteTextWithBackup(call.arguments['path'] as String, call.arguments['content'] as String? ?? '');
          output = 'written with .bak backup';
          await refreshFiles();
          break;
        case 'github_get_repo':
          output = await _githubRequest('GET', '/repos/${call.arguments['owner']}/${call.arguments['repo']}');
          break;
        case 'github_create_or_update_file':
          output = await _githubCreateOrUpdateFile(
            owner: call.arguments['owner'] as String,
            repo: call.arguments['repo'] as String,
            path: call.arguments['path'] as String,
            content: call.arguments['content'] as String? ?? '',
            message: call.arguments['message'] as String? ?? 'Update file from LunaLink Agent',
            branch: call.arguments['branch'] as String? ?? 'main',
          );
          break;
        case 'github_dispatch_workflow':
          output = await _githubDispatchWorkflow(
            owner: call.arguments['owner'] as String,
            repo: call.arguments['repo'] as String,
            workflow: call.arguments['workflow'] as String? ?? 'flutter_android_ci.yml',
            ref: call.arguments['ref'] as String? ?? 'main',
            inputs: Map<String, dynamic>.from(call.arguments['inputs'] as Map? ?? {'build_mode': 'release'}),
          );
          break;
        case 'github_list_runs':
          output = await _githubRequest('GET', '/repos/${call.arguments['owner']}/${call.arguments['repo']}/actions/runs?per_page=${call.arguments['per_page'] ?? 5}');
          break;
        default:
          output = '未知工具：${call.tool}';
      }
      _replaceTool(toolCallId, ToolCallRecord(id: call.id, tool: call.tool, arguments: call.arguments, status: 'done', output: output));
      await journal.append(conversationId: conversationId, event: {'type': 'tool', 'tool': call.tool, 'args': call.arguments, 'output': output});
    } catch (e) {
      _replaceTool(toolCallId, ToolCallRecord(id: call.id, tool: call.tool, arguments: call.arguments, status: 'error', output: '$e'));
      if (call.tool == 'ssh_exec') terminalLogs.add('ERROR: $e');
    }
  }

  Future<void> rejectTool(String toolCallId) async {
    final found = _findTool(toolCallId);
    if (found == null) return;
    final c = found.$2;
    _replaceTool(toolCallId, ToolCallRecord(id: c.id, tool: c.tool, arguments: c.arguments, status: 'rejected', output: '用户已拒绝'));
  }

  Future<void> applyChange(String changeId) async {
    final found = _findChange(changeId);
    if (found == null) return;
    final c = found.$2;
    await writeRemoteTextWithBackup(c.path, c.newText);
    _replaceChange(changeId, FileChangeRecord(id: c.id, path: c.path, oldText: c.oldText, newText: c.newText, status: 'saved'));
    await journal.append(conversationId: conversationId, event: {'type': 'change', 'path': c.path, 'old': c.oldText, 'new': c.newText});
    await refreshFiles();
  }

  Future<void> rejectChange(String changeId) async {
    final found = _findChange(changeId);
    if (found == null) return;
    final c = found.$2;
    _replaceChange(changeId, FileChangeRecord(id: c.id, path: c.path, oldText: c.oldText, newText: c.newText, status: 'rejected'));
  }

  Map<String, String> get _githubHeaders => {
        'Authorization': 'Bearer ${github.token}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'LunaLink-Agent',
      };

  Future<String> _githubRequest(String method, String path, {Map<String, dynamic>? body}) async {
    if (!github.isConnected) throw StateError('GitHub Token 未配置');
    final uri = Uri.parse('https://api.github.com$path');
    final headers = {..._githubHeaders, if (body != null) 'Content-Type': 'application/json'};
    final res = switch (method) {
      'GET' => await http.get(uri, headers: headers),
      'POST' => await http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body)),
      'PUT' => await http.put(uri, headers: headers, body: body == null ? null : jsonEncode(body)),
      _ => throw StateError('Unsupported GitHub method: $method'),
    };
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('GitHub ${res.statusCode}: ${res.body}');
    return res.body.isEmpty ? 'OK' : res.body;
  }

  Future<String> _githubCreateOrUpdateFile({required String owner, required String repo, required String path, required String content, required String message, required String branch}) async {
    String? sha;
    try {
      final existing = await _githubRequest('GET', '/repos/$owner/$repo/contents/$path?ref=$branch');
      sha = (jsonDecode(existing) as Map<String, dynamic>)['sha'] as String?;
    } catch (_) {}
    await _githubRequest('PUT', '/repos/$owner/$repo/contents/$path', body: {
      'message': message,
      'content': base64Encode(utf8.encode(content)),
      'branch': branch,
      if (sha != null) 'sha': sha,
    });
    return sha == null ? 'GitHub 文件已创建：$path' : 'GitHub 文件已更新：$path';
  }

  Future<String> _githubDispatchWorkflow({required String owner, required String repo, required String workflow, required String ref, required Map<String, dynamic> inputs}) async {
    await _githubRequest('POST', '/repos/$owner/$repo/actions/workflows/$workflow/dispatches', body: {'ref': ref, 'inputs': inputs});
    return '已触发 GitHub Actions：$workflow@$ref';
  }

  Future<String> testGitHubConnection() async {
    final result = await _githubRequest('GET', '/user');
    final data = jsonDecode(result) as Map<String, dynamic>;
    return '已连接：${data['login']}';
  }

  Future<void> _materializeAgentOutput(String messageId, String rawContent, String? thinking, String? modelLabel) async {
    final tools = _parseTools(rawContent);
    final changes = _parseChanges(rawContent);
    final clean = rawContent
        .replaceAll(RegExp(r'<tool>[\s\S]*?<\/tool>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<file_change>[\s\S]*?<\/file_change>', caseSensitive: false), '')
        .trim();
    updateAssistantMessage(messageId, clean.isEmpty && (tools.isNotEmpty || changes.isNotEmpty) ? '已生成待处理操作。' : clean, thinking: thinking, modelLabel: modelLabel);
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      final msg = messages[idx];
      messages[idx] = AgentMessage(id: msg.id, role: msg.role, content: msg.content, createdAt: msg.createdAt, thinking: msg.thinking, modelLabel: msg.modelLabel, toolCalls: tools, changes: changes);
      notifyListeners();
    }
    for (final t in tools) {
      if (_shouldAutoApprove(t.tool)) await executeTool(t.id);
    }
    if (permissionMode == ToolPermissionMode.autoAll) {
      for (final c in changes) { await applyChange(c.id); }
    }
  }

  bool _shouldAutoApprove(String tool) {
    if (permissionMode == ToolPermissionMode.autoAll) return true;
    if (permissionMode == ToolPermissionMode.autoReadOnly) return {'list_files', 'read_file', 'github_get_repo', 'github_list_runs'}.contains(tool);
    return false;
  }

  List<ToolCallRecord> _parseTools(String raw) {
    final reg = RegExp(r'<tool>([\s\S]*?)<\/tool>', caseSensitive: false);
    return reg.allMatches(raw).map((m) {
      try {
        final data = jsonDecode(m.group(1)!.trim()) as Map<String, dynamic>;
        return ToolCallRecord(id: const Uuid().v4(), tool: data['tool']?.toString() ?? '', arguments: Map<String, dynamic>.from(data['arguments'] as Map? ?? {}));
      } catch (_) {
        return ToolCallRecord(id: const Uuid().v4(), tool: 'parse_error', arguments: {'raw': m.group(1)}, status: 'error', output: '工具调用 JSON 解析失败');
      }
    }).toList();
  }

  List<FileChangeRecord> _parseChanges(String raw) {
    final reg = RegExp(r'<file_change>([\s\S]*?)<\/file_change>', caseSensitive: false);
    return reg.allMatches(raw).map((m) {
      try {
        final data = jsonDecode(m.group(1)!.trim()) as Map<String, dynamic>;
        return FileChangeRecord(id: const Uuid().v4(), path: data['path']?.toString() ?? currentPath, oldText: data['oldText']?.toString() ?? '', newText: data['newText']?.toString() ?? '');
      } catch (_) {
        return FileChangeRecord(id: const Uuid().v4(), path: 'parse_error', oldText: '', newText: m.group(1) ?? '', status: 'error');
      }
    }).toList();
  }

  AiServiceConfig get activeAiConfig => aiConfigs.firstWhere((e) => e.id == selectedAiConfigId, orElse: () => aiConfigs.first);

  Future<void> setActiveAiConfig(String id) async {
    selectedAiConfigId = id;
    await store.writeMap('profiles', 'active_ai', {'id': id});
    notifyListeners();
  }

  Future<List<String>> fetchModelsFor(AiServiceConfig config) => AiClient(config).fetchModels();

  Future<String> testAiConfig(AiServiceConfig config) async {
    final text = await AiClient(config).sendChat(const [
      {'role': 'user', 'content': '请只回复：连接成功'},
    ]);
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '响应为空';
    return trimmed.length > 120 ? '${trimmed.substring(0, 120)}...' : trimmed;
  }

  Future<void> saveAiConfig(AiServiceConfig config) async {
    final index = aiConfigs.indexWhere((e) => e.id == config.id);
    if (index >= 0) {
      aiConfigs[index] = config;
    } else {
      aiConfigs.add(config);
    }
    await store.writeMap('profiles', 'ai_services', {'items': aiConfigs.map((e) => e.toJson()).toList()});
    selectedAiConfigId ??= config.id;
    await store.writeMap('profiles', 'active_ai', {'id': selectedAiConfigId});
    notifyListeners();
  }

  void addUserMessage(String content) {
    messages.add(AgentMessage(id: const Uuid().v4(), role: 'user', content: content, createdAt: DateTime.now()));
    _touchConversation(content);
    _rewriteMemoryFromMessages();
    notifyListeners();
  }

  void _touchConversation(String titleHint) {
    final idx = conversations.indexWhere((e) => e.id == conversationId);
    final title = titleHint.length > 16 ? '${titleHint.substring(0, 16)}...' : titleHint;
    final next = ConversationMeta(id: conversationId, title: title.isEmpty ? '新话题' : title, updatedAt: DateTime.now());
    if (idx >= 0) {
      conversations[idx] = next;
    } else {
      conversations.insert(0, next);
    }
    _saveConversations();
  }

  String addAssistantMessage(String content, {String? thinking, String? modelLabel, List<ToolCallRecord> toolCalls = const [], List<FileChangeRecord> changes = const []}) {
    final id = const Uuid().v4();
    messages.add(AgentMessage(id: id, role: 'assistant', content: content, createdAt: DateTime.now(), thinking: thinking, modelLabel: modelLabel, toolCalls: toolCalls, changes: changes));
    _rewriteMemoryFromMessages();
    notifyListeners();
    return id;
  }

  void updateAssistantMessage(String id, String content, {String? thinking, String? modelLabel, bool persist = true}) {
    final index = messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    final msg = messages[index];
    final parsed = _extractThinking(content);
    messages[index] = AgentMessage(id: msg.id, role: msg.role, content: parsed.$2, createdAt: msg.createdAt, thinking: thinking ?? parsed.$1 ?? msg.thinking, modelLabel: modelLabel ?? msg.modelLabel, toolCalls: msg.toolCalls, changes: msg.changes);
    if (persist) _rewriteMemoryFromMessages();
    notifyListeners();
  }



  void deleteMessage(String id) {
    messages.removeWhere((e) => e.id == id);
    _rewriteMemoryFromMessages();
    notifyListeners();
  }

  String? rollbackToMessage(String id) {
    final idx = messages.indexWhere((e) => e.id == id);
    if (idx < 0) return null;
    final text = messages[idx].content;
    messages.removeRange(idx, messages.length);
    _rewriteMemoryFromMessages();
    notifyListeners();
    return text;
  }

  Future<void> regenerateAfter(String id) async {
    final idx = messages.indexWhere((e) => e.id == id);
    if (idx <= 0) return;
    final prevUsers = messages.take(idx).where((e) => e.role == 'user').toList();
    if (prevUsers.isEmpty) return;
    messages.removeRange(idx, messages.length);
    notifyListeners();
    await sendAgentTask(prevUsers.last.content);
  }

  Future<void> _rewriteMemoryFromMessages() async {
    await store.writeMap('memory', conversationId, {'events': messages.map((m) => {'type': 'message', 'id': m.id, 'role': m.role, 'content': m.content, 'thinking': m.thinking, 'modelLabel': m.modelLabel, 'at': m.createdAt.toIso8601String()}).toList()});
  }

  Future<void> summarizeCurrentMemory() async {
    final content = messages.map((m) => '${m.role}: ${m.content}').join('\n');
    final summary = content.length > 1400 ? '${content.substring(0, 1400)}\n...已压缩 ${messages.length} 条上下文。' : content;
    await store.writeMap('memory', conversationId, {'events': [{'type': 'summary', 'content': summary, 'at': DateTime.now().toIso8601String()}]});
  }
  (int, ToolCallRecord)? _findTool(String id) {
    for (var i = 0; i < messages.length; i++) {
      for (final t in messages[i].toolCalls) {
        if (t.id == id) return (i, t);
      }
    }
    return null;
  }

  (int, FileChangeRecord)? _findChange(String id) {
    for (var i = 0; i < messages.length; i++) {
      for (final c in messages[i].changes) {
        if (c.id == id) return (i, c);
      }
    }
    return null;
  }

  void _replaceTool(String id, ToolCallRecord next) {
    final found = _findTool(id);
    if (found == null) return;
    final msg = messages[found.$1];
    final tools = msg.toolCalls.map((e) => e.id == id ? next : e).toList();
      messages[found.$1] = AgentMessage(id: msg.id, role: msg.role, content: msg.content, createdAt: msg.createdAt, thinking: msg.thinking, modelLabel: msg.modelLabel, toolCalls: tools, changes: msg.changes);
    notifyListeners();
  }

  void _replaceChange(String id, FileChangeRecord next) {
    final found = _findChange(id);
    if (found == null) return;
    final msg = messages[found.$1];
    final changes = msg.changes.map((e) => e.id == id ? next : e).toList();
    messages[found.$1] = AgentMessage(id: msg.id, role: msg.role, content: msg.content, createdAt: msg.createdAt, thinking: msg.thinking, modelLabel: msg.modelLabel, toolCalls: msg.toolCalls, changes: changes);
    notifyListeners();
  }

  (String?, String) _extractThinking(String raw) {
    final reg = RegExp(r'<thinking>([\s\S]*?)</thinking>', caseSensitive: false);
    final matches = reg.allMatches(raw).toList();
    if (matches.isEmpty) return (null, raw);
    final thinking = matches.map((m) => m.group(1)?.trim()).whereType<String>().where((e) => e.isNotEmpty).join('\n');
    final content = raw.replaceAll(reg, '').trim();
    return (thinking.isEmpty ? null : thinking, content);
  }

  (String?, String) _extractThinkingStreaming(String raw) {
    final closed = _extractThinking(raw);
    var content = closed.$2;
    var thinking = closed.$1;
    final open = RegExp(r'<thinking>([\s\S]*)$', caseSensitive: false).firstMatch(content);
    if (open != null) {
      final openThinking = open.group(1)?.trim();
      thinking = [thinking, if (openThinking != null && openThinking.isNotEmpty) openThinking].whereType<String>().where((e) => e.isNotEmpty).join('\n');
      content = content.substring(0, open.start).trim();
    }
    return (thinking == null || thinking.isEmpty ? null : thinking, content);
  }

  String _joinRemote(String base, String child) => base.endsWith('/') ? '$base$child' : '$base/$child';
  String _parentRemote(String path) {
    final parts = path.split('/')..removeLast();
    final joined = parts.join('/');
    return joined.isEmpty ? '/' : joined;
  }
  String _normalizeRemote(String path) => path.replaceAll('//', '/').isEmpty ? '/' : path.replaceAll('//', '/');
}
