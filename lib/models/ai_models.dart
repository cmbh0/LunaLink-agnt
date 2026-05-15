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

enum ToolPermissionMode { askEveryTime, autoReadOnly, autoAll }

static const Map<AiProviderType, String> providerEndpoints = {
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
  final String? thinkingModel;
  final bool enableThinking;
  final bool streamOutput;
  final double temperature;
  final int maxTokens;
  final Map<String, String> headers;
  final ToolPermissionMode permissionMode;

  const AiServiceConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.thinkingModel,
    this.enableThinking = true,
    this.streamOutput = true,
    this.temperature = .2,
    this.maxTokens = 4096,
    this.headers = const {},
    this.permissionMode = ToolPermissionMode.askEveryTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider.name,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'thinkingModel': thinkingModel,
        'enableThinking': enableThinking,
        'streamOutput': streamOutput,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'headers': headers,
        'permissionMode': permissionMode.name,
      };

  factory AiServiceConfig.fromJson(Map<String, dynamic> json) => AiServiceConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        provider: AiProviderType.values.firstWhere((e) => e.name == json['provider'], orElse: () => AiProviderType.openai),
        endpoint: json['endpoint'] as String,
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String,
        thinkingModel: json['thinkingModel'] as String?,
        enableThinking: json['enableThinking'] as bool? ?? true,
        streamOutput: json['streamOutput'] as bool? ?? true,
        temperature: (json['temperature'] as num?)?.toDouble() ?? .2,
        maxTokens: json['maxTokens'] as int? ?? 4096,
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        permissionMode: ToolPermissionMode.values.firstWhere((e) => e.name == json['permissionMode'], orElse: () => ToolPermissionMode.askEveryTime),
      );
}

class AgentMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final String? thinking;
  final List<ToolCallRecord> toolCalls;
  final List<FileChangeRecord> changes;

  const AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.thinking,
    this.toolCalls = const [],
    this.changes = const [],
  });
}

class ToolCallRecord {
  final String id;
  final String tool;
  final Map<String, dynamic> arguments;
  final String status;
  final String? output;
  const ToolCallRecord({required this.id, required this.tool, required this.arguments, this.status = 'pending', this.output});
}

class FileChangeRecord {
  final String id;
  final String path;
  final String oldText;
  final String newText;
  final String status;
  const FileChangeRecord({required this.id, required this.path, required this.oldText, required this.newText, this.status = 'pending'});
}
