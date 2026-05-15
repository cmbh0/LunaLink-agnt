import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/server_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
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
    return ListView(padding: const EdgeInsets.all(16), children: [
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
          await context.read<AppState>().connect(profile);
          if (context.mounted) DefaultTabController.of(context).animateTo(1);
        },
        icon: state.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
        label: const Text('连接并读取服务器信息'),
      ),
      const SizedBox(height: 18),
      if (state.serverInfo != null) _InfoCard(info: state.serverInfo!),
    ]);
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
