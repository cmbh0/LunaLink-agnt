import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class JsonTxtStore {
  static const _root = 'lunalink_store';

  Future<Directory> _dir(String scope) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _root, scope));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> file(String scope, String name) async {
    final dir = await _dir(scope);
    return File(p.join(dir.path, '$name.txt'));
  }

  Future<Map<String, dynamic>> readMap(String scope, String name, {Map<String, dynamic> fallback = const {}}) async {
    final f = await file(scope, name);
    if (!await f.exists()) return fallback;
    final text = await f.readAsString();
    if (text.trim().isEmpty) return fallback;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> writeMap(String scope, String name, Map<String, dynamic> data, {bool backup = true}) async {
    final f = await file(scope, name);
    if (backup && await f.exists()) {
      final backups = await _dir('$scope/backups');
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      await f.copy(p.join(backups.path, '$name.$stamp.txt'));
    }
    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(data));
  }

  Future<List<FileSystemEntity>> listBackups(String scope) async {
    final dir = await _dir('$scope/backups');
    return dir.list().toList();
  }
}

class ChangeJournal {
  final JsonTxtStore store;
  ChangeJournal(this.store);

  Future<void> append({required String conversationId, required Map<String, dynamic> event}) async {
    final doc = await store.readMap('memory', conversationId, fallback: {'events': <dynamic>[]});
    final events = List<dynamic>.from(doc['events'] as List? ?? []);
    events.add({...event, 'at': DateTime.now().toIso8601String()});
    await store.writeMap('memory', conversationId, {'events': events});
  }
}
