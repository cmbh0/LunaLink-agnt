import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../models/server_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';
import 'file_viewer_screen.dart';

class FileManagerScreen extends StatefulWidget {
  final bool compact;
  const FileManagerScreen({super.key, this.compact = false});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  String localPath = '';
  Future<List<RemoteFileEntry>>? localFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.developmentEnvironment == DevelopmentEnvironment.local) localFuture ??= state.listLocalWorkspaceDir(localPath);
  }

  void _reloadLocal() => setState(() => localFuture = context.read<AppState>().listLocalWorkspaceDir(localPath));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLocal = state.developmentEnvironment == DevelopmentEnvironment.local;
    final path = isLocal ? (localPath.isEmpty ? '/' : '/$localPath') : state.currentPath;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(isLocal ? '本地文件管理' : '文件管理')),
      body: SafeArea(child: Column(children: [
        _SourceBadge(isLocal: isLocal),
        _FileToolbar(path: path, isLocal: isLocal, onLocalUp: localPath.isEmpty ? null : () { setState(() { localPath = _parentLocal(localPath); localFuture = state.listLocalWorkspaceDir(localPath); }); }, onLocalRefresh: _reloadLocal),
        if (state.busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 16, offset: const Offset(0, 6))]),
            child: isLocal
                ? _LocalList(future: localFuture ?? state.listLocalWorkspaceDir(localPath), reload: _reloadLocal, openDir: (entry) { setState(() { localPath = _relativeLocal(state, entry.path); localFuture = state.listLocalWorkspaceDir(localPath); }); })
                : state.files.isEmpty
                    ? const Center(child: Text('目录为空或尚未连接服务器'))
                    : ListView.builder(itemCount: state.files.length, itemBuilder: (context, i) => _TreeTile(entry: state.files[i], depth: 0, isLocal: false, reload: () => state.refreshFiles())),
          ),
        ),
      ])),
    );
  }
}

class _LocalList extends StatelessWidget {
  final Future<List<RemoteFileEntry>> future;
  final VoidCallback reload;
  final ValueChanged<RemoteFileEntry> openDir;
  const _LocalList({required this.future, required this.reload, required this.openDir});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<RemoteFileEntry>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final files = snap.data ?? const [];
          if (files.isEmpty) return const Center(child: Text('本地工作区为空'));
          return ListView.builder(itemCount: files.length, itemBuilder: (context, i) => _TreeTile(entry: files[i], depth: 0, isLocal: true, reload: reload, openLocalDir: openDir));
        },
      );
}

class _SourceBadge extends StatelessWidget {
  final bool isLocal;
  const _SourceBadge({required this.isLocal});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeServerId == null ? null : state.servers.where((e) => e.id == state.activeServerId).toList();
    final label = isLocal
        ? 'Local：${state.activeWorkspace == null ? '未绑定本地工作区' : '${state.activeWorkspace!.name} · ${state.activeWorkspace!.path}'}'
        : (active == null || active.isEmpty ? 'Cloud：未连接' : 'Cloud：${active.first.mode == ServerAccessMode.ftp ? 'FTP' : active.first.mode == ServerAccessMode.sftp ? 'SFTP' : 'Linux SSH'} · ${active.first.name}');
    final color = isLocal ? const Color(0xFF16A34A) : const Color(0xFF2563EB);
    final bg = isLocal ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF);
    final edge = isLocal ? const Color(0xFFBBF7D0) : const Color(0xFFBFDBFE);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: edge)),
      child: Row(children: [Icon(isLocal ? Icons.laptop_mac_rounded : Icons.cloud_outlined, size: 16, color: color), const SizedBox(width: 8), Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)))]),
    );
  }
}

class _FileToolbar extends StatelessWidget {
  final String path;
  final bool isLocal;
  final VoidCallback? onLocalUp;
  final VoidCallback? onLocalRefresh;
  const _FileToolbar({required this.path, required this.isLocal, this.onLocalUp, this.onLocalRefresh});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Row(children: [
      IconButton(onPressed: isLocal ? onLocalUp : (path == '/' ? null : () => context.read<AppState>().openDir(_parent(path))), icon: const Icon(Icons.arrow_upward_rounded)),
      Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: MoonGlass.panel2(context), borderRadius: BorderRadius.circular(14)), child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)))),
      IconButton(onPressed: isLocal ? onLocalRefresh : () => context.read<AppState>().refreshFiles(), icon: const Icon(Icons.refresh_rounded)),
      _MoonPopupButton(
        icon: Icons.more_horiz_rounded,
        items: [
          const MoonSelectOption(value: 'new_file', label: '新建文件', icon: Icons.note_add_outlined),
          const MoonSelectOption(value: 'new_dir', label: '新建文件夹', icon: Icons.create_new_folder_outlined),
          if (!isLocal) const MoonSelectOption(value: 'upload', label: '上传本地文件', icon: Icons.upload_file_rounded),
          if (!isLocal) const MoonSelectOption(value: 'terminal', label: '在此处打开终端', icon: Icons.terminal_rounded),
          if (!isLocal) const MoonSelectOption(value: 'ftp', label: '自动创建 FTP(vsftpd)', icon: Icons.dns_outlined),
        ],
        onSelected: (v) => _handleTopAction(context, v),
      ),
    ]),
  );

  Future<void> _handleTopAction(BuildContext context, String action) async {
    final state = context.read<AppState>();
    if (action == 'terminal') { await state.runTerminalCommand('cd ${state.currentPath} && pwd && ls -la'); return; }
    if (action == 'ftp') { final out = await state.ssh.installVsftpd(); if (context.mounted) showDialog(context: context, builder: (_) => AlertDialog(title: const Text('FTP 创建结果'), content: SingleChildScrollView(child: Text(out)))); return; }
    if (action == 'upload') { final picked = await FilePicker.platform.pickFiles(); final local = picked?.files.single.path; if (local != null) await state.uploadLocalFile(local); return; }
    final name = await _askName(context, action == 'new_dir' ? '新建文件夹' : '新建文件');
    if (name != null && name.trim().isNotEmpty) {
      if (isLocal) {
        await state.createLocalWorkspaceEntry(name.trim(), directory: action == 'new_dir', relativeDir: path == '/' ? '' : path.substring(1));
        onLocalRefresh?.call();
      } else {
        await state.createRemoteFile(name.trim(), directory: action == 'new_dir');
      }
    }
  }
}

class _TreeTile extends StatelessWidget {
  final RemoteFileEntry entry;
  final int depth;
  final bool isLocal;
  final VoidCallback reload;
  final ValueChanged<RemoteFileEntry>? openLocalDir;
  const _TreeTile({required this.entry, required this.depth, required this.isLocal, required this.reload, this.openLocalDir});
  @override
  Widget build(BuildContext context) {
    final isBak = entry.name.endsWith('.bak') || entry.name.contains('.bak.');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final state = context.read<AppState>();
if (entry.isDirectory) {
             if (isLocal) { openLocalDir?.call(entry); } else { await state.openDir(entry.path); }
           } else {
             final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => FileViewerScreen(state: state, path: entry.path, local: isLocal)));
             if (changed == true && context.mounted) reload();
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
            _MoonPopupButton(
              icon: Icons.more_vert_rounded,
              items: [
                const MoonSelectOption(value: 'rename', label: '重命名', icon: Icons.drive_file_rename_outline_rounded),
                if (!entry.isDirectory) const MoonSelectOption(value: 'duplicate', label: '复制', icon: Icons.copy_rounded),
                if (!isLocal) const MoonSelectOption(value: 'chmod', label: '权限 chmod', icon: Icons.admin_panel_settings_outlined),
                if (!entry.isDirectory) MoonSelectOption(value: 'download', label: isLocal ? '复制到下载目录' : '下载到默认下载目录', icon: Icons.download_rounded),
                if (!isLocal && isBak) const MoonSelectOption(value: 'restore', label: '从备份还原', icon: Icons.restore_rounded),
                const MoonSelectOption(value: 'delete', label: '删除', icon: Icons.delete_outline_rounded),
              ],
              onSelected: (v) => _handleEntryAction(context, v),
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
      final name = await _askName(context, '重命名', initial: entry.name); if (name != null && name.trim().isNotEmpty) { isLocal ? await state.renameLocalEntry(entry, name.trim()) : await state.renameRemote(entry, name.trim()); reload(); }
    } else if (action == 'duplicate') {
      final name = await _askName(context, '复制为', initial: '${entry.name}.copy'); if (name != null && name.trim().isNotEmpty) { isLocal ? await state.duplicateLocalEntry(entry, name.trim()) : await state.duplicateRemote(entry, name.trim()); reload(); }
    } else if (action == 'chmod') {
      final mode = await _askName(context, '权限 chmod', initial: '755'); if (mode != null && mode.trim().isNotEmpty) await state.chmodRemote(entry, mode.trim());
    } else if (action == 'download') {
      final dir = Directory('/storage/emulated/0/download'); if (!await dir.exists()) await dir.create(recursive: true); final file = isLocal ? await state.downloadLocalFile(entry, dir) : await state.downloadRemoteFile(entry, dir); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存到 ${file.path}')));
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('确认删除'), content: Text(entry.path), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))]));
      if (ok == true) { isLocal ? await state.deleteLocalEntry(entry) : await state.deleteRemote(entry); reload(); }
    }
  }
}

class _MoonPopupButton extends StatelessWidget {
  final IconData icon;
  final List<MoonSelectOption<String>> items;
  final ValueChanged<String> onSelected;
  const _MoonPopupButton({required this.icon, required this.items, required this.onSelected});
  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon),
        onPressed: () async {
          final selected = await showModalBottomSheet<String>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (_) => Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, item.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(color: MoonGlass.panel2(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.edge)),
                    child: Row(children: [Icon(item.icon ?? Icons.circle_outlined, size: 18, color: MoonColors.muted), const SizedBox(width: 10), Expanded(child: Text(item.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MoonColors.text)))]),
                  ),
                ),
              )).toList())),
            ),
          );
          if (selected != null) onSelected(selected);
        },
      );
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
String _parentLocal(String path) { final parts = path.split('/')..removeLast(); return parts.join('/'); }
String _relativeLocal(AppState state, String absolute) {
  final root = state.activeWorkspace?.path ?? '';
  if (root.isEmpty || !absolute.startsWith(root)) return '';
  return absolute.substring(root.length).replaceFirst(RegExp(r'^/+'), '');
}

Future<String?> _askName(BuildContext context, String title, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(context: context, builder: (_) => AlertDialog(title: Text(title), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '名称')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确认'))]));
}
