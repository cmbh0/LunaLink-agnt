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
  AgentTodoPlan? todoPlan;
  FileChangeRecord? liveCodeChange;
  int _agentLoopRound = 0;
  int _aiRetryCount = 0;
  bool _agentLoopRunning = false;
  static const int _maxAgentLoopRounds = 50;
  static const int _maxAiRetries = 5;
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
    todoPlan = null;
    liveCodeChange = null;
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

  Future<void> moveConversationDown(String id) async {
    final index = conversations.indexWhere((e) => e.id == id);
    if (index < 0 || index >= conversations.length - 1) return;
    final item = conversations.removeAt(index);
    conversations.insert(index + 1, item);
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
    final planDoc = doc['todoPlan'];
    todoPlan = planDoc is Map ? AgentTodoPlan.fromJson(Map<String, dynamic>.from(planDoc)) : null;
    messages
      ..clear()
      ..addAll((doc['events'] as List? ?? []).whereType<Map>().where((e) => e['type'] == 'message' || e['type'] == 'summary').map((e) => AgentMessage(
            id: e['id'] as String? ?? const Uuid().v4(),
            role: e['type'] == 'summary' ? 'assistant' : (e['role'] as String? ?? 'assistant'),
            content: e['type'] == 'summary' ? '【上下文总结】\n${e['content'] as String? ?? ''}' : (e['content'] as String? ?? ''),
            createdAt: DateTime.tryParse(e['at'] as String? ?? '') ?? DateTime.now(),
            thinking: e['thinking'] as String?,
            modelLabel: e['modelLabel'] as String?,
            toolCalls: (e['toolCalls'] as List? ?? const []).whereType<Map>().map((t) => ToolCallRecord.fromJson(Map<String, dynamic>.from(t))).toList(),
            changes: (e['changes'] as List? ?? const []).whereType<Map>().map((c) => FileChangeRecord.fromJson(Map<String, dynamic>.from(c))).toList(),
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

  void clearLiveCodeChange() {
    liveCodeChange = null;
    notifyListeners();
  }

  Future<void> sendAgentTask(String content) async {
    if (generationActive || busy) return;
    _agentLoopRound = 0;
    _aiRetryCount = 0;
    await _requestAgentTurn(content, isContinuation: false);
  }

  Future<void> _requestAgentTurn(String content, {required bool isContinuation}) async {
    if (generationActive || busy) return;
    busy = true;
    generationActive = true;
    cancelRequested = false;
    notifyListeners();

    if (!isContinuation) addUserMessage(content);
    final cfg = activeAiConfig;
    final modeGuide = agentMode == AgentMode.mtc
        ? '当前是 MTC 方案沟通模式：只能聊天和整理需求，禁止输出 <tool> 或 <file_change>，禁止要求应用执行任何工具调用。你需要专注需求澄清、架构方案、UI/UX 设计和风险评估。'
        : '当前是 Code 编码模式：必须按照持续 Agent 工作流推进：先规划 todo，再执行工具；工具结果会自动回传给你；todo 未全部 done 前必须继续下一步；全部 done 后输出最终总结并停止。当前授权策略：${permissionMode.name}。';
    final prompt = '$modeGuide\n当前远程目录：$currentPath\n${isContinuation ? '系统继续请求：工具/文件操作结果已写入上文，请根据最新结果继续执行任务。如果目标完成，请输出全部 done 的 <todo> 和最终总结；如果未完成，请继续输出下一步需要的 <tool> 或 <file_change>。' : '用户任务：$content'}';
    final modelLabel = '${cfg.name} · ${cfg.model}';
    final id = addAssistantMessage('', modelLabel: modelLabel);
    activeAssistantMessageId = id;

    var turnOk = false;
    var shouldRetry = false;
    var retryReason = '';
    var wasCancelled = false;

    try {
      if (cfg.endpoint.trim().isEmpty) throw StateError('未配置 API Base URL。请进入 AI 配置填写接口地址。');
      if (cfg.model.trim().isEmpty) throw StateError('未配置模型 ID。请进入 AI 配置填写模型名称。');
      if (cfg.apiKey.trim().isEmpty) throw StateError('未配置 API Key。请进入 AI 配置填写密钥。');

      final systemPrompt = AgentSystemPrompt.build(hasGitHub: github.isConnected, permissionMode: permissionMode.name);
      final req = _buildAiRequest(systemPrompt, prompt, includeExistingCurrentUser: !isContinuation ? false : true);

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
          wasCancelled = true;
          final parsed = _extractThinkingStreaming(raw);
          updateAssistantMessage(id, raw.isEmpty ? '已取消 AI 输出。' : '${parsed.$2}\n\n_已取消继续输出。_', thinking: parsed.$1, modelLabel: modelLabel);
        } else if (!gotAnyChunk || raw.trim().isEmpty) {
          shouldRetry = true;
          retryReason = 'AI 请求完成，但没有收到任何文本内容。请检查接口模式、模型 ID、流式输出兼容性，或关闭“流式输出”后重试。';
          updateAssistantMessage(id, _retryMessage(retryReason), modelLabel: modelLabel);
        } else {
          final parsed = _extractThinking(raw);
          await _materializeAgentOutput(id, parsed.$2, parsed.$1, modelLabel);
          turnOk = true;
        }
      } else {
        final text = await AiClient(cfg).sendChat(req);
        if (cancelRequested) {
          wasCancelled = true;
          updateAssistantMessage(id, '已取消 AI 输出。', modelLabel: modelLabel);
        } else if (text.trim().isEmpty) {
          shouldRetry = true;
          retryReason = 'AI 请求完成，但响应文本为空。请检查接口模式或模型返回格式。';
          updateAssistantMessage(id, _retryMessage(retryReason), modelLabel: modelLabel);
        } else {
          final parsed = _extractThinking(text);
          await _materializeAgentOutput(id, parsed.$2, parsed.$1, modelLabel);
          turnOk = true;
        }
      }
    } catch (e) {
      shouldRetry = true;
      retryReason = '$e';
      updateAssistantMessage(id, _retryMessage('AI 请求失败：$e'), modelLabel: modelLabel);
    } finally {
      final stopRequested = cancelRequested || wasCancelled;
      busy = false;
      generationActive = false;
      cancelRequested = false;
      activeAssistantMessageId = null;
      notifyListeners();
      await _rewriteMemoryFromMessages();
      var scheduledRetry = false;
      if (agentMode == AgentMode.code && !stopRequested) {
        if (turnOk) {
          if (!isContinuation) _aiRetryCount = 0;
        } else if (shouldRetry) {
          scheduledRetry = true;
          Future.microtask(() => _retryAgentTurnIfNeeded(content, isContinuation: isContinuation, reason: retryReason));
        }
      }
      if (!scheduledRetry && agentMode == AgentMode.code && !_agentLoopRunning && !stopRequested) {
        Future.microtask(_continueAgentLoopIfNeeded);
      }
    }
  }

  List<Map<String, String>> _buildAiRequest(String systemPrompt, String currentPrompt, {bool includeExistingCurrentUser = true}) {
    final source = includeExistingCurrentUser ? messages : messages.where((m) => !(m.role == 'user' && m.content == currentPrompt)).toList();
    final history = source
        .where((m) => m.content.trim().isNotEmpty || m.toolCalls.isNotEmpty || m.changes.isNotEmpty)
        .map((m) {
          final extra = <String>[];
          for (final t in m.toolCalls) {
            if ((t.output ?? '').trim().isNotEmpty || t.status != 'pending') {
              extra.add('【工具 ${t.tool} / ${t.status}】\n参数: ${jsonEncode(t.arguments)}\n结果:\n${t.output ?? ''}');
            }
          }
          for (final c in m.changes) {
            extra.add('【文件变更 ${c.path} / ${c.status}】新增 ${c.addedLines} 行，删除 ${c.removedLines} 行，字节变化 ${c.byteDelta}');
          }
          final body = [m.content, ...extra].where((e) => e.trim().isNotEmpty).join('\n\n');
          return {'role': m.role == 'user' ? 'user' : 'assistant', 'content': body};
        })
        .toList();
    final capped = history.length > 24 ? history.sublist(history.length - 24) : history;
    return [
      {'role': 'system', 'content': systemPrompt},
      ...capped,
      {'role': 'user', 'content': currentPrompt},
    ];
  }

  void cancelGeneration() {
    cancelRequested = true;
    _agentLoopRound = _maxAgentLoopRounds;
    notifyListeners();
  }

  String _retryMessage(String reason) {
    final next = _aiRetryCount + 1;
    return 'AI 响应异常，正在自动重试 ($next/$_maxAiRetries)：\n\n```text\n$reason\n```';
  }

  Future<void> _retryAgentTurnIfNeeded(String content, {required bool isContinuation, required String reason}) async {
    if (agentMode != AgentMode.code || cancelRequested) return;
    if (_aiRetryCount >= _maxAiRetries) {
      addAssistantMessage('AI 自动重试已达到最大次数 $_maxAiRetries，流程已安全停止。最后错误：\n\n```text\n$reason\n```');
      await _rewriteMemoryFromMessages();
      notifyListeners();
      return;
    }
    _aiRetryCount += 1;
    await Future.delayed(Duration(milliseconds: 700 * _aiRetryCount));
    if (busy || generationActive || cancelRequested) return;
    await _requestAgentTurn(content, isContinuation: isContinuation);
  }

  Future<void> _continueAgentLoopIfNeeded() async {
    if (_agentLoopRunning || agentMode != AgentMode.code || busy || generationActive || cancelRequested) return;
    if (_isTodoComplete) return;
    if (!_hasActionNeedingContinuation) return;
    if (_agentLoopRound >= _maxAgentLoopRounds) {
      addAssistantMessage('Agent 已连续自动执行 $_maxAgentLoopRounds 轮。为保护设备和接口资源，系统已安全停止本次自动流程；这不是让用户手动继续，而是防止异常无限循环的硬保护。');
      await _rewriteMemoryFromMessages();
      return;
    }
    _agentLoopRunning = true;
    try {
      _agentLoopRound += 1;
      await _requestAgentTurn('继续', isContinuation: true);
    } finally {
      _agentLoopRunning = false;
    }
  }

  bool get _isTodoComplete => todoPlan != null && todoPlan!.items.isNotEmpty && todoPlan!.items.every((e) => e.done);

  bool get _hasActionNeedingContinuation {
    if (todoPlan != null && todoPlan!.items.isNotEmpty && !todoPlan!.items.every((e) => e.done)) return true;
    for (final m in messages.reversed.take(8)) {
      final hasRunning = m.toolCalls.any((t) => t.status == 'running' || t.status == 'pending') || m.changes.any((c) => c.status == 'pending' || c.status == 'running');
      if (hasRunning) return false;
      final hasFinishedAction = m.toolCalls.any((t) => t.status == 'done' || t.status == 'error' || t.status == 'rejected') || m.changes.any((c) => c.status == 'saved' || c.status == 'error' || c.status == 'rejected');
      if (hasFinishedAction) return true;
      if (m.role == 'assistant' && m.content.trim().isNotEmpty) return false;
    }
    return false;
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
          final command = _requiredString(call, 'command', 'ls -la');
          output = await ssh.exec(command);
          terminalLogs.add('\$ $command');
          terminalLogs.add(output.trim().isEmpty ? '[no output]' : output);
          break;
        case 'terminal_wait':
          final delay = call.arguments['delayMs'] is num ? (call.arguments['delayMs'] as num).toInt() : 1000;
          await Future.delayed(Duration(milliseconds: delay.clamp(0, 30000)));
          output = terminalLogs.take(80).join('\n');
          break;
        case 'list_files':
          final path = call.arguments['path'] as String? ?? currentPath;
          final list = await ssh.listDir(path);
          output = list.map((e) => '${e.isDirectory ? 'd' : '-'} ${e.name} ${e.size}').join('\n');
          break;
        case 'read_file':
          final bytes = await ssh.readFile(_requiredString(call, 'path', '/home/user/project/main.dart'));
          output = utf8.decode(bytes, allowMalformed: true);
          break;
        case 'write_file':
          final path = _requiredString(call, 'path', '/path/file');
          final content = call.arguments['content'] as String? ?? '';
          String old = '';
          try { old = utf8.decode(await ssh.readFile(path), allowMalformed: true); } catch (_) {}
          liveCodeChange = FileChangeRecord(id: call.id, path: path, oldText: old, newText: content, status: 'running');
          notifyListeners();
          await writeRemoteTextWithBackup(path, content);
          liveCodeChange = FileChangeRecord(id: call.id, path: path, oldText: old, newText: content, status: 'saved');
          output = 'written with .bak backup';
          await refreshFiles();
          break;
        case 'replace_file_text':
          final path = _requiredString(call, 'path', '/path/file');
          final oldText = _requiredString(call, 'oldText', '旧文本');
          final newText = _requiredString(call, 'newText', '新文本');
          final current = utf8.decode(await ssh.readFile(path), allowMalformed: true);
          if (!current.contains(oldText)) throw StateError('oldText not found in file.');
          final next = current.replaceFirst(oldText, newText);
          liveCodeChange = FileChangeRecord(id: call.id, path: path, oldText: current, newText: next, status: 'running');
          notifyListeners();
          await writeRemoteTextWithBackup(path, next);
          liveCodeChange = FileChangeRecord(id: call.id, path: path, oldText: current, newText: next, status: 'saved');
          output = 'replaced text in $path';
          await refreshFiles();
          break;
        case 'move_file':
          await ssh.rename(_requiredString(call, 'from', '/old/path'), _requiredString(call, 'to', '/new/path'));
          output = 'moved';
          await refreshFiles();
          break;
        case 'delete_file':
          await ssh.delete(_requiredString(call, 'path', '/path/file'), directory: call.arguments['directory'] == true);
          output = 'deleted';
          await refreshFiles();
          break;
        case 'mkdir':
          await ssh.mkdir(_requiredString(call, 'path', '/path/dir'));
          output = 'directory created';
          await refreshFiles();
          break;
        case 'github_status':
          output = github.isConnected ? 'GitHub token configured. Use github_verify_token to validate current user.' : 'GitHub token not configured.';
          break;
        case 'github_verify_token':
          output = await testGitHubConnection();
          break;
        case 'github_list_repos':
          output = await _githubRequest('GET', '/user/repos?visibility=${call.arguments['visibility'] ?? 'all'}&per_page=${call.arguments['per_page'] ?? 30}');
          break;
        case 'github_create_repo':
          output = await _githubRequest('POST', '/user/repos', body: {
            'name': _requiredString(call, 'name', 'my-project'),
            'private': call.arguments['private'] != false,
            if ((call.arguments['description'] as String?)?.isNotEmpty == true) 'description': call.arguments['description'],
          });
          break;
        case 'github_get_repo':
          output = await _githubRequest('GET', '/repos/${_requiredString(call, 'owner', 'user')}/${_requiredString(call, 'repo', 'repo')}');
          break;
        case 'github_create_or_update_file':
          output = await _githubCreateOrUpdateFile(
            owner: _requiredString(call, 'owner', 'user'),
            repo: _requiredString(call, 'repo', 'repo'),
            path: _requiredString(call, 'path', 'file.txt'),
            content: call.arguments['content'] as String? ?? '',
            message: call.arguments['message'] as String? ?? 'Update file from LunaLink Agent',
            branch: call.arguments['branch'] as String? ?? 'main',
          );
          break;
        case 'github_dispatch_workflow':
          output = await _githubDispatchWorkflow(
            owner: _requiredString(call, 'owner', 'user'),
            repo: _requiredString(call, 'repo', 'repo'),
            workflow: call.arguments['workflow'] as String? ?? 'flutter_android_ci.yml',
            ref: call.arguments['ref'] as String? ?? 'main',
            inputs: Map<String, dynamic>.from(call.arguments['inputs'] as Map? ?? {'build_mode': 'release'}),
          );
          break;
        case 'github_list_runs':
          output = await _githubRequest('GET', '/repos/${_requiredString(call, 'owner', 'user')}/${_requiredString(call, 'repo', 'repo')}/actions/runs?per_page=${call.arguments['per_page'] ?? 5}');
          break;
        default:
          throw StateError('Unknown tool: ${call.tool}');
      }
      _replaceTool(toolCallId, ToolCallRecord(id: call.id, tool: call.tool, arguments: call.arguments, status: 'done', output: output));
      await journal.append(conversationId: conversationId, event: {'type': 'tool', 'tool': call.tool, 'args': call.arguments, 'output': output});
    } catch (e) {
      final err = _toolErrorMessage(call, e);
      _replaceTool(toolCallId, ToolCallRecord(id: call.id, tool: call.tool, arguments: call.arguments, status: 'error', output: err));
      if (call.tool == 'ssh_exec') terminalLogs.add('ERROR: $err');
    } finally {
      notifyListeners();
      await _rewriteMemoryFromMessages();
      if (agentMode == AgentMode.code) Future.microtask(_continueAgentLoopIfNeeded);
    }
  }

  String _requiredString(ToolCallRecord call, String key, String example) {
    final value = call.arguments[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw StateError('Missing required parameter `$key`. Example: ${jsonEncode({'tool': call.tool, 'arguments': {key: example}})}');
  }

  String _toolErrorMessage(ToolCallRecord call, Object error) => '''English:
Tool call failed.
Tool: ${call.tool}
Arguments: ${jsonEncode(call.arguments)}
Reason: $error
Please call the tool with the exact schema and all required parameters. If a parameter is missing or has a wrong type, correct it before retrying.
Correct usage example:
${_toolUsageExample(call.tool)}

中文：
工具调用失败。
工具：${call.tool}
参数：${jsonEncode(call.arguments)}
原因：$error
请严格按照工具 schema 调用，并提供所有必需参数。如果参数缺失或类型错误，请修正后再重试。
正确调用示例：
${_toolUsageExample(call.tool)}''';

  String _toolUsageExample(String tool) {
    final args = switch (tool) {
      'ssh_exec' => {'command': 'ls -la'},
      'terminal_wait' => {'delayMs': 3000},
      'list_files' => {'path': '/home/user'},
      'read_file' => {'path': '/home/user/main.dart'},
      'write_file' => {'path': '/home/user/main.dart', 'content': '...'},
      'replace_file_text' => {'path': '/home/user/main.dart', 'oldText': 'old', 'newText': 'new'},
      'move_file' => {'from': '/home/user/a.txt', 'to': '/home/user/b.txt'},
      'delete_file' => {'path': '/home/user/a.txt', 'directory': false},
      'mkdir' => {'path': '/home/user/src'},
      'github_status' => {},
      'github_verify_token' => {},
      'github_list_repos' => {'visibility': 'all', 'per_page': 30},
      'github_create_repo' => {'name': 'my-project', 'private': true, 'description': '...'},
      'github_get_repo' => {'owner': 'user', 'repo': 'repo'},
      'github_create_or_update_file' => {'owner': 'user', 'repo': 'repo', 'path': 'file.txt', 'content': '...', 'message': 'update file', 'branch': 'main'},
      'github_dispatch_workflow' => {'owner': 'user', 'repo': 'repo', 'workflow': 'ci.yml', 'ref': 'main', 'inputs': <String, dynamic>{}},
      'github_list_runs' => {'owner': 'user', 'repo': 'repo', 'per_page': 5},
      _ => {'tool': tool, 'arguments': <String, dynamic>{}},
    };
    return jsonEncode({'tool': tool, 'arguments': args});
  }

  Future<void> rejectTool(String toolCallId) async {
    final found = _findTool(toolCallId);
    if (found == null) return;
    final c = found.$2;
    _replaceTool(toolCallId, ToolCallRecord(id: c.id, tool: c.tool, arguments: c.arguments, status: 'rejected', output: '用户已拒绝'));
    await _rewriteMemoryFromMessages();
    if (agentMode == AgentMode.code) Future.microtask(_continueAgentLoopIfNeeded);
  }

  Future<void> applyChange(String changeId) async {
    final found = _findChange(changeId);
    if (found == null) return;
    final c = found.$2;
    liveCodeChange = FileChangeRecord(id: c.id, path: c.path, oldText: c.oldText, newText: c.newText, status: 'running');
    notifyListeners();
    await writeRemoteTextWithBackup(c.path, c.newText);
    liveCodeChange = FileChangeRecord(id: c.id, path: c.path, oldText: c.oldText, newText: c.newText, status: 'saved');
    _replaceChange(changeId, FileChangeRecord(id: c.id, path: c.path, oldText: c.oldText, newText: c.newText, status: 'saved'));
    await journal.append(conversationId: conversationId, event: {'type': 'change', 'path': c.path, 'old': c.oldText, 'new': c.newText});
    await refreshFiles();
    await _rewriteMemoryFromMessages();
  }

  Future<void> rejectChange(String changeId) async {
    final found = _findChange(changeId);
    if (found == null) return;
    final c = found.$2;
    _replaceChange(changeId, FileChangeRecord(id: c.id, path: c.path, oldText: c.oldText, newText: c.newText, status: 'rejected'));
    await _rewriteMemoryFromMessages();
    if (agentMode == AgentMode.code) Future.microtask(_continueAgentLoopIfNeeded);
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
    if (agentMode == AgentMode.mtc) {
        final parsed = _extractThinking(rawContent);
        updateAssistantMessage(messageId, parsed.$2.isEmpty ? rawContent : parsed.$2, thinking: thinking ?? parsed.$1, modelLabel: modelLabel);
        return;
      }
      final plan = _parseTodo(rawContent);
      if (plan != null) todoPlan = plan;
      final tools = _parseTools(rawContent);
    final changes = _parseChanges(rawContent);
    if (changes.isNotEmpty) liveCodeChange = changes.first;
    final clean = rawContent
        .replaceAll(RegExp(r'<tool>[\s\S]*?<\/tool>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<file_change>[\s\S]*?<\/file_change>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<todo>[\s\S]*?<\/todo>', caseSensitive: false), '')
        .trim();
    updateAssistantMessage(messageId, clean.isEmpty && (tools.isNotEmpty || changes.isNotEmpty || plan != null) ? '已生成待处理操作。' : clean, thinking: thinking, modelLabel: modelLabel);
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      final msg = messages[idx];
      messages[idx] = AgentMessage(id: msg.id, role: msg.role, content: msg.content, createdAt: msg.createdAt, thinking: msg.thinking, modelLabel: msg.modelLabel, toolCalls: tools, changes: changes);
      notifyListeners();
    }
    if (permissionMode == ToolPermissionMode.autoAll) {
      for (final t in tools) { await executeTool(t.id); }
      for (final c in changes) { await applyChange(c.id); }
    } else if (agentMode == AgentMode.code && (tools.isNotEmpty || changes.isNotEmpty)) {
      _agentLoopRound = 0;
    }
    await _rewriteMemoryFromMessages();
  }
  List<ToolCallRecord> _parseTools(String raw) {
    final reg = RegExp(r'<tool>([\s\S]*?)<\/tool>', caseSensitive: false);
    return reg.allMatches(raw).map((m) {
      try {
        final data = jsonDecode(m.group(1)!.trim()) as Map<String, dynamic>;
        return ToolCallRecord(id: const Uuid().v4(), tool: data['tool']?.toString() ?? '', arguments: Map<String, dynamic>.from(data['arguments'] as Map? ?? {}));
      } catch (e) {
        return ToolCallRecord(id: const Uuid().v4(), tool: 'parse_error', arguments: {'raw': m.group(1)}, status: 'error', output: _toolErrorMessage(ToolCallRecord(id: 'parse_error', tool: 'parse_error', arguments: {'raw': m.group(1)}), e));
      }
    }).toList();
  }

  AgentTodoPlan? _parseTodo(String raw) {
    final reg = RegExp(r'<todo>([\s\S]*?)<\/todo>', caseSensitive: false);
    final matches = reg.allMatches(raw).toList();
    if (matches.isEmpty) return null;
    final match = matches.last;
    try {
      final data = jsonDecode(match.group(1)!.trim()) as Map<String, dynamic>;
      return AgentTodoPlan.fromJson(data);
    } catch (_) {
      return null;
    }
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

  AiServiceConfig get activeAiConfig {
    if (aiConfigs.isEmpty) {
      const fallback = AiServiceConfig(
        id: 'default-openai',
        name: 'OpenAI Compatible',
        provider: AiProviderType.openai,
        endpoint: 'https://api.openai.com/v1',
        apiKey: '',
        model: 'gpt-4.1',
      );
      aiConfigs.add(fallback);
      selectedAiConfigId = fallback.id;
      return fallback;
    }
    return aiConfigs.firstWhere((e) => e.id == selectedAiConfigId, orElse: () => aiConfigs.first);
  }

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
    final idx = messages.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    messages.removeRange(idx, messages.length);
    _rewriteMemoryFromMessages();
    notifyListeners();
  }

  String? rollbackToMessage(String id) {
    final idx = messages.indexWhere((e) => e.id == id);
    if (idx < 0) return null;
    final msg = messages[idx];
    final text = msg.role == 'user' ? msg.content : null;
    messages.removeRange(idx, messages.length);
    _rewriteMemoryFromMessages();
    notifyListeners();
    return text;
  }

  String? editAndResend(String id) => rollbackToMessage(id);

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
    await store.writeMap('memory', conversationId, {
      'todoPlan': todoPlan?.toJson(),
      'events': messages.map((m) => m.toJson()).toList(),
    });
    final cfg = activeAiConfig;
    final threshold = cfg.summaryThreshold <= 0 ? 999999 : cfg.summaryThreshold;
    final userCount = messages.where((m) => m.role == 'user').length;
    if (userCount > 0 && userCount % threshold == 0 && messages.length > 2) {
      await summarizeCurrentMemory(auto: true);
    }
  }

  Future<void> summarizeCurrentMemory({bool auto = false}) async {
    final cfg = activeAiConfig;
    final content = messages.map((m) => '${m.role == 'user' ? '用户' : 'AI'}: ${m.content}').join('\n');
    var summary = content.length > 1600 ? '${content.substring(0, 1600)}\n...已压缩 ${messages.length} 条上下文。' : content;
    if (cfg.apiKey.isNotEmpty && cfg.endpoint.isNotEmpty && cfg.model.isNotEmpty) {
      try {
        summary = await AiClient(cfg).sendChat([
          {'role': 'system', 'content': '你是上下文记忆总结器。请把对话压缩成结构化回顾，保留用户需求、已完成事项、未完成事项、关键配置、仓库/服务器信息、风险与下一步。用“用户/AI/系统状态”分段，简洁但不能遗漏关键事实。'},
          {'role': 'user', 'content': content},
        ]);
      } catch (_) {}
    }
    await store.writeMap('memory', conversationId, {'todoPlan': todoPlan?.toJson(), 'events': [
      {'type': 'summary', 'content': summary, 'auto': auto, 'at': DateTime.now().toIso8601String()},
      ...messages.reversed.take(6).toList().reversed.map((m) => m.toJson()),
    ]});
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
    final thinking = matches.map((m) => _normalizeThinkingText(m.group(1))).whereType<String>().where((e) => e.isNotEmpty).join('\n');
    final content = raw.replaceAll(reg, '').trim();
    return (thinking.isEmpty ? null : thinking, content);
  }

  (String?, String) _extractThinkingStreaming(String raw) {
    final closed = _extractThinking(raw);
    var content = closed.$2;
    var thinking = _normalizeThinkingText(closed.$1);
    final open = RegExp(r'<thinking>([\s\S]*)$', caseSensitive: false).firstMatch(content);
    if (open != null) {
      final openThinking = _normalizeThinkingText(open.group(1));
      thinking = [thinking, if (openThinking != null && openThinking.isNotEmpty) openThinking].whereType<String>().where((e) => e.isNotEmpty).join('\n');
      final start = open.start.clamp(0, content.length);
      content = content.substring(0, start).trim();
    }
    return (thinking == null || thinking.isEmpty ? null : thinking, content);
  }

  String? _normalizeThinkingText(String? value) {
    if (value == null) return null;
    final normalized = value
        .replaceAll(RegExp(r'</?thinking>', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\n\s*'), '\n')
        .trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _joinRemote(String base, String child) => base.endsWith('/') ? '$base$child' : '$base/$child';
  String _parentRemote(String path) {
    final parts = path.split('/')..removeLast();
    final joined = parts.join('/');
    return joined.isEmpty ? '/' : joined;
  }
  String _normalizeRemote(String path) => path.replaceAll('//', '/').isEmpty ? '/' : path.replaceAll('//', '/');
}
