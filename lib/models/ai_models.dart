enum AiProviderType { openai, gemini, claude, rest }

enum ToolPermissionMode { askEveryTime, autoReadOnly, autoAll }

class AiServiceConfig {
  final String id;
  final String name;
  final AiProviderType provider;
  final String endpoint;
  final String apiKey;
  final String model;
  final Map<String, String> headers;
  final ToolPermissionMode permissionMode;

  const AiServiceConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.model,
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
        'headers': headers,
        'permissionMode': permissionMode.name,
      };

  factory AiServiceConfig.fromJson(Map<String, dynamic> json) => AiServiceConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        provider: AiProviderType.values.firstWhere(
          (e) => e.name == json['provider'],
          orElse: () => AiProviderType.openai,
        ),
        endpoint: json['endpoint'] as String,
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String,
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        permissionMode: ToolPermissionMode.values.firstWhere(
          (e) => e.name == json['permissionMode'],
          orElse: () => ToolPermissionMode.askEveryTime,
        ),
      );
}

class AgentMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final List<ToolCallRecord> toolCalls;
  final List<FileChangeRecord> changes;

  const AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
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