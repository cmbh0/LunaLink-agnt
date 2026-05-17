import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../models/server_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cloudServers = state.servers;
    return Scaffold(
            appBar: AppBar(title: const Text('工作区绑定')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: state.developmentEnvironment == DevelopmentEnvironment.cloud ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(14), border: Border.all(color: state.developmentEnvironment == DevelopmentEnvironment.cloud ? const Color(0xFFBFDBFE) : const Color(0xFFBBF7D0))),
          child: Row(children: [
            Icon(state.developmentEnvironment == DevelopmentEnvironment.cloud ? Icons.cloud_outlined : Icons.laptop_mac_rounded, size: 18, color: state.developmentEnvironment == DevelopmentEnvironment.cloud ? const Color(0xFF2563EB) : const Color(0xFF16A34A)),
            const SizedBox(width: 8),
            Expanded(child: Text('当前开发环境：${state.developmentEnvironment.label}。切换后 AI 工具优先级会随之调整。', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: state.developmentEnvironment == DevelopmentEnvironment.cloud ? const Color(0xFF1D4ED8) : const Color(0xFF15803D)))),
          ]),
        ),
        const SizedBox(height: 12),
        SegmentedButton<DevelopmentEnvironment>(
          segments: const [
            ButtonSegment(value: DevelopmentEnvironment.cloud, icon: Icon(Icons.cloud_outlined), label: Text('Cloud')),
            ButtonSegment(value: DevelopmentEnvironment.local, icon: Icon(Icons.laptop_mac_rounded), label: Text('Local')),
          ],
          selected: {state.developmentEnvironment},
          onSelectionChanged: (v) => context.read<AppState>().setDevelopmentEnvironment(v.first),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('本地工作区绑定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('应用内创建的工作区全部是本地工作区，每个对话可绑定一个。', style: TextStyle(fontSize: 12, color: MoonColors.muted)),
            const SizedBox(height: 10),
            MoonSelectField<String>(
              value: state.boundWorkspaceId,
              label: '绑定本地工作区',
              options: [const MoonSelectOption<String>(value: '', label: '不绑定', icon: Icons.link_off_rounded), ...state.localWorkspaces.map((w) => MoonSelectOption<String>(value: w.id, label: w.name, icon: Icons.folder_rounded))],
              onChanged: (v) => context.read<AppState>().bindWorkspace(v == null || v.isEmpty ? null : v),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.create_new_folder_rounded), label: const Text('新建本地并绑定')),
              if (state.activeWorkspace != null) OutlinedButton.icon(onPressed: () => context.read<AppState>().bindWorkspace(null), icon: const Icon(Icons.link_off_rounded), label: const Text('解绑本地')),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cloud 工作目录绑定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Cloud 不在应用内创建工作区；这里只是绑定服务器上的一个目录，AI 可在该目录内继续创建项目目录和操作文件。', style: TextStyle(fontSize: 12, color: MoonColors.muted, height: 1.4)),
            const SizedBox(height: 10),
            MoonSelectField<String>(
              value: state.boundCloudWorkspace?.serverId ?? '',
              label: '绑定服务器',
              options: [const MoonSelectOption<String>(value: '', label: '不绑定', icon: Icons.link_off_rounded), ...cloudServers.map((s) => MoonSelectOption<String>(value: s.id, label: '${s.name} · ${s.mode.label}', icon: Icons.cloud_outlined))],
              onChanged: (v) => context.read<AppState>().bindCloudWorkspace(serverId: v == null || v.isEmpty ? null : v, path: v == null || v.isEmpty ? null : (state.boundCloudWorkspace?.path ?? state.currentPath)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: state.boundCloudWorkspace?.path ?? state.currentPath,
              decoration: const InputDecoration(labelText: 'Cloud 目录路径', hintText: '/home/user/project'),
              onFieldSubmitted: (v) {
                final serverId = state.boundCloudWorkspace?.serverId ?? state.activeServerId;
                if (serverId != null) context.read<AppState>().bindCloudWorkspace(serverId: serverId, path: v);
              },
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: state.activeServerId == null ? null : () => context.read<AppState>().bindCloudWorkspace(serverId: state.activeServerId, path: state.currentPath), icon: const Icon(Icons.my_location_rounded), label: const Text('绑定当前 Cloud 目录')),
              if (state.boundCloudWorkspace != null) OutlinedButton.icon(onPressed: () => context.read<AppState>().bindCloudWorkspace(), icon: const Icon(Icons.link_off_rounded), label: const Text('解绑 Cloud')),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('本地工作区列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
              const Text('当前本地工作区文件（隐藏 .backup）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (state.activeWorkspace == null) const Text('当前对话未绑定本地工作区。'),
              for (final f in files) ListTile(dense: true, leading: Icon(f.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined), title: Text(f.name), subtitle: Text('${f.size} bytes')),
            ]);
          },
        ),
      ]),
    );
  }

  Future<void> _create(BuildContext context) async {
    final c = TextEditingController(text: 'workspace');
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('新建本地工作区'), content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: '名称')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('创建'))]));
    if (name != null && context.mounted) await context.read<AppState>().createLocalWorkspace(name);
  }

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('确认删除本地工作区'), content: const Text('本地工作区文件和 .backup 将一起删除。Cloud 绑定不会受影响。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除'))]));
    if (ok == true && context.mounted) await context.read<AppState>().deleteLocalWorkspace(id);
  }
}
