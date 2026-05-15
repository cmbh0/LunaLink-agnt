import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

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
      const SizedBox(height: 58),
      Padding(
        padding: const EdgeInsets.fromLTRB(68, 0, 68, 8),
        child: Column(children: const [
          Text('LunaLink Agent', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: .2)),
          SizedBox(height: 2),
          Text('移动端 AI 开发工作台', style: TextStyle(color: MoonColors.muted, fontSize: 12)),
        ]),
      ),
      if (state.busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: state.messages.isEmpty ? const _EmptyChat() : ListView.builder(controller: scroll, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), itemCount: state.messages.length, itemBuilder: (context, i) => _Bubble(message: state.messages[i])),
      ),
      _Composer(controller: input, onSend: _send, onConfig: () => _showAiConfig(context)),
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          await state.saveAiConfig(AiServiceConfig(id: cfg.id, name: provider.name, provider: provider, endpoint: endpoint.text.trim(), apiKey: key.text, model: model.text.trim().isEmpty ? cfg.model : model.text.trim(), thinkingModel: thinkingModel.text.trim().isEmpty ? null : thinkingModel.text.trim(), enableThinking: enableThinking, streamOutput: stream, temperature: double.tryParse(temp.text) ?? .2, maxTokens: int.tryParse(maxTokens.text) ?? 4096, permissionMode: state.permissionMode));
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('保存')),
      ],
    )));
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) => Center(child: Container(
    margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: MoonColors.panel.withOpacity(.55), borderRadius: BorderRadius.circular(24), border: Border.all(color: MoonColors.edge)),
    child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome_rounded, size: 52, color: MoonColors.accent), SizedBox(height: 12), Text('直接描述你想做的开发任务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), SizedBox(height: 8), Text('文件、终端、工具调用、diff 变更都会在对话内折叠展示。', textAlign: TextAlign.center, style: TextStyle(color: MoonColors.muted))]),
  ));
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isUser ? MoonColors.accent.withOpacity(.24) : MoonColors.panel.withOpacity(.78), borderRadius: BorderRadius.circular(20), border: Border.all(color: isUser ? MoonColors.accent.withOpacity(.5) : MoonColors.edge)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (message.thinking?.isNotEmpty == true) _Fold(title: '思考内容', icon: Icons.psychology_rounded, child: Text(message.thinking!, style: const TextStyle(color: MoonColors.muted))),
          MarkdownBody(data: message.content, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: const TextStyle(color: MoonColors.text, height: 1.45), code: const TextStyle(fontFamily: 'monospace', color: MoonColors.warn), codeblockDecoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)))),
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
      width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.warn.withOpacity(.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('参数：${call.arguments}', style: const TextStyle(fontFamily: 'monospace')),
        if (call.output != null) Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)), child: Text(call.output!, maxLines: 10, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace'))),
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
      width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.accent.withOpacity(.45))),
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
      ...oldLines.take(8).map((e) => Container(width: double.infinity, color: MoonColors.danger.withOpacity(.12), child: Text('- $e', style: const TextStyle(color: MoonColors.danger, fontFamily: 'monospace')))),
      ...newLines.take(8).map((e) => Container(width: double.infinity, color: MoonColors.ok.withOpacity(.12), child: Text('+ $e', style: const TextStyle(color: MoonColors.ok, fontFamily: 'monospace')))),
    ]);
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final AsyncCallback onSend;
  final VoidCallback onConfig;
  const _Composer({required this.controller, required this.onSend, required this.onConfig});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: MoonColors.panel.withOpacity(.86), borderRadius: BorderRadius.circular(24), border: Border.all(color: MoonColors.edge)),
    child: Row(children: [
      IconButton(onPressed: onConfig, icon: const Icon(Icons.tune_rounded)),
      IconButton(onPressed: () {}, icon: const Icon(Icons.attach_file_rounded)),
      Expanded(child: TextField(controller: controller, minLines: 1, maxLines: 5, decoration: const InputDecoration(hintText: '描述任务，默认流式输出...', border: InputBorder.none, enabledBorder: InputBorder.none, filled: false))),
      IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send_rounded)),
    ]),
  ));
}
