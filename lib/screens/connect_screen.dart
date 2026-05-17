import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
  ServerAccessMode mode = ServerAccessMode.linux;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.fullPage ? AppBar(title: const Text('Cloud 服务器')) : null,
      body: ListView(padding: const EdgeInsets.all(16), children: [
const Text('连接服务器 / 虚拟主机', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
       const SizedBox(height: 12),
       InkWell(
         borderRadius: BorderRadius.circular(18),
         onTap: () => launchUrl(Uri.parse('https://sadidc.com/aff/LYGJKADP'), mode: LaunchMode.externalApplication),
         child: Container(
           padding: const EdgeInsets.all(14),
           decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)]), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF97316), width: 1.2)),
           child: const Row(children: [Icon(Icons.local_fire_department_rounded, color: Color(0xFFF97316)), SizedBox(width: 10), Expanded(child: Text('没有服务器？点击购买超低价 Cloud 服务，包括 NAT 机等产品！', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF9A3412))))]),
         ),
       ),
       const SizedBox(height: 12),
MoonSelectField<ServerAccessMode>(
          value: mode,
          label: '连接模式',
          options: ServerAccessMode.values.map((e) => MoonSelectOption(value: e, label: e.label, icon: Icons.terminal_rounded)).toList(),
          onChanged: (v) => setState(() { mode = v ?? ServerAccessMode.linux; port.text = mode == ServerAccessMode.ftp ? '21' : '22'; }),
        ),
      TextField(controller: host, decoration: const InputDecoration(labelText: 'Host / IP')),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: mode == ServerAccessMode.ftp ? 'FTP Port' : 'SSH/SFTP Port'))), const SizedBox(width: 10), Expanded(child: TextField(controller: user, decoration: const InputDecoration(labelText: 'Username')))]),
      const SizedBox(height: 10),
      TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      const SizedBox(height: 10),
      TextField(controller: root, decoration: const InputDecoration(labelText: '默认远程目录')),
      const SizedBox(height: 18),
FilledButton.icon(
         onPressed: state.busy ? null : () async {
           final profile = ServerProfile(id: const Uuid().v4(), name: host.text.trim(), host: host.text.trim(), port: int.tryParse(port.text) ?? (mode == ServerAccessMode.ftp ? 21 : 22), username: user.text.trim(), password: pass.text, rootPath: root.text.trim().isEmpty ? '/' : root.text.trim(), mode: mode);
           await context.read<AppState>().connect(profile, persistAutoReconnect: state.autoReconnect);
           if (context.mounted && !widget.fullPage) Navigator.maybePop(context);
         },
         icon: state.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
label: Text(mode.terminalEnabled ? '连接并读取服务器信息' : '连接文件服务'),
        ),
       if (state.activeServerId != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => context.read<AppState>().disconnectServer(), icon: const Icon(Icons.link_off_rounded), label: const Text('断开并关闭自动连接'))),
      const SizedBox(height: 18),
      if (state.servers.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('已保存服务器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        for (final s in state.servers) Card(child: ListTile(
          leading: Icon(state.activeServerId == s.id ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded),
          title: Text(s.name),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.username}@${s.host}:${s.port} · ${s.rootPath}'),
            const SizedBox(height: 6),
            MoonSelectField<bool>(
              value: s.autoConnect,
              label: '启动时自动连接',
              dense: true,
              options: const [MoonSelectOption(value: false, label: '不自动连接', icon: Icons.link_off_rounded), MoonSelectOption(value: true, label: '自动连接此项', icon: Icons.link_rounded)],
              onChanged: (v) => context.read<AppState>().updateServerAutoConnect(s.id, v ?? false),
            ),
          ]),
          trailing: Wrap(spacing: 4, children: [
            if (state.activeServerId == s.id) const Padding(padding: EdgeInsets.only(top: 8), child: Text('当前')) else TextButton(onPressed: () => context.read<AppState>().switchServer(s.id), child: const Text('连接')),
            IconButton(onPressed: () => context.read<AppState>().deleteServer(s.id), icon: const Icon(Icons.delete_outline_rounded, color: MoonColors.danger)),
          ]),
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
