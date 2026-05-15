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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(children: [
          IconButton(onPressed: state.currentPath == '/' ? null : () => context.read<AppState>().openDir(_parent(state.currentPath)), icon: const Icon(Icons.arrow_upward_rounded)),
          Expanded(child: Text(state.currentPath, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MoonColors.moon))),
          IconButton(onPressed: () => context.read<AppState>().refreshFiles(), icon: const Icon(Icons.refresh_rounded)),
          PopupMenuButton<String>(
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
      ),
      if (state.busy) const LinearProgressIndicator(),
      Expanded(
        child: state.files.isEmpty
            ? const Center(child: Text('目录为空或尚未连接服务器'))
            : ListView.builder(
                itemCount: state.files.length,
                itemBuilder: (context, i) => _FileTile(entry: state.files[i]),
              ),
      ),
    ]);
  }

  Future<void> _handleTopAction(BuildContext context, String action) async {
    final state = context.read<AppState>();
    if (action == 'terminal') {
      await state.runTerminalCommand('cd ${state.currentPath} && pwd && ls -la');
      return;
    }
    if (action == 'ftp') {
      final out = await state.ssh.installVsftpd();
      if (context.mounted) showDialog(context: context, builder: (_) => AlertDialog(title: const Text('FTP 创建结果'), content: SingleChildScrollView(child: Text(out))));
      return;
    }
    if (action == 'upload') {
      final picked = await FilePicker.platform.pickFiles();
      final path = picked?.files.single.path;
      if (path != null) await state.uploadLocalFile(path);
      return;
    }
    final name = await _askName(context, action == 'new_dir' ? '新建文件夹' : '新建文件');
    if (name != null && name.trim().isNotEmpty) {
      await state.createRemoteFile(name.trim(), directory: action == 'new_dir');
    }
  }
}

class _FileTile extends StatelessWidget {
  final RemoteFileEntry entry;
  const _FileTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(entry.isDirectory ? Icons.folder_rounded : _iconFor(entry.name), color: entry.isDirectory ? MoonColors.accent : MoonColors.muted),
      title: Text(entry.name),
      subtitle: Text('${entry.size} bytes  ${entry.permissions}', maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final state = context.read<AppState>();
        if (entry.isDirectory) {
          await state.openDir(entry.path);
        } else {
          final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => FileViewerScreen(state: state, path: entry.path)));
          if (changed == true && context.mounted) await state.refreshFiles();
        }
      },
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _handleEntryAction(context, v),
        itemBuilder: (_) => const [
PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(value: 'duplicate', child: Text('复制')),
          PopupMenuItem(value: 'chmod', child: Text('权限 chmod')),
          PopupMenuItem(value: 'download', child: Text('下载到应用目录')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  Future<void> _handleEntryAction(BuildContext context, String action) async {
    final state = context.read<AppState>();
    if (action == 'rename') {
      final name = await _askName(context, '重命名', initial: entry.name);
      if (name != null && name.trim().isNotEmpty) await state.renameRemote(entry, name.trim());
    } else if (action == 'duplicate') {
      final name = await _askName(context, '复制为', initial: '${entry.name}.copy');
      if (name != null && name.trim().isNotEmpty) await state.duplicateRemote(entry, name.trim());
    } else if (action == 'chmod') {
      final mode = await _askName(context, '权限 chmod', initial: '755');
      if (mode != null && mode.trim().isNotEmpty) await state.chmodRemote(entry, mode.trim());
    } else if (action == 'download') {
      final dir = await getApplicationDocumentsDirectory();
      final file = await state.downloadRemoteFile(entry, dir);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已下载到 ${file.path}')));
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('确认删除'), content: Text(entry.path), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))]));
      if (ok == true) {
        await state.deleteRemote(entry);
      }
    }
  }
}

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.webp') || n.endsWith('.gif')) return Icons.image_rounded;
  if (n.endsWith('.mp3') || n.endsWith('.wav') || n.endsWith('.flac')) return Icons.music_note_rounded;
  if (n.endsWith('.mp4') || n.endsWith('.mkv') || n.endsWith('.mov')) return Icons.movie_rounded;
  if (n.endsWith('.zip') || n.endsWith('.tar') || n.endsWith('.gz')) return Icons.archive_rounded;
  return Icons.insert_drive_file_rounded;
}

String _parent(String path) {
  final parts = path.split('/')..removeLast();
  final joined = parts.join('/');
  return joined.isEmpty ? '/' : joined;
}

Future<String?> _askName(BuildContext context, String title, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '名称')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确认'))],
    ),
  );
}
