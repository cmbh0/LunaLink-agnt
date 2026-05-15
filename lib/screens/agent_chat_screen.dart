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
    if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(children: [
      _TopBar(onSettings: () => _showAiConfig(context)),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: state.messages.isEmpty
              ? const _HeroEmpty(key: ValueKey('empty'))
              : ListView.builder(
                  key: const ValueKey('messages'),
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) => _Bubble(message: state.messages[i]),
                ),
        ),
      ),
      _Composer(controller: input, onSend: _send),
    ]);
  }

  Future<void> _showAiConfig(BuildContext context) async {
    final state = context.read<AppState>();
    final cfg = state.aiConfigs.first;
    var provider = cfg.provider;
    var apiMode = cfg.apiMode;
    var enableThinking = cfg.enableThinking;
    var stream = cfg.streamOutput;
    final endpoint = TextEditingController(text: cfg.endpoint);
    final model = TextEditingController(text: cfg.model);
    final thinkingModel = TextEditingController(text: cfg.thinkingModel ?? '');
    final key = TextEditingController(text: cfg.apiKey);
    final temp = TextEditingController(text: cfg.temperature.toString());
    final maxTokens = TextEditingController(text: cfg.maxTokens.toString());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(builder: (context, setDialog) => Padding(
        padding: EdgeInsets.only(left: 18, right: 18, bottom: MediaQuery.viewInsetsOf(context).bottom + 18),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('AI 设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          DropdownButtonFormField<AiProviderType>(
            value: provider,
            onChanged: (v) => setDialog(() { provider = v!; endpoint.text = providerEndpoints[provider] ?? endpoint.text; }),
            items: AiProviderType.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(),
            decoration: const InputDecoration(labelText: '模型提供商'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AiApiMode>(
            value: apiMode,
            onChanged: (v) => setDialog(() => apiMode = v!),
            items: const [DropdownMenuItem(value: AiApiMode.messages, child: Text('Messages / Chat Completions')), DropdownMenuItem(value: AiApiMode.responses, child: Text('Responses'))],
            decoration: const InputDecoration(labelText: '接口模式'),
          ),
          const SizedBox(height: 8), TextField(controller: endpoint, decoration: const InputDecoration(labelText: '接口地址 Endpoint')),
          const SizedBox(height: 8), TextField(controller: model, decoration: const InputDecoration(labelText: '对话模型')),
          const SizedBox(height: 8), TextField(controller: thinkingModel, decoration: const InputDecoration(labelText: '思考模型 / Reasoning Model')),
          const SizedBox(height: 8), TextField(controller: key, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
          const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: temp, decoration: const InputDecoration(labelText: 'Temperature'))), const SizedBox(width: 8), Expanded(child: TextField(controller: maxTokens, decoration: const InputDecoration(labelText: 'Max Tokens')))]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: enableThinking, onChanged: (v) => setDialog(() => enableThinking = v), title: const Text('启用思考内容折叠')),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: stream, onChanged: (v) => setDialog(() => stream = v), title: const Text('默认流式输出')),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))), const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: () async {
            await state.saveAiConfig(AiServiceConfig(id: cfg.id, name: provider.name, provider: provider, endpoint: endpoint.text.trim(), apiKey: key.text, model: model.text.trim().isEmpty ? cfg.model : model.text.trim(), thinkingModel: thinkingModel.text.trim().isEmpty ? null : thinkingModel.text.trim(), enableThinking: enableThinking, streamOutput: stream, temperature: double.tryParse(temp.text) ?? .2, maxTokens: int.tryParse(maxTokens.text) ?? 4096, apiMode: apiMode, permissionMode: state.permissionMode));
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('保存')))]),
        ])),
      )),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSettings;
  const _TopBar({required this.onSettings});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
      child: Row(children: [
        IconButton(onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu_rounded, size: 26)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFFE9E9E9), borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            _Segment(text: 'MTC', selected: state.agentMode == AgentMode.mtc, onTap: () => context.read<AppState>().setAgentMode(AgentMode.mtc)),
            _Segment(text: 'Code', selected: state.agentMode == AgentMode.code, onTap: () => context.read<AppState>().setAgentMode(AgentMode.code)),
          ]),
        ),
        const Spacer(),
        IconButton(onPressed: onSettings, icon: const Icon(Icons.tune_rounded, size: 24)),
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
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(24), boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(.07), blurRadius: 7, offset: const Offset(0, 2))] : null),
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: selected ? MoonColors.text : MoonColors.muted)),
    ),
  );
}

class _HeroEmpty extends StatelessWidget {
  const _HeroEmpty({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeServerId;
    final isMtc = state.agentMode == AgentMode.mtc;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: Padding(
        key: ValueKey(state.agentMode),
        padding: const EdgeInsets.fromLTRB(24, 96, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isMtc ? 'MTC' : 'Code', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w500, height: 1.12)),
          const SizedBox(height: 8),
          Text(isMtc ? '聊天模式，沟通好方案之后再构建项目的方案' : '编码模式，正式开始写项目，随心所欲', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400, height: 1.18)),
          const SizedBox(height: 18),
          if (state.servers.isNotEmpty) Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: active,
              hint: const Text('选择云服务器'),
              items: state.servers.map((e) => DropdownMenuItem(value: e.id, child: Text('${e.name} · ${e.host}'))).toList(),
              onChanged: (v) { if (v != null) context.read<AppState>().switchServer(v); },
            )),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AgentMessage message;
  const _Bubble({required this.message});
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .72),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: isUser ? MoonColors.accent.withOpacity(.11) : Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (message.thinking?.isNotEmpty == true) _Fold(title: '思考内容', icon: Icons.psychology_rounded, child: Text(message.thinking!, style: const TextStyle(color: MoonColors.muted))),
            MarkdownBody(data: message.content, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: const TextStyle(color: MoonColors.text, height: 1.42), code: const TextStyle(fontFamily: 'monospace', color: MoonColors.warn), codeblockDecoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(12)))),
            for (final t in message.toolCalls) _ToolApproval(call: t),
            for (final c in message.changes) _ChangeApproval(change: c),
          ]),
        ),
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
      width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(14)),
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
      width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(14)),
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
  const _Composer({required this.controller, required this.onSend});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 14, offset: const Offset(0, 4))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '发消息...', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _MiniAction(icon: const Icon(Icons.cloud_outlined, size: 16), label: 'Cloud', onTap: () => Navigator.push(context, _softRoute(const ConnectScreen(fullPage: true)))),
          const SizedBox(width: 10),
          _MiniAction.custom(icon: const _GitHubMark(size: 15), label: 'GitHub', onTap: () => Navigator.push(context, _softRoute(const GitHubSettingsScreen()))),
          const Spacer(),
          IconButton.filled(onPressed: onSend, style: IconButton.styleFrom(backgroundColor: MoonColors.accent, minimumSize: const Size(38, 38)), icon: const Icon(Icons.send_rounded, size: 18)),
        ]),
      ]),
    ),
  );
}

PageRouteBuilder<void> _softRoute(Widget page) => PageRouteBuilder<void>(
  transitionDuration: const Duration(milliseconds: 260),
  reverseTransitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: child)),
);

class _MiniAction extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  const _MiniAction({required this.icon, required this.label, required this.onTap});
  const _MiniAction.custom({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))])));
}

class _GitHubMark extends StatelessWidget {
  final double size;
  const _GitHubMark({required this.size});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GitHubPainter());
}

class _GitHubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black87;
    canvas.drawCircle(size.center(Offset.zero), size.width * .48, p);
    canvas.drawCircle(Offset(size.width * .28, size.height * .18), size.width * .14, p);
    canvas.drawCircle(Offset(size.width * .72, size.height * .18), size.width * .14, p);
    final cut = Paint()..color = Colors.white;
    canvas.drawOval(Rect.fromLTWH(size.width * .28, size.height * .36, size.width * .44, size.height * .30), cut);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}