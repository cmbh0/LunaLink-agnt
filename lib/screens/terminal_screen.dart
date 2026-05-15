import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final input = TextEditingController();
  bool running = false;

  Future<void> _run() async {
    final cmd = input.text.trim();
    if (cmd.isEmpty) return;
    input.clear();
    setState(() => running = true);
    await context.read<AppState>().runTerminalCommand(cmd);
    if (mounted) setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          const Icon(Icons.terminal_rounded, color: MoonColors.ok),
          const SizedBox(width: 8),
          const Expanded(child: Text('模拟终端 / AI 指令回显', style: TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => context.read<AppState>().clearTerminalLogs(), icon: const Icon(Icons.cleaning_services_rounded)),
        ]),
      ),
      if (running) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withOpacity(.55), borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
        child: ListView(children: state.terminalLogs.map((e) => Text(e, style: const TextStyle(fontFamily: 'monospace', color: MoonColors.ok, height: 1.35))).toList()),
      )),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: TextField(controller: input, decoration: const InputDecoration(hintText: '输入 SSH 命令，例如: pwd && ls -la'))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: running ? null : _run, icon: const Icon(Icons.play_arrow_rounded)),
        ]),
      ),
    ]);
  }
}
