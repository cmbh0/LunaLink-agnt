import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_models.dart';

class SshService {
  SSHClient? _client;
  SftpClient? _sftp;
  Socket? _ftpControl;
  StreamSubscription<List<int>>? _ftpSub;
  final StringBuffer _ftpBuffer = StringBuffer();
  int _ftpCode = 0;
  String _ftpMessage = '';
  ServerProfile? current;

  bool get isConnected => _client != null || _ftpControl != null;

  Future<void> connect(ServerProfile profile) async {
    await disconnect();
    if (profile.mode == ServerAccessMode.ftp) {
      await _connectFtp(profile);
      current = profile;
      return;
    }
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
    _ftpSub?.cancel();
    _ftpControl?.destroy();
    _sftp = null;
    _client = null;
    _ftpSub = null;
    _ftpControl = null;
    current = null;
  }

  Future<String> exec(String command) async {
    final buffer = StringBuffer();
    await execStream(command, onChunk: buffer.write);
    return buffer.toString();
  }

  Future<String> execStream(String command, {void Function(String chunk)? onChunk}) async {
    final client = _requireClient();
    final session = await client.execute(command, pty: SSHPtyConfig(term: 'xterm-256color', width: 120, height: 32));
    final buffer = StringBuffer();
    final done = Completer<void>();
    void add(List<int> data) {
      final text = utf8.decode(data, allowMalformed: true);
      buffer.write(text);
      onChunk?.call(text);
    }
    final subOut = session.stdout.listen(add);
    final subErr = session.stderr.listen(add);
    session.done.then((_) async {
      await subOut.cancel();
      await subErr.cancel();
      if (!done.isCompleted) done.complete();
    }).catchError((e) {
      if (!done.isCompleted) done.completeError(e);
    });
    await done.future;
    return buffer.toString();
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
    if (current?.mode == ServerAccessMode.ftp) return _ftpListDir(path);
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
    if (current?.mode == ServerAccessMode.ftp) return _ftpRetrieve(path);
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
    if (current?.mode == ServerAccessMode.ftp) { await _ftpStore(path, bytes); return; }
    final file = await _requireSftp().open(path, mode: SftpFileOpenMode.create | SftpFileOpenMode.truncate | SftpFileOpenMode.write);
    try {
      await file.write(Stream.value(Uint8List.fromList(bytes)));
    } finally {
      await file.close();
    }
  }

  Future<void> mkdir(String path) async { if (current?.mode == ServerAccessMode.ftp) { await _ftpCommand('MKD $path'); return; } await _requireSftp().mkdir(path); }
  Future<void> delete(String path, {required bool directory}) async { if (current?.mode == ServerAccessMode.ftp) { await _ftpCommand('${directory ? 'RMD' : 'DELE'} $path'); return; } return directory ? _requireSftp().rmdir(path) : _requireSftp().remove(path); }
  Future<void> rename(String oldPath, String newPath) async { if (current?.mode == ServerAccessMode.ftp) { await _ftpCommand('RNFR $oldPath'); await _ftpCommand('RNTO $newPath'); return; } return _requireSftp().rename(oldPath, newPath); }

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

  Future<void> _connectFtp(ServerProfile profile) async {
    final socket = await Socket.connect(profile.host, profile.port, timeout: const Duration(seconds: 12));
    _ftpControl = socket;
    _ftpBuffer.clear();
    _ftpSub = socket.listen((data) => _ftpBuffer.write(latin1.decode(data, allowInvalid: true)));
    await _ftpReadResponse();
    await _ftpCommand('USER ${profile.username}', expect: const [230, 331]);
    if (_ftpCode == 331) await _ftpCommand('PASS ${profile.password ?? ''}');
    await _ftpCommand('TYPE I');
  }

  Future<String> _ftpCommand(String command, {List<int> expect = const [200, 213, 220, 221, 226, 227, 230, 250, 257, 331, 350, 150, 125]}) async {
    final c = _ftpControl;
    if (c == null) throw StateError('FTP is not connected');
    c.write('$command\r\n');
    final msg = await _ftpReadResponse();
    if (!expect.contains(_ftpCode)) throw StateError('FTP command failed: $command => $_ftpCode $msg');
    return msg;
  }

  Future<String> _ftpReadResponse() async {
    if (_ftpControl == null) throw StateError('FTP is not connected');
    final start = DateTime.now();
    while (DateTime.now().difference(start) < const Duration(seconds: 20)) {
      final text = _ftpBuffer.toString();
      final lines = const LineSplitter().convert(text.replaceAll('\r', ''));
      if (lines.isNotEmpty) {
        final first = RegExp(r'^(\d{3})([- ])').firstMatch(lines.first);
        if (first != null) {
          final code = first.group(1)!;
          final done = first.group(2) == ' ' || lines.any((l) => l.startsWith('$code '));
          if (done) {
            _ftpCode = int.parse(code);
            _ftpMessage = text.trim();
            _ftpBuffer.clear();
            return _ftpMessage;
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 35));
    }
    throw StateError('FTP response timeout');
  }

  Future<Socket> _ftpPassiveDataSocket() async {
    final msg = await _ftpCommand('PASV', expect: const [227]);
    final m = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)').firstMatch(msg);
    if (m == null) throw StateError('FTP PASV response not understood: $msg');
    final host = '${m.group(1)}.${m.group(2)}.${m.group(3)}.${m.group(4)}';
    final port = int.parse(m.group(5)!) * 256 + int.parse(m.group(6)!);
    return Socket.connect(host, port, timeout: const Duration(seconds: 12));
  }

  Future<List<RemoteFileEntry>> _ftpListDir(String path) async {
    final data = await _ftpPassiveDataSocket();
    await _ftpCommand('LIST $path', expect: const [150, 125]);
    final chunks = <int>[];
    await for (final chunk in data) { chunks.addAll(chunk); }
    await _ftpReadResponse();
    final text = latin1.decode(chunks, allowInvalid: true);
    final out = <RemoteFileEntry>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 9) continue;
      final name = parts.sublist(8).join(' ');
      if (name == '.' || name == '..') continue;
      final isDir = parts.first.startsWith('d');
      final full = path.endsWith('/') ? '$path$name' : '$path/$name';
      out.add(RemoteFileEntry(name: name, path: full, isDirectory: isDir, size: int.tryParse(parts[4]) ?? 0, permissions: line));
    }
    out.sort((a, b) => a.isDirectory == b.isDirectory ? a.name.compareTo(b.name) : (a.isDirectory ? -1 : 1));
    return out;
  }

  Future<Uint8List> _ftpRetrieve(String path) async {
    final data = await _ftpPassiveDataSocket();
    await _ftpCommand('RETR $path', expect: const [150, 125]);
    final chunks = <int>[];
    await for (final chunk in data) { chunks.addAll(chunk); }
    await _ftpReadResponse();
    return Uint8List.fromList(chunks);
  }

  Future<void> _ftpStore(String path, List<int> bytes) async {
    final data = await _ftpPassiveDataSocket();
    await _ftpCommand('STOR $path', expect: const [150, 125]);
    data.add(bytes);
    await data.flush();
    await data.close();
    await _ftpReadResponse();
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
