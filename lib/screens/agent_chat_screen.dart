import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';
import 'connect_screen.dart';
import 'github_settings_screen.dart';

class AgentChatScreen extends StatefulWidget {
  final bool embedded;
  const AgentChatScreen({super.key, this.embedded = false});
  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    await context.read<AppState>().sendAgentTask(text);
    if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(children: [
      _TopBar(onSettings: () => _showAiConfig(context)),
      Expanded(
        child: state.messages.isEmpty ? const _HeroEmpty() : ListView.builder(controller: scroll, padding: const EdgeInsets.fromLTRB(24, 12, 24, 10), itemCount: state.messages.length, itemBuilder: (context, i) => _Bubble(message: state.messages[i])),
      ),
      _Composer(controller: input, onSend: _send, onConfig: () => _showAiConfig(context)),
      const _BottomActions(),
    ]);
  }

  Future<void> _showAiConfig(BuildContext context) async {
    final state = context.read<AppState>();
    final cfg = state.aiConfigs.first;
    var provider = cfg.provider;
    var enableThinking = cfg.enableThinking;
    var stream = cfg.streamOutput;
    final endpoint = TextEditingController(text: cfg.endpoint);
    final model = TextEditingController(text: cfg.model);
    final thinkingModel = TextEditingController(text: cfg.thinkingModel ?? '');
    final key = TextEditingController(text: cfg.apiKey);
    final temp = TextEditingController(text: cfg.temperature.toString());
    final maxTokens = TextEditingController(text: cfg.maxTokens.toString());
    await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: const Text('AI / 思考模型配置'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<AiProviderType>(value: provider, onChanged: (v) => setDialog(() => provider = v!), items: AiProviderType.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(), decoration: const InputDecoration(labelText: 'Provider')),
        const SizedBox(height: 8), TextField(controller: endpoint, decoration: const InputDecoration(labelText: 'Endpoint')),
        const SizedBox(height: 8), TextField(controller: model, decoration: const InputDecoration(labelText: '对话模型')),
        const SizedBox(height: 8), TextField(controller: thinkingModel, decoration: const InputDecoration(labelText: '思考模型 / Reasoning Model')),
        const SizedBox(height: 8), TextField(controller: key, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
        const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: temp, decoration: const InputDecoration(labelText: 'Temperature'))), const SizedBox(width: 8), Expanded(child: TextField(controller: maxTokens, decoration: const InputDecoration(labelText: 'Max Tokens')))]),
        SwitchListTile(value: enableThinking, onChanged: (v) => setDialog(() => enableThinking = v), title: const Text('启用思考内容折叠')),
        SwitchListTile(value: stream, onChanged: (v) => setDialog(() => stream = v), title: const Text('默认流式输出')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () async {
        await state.saveAiConfig(AiServiceConfig(id: cfg.id, name: provider.name, provider: provider, endpoint: endpoint.text.trim(), apiKey: key.text, model: model.text.trim().isEmpty ? cfg.model : model.text.trim(), thinkingModel: thinkingModel.text.trim().isEmpty ? null : thinkingModel.text.trim(), enableThinking: enableThinking, streamOutput: stream, temperature: double.tryParse(temp.text) ?? .2, maxTokens: int.tryParse(maxTokens.text) ?? 4096, permissionMode: state.permissionMode));
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('保存'))],
    )));
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSettings;
  const _TopBar({required this.onSettings});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 0),
      child: Row(children: [
        IconButton(onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu_rounded, size: 30)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: const Color(0xFFE9E9E9), borderRadius: BorderRadius.circular(32)),
          child: Row(children: [
            _Segment(text: 'MTC', selected: state.agentMode == AgentMode.mtc, onTap: () => context.read<AppState>().setAgentMode(AgentMode.mtc)),
            _Segment(text: 'Code', selected: state.agentMode == AgentMode.code, onTap: () => context.read<AppState>().setAgentMode(AgentMode.code)),
          ]),
        ),
        const Spacer(),
        _CircleButton(icon: Icons.tune_rounded, onTap: onSettings),
      ]),
    );
  }
}

class _Segment extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({required this.text, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(28), boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 8)] : null),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    ),
  );
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(color: Colors.white, shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 54, height: 54, child: Icon(icon))));
}

class _HeroEmpty extends StatelessWidget {
  const _HeroEmpty();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeServerId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 130, 28, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Hey 👋 用户', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w400, height: 1.15)),
        const SizedBox(height: 2),
        const Text('代码开发，从这里开始', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w400, height: 1.15)),
        const SizedBox(height: 22),
        if (state.servers.isNotEmpty) Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: active,
            hint: const Text('选择云服务器'),
            items: state.servers.map((e) => DropdownMenuItem(value: e.id, child: Text('${e.name} · ${e.host}'))).toList(),
            onChanged: (v) { if (v != null) context.read<AppState>().switchServer(v); },
          )),
        ),
      ]),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(34, 0, 34, 14),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _NavAction(icon: Icons.cloud_outlined, label: 'Cloud', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen(fullPage: true)))),
      _NavAction(icon: Icons.hub_outlined, label: '连接 Github', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GitHubSettingsScreen()))),
      _NavAction(icon: Icons.account_tree_outlined, label: '分支', muted: true, onTap: () {}),
    ]),
  );
}

class _NavAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;
  final VoidCallback onTap;
  const _NavAction({required this.icon, required this.label, required this.onTap, this.muted = false});
  @override
  Widget build(BuildContext context) => InkWell(onTap: muted ? null : onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Row(children: [Icon(icon, color: muted ? Colors.black26 : Colors.black87), const SizedBox(width: 8), Text(label, style: TextStyle(fontSize: 16, color: muted ? Colors.black26 : Colors.black87, fontWeight: FontWeight.w500))])));
}

class _Bubble extends StatelessWidget {
  final AgentMessage message;
  const _Bubble({required this.message});
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: MediaQuery.sizeOf(context).width * .88,
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: isUser ? MoonColors.accent.withOpacity(.10) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: MoonColors.edge)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (message.thinking?.isNotEmpty == true) _Fold(title: '思考内容', icon: Icons.psychology_rounded, child: Text(message.thinking!, style: const TextStyle(color: MoonColors.muted))),
          MarkdownBody(data: message.content, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: const TextStyle(color: MoonColors.text, height: 1.45), code: const TextStyle(fontFamily: 'monospace', color: MoonColors.warn), codeblockDecoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(12)))),
          for (final t in message.toolCalls) _ToolApproval(call: t),
          for (final c in message.changes) _ChangeApproval(change: c),
        ]),
      ),
    );
  }
}

class _Fold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Fold({required this.title, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) => Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(tilePadding: EdgeInsets.zero, leading: Icon(icon, color: MoonColors.purple), title: Text(title), children: [Align(alignment: Alignment.centerLeft, child: child)]));
}

class _ToolApproval extends StatelessWidget {
  final ToolCallRecord call;
  const _ToolApproval({required this.call});
  @override
  Widget build(BuildContext context) {
    final done = {'done', 'rejected', 'error'}.contains(call.status);
    return _Fold(title: '工具调用：${call.tool} [${call.status}]', icon: Icons.build_circle_rounded, child: Container(
      width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.edge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('参数：${call.arguments}', style: const TextStyle(fontFamily: 'monospace')),
        if (call.output != null) Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Text(call.output!, maxLines: 10, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace'))),
        if (!done) Row(children: [TextButton(onPressed: () => context.read<AppState>().rejectTool(call.id), child: const Text('拒绝')), FilledButton(onPressed: () => context.read<AppState>().executeTool(call.id), child: const Text('授权执行'))]),
      ]),
    ));
  }
}

class _ChangeApproval extends StatelessWidget {
  final FileChangeRecord change;
  const _ChangeApproval({required this.change});
  @override
  Widget build(BuildContext context) {
    final done = {'saved', 'rejected'}.contains(change.status);
    return _Fold(title: '文件 Diff：${change.path} [${change.status}]', icon: Icons.difference_rounded, child: Container(
      width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.edge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DiffBlock(oldText: change.oldText, newText: change.newText),
        if (!done) Row(children: [TextButton(onPressed: () => context.read<AppState>().rejectChange(change.id), child: const Text('拒绝')), FilledButton(onPressed: () => context.read<AppState>().applyChange(change.id), child: const Text('保存更改'))]),
      ]),
    ));
  }
}

class _DiffBlock extends StatelessWidget {
  final String oldText;
  final String newText;
  const _DiffBlock({required this.oldText, required this.newText});
  @override
  Widget build(BuildContext context) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('新增 ${newLines.length} 行 / 删除 ${oldLines.length} 行', style: const TextStyle(color: MoonColors.muted)),
      const SizedBox(height: 6),
      ...oldLines.take(8).map((e) => Container(width: double.infinity, color: MoonColors.danger.withOpacity(.10), child: Text('- $e', style: const TextStyle(color: MoonColors.danger, fontFamily: 'monospace')))),
      ...newLines.take(8).map((e) => Container(width: double.infinity, color: MoonColors.ok.withOpacity(.10), child: Text('+ $e', style: const TextStyle(color: MoonColors.ok, fontFamily: 'monospace')))),
    ]);
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final AsyncCallback onSend;
  final VoidCallback onConfig;
  const _Composer({required this.controller, required this.onSend, required this.onConfig});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(28, 6, 28, 4), child: Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: MoonColors.edge), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 12)]),
    child: Column(children: [
      TextField(controller: controller, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: '发消息或按住说话...', border: InputBorder.none, enabledBorder: InputBorder.none, filled: false)),
      const SizedBox(height: 4),
      Row(children: [IconButton.filledTonal(onPressed: onConfig, icon: const Icon(Icons.add_rounded)), const Spacer(), IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.mic_none_rounded)), const SizedBox(width: 8), IconButton.filled(onPressed: onSend, style: IconButton.styleFrom(backgroundColor: MoonColors.accent), icon: const Icon(Icons.graphic_eq_rounded))]),
    ]),
  ));
}