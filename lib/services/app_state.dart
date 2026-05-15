import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
  bool autoReconnect = true;
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
      thinkingModel: 'o3-mini',
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
    messages.clear();
    notifyListeners();
  }

  Future<void> _saveConversations() => store.writeMap('memory', 'conversations', {'items': conversations.map((e) => e.toJson()).toList()});

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

  Future<void> connect(ServerProfile profile) async {
    busy = true;
    notifyListeners();
    try {
      await ssh.connect(profile);
      activeServerId = profile.id;
      serverInfo = await ssh.readInfo();
      currentPath = profile.rootPath;
      files = await ssh.listDir(currentPath);
      if (!servers.any((e) => e.id == profile.id)) servers.add(profile);
      await store.writeMap('profiles', 'servers', {'items': servers.map((e) => e.toJson()).toList()});
    } finally {
      busy = false;
      notifyListeners();
    }
  }

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

  void setPermissionMode(ToolPermissionMode mode) {
    permissionMode = mode;
    notifyListeners();
  }

  Future<void> sendAgentTask(String content) async {
    addUserMessage(content);
    final cfg = activeAiConfig;
    final modeGuide = agentMode == AgentMode.mtc
        ? '当前是 MTC 方案沟通模式：必须真实回复用户，专注需求澄清、架构方案、UI/UX 设计和风险评估；不要提出或执行工具调用。'
        : '当前是 Code 编码模式：可提出工具调用和文件变更建议，但写文件、删除文件、执行终端命令必须等待授权。';
    final prompt = '$modeGuide\n当前远程目录：$currentPath\n用户任务：$content';
    if (cfg.apiKey.isEmpty) {
      addAssistantMessage('未配置 AI 提供商或 API Key，无法发送真实请求。请进入 AI 设置填写 Endpoint、API Key 与模型 ID。', modelLabel: '${cfg.name} · ${cfg.model}');
      return;
    }
    busy = true;
    notifyListeners();
    final modelLabel = '${cfg.name} · ${cfg.model}';
    try {
      final req = [
        {'role': 'system', 'content': AgentSystemPrompt.text},
        {'role': 'user', 'content': prompt},
      ];
      if (cfg.streamOutput) {
        final id = addAssistantMessage('', modelLabel: modelLabel);
        var raw = '';
        await for (final chunk in AiClient(cfg).streamChat(req)) {
          raw += chunk;
          updateAssistantMessage(id, raw, modelLabel: modelLabel);
        }
        final parsed = _extractThinking(raw);
        updateAssistantMessage(id, parsed.$2, thinking: parsed.$1, modelLabel: modelLabel);
      } else {
        final text = await AiClient(cfg).sendChat(req);
        final parsed = _extractThinking(text);
        addAssistantMessage(parsed.$2, thinking: parsed.$1, modelLabel: modelLabel);
      }
    } catch (e) {
      addAssistantMessage('AI 请求失败：\n\n```text\n$e\n```', modelLabel: modelLabel);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> executeTool(String toolCallId) async {
    final found = _findTool(toolCallId);
    if (found == null) return;
    final call = found.$2;
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
          await ssh.writeFile(call.arguments['path'] as String, utf8.encode(call.arguments['content'] as String? ?? ''));
          output = 'written';
          await refreshFiles();
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
    await ssh.writeFile(c.path, utf8.encode(c.newText));
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

  AiServiceConfig get activeAiConfig => aiConfigs.firstWhere((e) => e.id == selectedAiConfigId, orElse: () => aiConfigs.first);

  Future<void> setActiveAiConfig(String id) async {
    selectedAiConfigId = id;
    await store.writeMap('profiles', 'active_ai', {'id': id});
    notifyListeners();
  }

  Future<List<String>> fetchModelsFor(AiServiceConfig config) => AiClient(config).fetchModels();

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
    notifyListeners();
    return id;
  }

  void updateAssistantMessage(String id, String content, {String? thinking, String? modelLabel}) {
    final index = messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    final msg = messages[index];
    messages[index] = AgentMessage(id: msg.id, role: msg.role, content: content, createdAt: msg.createdAt, thinking: thinking ?? msg.thinking, modelLabel: modelLabel ?? msg.modelLabel, toolCalls: msg.toolCalls, changes: msg.changes);
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
    await store.writeMap('memory', conversationId, {'events': messages.map((m) => {'type': 'message', 'role': m.role, 'content': m.content, 'at': m.createdAt.toIso8601String()}).toList()});
  }

  Future<void> summarizeCurrentMemory() async {
    final content = messages.map((m) => '${m.role}: ${m.content}').join('\n');
    final summary = content.length > 1400 ? '${content.substring(0, 1400)}\n...已压缩 ${messages.length} 条上下文。' : content;
    await store.writeMap('memory', conversationId, {'events': [{'type': 'summary', 'content': summary, 'at': DateTime.now().toIso8601String()}]});
  }

  String _autoStatus(String tool) {
    if (permissionMode == ToolPermissionMode.autoAll) return 'auto';
    if (permissionMode == ToolPermissionMode.autoReadOnly && {'list_files', 'read_file'}.contains(tool)) return 'auto';
    return 'needs_approval';
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
    final match = reg.firstMatch(raw);
    if (match == null) return (null, raw);
    final thinking = match.group(1)?.trim();
    final content = raw.replaceFirst(reg, '').trim();
    return (thinking, content.isEmpty ? raw : content);
  }

  String _joinRemote(String base, String child) => base.endsWith('/') ? '$base$child' : '$base/$child';
  String _parentRemote(String path) {
    final parts = path.split('/')..removeLast();
    final joined = parts.join('/');
    return joined.isEmpty ? '/' : joined;
  }
  String _normalizeRemote(String path) => path.replaceAll('//', '/').isEmpty ? '/' : path.replaceAll('//', '/');
}
