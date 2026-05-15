import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/agent_chat_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/file_manager_screen.dart';
import 'screens/terminal_screen.dart';
import 'services/app_state.dart';
import 'theme/moon_theme.dart';
import 'widgets/moon_scaffold.dart';

void main() => runApp(const LunaLinkApp());

class LunaLinkApp extends StatelessWidget {
  const LunaLinkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LunaLink Agent',
        theme: MoonTheme.dark,
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int panel = 0;

  @override
  Widget build(BuildContext context) {
    return MoonScaffold(
      child: Stack(children: [
        const Positioned.fill(child: AgentChatScreen(embedded: true)),
        Positioned(top: 10, left: 10, child: _GlassIcon(icon: Icons.menu_rounded, onTap: _openMenu)),
        Positioned(top: 10, right: 10, child: _GlassIcon(icon: Icons.settings_suggest_rounded, onTap: () => _showPanel(3))),
      ]),
    );
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: .72,
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: MoonColors.panel.withOpacity(.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: MoonColors.edge),
          ),
          child: Column(children: [
            Container(width: 44, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: MoonColors.edge, borderRadius: BorderRadius.circular(9))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                _MenuChip(icon: Icons.dns_rounded, label: '服务器', selected: panel == 0, onTap: () => _showPanel(0)),
                _MenuChip(icon: Icons.folder_rounded, label: '文件', selected: panel == 1, onTap: () => _showPanel(1)),
                _MenuChip(icon: Icons.terminal_rounded, label: '终端', selected: panel == 2, onTap: () => _showPanel(2)),
                _MenuChip(icon: Icons.tune_rounded, label: '设置', selected: panel == 3, onTap: () => _showPanel(3)),
              ]),
            ),
            const Divider(color: MoonColors.edge),
            Expanded(child: IndexedStack(index: panel, children: const [ConnectScreen(), FileManagerScreen(compact: true), TerminalScreen(), _SettingsAboutPanel()])),
          ]),
        ),
      ),
    );
  }

  void _showPanel(int index) {
    setState(() => panel = index);
    _openMenu();
  }
}

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: MoonColors.panel.withOpacity(.55),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(width: 46, height: 46, decoration: BoxDecoration(border: Border.all(color: MoonColors.edge), borderRadius: BorderRadius.circular(16)), child: Icon(icon)),
        ),
      );
}

class _MenuChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MenuChip({required this.icon, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(backgroundColor: selected ? MoonColors.accent.withOpacity(.28) : MoonColors.panel2.withOpacity(.6), padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
}

class _SettingsAboutPanel extends StatelessWidget {
  const _SettingsAboutPanel();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('设置与关于', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const Icon(Icons.auto_awesome_rounded), title: const Text('默认流式输出'), subtitle: const Text('AI 回复以流式体验更新，思考与工具调用默认折叠展示。'), trailing: Switch(value: true, onChanged: (_) {}))),
        Card(child: ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('默认主题'), subtitle: const Text('使用 Flutter Material 默认主题效果，去除月亮星空特效。'), trailing: Switch(value: true, onChanged: (_) {}))),
        const SizedBox(height: 8),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('关于 LunaLink Agent', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text('作者：北海cmbh'),
              Text('Linuxdo：北海呜'),
              SizedBox(height: 10),
              Text('本工具完全公益，设计初衷是为了移动端开发简化，适合没有电脑想搞开发的用户。'),
            ]),
          ),
        ),
      ]);
}
