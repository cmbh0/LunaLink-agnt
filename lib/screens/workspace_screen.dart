import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('本地工作区')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFBBF7D0))), child: const Row(children: [Icon(Icons.workspaces_outline, size: 16, color: Color(0xFF16A34A)), SizedBox(width: 8), Expanded(child: Text('本地：当前页面管理本机工作区，不是 Cloud 远程目录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF15803D))))])),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('当前对话绑定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: state.boundWorkspaceId,
              decoration: const InputDecoration(labelText: '绑定工作区'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('不绑定')), ...state.localWorkspaces.map((w) => DropdownMenuItem<String?>(value: w.id, child: Text(w.name)))],
              onChanged: (v) => context.read<AppState>().bindWorkspace(v),
            ),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.create_new_folder_rounded), label: const Text('新建并绑定')),
              const SizedBox(width: 8),
              if (state.activeWorkspace != null) OutlinedButton.icon(onPressed: () => context.read<AppState>().bindWorkspace(null), icon: const Icon(Icons.link_off_rounded), label: const Text('解绑')),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('工作区列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (state.localWorkspaces.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('暂无本地工作区'))),
        for (final w in state.localWorkspaces) Card(child: ListTile(
          leading: Icon(state.boundWorkspaceId == w.id ? Icons.folder_special_rounded : Icons.folder_rounded, color: MoonColors.accent),
          title: Text(w.name),
          subtitle: Text(w.path, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Wrap(spacing: 4, children: [
            TextButton(onPressed: () => context.read<AppState>().bindWorkspace(w.id), child: const Text('绑定')),
            IconButton(onPressed: () => _delete(context, w.id), icon: const Icon(Icons.delete_outline_rounded, color: MoonColors.danger)),
          ]),
        )),
        const SizedBox(height: 16),
        FutureBuilder(
          future: state.listLocalWorkspace(),
          builder: (context, snap) {
            final files = snap.data ?? const [];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('当前工作区文件（隐藏 .backup）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (state.activeWorkspace == null) const Text('当前对话未绑定工作区。'),
              for (final f in files) ListTile(dense: true, leading: Icon(f.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined), title: Text(f.name), subtitle: Text('${f.size} bytes')),
            ]);
          },
        ),
      ]),
    );
  }

  Future<void> _create(BuildContext context) async {
    final c = TextEditingController(text: 'workspace');
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('新建工作区'), content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: '名称')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('创建'))]));
    if (name != null && context.mounted) await context.read<AppState>().createLocalWorkspace(name);
  }

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('确认删除工作区'), content: const Text('工作区文件和 .backup 将一起删除。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))]));
    if (ok == true && context.mounted) await context.read<AppState>().deleteLocalWorkspace(id);
  }
}
