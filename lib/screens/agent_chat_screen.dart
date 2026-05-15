import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});
  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final input = TextEditingController();

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    await context.read<AppState>().sendAgentTask(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          const Text('Agent 自动运行策略'),
          const SizedBox(width: 10),
          DropdownButton<ToolPermissionMode>(
            value: state.permissionMode,
            onChanged: (v) => context.read<AppState>().setPermissionMode(v!),
            items: const [
              DropdownMenuItem(value: ToolPermissionMode.askEveryTime, child: Text('每次询问')),
              DropdownMenuItem(value: ToolPermissionMode.autoReadOnly, child: Text('自动只读')),
              DropdownMenuItem(value: ToolPermissionMode.autoAll, child: Text('自动全部')),
            ],
          ),
          const Spacer(),
          IconButton(onPressed: () => _showAiConfig(context), icon: const Icon(Icons.settings_rounded)),
        ]),
      ),
      if (state.busy) const LinearProgressIndicator(),
      Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: state.messages.length, itemBuilder: (context, i) => _Bubble(message: state.messages[i]))),
      _Composer(controller: input, onSend: _send),
    ]);
  }

  Future<void> _showAiConfig(BuildContext context) async {
    final state = context.read<AppState>();
    final cfg = state.aiConfigs.first;
    var provider = cfg.provider;
    final endpoint = TextEditingController(text: cfg.endpoint);
    final model = TextEditingController(text: cfg.model);
    final key = TextEditingController(text: cfg.apiKey);
    await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: const Text('AI 服务配置'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<AiProviderType>(value: provider, onChanged: (v) => setDialog(() => provider = v!), items: AiProviderType.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(), decoration: const InputDecoration(labelText: 'Provider')),
        const SizedBox(height: 8), TextField(controller: endpoint, decoration: const InputDecoration(labelText: 'Endpoint')),
        const SizedBox(height: 8), TextField(controller: model, decoration: const InputDecoration(labelText: 'Model')),
        const SizedBox(height: 8), TextField(controller: key, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () async {
          await state.saveAiConfig(AiServiceConfig(id: cfg.id, name: provider.name, provider: provider, endpoint: endpoint.text.trim(), apiKey: key.text, model: model.text.trim().isEmpty ? cfg.model : model.text.trim(), permissionMode: state.permissionMode));
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('保存')),
      ],
    )));
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
      child: Container(
        width: MediaQuery.sizeOf(context).width * .86,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isUser ? MoonColors.accent.withOpacity(.22) : MoonColors.panel.withOpacity(.94), borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message.content),
          for (final t in message.toolCalls) _ToolApproval(call: t),
          for (final c in message.changes) _ChangeApproval(change: c),
        ]),
      ),
    );
  }
}

class _ToolApproval extends StatelessWidget {
  final ToolCallRecord call;
  const _ToolApproval({required this.call});
  @override
  Widget build(BuildContext context) {
    final done = {'done', 'rejected', 'error'}.contains(call.status);
    return Container(
      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.warn.withOpacity(.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('工具：${call.tool}  [${call.status}]', style: const TextStyle(color: MoonColors.warn, fontWeight: FontWeight.bold)),
        Text(call.arguments.toString(), style: const TextStyle(fontFamily: 'monospace')),
        if (call.output != null) Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)), child: Text(call.output!, maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace'))),
        if (!done) Row(children: [TextButton(onPressed: () => context.read<AppState>().rejectTool(call.id), child: const Text('拒绝')), FilledButton(onPressed: () => context.read<AppState>().executeTool(call.id), child: const Text('授权执行'))]),
      ]),
    );
  }
}

class _ChangeApproval extends StatelessWidget {
  final FileChangeRecord change;
  const _ChangeApproval({required this.change});
  @override
  Widget build(BuildContext context) {
    final done = {'saved', 'rejected'}.contains(change.status);
    return Container(
      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.accent.withOpacity(.45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('文件更改：${change.path}  [${change.status}]', style: const TextStyle(color: MoonColors.accent, fontWeight: FontWeight.bold)),
        Text('- ${change.oldText}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MoonColors.danger, fontFamily: 'monospace')),
        Text('+ ${change.newText}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MoonColors.ok, fontFamily: 'monospace')),
        if (!done) Row(children: [TextButton(onPressed: () => context.read<AppState>().rejectChange(change.id), child: const Text('拒绝')), FilledButton(onPressed: () => context.read<AppState>().applyChange(change.id), child: const Text('保存更改'))]),
      ]),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final AsyncCallback onSend;
  const _Composer({required this.controller, required this.onSend});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Row(children: [
    Expanded(child: TextField(controller: controller, minLines: 1, maxLines: 5, decoration: const InputDecoration(hintText: '像 Trae/Codex 一样描述你的任务...'))),
    const SizedBox(width: 8), IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send_rounded)),
  ]));
}