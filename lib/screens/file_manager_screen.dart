import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/server_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';
import 'file_viewer_screen.dart';

class FileManagerScreen extends StatelessWidget {
  final bool compact;
  const FileManagerScreen({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('文件管理')),
      body: SafeArea(child: Column(children: [
        _FileToolbar(path: state.currentPath),
      if (state.busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 16, offset: const Offset(0, 6))]),
          child: state.files.isEmpty
              ? const Center(child: Text('目录为空或尚未连接服务器'))
              : ListView.builder(itemCount: state.files.length, itemBuilder: (context, i) => _TreeTile(entry: state.files[i], depth: 0)),
        ),
      ),
      ])),
    );
  }
}

class _FileToolbar extends StatelessWidget {
  final String path;
  const _FileToolbar({required this.path});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Row(children: [
      IconButton(onPressed: path == '/' ? null : () => context.read<AppState>().openDir(_parent(path)), icon: const Icon(Icons.arrow_upward_rounded)),
      Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(14)), child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)))),
      IconButton(onPressed: () => context.read<AppState>().refreshFiles(), icon: const Icon(Icons.refresh_rounded)),
      PopupMenuButton<String>(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: MoonColors.edge)),
        onSelected: (v) => _handleTopAction(context, v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'new_file', child: Text('新建文件')),
          PopupMenuItem(value: 'new_dir', child: Text('新建文件夹')),
          PopupMenuItem(value: 'upload', child: Text('上传本地文件')),
          PopupMenuItem(value: 'terminal', child: Text('在此处打开终端')),
          PopupMenuItem(value: 'ftp', child: Text('自动创建 FTP(vsftpd)')),
        ],
      ),
    ]),
  );

  Future<void> _handleTopAction(BuildContext context, String action) async {
    final state = context.read<AppState>();
    if (action == 'terminal') { await state.runTerminalCommand('cd ${state.currentPath} && pwd && ls -la'); return; }
    if (action == 'ftp') { final out = await state.ssh.installVsftpd(); if (context.mounted) showDialog(context: context, builder: (_) => AlertDialog(title: const Text('FTP 创建结果'), content: SingleChildScrollView(child: Text(out)))); return; }
    if (action == 'upload') { final picked = await FilePicker.platform.pickFiles(); final path = picked?.files.single.path; if (path != null) await state.uploadLocalFile(path); return; }
    final name = await _askName(context, action == 'new_dir' ? '新建文件夹' : '新建文件');
    if (name != null && name.trim().isNotEmpty) await state.createRemoteFile(name.trim(), directory: action == 'new_dir');
  }
}

class _TreeTile extends StatelessWidget {
  final RemoteFileEntry entry;
  final int depth;
  const _TreeTile({required this.entry, required this.depth});
  @override
  Widget build(BuildContext context) {
    final isBak = entry.name.endsWith('.bak') || entry.name.contains('.bak.');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final state = context.read<AppState>();
          if (entry.isDirectory) {
            await state.openDir(entry.path);
          } else {
            final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => FileViewerScreen(state: state, path: entry.path)));
            if (changed == true && context.mounted) await state.refreshFiles();
          }
        },
        child: Container(
          padding: EdgeInsets.only(left: 12 + depth * 18, right: 4, top: 7, bottom: 7),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F2F5), width: .7))),
          child: Row(children: [
            Icon(entry.isDirectory ? Icons.keyboard_arrow_right_rounded : Icons.insert_drive_file_outlined, size: 17, color: MoonColors.muted),
            const SizedBox(width: 4),
            Icon(entry.isDirectory ? Icons.folder_rounded : _iconFor(entry.name), size: 20, color: entry.isDirectory ? MoonColors.accent : (isBak ? MoonColors.warn : MoonColors.muted)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: entry.isDirectory ? FontWeight.w600 : FontWeight.w500, color: isBak ? MoonColors.warn : MoonColors.text)),
              Text('${entry.size} bytes  ${entry.permissions}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: MoonColors.muted)),
            ])),
            PopupMenuButton<String>(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: MoonColors.edge)),
              onSelected: (v) => _handleEntryAction(context, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
                const PopupMenuItem(value: 'duplicate', child: Text('复制')),
                const PopupMenuItem(value: 'chmod', child: Text('权限 chmod')),
                const PopupMenuItem(value: 'download', child: Text('下载到应用目录')),
                if (isBak) const PopupMenuItem(value: 'restore', child: Text('从备份还原')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _handleEntryAction(BuildContext context, String action) async {
    final state = context.read<AppState>();
    if (action == 'restore') {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('确认还原备份'), content: Text('将 ${entry.path} 还原到原文件'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('还原'))]));
      if (ok == true) await state.restoreBackup(entry.path);
    } else if (action == 'rename') {
      final name = await _askName(context, '重命名', initial: entry.name); if (name != null && name.trim().isNotEmpty) await state.renameRemote(entry, name.trim());
    } else if (action == 'duplicate') {
      final name = await _askName(context, '复制为', initial: '${entry.name}.copy'); if (name != null && name.trim().isNotEmpty) await state.duplicateRemote(entry, name.trim());
    } else if (action == 'chmod') {
      final mode = await _askName(context, '权限 chmod', initial: '755'); if (mode != null && mode.trim().isNotEmpty) await state.chmodRemote(entry, mode.trim());
    } else if (action == 'download') {
      final dir = await getApplicationDocumentsDirectory(); final file = await state.downloadRemoteFile(entry, dir); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已下载到 ${file.path}')));
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('确认删除'), content: Text(entry.path), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))]));
      if (ok == true) await state.deleteRemote(entry);
    }
  }
}

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.dart')) return Icons.flutter_dash_rounded;
  if (n.endsWith('.js') || n.endsWith('.ts')) return Icons.javascript_rounded;
  if (n.endsWith('.json') || n.endsWith('.yaml') || n.endsWith('.yml')) return Icons.data_object_rounded;
  if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.webp') || n.endsWith('.gif')) return Icons.image_rounded;
  if (n.endsWith('.mp3') || n.endsWith('.wav') || n.endsWith('.flac')) return Icons.music_note_rounded;
  if (n.endsWith('.mp4') || n.endsWith('.mkv') || n.endsWith('.mov')) return Icons.movie_rounded;
  if (n.endsWith('.zip') || n.endsWith('.tar') || n.endsWith('.gz')) return Icons.archive_rounded;
  return Icons.description_outlined;
}

String _parent(String path) { final parts = path.split('/')..removeLast(); final joined = parts.join('/'); return joined.isEmpty ? '/' : joined; }

Future<String?> _askName(BuildContext context, String title, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text(title), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '名称')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确认'))]));
}
