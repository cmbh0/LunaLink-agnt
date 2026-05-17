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

  void _appendKey(String value) {
    final text = input.text;
    final sel = input.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    input.text = text.replaceRange(start, end, value);
    input.selection = TextSelection.collapsed(offset: start + value.length);
  }

  Future<void> _quickKey(String sequence, String label) => context.read<AppState>().sendTerminalKey(sequence, label);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('SSH 终端')),
      body: SafeArea(child: Column(children: [
        if (running) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(14)),
          child: ListView(children: state.terminalLogs.map((e) => Text(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF89DCEB), height: 1.4))).toList()),
        )),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            _KeyButton(label: 'ESC', onTap: () => _appendKey('\u001b')),
            _KeyButton(label: 'CTRL', onTap: () => _appendKey('^')),
            _KeyButton(label: 'Ctrl+C', onTap: () => _quickKey('\u0003', 'Ctrl+C')),
            _KeyButton(label: 'TAB', onTap: () => _appendKey('\t')),
            _KeyButton(label: '/', onTap: () => _appendKey('/')),
            _KeyButton(label: '-', onTap: () => _appendKey('-')),
            _KeyButton(label: '~', onTap: () => _appendKey('~')),
            _KeyButton(label: '↑', onTap: () => _appendKey('↑')),
            _KeyButton(label: '↓', onTap: () => _appendKey('↓')),
          ]),
        ),
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

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _KeyButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      onPressed: onTap,
      backgroundColor: MoonColors.panel2,
      side: const BorderSide(color: MoonColors.edge),
      visualDensity: VisualDensity.compact,
    ),
  );
}
