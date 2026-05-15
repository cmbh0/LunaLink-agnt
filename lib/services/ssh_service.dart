import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_models.dart';

class SshService {
  SSHClient? _client;
  SftpClient? _sftp;
  ServerProfile? current;

  bool get isConnected => _client != null;

  Future<void> connect(ServerProfile profile) async {
    await disconnect();
    final socket = await SSHSocket.connect(profile.host, profile.port, timeout: const Duration(seconds: 12));
    final client = SSHClient(
      socket,
      username: profile.username,
      onPasswordRequest: profile.authType == AuthType.password ? () => profile.password ?? '' : null,
      identities: profile.authType == AuthType.privateKey && profile.privateKey != null ? SSHKeyPair.fromPem(profile.privateKey!) : null,
    );
    _client = client;
    _sftp = await client.sftp();
    current = profile;
  }

  Future<void> disconnect() async {
    _sftp?.close();
    _client?.close();
    _sftp = null;
    _client = null;
    current = null;
  }

  Future<String> exec(String command) async {
    final client = _requireClient();
    final session = await client.execute(command);
    final out = await utf8.decodeStream(session.stdout.cast<List<int>>());
    final err = await utf8.decodeStream(session.stderr.cast<List<int>>());
    return err.trim().isEmpty ? out : '$out\n$err';
  }

  Future<ServerInfo> readInfo() async {
    const script = r'''
printf "HOST=%s\n" "$(hostname)"
printf "OS=%s\n" "$(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-unknown})"
printf "KERNEL=%s\n" "$(uname -r)"
printf "UPTIME=%s\n" "$(uptime -p 2>/dev/null || uptime)"
printf "CPU=%s\n" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
printf "MEM=%s\n" "$(free -h | awk '/Mem:/ {print $3" / "$2}')"
printf "DISK=%s\n" "$(df -h / | awk 'NR==2 {print $3" / "$2" ("$5")"}')"
printf "LOAD=%s\n" "$(cat /proc/loadavg | cut -d' ' -f1-3)"
''';
    final text = await exec(script);
    final map = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final idx = line.indexOf('=');
      if (idx > 0) map[line.substring(0, idx)] = line.substring(idx + 1);
    }
    return ServerInfo(
      hostname: map['HOST'] ?? '-',
      os: map['OS'] ?? '-',
      kernel: map['KERNEL'] ?? '-',
      uptime: map['UPTIME'] ?? '-',
      cpu: map['CPU'] ?? '-',
      memory: map['MEM'] ?? '-',
      disk: map['DISK'] ?? '-',
      load: map['LOAD'] ?? '-',
    );
  }

  Future<List<RemoteFileEntry>> listDir(String path) async {
    final entries = await _requireSftp().listdir(path);
    final result = <RemoteFileEntry>[];
    for (final e in entries) {
      if (e.filename == '.' || e.filename == '..') continue;
      final full = path.endsWith('/') ? '$path${e.filename}' : '$path/${e.filename}';
      result.add(RemoteFileEntry(
        name: e.filename,
        path: full,
        isDirectory: e.attr.isDirectory,
        size: e.attr.size ?? 0,
        modified: e.attr.modifyTime != null ? DateTime.fromMillisecondsSinceEpoch(e.attr.modifyTime! * 1000) : null,
        permissions: e.longname,
      ));
    }
    result.sort((a, b) => a.isDirectory == b.isDirectory ? a.name.compareTo(b.name) : (a.isDirectory ? -1 : 1));
    return result;
  }

  Future<Uint8List> readFile(String path) async {
    final file = await _requireSftp().open(path, mode: SftpFileOpenMode.read);
    try {
      final chunks = <int>[];
      await for (final chunk in file.read()) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } finally {
      await file.close();
    }
  }

  Future<void> writeFile(String path, List<int> bytes) async {
    final file = await _requireSftp().open(path, mode: SftpFileOpenMode.create | SftpFileOpenMode.truncate | SftpFileOpenMode.write);
    try {
      await file.write(Stream.value(Uint8List.fromList(bytes)));
    } finally {
      await file.close();
    }
  }

  Future<void> mkdir(String path) => _requireSftp().mkdir(path);
  Future<void> delete(String path, {required bool directory}) => directory ? _requireSftp().rmdir(path) : _requireSftp().remove(path);
  Future<void> rename(String oldPath, String newPath) => _requireSftp().rename(oldPath, newPath);

  Future<String> installVsftpd({String ftpUser = 'lunalink', String ftpPassword = 'LunaLink_ChangeMe_123'}) async {
    final host = current?.host ?? '';
    final script = '''
if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y vsftpd; fi
if command -v dnf >/dev/null 2>&1; then sudo dnf install -y vsftpd; fi
if ! id $ftpUser >/dev/null 2>&1; then sudo useradd -m -s /bin/bash $ftpUser; fi
echo '$ftpUser:$ftpPassword' | sudo chpasswd
sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.lunalink.bak 2>/dev/null || true
printf '%s\n' 'listen=YES' 'anonymous_enable=NO' 'local_enable=YES' 'write_enable=YES' 'chroot_local_user=YES' 'allow_writeable_chroot=YES' | sudo tee /etc/vsftpd.conf >/dev/null
sudo systemctl enable --now vsftpd || sudo service vsftpd restart
printf 'FTP_READY user=$ftpUser password=$ftpPassword host=$host\n'
''';
    return exec(script);
  }

  SSHClient _requireClient() {
    final c = _client;
    if (c == null) throw StateError('SSH is not connected');
    return c;
  }

  SftpClient _requireSftp() {
    final s = _sftp;
    if (s == null) throw StateError('SFTP is not connected');
    return s;
  }
}
