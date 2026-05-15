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
  ServerInfo? serverInfo;
  String currentPath = '/';
  List<RemoteFileEntry> files = [];
  bool busy = false;
  String conversationId = 'default_conversation';
  ToolPermissionMode permissionMode = ToolPermissionMode.askEveryTime;

  AppState() {
    aiConfigs.add(const AiServiceConfig(
      id: 'default-openai',
      name: 'OpenAI Compatible',
      provider: AiProviderType.openai,
      endpoint: 'https://api.openai.com/v1',
      apiKey: '',
      model: 'gpt-4.1',
    ));
  }

  Future<void> connect(ServerProfile profile) async {
    busy = true;
    notifyListeners();
    try {
      await ssh.connect(profile);
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

  void setPermissionMode(ToolPermissionMode mode) {
    permissionMode = mode;
    notifyListeners();
  }

  Future<void> sendAgentTask(String content) async {
    addUserMessage(content);
    final cfg = aiConfigs.first;
    final prompt = '${AgentSystemPrompt.text}\n当前远程目录：$currentPath\n用户任务：$content';
    if (cfg.apiKey.isEmpty) {
      addAssistantMessage(
        '未配置 API Key。已生成可执行计划模板：\n1. 读取上下文和目录。\n2. 如需修改文件，生成变更卡片等待保存。\n3. 如需终端命令，生成授权卡片等待执行。',
        toolCalls: [ToolCallRecord(id: const Uuid().v4(), tool: 'list_files', arguments: {'path': currentPath}, status: _autoStatus('list_files'))],
      );
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final text = await AiClient(cfg).sendChat([
        {'role': 'system', 'content': AgentSystemPrompt.text},
        {'role': 'user', 'content': prompt},
      ]);
      addAssistantMessage(text);
    } catch (e) {
      addAssistantMessage('AI 请求失败：$e');
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

  Future<void> saveAiConfig(AiServiceConfig config) async {
    final index = aiConfigs.indexWhere((e) => e.id == config.id);
    if (index >= 0) {
      aiConfigs[index] = config;
    } else {
      aiConfigs.add(config);
    }
    await store.writeMap('profiles', 'ai_services', {'items': aiConfigs.map((e) => e.toJson()).toList()});
    notifyListeners();
  }

  void addUserMessage(String content) {
    messages.add(AgentMessage(id: const Uuid().v4(), role: 'user', content: content, createdAt: DateTime.now()));
    notifyListeners();
  }

  void addAssistantMessage(String content, {List<ToolCallRecord> toolCalls = const [], List<FileChangeRecord> changes = const []}) {
    messages.add(AgentMessage(id: const Uuid().v4(), role: 'assistant', content: content, createdAt: DateTime.now(), toolCalls: toolCalls, changes: changes));
    notifyListeners();
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
    messages[found.$1] = AgentMessage(id: msg.id, role: msg.role, content: msg.content, createdAt: msg.createdAt, toolCalls: tools, changes: msg.changes);
    notifyListeners();
  }

  void _replaceChange(String id, FileChangeRecord next) {
    final found = _findChange(id);
    if (found == null) return;
    final msg = messages[found.$1];
    final changes = msg.changes.map((e) => e.id == id ? next : e).toList();
    messages[found.$1] = AgentMessage(id: msg.id, role: msg.role, content: msg.content, createdAt: msg.createdAt, toolCalls: msg.toolCalls, changes: changes);
    notifyListeners();
  }

  String _joinRemote(String base, String child) => base.endsWith('/') ? '$base$child' : '$base/$child';
  String _parentRemote(String path) {
    final parts = path.split('/')..removeLast();
    final joined = parts.join('/');
    return joined.isEmpty ? '/' : joined;
  }
  String _normalizeRemote(String path) => path.replaceAll('//', '/').isEmpty ? '/' : path.replaceAll('//', '/');
}