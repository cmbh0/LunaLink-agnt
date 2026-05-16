import 'dart:convert';
import 'package:path/path.dart' as p;

class ConversationMeta {
  final String id;
  final String title;
  final DateTime updatedAt;
  const ConversationMeta({required this.id, required this.title, required this.updatedAt});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'updatedAt': updatedAt.toIso8601String()};
  factory ConversationMeta.fromJson(Map<String, dynamic> json) => ConversationMeta(
        id: json['id'] as String,
        title: json['title'] as String? ?? '新话题',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

enum AgentMode { mtc, code }

class GitHubConfig {
  final String token;
  final bool autoApprove;

  const GitHubConfig({this.token = '', this.autoApprove = false});

  bool get isConnected => token.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'token': token, 'autoApprove': autoApprove};

  factory GitHubConfig.fromJson(Map<String, dynamic> json) => GitHubConfig(
        token: json['token'] as String? ?? '',
        autoApprove: json['autoApprove'] as bool? ?? false,
      );
}

enum AiProviderType { openai, gemini, claude, rest }

enum AiApiMode { openAiChat, responses, messages }

extension AiApiModeLabel on AiApiMode {
  String get label => switch (this) {
        AiApiMode.openAiChat => 'OpenAI 兼容 /chat/completions',
        AiApiMode.responses => 'OpenAI Responses /responses',
        AiApiMode.messages => '自定义 Messages Endpoint',
      };
}
enum ToolPermissionMode { askEveryTime, autoAll }


const Map<AiProviderType, String> providerEndpoints = {
  AiProviderType.openai: 'https://api.openai.com/v1',
  AiProviderType.gemini: 'https://generativelanguage.googleapis.com/v1beta/openai',
  AiProviderType.claude: 'https://api.anthropic.com/v1',
  AiProviderType.rest: 'https://api.example.com/v1',
};

class AiServiceConfig {
  final String id;
  final String name;
  final AiProviderType provider;
  final String endpoint;
  final String apiKey;
  final String model;
  final List<String> availableModels;
  final List<String> enabledModels;
  final int summaryThreshold;
  final int dailySummaryMessages;
  final String? thinkingModel;
  final bool enableThinking;
  final bool streamOutput;
  final double temperature;
  final int maxTokens;
  final Map<String, String> headers;
  final AiApiMode apiMode;
  final ToolPermissionMode permissionMode;

  const AiServiceConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.availableModels = const [],
    this.enabledModels = const [],
    this.summaryThreshold = 30,
    this.dailySummaryMessages = 80,
    this.thinkingModel,
    this.enableThinking = true,
    this.streamOutput = true,
    this.temperature = .2,
    this.maxTokens = 4096,
    this.headers = const {},
    this.apiMode = AiApiMode.openAiChat,
    this.permissionMode = ToolPermissionMode.askEveryTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider.name,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'availableModels': availableModels,
        'enabledModels': enabledModels,
        'summaryThreshold': summaryThreshold,
        'dailySummaryMessages': dailySummaryMessages,
        'thinkingModel': thinkingModel,
        'enableThinking': enableThinking,
        'streamOutput': streamOutput,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'headers': headers,
        'apiMode': apiMode.name,
        'permissionMode': permissionMode.name,
      };

  factory AiServiceConfig.fromJson(Map<String, dynamic> json) => AiServiceConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        provider: AiProviderType.values.firstWhere((e) => e.name == json['provider'], orElse: () => AiProviderType.openai),
        endpoint: json['endpoint'] as String,
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String,
        availableModels: (json['availableModels'] as List? ?? const []).map((e) => e.toString()).toList(),
        enabledModels: (json['enabledModels'] as List? ?? const []).map((e) => e.toString()).toList(),
        summaryThreshold: json['summaryThreshold'] as int? ?? 30,
        dailySummaryMessages: json['dailySummaryMessages'] as int? ?? 80,
        thinkingModel: json['thinkingModel'] as String?,
        enableThinking: json['enableThinking'] as bool? ?? true,
        streamOutput: json['streamOutput'] as bool? ?? true,
        temperature: (json['temperature'] as num?)?.toDouble() ?? .2,
        maxTokens: json['maxTokens'] as int? ?? 4096,
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        apiMode: AiApiMode.values.firstWhere((e) => e.name == json['apiMode'], orElse: () => AiApiMode.messages),
        permissionMode: ToolPermissionMode.values.firstWhere((e) => e.name == json['permissionMode'], orElse: () => ToolPermissionMode.askEveryTime),
      );
}

class AgentMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final String? thinking;
  final String? modelLabel;
  final List<ToolCallRecord> toolCalls;
  final List<FileChangeRecord> changes;

  const AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.thinking,
    this.modelLabel,
    this.toolCalls = const [],
    this.changes = const [],
  });

  Map<String, dynamic> toJson() => {
        'type': 'message',
        'id': id,
        'role': role,
        'content': content,
        'thinking': thinking,
        'modelLabel': modelLabel,
        'toolCalls': toolCalls.map((e) => e.toJson()).toList(),
        'changes': changes.map((e) => e.toJson()).toList(),
        'at': createdAt.toIso8601String(),
      };

  AgentMessage copyWith({
    String? content,
    String? thinking,
    String? modelLabel,
    List<ToolCallRecord>? toolCalls,
    List<FileChangeRecord>? changes,
  }) => AgentMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        thinking: thinking ?? this.thinking,
        modelLabel: modelLabel ?? this.modelLabel,
        toolCalls: toolCalls ?? this.toolCalls,
        changes: changes ?? this.changes,
      );
}

class LocalWorkspace {
  final String id;
  final String name;
  final String path;
  const LocalWorkspace({required this.id, required this.name, required this.path});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory LocalWorkspace.fromJson(Map<String, dynamic> json) => LocalWorkspace(id: json['id'] as String? ?? '', name: json['name'] as String? ?? 'workspace', path: json['path'] as String? ?? '');
}

class BrowserSnapshot {
  final String url;
  final String title;
  final String html;
  final String text;
  final DateTime updatedAt;
  const BrowserSnapshot({required this.url, required this.title, required this.html, required this.text, required this.updatedAt});
}

class ToolCallRecord {
  final String id;
  final String tool;
  final Map<String, dynamic> arguments;
  final String status;
  final String? output;
  const ToolCallRecord({required this.id, required this.tool, required this.arguments, this.status = 'pending', this.output});

  Map<String, dynamic> toJson() => {'id': id, 'tool': tool, 'arguments': arguments, 'status': status, 'output': output};

  factory ToolCallRecord.fromJson(Map<String, dynamic> json) => ToolCallRecord(
        id: json['id'] as String? ?? '',
        tool: json['tool'] as String? ?? '',
        arguments: Map<String, dynamic>.from(json['arguments'] as Map? ?? {}),
        status: json['status'] as String? ?? 'pending',
        output: json['output'] as String?,
      );
}

class FileChangeRecord {
  final String id;
  final String path;
  final String oldText;
  final String newText;
  final String status;
  const FileChangeRecord({required this.id, required this.path, required this.oldText, required this.newText, this.status = 'pending'});

  int get addedLines => _diffStats(oldText, newText).$1;
  int get removedLines => _diffStats(oldText, newText).$2;
  int get byteDelta => utf8.encode(newText).length - utf8.encode(oldText).length;
  String get fileName => p.basename(path);

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'oldText': oldText, 'newText': newText, 'status': status};

  factory FileChangeRecord.fromJson(Map<String, dynamic> json) => FileChangeRecord(
        id: json['id'] as String? ?? '',
        path: json['path'] as String? ?? '',
        oldText: json['oldText'] as String? ?? '',
        newText: json['newText'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
      );
}

class AgentTodoItem {
  final String title;
  final String status;
  const AgentTodoItem({required this.title, this.status = 'pending'});
  bool get done => status == 'done';
  bool get active => status == 'active' || status == 'running' || status == 'inProgress';
  Map<String, dynamic> toJson() => {'title': title, 'status': status};
  factory AgentTodoItem.fromJson(Map<String, dynamic> json) => AgentTodoItem(title: json['title'] as String? ?? '', status: json['status'] as String? ?? 'pending');
}

class AgentTodoPlan {
  final String goal;
  final List<AgentTodoItem> items;
  const AgentTodoPlan({required this.goal, required this.items});
  int get doneCount => items.where((e) => e.done).length;
  int get totalCount => items.length;
  bool get isEmpty => goal.trim().isEmpty && items.isEmpty;
  Map<String, dynamic> toJson() => {'goal': goal, 'items': items.map((e) => e.toJson()).toList()};
  factory AgentTodoPlan.fromJson(Map<String, dynamic> json) => AgentTodoPlan(
        goal: json['goal'] as String? ?? '',
        items: (json['items'] as List? ?? const []).whereType<Map>().map((e) => AgentTodoItem.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

(int, int) _diffStats(String oldText, String newText) {
  final oldLines = oldText.isEmpty ? <String>[] : const LineSplitter().convert(oldText);
  final newLines = newText.isEmpty ? <String>[] : const LineSplitter().convert(newText);
  var prefix = 0;
  while (prefix < oldLines.length && prefix < newLines.length && oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }
  var oldSuffix = oldLines.length - 1;
  var newSuffix = newLines.length - 1;
  while (oldSuffix >= prefix && newSuffix >= prefix && oldLines[oldSuffix] == newLines[newSuffix]) {
    oldSuffix--;
    newSuffix--;
  }
  final removed = oldSuffix >= prefix ? oldSuffix - prefix + 1 : 0;
  final added = newSuffix >= prefix ? newSuffix - prefix + 1 : 0;
  return (added, removed);
}
