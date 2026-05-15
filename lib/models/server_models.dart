enum AuthType { password, privateKey }

class ServerProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthType authType;
  final String? password;
  final String? privateKey;
  final String rootPath;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = AuthType.password,
    this.password,
    this.privateKey,
    this.rootPath = '/',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authType': authType.name,
        'password': password,
        'privateKey': privateKey,
        'rootPath': rootPath,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: (json['port'] as num?)?.toInt() ?? 22,
        username: json['username'] as String,
        authType: AuthType.values.firstWhere(
          (e) => e.name == json['authType'],
          orElse: () => AuthType.password,
        ),
        password: json['password'] as String?,
        privateKey: json['privateKey'] as String?,
        rootPath: json['rootPath'] as String? ?? '/',
      );
}

class ServerInfo {
  final String hostname;
  final String os;
  final String kernel;
  final String uptime;
  final String cpu;
  final String memory;
  final String disk;
  final String load;

  const ServerInfo({
    required this.hostname,
    required this.os,
    required this.kernel,
    required this.uptime,
    required this.cpu,
    required this.memory,
    required this.disk,
    required this.load,
  });
}

class RemoteFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
  final String permissions;

  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modified,
    this.permissions = '',
  });
}
