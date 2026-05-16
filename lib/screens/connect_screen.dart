import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/server_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class ConnectScreen extends StatefulWidget {
  final bool fullPage;
  const ConnectScreen({super.key, this.fullPage = false});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final host = TextEditingController();
  final port = TextEditingController(text: '22');
  final user = TextEditingController(text: 'root');
  final pass = TextEditingController();
  final root = TextEditingController(text: '/');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: widget.fullPage ? AppBar(title: const Text('Cloud 服务器')) : null,
      body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('连接 Linux 服务器', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      TextField(controller: host, decoration: const InputDecoration(labelText: 'Host / IP')),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'SSH Port'))), const SizedBox(width: 10), Expanded(child: TextField(controller: user, decoration: const InputDecoration(labelText: 'Username')))]),
      const SizedBox(height: 10),
      TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      const SizedBox(height: 10),
      TextField(controller: root, decoration: const InputDecoration(labelText: '默认远程目录')),
      const SizedBox(height: 18),
FilledButton.icon(
         onPressed: state.busy ? null : () async {
           final profile = ServerProfile(id: const Uuid().v4(), name: host.text, host: host.text.trim(), port: int.tryParse(port.text) ?? 22, username: user.text.trim(), password: pass.text, rootPath: root.text.trim().isEmpty ? '/' : root.text.trim());
           await context.read<AppState>().connect(profile, persistAutoReconnect: state.autoReconnect);
           if (context.mounted && !widget.fullPage) Navigator.maybePop(context);
         },
         icon: state.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
         label: const Text('连接并读取服务器信息'),
       ),
       CheckboxListTile(
         contentPadding: EdgeInsets.zero,
         value: state.autoReconnect,
         onChanged: (v) => context.read<AppState>().setAutoReconnect(v ?? false),
         title: const Text('下次启动自动连接此服务器'),
         subtitle: const Text('默认关闭；只有勾选后再连接才会自动重连。'),
       ),
       if (state.activeServerId != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => context.read<AppState>().disconnectServer(), icon: const Icon(Icons.link_off_rounded), label: const Text('断开并关闭自动连接'))),
      const SizedBox(height: 18),
      if (state.servers.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('已保存服务器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        for (final s in state.servers) Card(child: ListTile(
          leading: Icon(state.activeServerId == s.id ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded),
          title: Text(s.name),
          subtitle: Text('${s.username}@${s.host}:${s.port} · ${s.rootPath}'),
          trailing: state.activeServerId == s.id ? const Text('当前') : TextButton(onPressed: () => context.read<AppState>().switchServer(s.id), child: const Text('连接')),
        )),
      ],
      if (state.serverInfo != null) _InfoCard(info: state.serverInfo!),
    ]));
  }
}

class _InfoCard extends StatelessWidget {
  final ServerInfo info;
  const _InfoCard({required this.info});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(info.hostname, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: MoonColors.moon)),
    Text('OS: ${info.os}'), Text('Kernel: ${info.kernel}'), Text('Uptime: ${info.uptime}'), Text('CPU: ${info.cpu}'), Text('Memory: ${info.memory}'), Text('Disk: ${info.disk}'), Text('Load: ${info.load}'),
  ])));
}
