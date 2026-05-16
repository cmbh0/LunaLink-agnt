import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ai_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';
import 'connect_screen.dart';
import 'file_manager_screen.dart';
import 'github_settings_screen.dart';
import 'terminal_screen.dart';

class AgentChatScreen extends StatefulWidget {
  final bool embedded;
  const AgentChatScreen({super.key, this.embedded = false});
  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  bool _sending = false;

  bool _isBusy(BuildContext context) => _sending || context.read<AppState>().generationActive || context.read<AppState>().busy;

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || _isBusy(context)) return;
    setState(() => _sending = true);
    input.clear();
    try {
      await context.read<AppState>().sendAgentTask(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(children: [
      _TopBar(onSettings: () => _showAiConfig(context)),
      if (state.busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: state.messages.isEmpty
            ? const _HeroEmpty()
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                itemCount: state.messages.length,
                itemBuilder: (context, i) =>
                    _Bubble(message: state.messages[i], onRollback: (t) => input.text = t),
              ),
      ),
      _Composer(controller: input, onSend: _send),
    ]);
  }

  Future<void> _showAiConfig(BuildContext context) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiConfigPage()));
  }
}

// ─── AI Config as real page ───
class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});
  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  late TextEditingController endpoint, name, model, key, temp, maxTokens;
  late AiApiMode apiMode;
  late bool stream;
  String? testResult;
  bool testing = false;
  bool fetchingModels = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().activeAiConfig;
    endpoint = TextEditingController(text: cfg.endpoint);
    name = TextEditingController(text: cfg.name);
    model = TextEditingController(text: cfg.model);
    key = TextEditingController(text: cfg.apiKey);
    temp = TextEditingController(text: cfg.temperature.toString());
    maxTokens = TextEditingController(text: cfg.maxTokens.toString());
    apiMode = cfg.apiMode;
    stream = cfg.streamOutput;
    endpoint.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    endpoint.dispose(); name.dispose(); model.dispose(); key.dispose();
    temp.dispose(); maxTokens.dispose();
    super.dispose();
  }

  String get _resolvedUrl {
    final base = endpoint.text.trim();
    if (base.isEmpty) return '(未填写)';
    switch (apiMode) {
      case AiApiMode.openAiChat:
        return base.endsWith('/chat/completions') ? base : '$base/chat/completions';
      case AiApiMode.responses:
        return base.endsWith('/responses') ? base : '$base/responses';
      case AiApiMode.messages:
        return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cfg = state.activeAiConfig;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 配置')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _label('当前配置'),
        _dropdown<AiServiceConfig>(
          value: cfg,
          items: state.aiConfigs.map((e) => DropdownMenuItem(value: e, child: Text('${e.name} · ${e.model}', style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) { if (v != null) state.setActiveAiConfig(v.id); },
        ),
        const SizedBox(height: 12),
        _field(name, '配置名称'),
        _field(endpoint, 'API Base URL', hint: 'https://api.openai.com/v1'),
        _label('接口模式'),
        _dropdown<AiApiMode>(
          value: apiMode,
          items: AiApiMode.values.map((e) => DropdownMenuItem(value: e, child: Text(e.label, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setState(() => apiMode = v!),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Text('实际请求地址：$_resolvedUrl', style: const TextStyle(fontSize: 11, color: MoonColors.muted)),
        ),
        _field(model, '模型 ID', hint: 'gpt-4o / deepseek-chat / ...'),
        _field(key, 'API Key', obscure: true),
        Row(children: [Expanded(child: _field(temp, 'Temperature')), const SizedBox(width: 8), Expanded(child: _field(maxTokens, 'Max Tokens'))]),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: stream, onChanged: (v) => setState(() => stream = v), title: const Text('流式输出 (SSE)', style: TextStyle(fontSize: 14)), subtitle: const Text('若一直等待无内容，可关闭后重试；错误会直接显示在气泡里。')),
        if (testResult != null) Container(margin: const EdgeInsets.only(top: 4, bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(10), border: Border.all(color: MoonColors.edge)), child: SelectableText(testResult!, style: const TextStyle(fontSize: 12, color: MoonColors.text))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: testing ? null : _testConfig, child: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('测试请求'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: fetchingModels ? null : _fetchModels, child: fetchingModels ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('获取模型'))),
        ]),
        const SizedBox(height: 10),
        FilledButton(onPressed: _save, child: const Text('保存')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _addNew, child: const Text('新建配置')),
      ]),
    );
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final cfg = state.activeAiConfig;
    await state.saveAiConfig(AiServiceConfig(
      id: cfg.id,
      name: name.text.trim().isEmpty ? cfg.name : name.text.trim(),
      provider: cfg.provider,
      endpoint: endpoint.text.trim(),
      apiKey: key.text,
      model: model.text.trim().isEmpty ? cfg.model : model.text.trim(),
      availableModels: cfg.availableModels,
      enabledModels: cfg.enabledModels,
      streamOutput: stream,
      temperature: double.tryParse(temp.text) ?? .2,
      maxTokens: int.tryParse(maxTokens.text) ?? 4096,
      apiMode: apiMode,
      permissionMode: state.permissionMode,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addNew() async {
    final state = context.read<AppState>();
    final newCfg = AiServiceConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '新配置',
      provider: AiProviderType.openai,
      endpoint: '',
      apiKey: '',
      model: '',
    );
    await state.saveAiConfig(newCfg);
    await state.setActiveAiConfig(newCfg.id);
    if (mounted) {
      setState(() {
      final cfg = state.activeAiConfig;
      endpoint.text = cfg.endpoint;
      name.text = cfg.name;
      model.text = cfg.model;
      key.text = cfg.apiKey;
      temp.text = cfg.temperature.toString();
      maxTokens.text = cfg.maxTokens.toString();
      apiMode = cfg.apiMode;
      stream = cfg.streamOutput;
      });
    }
  }

  AiServiceConfig _draftConfig() {
    final cfg = context.read<AppState>().activeAiConfig;
    return AiServiceConfig(
      id: cfg.id,
      name: name.text.trim().isEmpty ? cfg.name : name.text.trim(),
      provider: cfg.provider,
      endpoint: endpoint.text.trim(),
      apiKey: key.text,
      model: model.text.trim().isEmpty ? cfg.model : model.text.trim(),
      availableModels: cfg.availableModels,
      enabledModels: cfg.enabledModels,
      streamOutput: stream,
      temperature: double.tryParse(temp.text) ?? .2,
      maxTokens: int.tryParse(maxTokens.text) ?? 4096,
      apiMode: apiMode,
      permissionMode: context.read<AppState>().permissionMode,
    );
  }

  Future<void> _testConfig() async {
    setState(() { testing = true; testResult = null; });
    try {
      final res = await context.read<AppState>().testAiConfig(_draftConfig());
      if (mounted) setState(() => testResult = '✅ 请求成功：$res');
    } catch (e) {
      if (mounted) setState(() => testResult = '❌ $e');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> _fetchModels() async {
    setState(() { fetchingModels = true; testResult = null; });
    try {
      final models = await context.read<AppState>().fetchModelsFor(_draftConfig());
      if (!mounted) return;
      setState(() {
        testResult = models.isEmpty ? '未获取到模型列表。' : '模型列表：\n${models.take(30).join('\n')}';
        if (models.isNotEmpty && model.text.trim().isEmpty) model.text = models.first;
      });
    } catch (e) {
      if (mounted) setState(() => testResult = '❌ $e');
    } finally {
      if (mounted) setState(() => fetchingModels = false);
    }
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false, String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: c, obscureText: obscure, style: const TextStyle(fontSize: 14), decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), filled: true, fillColor: MoonColors.panel2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.edge)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.edge)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.accent)))),
  );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MoonColors.muted)));

  Widget _dropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(value: value, isExpanded: true, isDense: true, items: items, onChanged: onChanged, style: const TextStyle(fontSize: 13, color: MoonColors.text))),
  );
}

class SponsorPage extends StatelessWidget {
  const SponsorPage({super.key});
  static const registerUrl = 'https://api.headone.fit/register?aff=nZoJ';
  static const qqUrl = 'https://qun.qq.com/universal-share/share?ac=1&authKey=iYUfYoNpOnAuDMfmis088QrKUWiuzODM5B8jzySiXE9O%2BwAaSG6tCeBYBVkkEmvP&busi_data=eyJncm91cENvZGUiOiI5ODI5NzIzNzEiLCJ0b2tlbiI6InM2d3ZGUW5zUjhadjk5MFVHcW00OHMvTE1TUVBrUGRmbVN5NXNROE03aFV2bExLdFlaRG1wZHZMc1pjaURlUW0iLCJ1aW4iOiIzODQ1OTM5Njk4In0%3D&data=WYC5wMLBHNxD7wsCgSSKMLsEfkFl8rQRI-LaLUhQo21P7kF6locIDZp96CEgOAcZJIy-6beGMQE25P4az8UaEA&svctype=4&tempid=h5_group_info';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('赞助与交流')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: MoonColors.edge)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('本工具由北海 cmbh 制作', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('制作不易 🙏 求求赏孩子一口饭吃吧', style: TextStyle(fontSize: 15, color: MoonColors.muted)),
        const SizedBox(height: 16),
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network('https://img.cdn1.vip/i/6a06eaf82e1cb_1778838264.webp', height: 300, width: double.infinity, fit: BoxFit.contain, loadingBuilder: (context, child, progress) => progress == null ? child : const SizedBox(height: 260, child: Center(child: CircularProgressIndicator())), errorBuilder: (_, __, ___) => const SizedBox(height: 260, child: Center(child: CircularProgressIndicator())))),
      ])),
      const SizedBox(height: 14),
      _SponsorAction(icon: Icons.open_in_new_rounded, title: '注册中转站', subtitle: '以后用得上中转站充值余额，也算支持本软件。', onTap: () => _openUrl(registerUrl)),
      const SizedBox(height: 10),
      _SponsorAction(icon: Icons.groups_2_outlined, title: '加入 QQ 交流群', subtitle: '反馈问题、交流功能、获取更新。', onTap: () => _openUrl(qqUrl)),
    ]),
  );
}

class _SponsorAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SponsorAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)), child: Row(children: [Icon(icon, color: MoonColors.accent), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 12, color: MoonColors.muted))])), const Icon(Icons.chevron_right_rounded, color: MoonColors.muted)])));
}

Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ─── Top Bar ───
class _TopBar extends StatelessWidget {
  final VoidCallback onSettings;
  const _TopBar({required this.onSettings});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.96), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(children: [
        SizedBox(width: 36, height: 36, child: IconButton(onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu_rounded, size: 20), padding: EdgeInsets.zero, tooltip: '对话历史')),
        SizedBox(width: 36, height: 36, child: IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FileManagerScreen(compact: false))), icon: const Icon(Icons.folder_outlined, size: 19), padding: EdgeInsets.zero, tooltip: '文件管理')),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: const Color(0xFFF0EEF6), borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _ModeChip(selected: state.agentMode == AgentMode.mtc, label: 'MTC', onTap: () => context.read<AppState>().setAgentMode(AgentMode.mtc)),
            _ModeChip(selected: state.agentMode == AgentMode.code, label: 'Code', onTap: () => context.read<AppState>().setAgentMode(AgentMode.code)),
          ]),
        ),
        const Spacer(),
        SizedBox(width: 36, height: 36, child: IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TerminalScreen())), icon: const Icon(Icons.terminal_rounded, size: 19), padding: EdgeInsets.zero, tooltip: '终端')),
        SizedBox(width: 36, height: 36, child: IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SponsorPage())), icon: const Icon(Icons.volunteer_activism_outlined, size: 19), padding: EdgeInsets.zero, tooltip: '赞助')),
        SizedBox(width: 36, height: 36, child: IconButton(onPressed: onSettings, icon: const Icon(Icons.tune_rounded, size: 19), padding: EdgeInsets.zero, tooltip: '设置')),
      ]),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;
  const _ModeChip({required this.selected, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(16), boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 6, offset: const Offset(0, 1))] : null),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? MoonColors.text : MoonColors.muted)),
    ),
  );
}

// ─── Empty state ───
class _HeroEmpty extends StatelessWidget {
  const _HeroEmpty();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMtc = state.agentMode == AgentMode.mtc;
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(isMtc ? 'MTC' : 'Code', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(isMtc ? '方案沟通模式' : '编码模式', style: const TextStyle(fontSize: 15, color: MoonColors.muted)),
        if (state.servers.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text('已连接：${state.servers.firstWhere((e) => e.id == state.activeServerId, orElse: () => state.servers.first).name}', style: const TextStyle(fontSize: 13, color: MoonColors.ok)),
        ),
      ]),
    ));
  }
}

// ─── Message Bubble ───
class _Bubble extends StatelessWidget {
  final AgentMessage message;
  final ValueChanged<String>? onRollback;
  const _Bubble({required this.message, this.onRollback});
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isLoadingAssistant = !isUser && context.watch<AppState>().generationActive && message.id == context.watch<AppState>().activeAssistantMessageId && message.content.trim().isEmpty && message.thinking?.trim().isNotEmpty != true && message.toolCalls.isEmpty && message.changes.isEmpty;
    return GestureDetector(
      onLongPress: () => _showMessageActions(context, message, onRollback),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? MoonColors.accent.withOpacity(.09) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isUser ? null : Border.all(color: MoonColors.edge, width: .6),
              boxShadow: isUser ? null : [BoxShadow(color: Colors.black.withOpacity(.02), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!isUser && message.modelLabel?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(message.modelLabel!, style: const TextStyle(fontSize: 10, color: MoonColors.muted))),
              if (isLoadingAssistant) const _LoadingDots(),
              if (message.thinking?.isNotEmpty == true) _ThinkingBlock(thinking: message.thinking!, active: message.content.trim().isEmpty),
              if (message.content.isNotEmpty) _MarkdownMsg(data: message.content),
              for (final t in message.toolCalls) _ToolCard(call: t),
              for (final c in message.changes) _ChangeCard(change: c),
            ]),
          ),
        ),
      ),
    );
  }
}

Future<void> _showMessageActions(BuildContext context, AgentMessage message, ValueChanged<String>? onRollback) async {
  final state = context.read<AppState>();
  final isUser = message.role == 'user';
  await showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Wrap(children: [
    ListTile(dense: true, leading: const Icon(Icons.copy_rounded, size: 20), title: const Text('复制'), onTap: () { Clipboard.setData(ClipboardData(text: message.content)); Navigator.pop(context); }),
    ListTile(dense: true, leading: const Icon(Icons.delete_outline_rounded, size: 20), title: const Text('删除'), onTap: () { state.deleteMessage(message.id); Navigator.pop(context); }),
    if (!isUser) ListTile(dense: true, leading: const Icon(Icons.refresh_rounded, size: 20), title: const Text('重新生成'), onTap: () { Navigator.pop(context); state.regenerateAfter(message.id); }),
    if (isUser) ListTile(dense: true, leading: const Icon(Icons.edit_rounded, size: 20), title: const Text('编辑并重发'), onTap: () { onRollback?.call(message.content); state.deleteMessage(message.id); Navigator.pop(context); }),
  ])));
}

// ─── Thinking ───
class _LoadingDots extends StatefulWidget {
  const _LoadingDots();
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (_, __) {
      final n = (c.value * 3).floor() + 1;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 2),
        Text('正在思考${'.' * n}', style: const TextStyle(fontSize: 13, color: MoonColors.muted, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
      ]);
    },
  );
}

// ─── Thinking ───
class _ThinkingBlock extends StatefulWidget {
  final String thinking;
  final bool active;
  const _ThinkingBlock({required this.thinking, this.active = false});
  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  bool open = false;
  @override
  void dispose() { pulse.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => setState(() => open = !open),
        child: FadeTransition(
          opacity: Tween<double>(begin: .4, end: 1.0).animate(CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 14, color: MoonColors.muted),
            const SizedBox(width: 3),
            Text(widget.active ? '正在思考...' : '思考过程', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MoonColors.muted)),
          ]),
        ),
      ),
      if (open) Container(
        margin: const EdgeInsets.only(left: 6, top: 4),
        padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: MoonColors.edge, width: 1.2))),
        child: Text(widget.thinking, style: const TextStyle(fontSize: 12, color: MoonColors.muted, height: 1.4)),
      ),
    ]),
  );
}

// ─── Markdown ───
class _MarkdownMsg extends StatelessWidget {
  final String data;
  const _MarkdownMsg({required this.data});
  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    selectable: true,
    builders: {'code': _CodeBuilder()},
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(color: MoonColors.text, fontSize: 14, height: 1.45),
      code: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: MoonColors.accent, backgroundColor: Color(0xFFF5F2FF)),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(color: Colors.transparent),
    ),
  );
}

class _CodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(dynamic element, TextStyle? preferredStyle) {
    if (element.tag != 'pre') return null;
    final text = element.textContent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFF7F4FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2D8FF))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
          child: Row(children: [const Text('code', style: TextStyle(fontSize: 10, color: MoonColors.muted)), const Spacer(), InkWell(onTap: () => Clipboard.setData(ClipboardData(text: text)), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.copy_rounded, size: 14, color: MoonColors.muted)))]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(10, 2, 10, 10), child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: MoonColors.text, height: 1.35))),
      ]),
    );
  }
}

// ─── Tool Card ───
class _ToolCard extends StatelessWidget {
  final ToolCallRecord call;
  const _ToolCard({required this.call});
  @override
  Widget build(BuildContext context) {
    final done = {'done', 'rejected', 'error', 'running'}.contains(call.status);
    final color = call.status == 'error' ? MoonColors.danger : call.status == 'done' ? MoonColors.ok : MoonColors.warn;
    final mode = context.watch<AppState>().permissionMode;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.build_circle_outlined, size: 15, color: color), const SizedBox(width: 5), Text(call.tool, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)), const Spacer(), Text(call.status, style: TextStyle(fontSize: 10, color: color))]),
        const SizedBox(height: 4),
        Text('${call.arguments}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        if (call.output != null) Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Text(call.output!, maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
        if (!done) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
          OutlinedButton(onPressed: () => context.read<AppState>().rejectTool(call.id), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 30), textStyle: const TextStyle(fontSize: 12)), child: const Text('拒绝')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => context.read<AppState>().executeTool(call.id), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 30), textStyle: const TextStyle(fontSize: 12)), child: const Text('允许')),
          const SizedBox(width: 8),
          Expanded(child: _PermissionDropdown(value: mode)),
        ])),
      ]),
    );
  }
}

// ─── Change Card ───
class _PermissionDropdown extends StatelessWidget {
  final ToolPermissionMode value;
  const _PermissionDropdown({required this.value});
  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
    child: DropdownButtonHideUnderline(child: DropdownButton<ToolPermissionMode>(
      value: value,
      isExpanded: true,
      isDense: true,
      items: const [
        DropdownMenuItem(value: ToolPermissionMode.askEveryTime, child: Text('每次询问')),
        DropdownMenuItem(value: ToolPermissionMode.autoReadOnly, child: Text('自动只读')),
        DropdownMenuItem(value: ToolPermissionMode.autoAll, child: Text('全部批准')),
      ],
      onChanged: (v) { if (v != null) context.read<AppState>().setPermissionMode(v); },
      style: const TextStyle(fontSize: 11, color: MoonColors.text),
    )),
  );
}

// ─── Change Card ───
class _ChangeCard extends StatelessWidget {
  final FileChangeRecord change;
  const _ChangeCard({required this.change});
  @override
  Widget build(BuildContext context) {
    final done = {'saved', 'rejected', 'error'}.contains(change.status);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: MoonColors.panel2, borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.difference_outlined, size: 15, color: MoonColors.accent), const SizedBox(width: 5), Expanded(child: Text(change.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))), Text(change.status, style: const TextStyle(fontSize: 10, color: MoonColors.muted))]),
        const SizedBox(height: 4),
        Text('+${change.newText.split('\n').length} / -${change.oldText.split('\n').length} lines', style: const TextStyle(fontSize: 11, color: MoonColors.muted)),
        if (!done) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
          OutlinedButton(onPressed: () => context.read<AppState>().rejectChange(change.id), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 30), textStyle: const TextStyle(fontSize: 12)), child: const Text('拒绝')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => context.read<AppState>().applyChange(change.id), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 30), textStyle: const TextStyle(fontSize: 12)), child: const Text('保存')),
        ])),
      ]),
    );
  }
}

// ─── Composer ───
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final AsyncCallback onSend;
  const _Composer({required this.controller, required this.onSend});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cfg = state.activeAiConfig;
    final serverLabel = state.activeServerId == null
        ? 'Cloud'
        : state.servers.firstWhere((e) => e.id == state.activeServerId, orElse: () => state.servers.first).name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: MoonColors.edge), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.045), blurRadius: 16, offset: const Offset(0, 5))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: '发消息...', hintStyle: TextStyle(fontSize: 14, color: MoonColors.muted), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, isDense: true, filled: false, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
          ),
          const SizedBox(height: 3),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _ModelPill(label: cfg.model, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiConfigPage()))),
            const SizedBox(width: 6),
            _ComposerPill(icon: Icons.cloud_outlined, label: serverLabel, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen(fullPage: true)))),
            const SizedBox(width: 6),
            _ComposerPill(icon: Icons.hub_outlined, label: 'GitHub', active: state.github.isConnected, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GitHubSettingsScreen()))),
            const Spacer(),
            SizedBox(height: 38, width: 38, child: IconButton.filled(onPressed: state.generationActive ? () => context.read<AppState>().cancelGeneration() : (state.busy ? null : onSend), padding: EdgeInsets.zero, style: IconButton.styleFrom(backgroundColor: state.generationActive ? MoonColors.warn : (state.busy ? MoonColors.muted : MoonColors.accent)), icon: Icon(state.generationActive ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 20))),
          ]),
        ]),
      ),
    );
  }
}

class _ModelPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ModelPill({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => _ComposerPill(icon: Icons.smart_toy_outlined, label: label, onTap: onTap);
}

class _ComposerPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _ComposerPill({required this.icon, required this.label, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: active ? MoonColors.ok.withOpacity(.10) : MoonColors.panel2, borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? MoonColors.ok.withOpacity(.35) : MoonColors.edge)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: active ? MoonColors.ok : MoonColors.muted),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: active ? MoonColors.ok : MoonColors.text))),
      ]),
    ),
  );
}
