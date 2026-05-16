import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('SSH 终端')),
      body: SafeArea(child: Column(children: [
        if (running) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(14)),
          child: ListView(children: state.terminalLogs.map((e) => Text(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF89DCEB), height: 1.4))).toList()),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Row(children: [
            Expanded(child: TextField(controller: input, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(hintText: '输入命令...', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: running ? null : _run, icon: const Icon(Icons.play_arrow_rounded, size: 20)),
          ]),
        ),
      ])),
    );
  }
}
