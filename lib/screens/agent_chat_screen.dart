import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ai_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';
import 'connect_screen.dart';
import 'file_manager_screen.dart';
import 'github_settings_screen.dart';
import 'terminal_screen.dart';
import 'workspace_screen.dart';

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
    return Stack(children: [
      Column(children: [
        _TopBar(onSettings: () => _showAiConfig(context)),
        const SizedBox(height: 38),
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
      ]),
      const _EnvironmentDock(),
      const _LiveCodeOverlay(),
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
  late TextEditingController endpoint, name, model, key, temp, maxTokens, summaryThreshold;
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
    temp = TextEditingController(text: cfg.temperature?.toString() ?? '');
    maxTokens = TextEditingController(text: cfg.maxTokens?.toString() ?? '');
    summaryThreshold = TextEditingController(text: cfg.summaryThreshold.toString());
    apiMode = cfg.apiMode;
    stream = cfg.streamOutput;
    endpoint.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    endpoint.dispose(); name.dispose(); model.dispose(); key.dispose();
    temp.dispose(); maxTokens.dispose(); summaryThreshold.dispose();
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('AI 配置')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _label('当前配置'),
        _dropdown<AiServiceConfig>(
          value: cfg,
          items: state.aiConfigs.map((e) => DropdownMenuItem(value: e, child: Text('${e.name} · ${e.model}', style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) { if (v != null) state.setActiveAiConfig(v.id); },
        ),
        const SizedBox(height: 10),
        _roleSelectors(state),
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
        if (cfg.enabledModels.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cfg.enabledModels.map((m) => _TinyChip(
              label: m,
              selected: m == model.text.trim(),
              onTap: () => setState(() => model.text = m),
              onDelete: () => _removeEnabledModel(m),
            )).toList(),
          ),
        ),
        _field(key, 'API Key', obscure: true),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: state.aiRoles.enableSummary, onChanged: (v) => state.setAiSummaryEnabled(v), title: const Text('开启自动总结 / 压缩对话', style: TextStyle(fontSize: 14)), subtitle: const Text('关闭后不会自动总结，也不会压缩当前对话上下文。')),
        Row(children: [Expanded(child: _field(temp, 'Temperature', hint: '留空则不传')), const SizedBox(width: 8), Expanded(child: _field(maxTokens, 'Max Tokens', hint: '留空则不传'))]),
        _label('记忆总结'),
        _field(summaryThreshold, '每多少条用户消息自动总结', hint: '例如 12'),
        const Text('总结使用当前配置与模型。达到阈值后会把上下文压缩为一条 summary 记忆，用于延长上下文。', style: TextStyle(fontSize: 11, color: MoonColors.muted, height: 1.35)),
        const SizedBox(height: 8),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: stream, onChanged: (v) => setState(() => stream = v), title: const Text('流式输出 (SSE)', style: TextStyle(fontSize: 14)), subtitle: const Text('若一直等待无内容，可关闭后重试；错误会直接显示在气泡里。')),
        if (testResult != null) Container(margin: const EdgeInsets.only(top: 4, bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: MoonGlass.panel2(context), borderRadius: BorderRadius.circular(10), border: Border.all(color: MoonColors.edge)), child: SelectableText(testResult!, style: const TextStyle(fontSize: 12, color: MoonColors.text))),
        const SizedBox(height: 10),
        _themeCard(state),
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

  Widget _roleSelectors(AppState state) {
    final options = state.aiConfigs.map((e) => MoonSelectOption<String>(value: e.id, label: '${e.name} · ${e.model}', icon: Icons.smart_toy_outlined)).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: MoonColors.edge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('AI 分工', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MoonColors.text)),
        const SizedBox(height: 8),
        MoonSelectField<String>(value: state.configForRole(AiTaskRole.chat).id, label: AiTaskRole.chat.label, options: options, onChanged: (v) { if (v != null) state.setAiRoleConfig(AiTaskRole.chat, v); }, dense: true),
        const SizedBox(height: 8),
        MoonSelectField<String>(value: state.configForRole(AiTaskRole.summary).id, label: AiTaskRole.summary.label, options: options, onChanged: (v) { if (v != null) state.setAiRoleConfig(AiTaskRole.summary, v); }, dense: true),
        const SizedBox(height: 8),
        MoonSelectField<String>(value: state.configForRole(AiTaskRole.webSearch).id, label: AiTaskRole.webSearch.label, options: options, onChanged: (v) { if (v != null) state.setAiRoleConfig(AiTaskRole.webSearch, v); }, dense: true),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: state.aiRoles.enableWebSearch, onChanged: (v) => state.setAiWebSearchEnabled(v), title: const Text('启用联网搜索委托模型', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), subtitle: const Text('AI 调用 web_search 时，会把需求交给该模型搜索整理后返回。')),
      ]),
    );
  }

  Widget _themeCard(AppState state) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: MoonColors.edge)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('主题与背景', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MoonColors.text)),
      const SizedBox(height: 6),
      Text(state.uiBackgroundPath == null ? '当前：默认白色主题' : '当前：背景图 + iOS 毛玻璃风格', style: const TextStyle(fontSize: 12, color: MoonColors.muted)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () async { final img = await ImagePicker().pickImage(source: ImageSource.gallery); if (img != null && mounted) await context.read<AppState>().setUiBackgroundPath(img.path); }, icon: const Icon(Icons.image_outlined), label: const Text('选择背景图'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: state.uiBackgroundPath == null ? null : () => context.read<AppState>().setUiBackgroundPath(null), icon: const Icon(Icons.format_color_reset_rounded), label: const Text('恢复默认'))),
      ]),
    ]),
  );

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
      summaryThreshold: int.tryParse(summaryThreshold.text) ?? cfg.summaryThreshold,
      streamOutput: stream,
      temperature: double.tryParse(temp.text.trim()),
      maxTokens: int.tryParse(maxTokens.text.trim()),
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
      temp.text = cfg.temperature?.toString() ?? '';
      maxTokens.text = cfg.maxTokens?.toString() ?? '';
      summaryThreshold.text = cfg.summaryThreshold.toString();
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
      summaryThreshold: int.tryParse(summaryThreshold.text) ?? cfg.summaryThreshold,
      streamOutput: stream,
      temperature: double.tryParse(temp.text.trim()),
      maxTokens: int.tryParse(maxTokens.text.trim()),
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
      if (models.isEmpty) {
        setState(() => testResult = '未获取到模型列表。');
        return;
      }
      await _showModelPicker(models);
    } catch (e) {
      if (mounted) setState(() => testResult = '❌ $e');
    } finally {
      if (mounted) setState(() => fetchingModels = false);
    }
  }

  Future<void> _removeEnabledModel(String target) async {
    final state = context.read<AppState>();
    final cfg = state.activeAiConfig;
    final enabled = cfg.enabledModels.where((e) => e != target).toList();
    final current = model.text.trim();
    final nextModel = current == target ? (enabled.isNotEmpty ? enabled.first : cfg.model == target ? '' : cfg.model) : current;
    model.text = nextModel;
    await state.saveAiConfig(AiServiceConfig(
      id: cfg.id,
      name: name.text.trim().isEmpty ? cfg.name : name.text.trim(),
      provider: cfg.provider,
      endpoint: endpoint.text.trim(),
      apiKey: key.text,
      model: nextModel,
      availableModels: cfg.availableModels,
      enabledModels: enabled,
      summaryThreshold: int.tryParse(summaryThreshold.text) ?? cfg.summaryThreshold,
      streamOutput: stream,
      temperature: double.tryParse(temp.text.trim()),
      maxTokens: int.tryParse(maxTokens.text.trim()),
      apiMode: apiMode,
      permissionMode: state.permissionMode,
    ));
    if (mounted) setState(() => testResult = '已移除模型：$target');
  }

  Future<void> _showModelPicker(List<String> models) async {
    final state = context.read<AppState>();
    final cfg = state.activeAiConfig;
    final selected = <String>{...cfg.enabledModels};
    if (selected.isEmpty && model.text.trim().isNotEmpty) selected.add(model.text.trim());
    final queryCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (context, setSheet) => Container(
        height: MediaQuery.sizeOf(context).height * .72,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('选择可用模型', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ]),
          const SizedBox(height: 4),
          const Text('勾选后会保存为输入框可快速切换的模型。', style: TextStyle(fontSize: 12, color: MoonColors.muted)),
          const SizedBox(height: 10),
          TextField(
            controller: queryCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: '搜索模型关键词，例如 gpt / deepseek / vision',
              isDense: true,
              filled: true,
              fillColor: MoonGlass.panel2(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: MoonColors.edge)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: MoonColors.edge)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: MoonColors.accent)),
            ),
            onChanged: (_) => setSheet(() {}),
          ),
          const SizedBox(height: 10),
          Expanded(child: Builder(builder: (_) {
            final q = queryCtrl.text.trim().toLowerCase();
            final filtered = q.isEmpty ? models : models.where((m) => m.toLowerCase().contains(q)).toList();
            if (filtered.isEmpty) return const Center(child: Text('没有匹配的模型', style: TextStyle(fontSize: 13, color: MoonColors.muted)));
            return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final m = filtered[i];
              final checked = selected.contains(m);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setSheet(() => checked ? selected.remove(m) : selected.add(m)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(color: checked ? const Color(0xFFF2EEFF) : MoonColors.panel2, borderRadius: BorderRadius.circular(12), border: Border.all(color: checked ? MoonColors.accent : MoonColors.edge)),
                    child: Row(children: [
                      Icon(checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 19, color: checked ? MoonColors.accent : MoonColors.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
                    ]),
                  ),
                ),
              );
            },
          );
          })),
          FilledButton(
            onPressed: () async {
              final enabled = selected.toList();
              final chosen = enabled.isNotEmpty ? enabled.first : model.text.trim();
              model.text = chosen;
              await state.saveAiConfig(AiServiceConfig(
                id: cfg.id,
                name: name.text.trim().isEmpty ? cfg.name : name.text.trim(),
                provider: cfg.provider,
                endpoint: endpoint.text.trim(),
                apiKey: key.text,
                model: chosen,
                availableModels: models,
                enabledModels: enabled,
                summaryThreshold: int.tryParse(summaryThreshold.text) ?? cfg.summaryThreshold,
                streamOutput: stream,
                temperature: double.tryParse(temp.text.trim()),
                maxTokens: int.tryParse(maxTokens.text.trim()),
                apiMode: apiMode,
                permissionMode: state.permissionMode,
              ));
              if (context.mounted) Navigator.pop(context);
              if (mounted) setState(() => testResult = '已保存 ${enabled.length} 个可切换模型。');
            },
            child: const Text('保存选择'),
          ),
        ]),
      )),
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false, String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: c, obscureText: obscure, style: const TextStyle(fontSize: 14), decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), filled: true, fillColor: MoonGlass.panel2(context), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.edge)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.edge)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.accent)))),
  );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MoonColors.muted)));

  Widget _dropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) {
    final labels = <T, String>{};
    for (final item in items) {
      final child = item.child;
      labels[item.value as T] = child is Text ? (child.data ?? '') : item.value.toString();
    }
    return _TinyDropdown<T>(value: value, labels: labels, onChanged: onChanged);
  }
}

class _TinyDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T?> onChanged;
  const _TinyDropdown({required this.value, required this.labels, required this.onChanged});
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () async {
      final selected = await showModalBottomSheet<T>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: labels.entries.map((e) {
            final active = e.key == value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(context, e.key),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(color: active ? const Color(0xFFF2EEFF) : MoonColors.panel2, borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? MoonColors.accent : MoonColors.edge)),
                  child: Row(children: [Expanded(child: Text(e.value, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500))), if (active) const Icon(Icons.check_rounded, size: 18, color: MoonColors.accent)]),
                ),
              ),
            );
          }).toList())),
        ),
      );
      if (selected != null) onChanged(selected);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(color: MoonGlass.panel2(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
      child: Row(children: [Expanded(child: Text(labels[value] ?? value.toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: MoonColors.text))), const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: MoonColors.muted)]),
    ),
  );
}

class _TinyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const _TinyChip({required this.label, required this.selected, required this.onTap, this.onDelete});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.only(left: 9, right: 5, top: 5, bottom: 5),
      decoration: BoxDecoration(color: selected ? const Color(0xFFF2EEFF) : MoonColors.panel2, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? MoonColors.accent : MoonColors.edge)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: selected ? MoonColors.accent : MoonColors.text, fontWeight: FontWeight.w600))),
        if (onDelete != null) ...[
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: Icon(Icons.close_rounded, size: 14, color: selected ? MoonColors.accent : MoonColors.muted),
          ),
        ],
      ]),
    ),
  );
}

class SponsorPage extends StatelessWidget {
  const SponsorPage({super.key});
  static const registerUrl = 'https://api.headone.fit/register?aff=nZoJ';
  static const qqUrl = 'https://qun.qq.com/universal-share/share?ac=1&authKey=iYUfYoNpOnAuDMfmis088QrKUWiuzODM5B8jzySiXE9O%2BwAaSG6tCeBYBVkkEmvP&busi_data=eyJncm91cENvZGUiOiI5ODI5NzIzNzEiLCJ0b2tlbiI6InM2d3ZGUW5zUjhadjk5MFVHcW00OHMvTE1TUVBrUGRmbVN5NXNROE03aFV2bExLdFlaRG1wZHZMc1pjaURlUW0iLCJ1aW4iOiIzODQ1OTM5Njk4In0%3D&data=WYC5wMLBHNxD7wsCgSSKMLsEfkFl8rQRI-LaLUhQo21P7kF6locIDZp96CEgOAcZJIy-6beGMQE25P4az8UaEA&svctype=4&tempid=h5_group_info';
  static const wechatId = 'CMBH_LYF';
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(title: const Text('赞助与交流')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(22), border: Border.all(color: MoonColors.edge)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('本工具由北海 cmbh 制作', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('如果你想赞赏或交流，请添加作者微信并说明来意。', style: TextStyle(fontSize: 15, color: MoonColors.muted)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF7F4FF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2D8FF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('作者微信', style: TextStyle(fontSize: 12, color: MoonColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(children: [
              const Expanded(child: SelectableText(wechatId, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: MoonColors.accent, letterSpacing: .5))),
              IconButton.filledTonal(onPressed: () {
                Clipboard.setData(const ClipboardData(text: wechatId));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('微信号已复制')));
              }, icon: const Icon(Icons.copy_rounded, size: 18)),
            ]),
            const SizedBox(height: 8),
            const Text('点击下方按钮可尝试跳转微信；若系统不支持直接打开，请复制微信号后在微信内搜索。', style: TextStyle(fontSize: 12, color: MoonColors.muted, height: 1.35)),
          ]),
        ),
      ])),
      const SizedBox(height: 14),
      _SponsorAction(icon: Icons.wechat, title: '复制微信号并打开微信', subtitle: wechatId, onTap: () async {
        Clipboard.setData(const ClipboardData(text: wechatId));
        await _openUrl('weixin://');
      }),
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
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)), child: Row(children: [Icon(icon, color: MoonColors.accent), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 12, color: MoonColors.muted))])), const Icon(Icons.chevron_right_rounded, color: MoonColors.muted)])));
}

Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

// ─── Top Bar ───
class _TopBar extends StatelessWidget {
  final VoidCallback onSettings;
  const _TopBar({required this.onSettings});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: MoonGlass.enabled(context) ? MoonGlass.panel(context) : Colors.white.withOpacity(.97), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Row(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          _TopIconButton(onTap: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu_rounded, size: 21), tooltip: '对话历史'),
          const SizedBox(width: 8),
          _TopIconButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkspaceScreen())), icon: const Text('<>', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, fontFamily: 'monospace')), tooltip: '工作区绑定'),
          const SizedBox(width: 8),
          _TopIconButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FileManagerScreen(compact: false))), icon: const Icon(Icons.folder_outlined, size: 20), tooltip: '文件管理'),
        ]),
        Expanded(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 104, maxWidth: 132),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: const Color(0xFFF0EEF6), borderRadius: BorderRadius.circular(18), border: Border.all(color: MoonColors.edge)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Expanded(child: _ModeChip(selected: state.agentMode == AgentMode.mtc, label: 'MTC', onTap: () => context.read<AppState>().setAgentMode(AgentMode.mtc))),
              Expanded(child: _ModeChip(selected: state.agentMode == AgentMode.code, label: 'Code', onTap: () => context.read<AppState>().setAgentMode(AgentMode.code))),
            ]),
          ),
        ))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _TopIconButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TerminalScreen())), icon: const Icon(Icons.terminal_rounded, size: 19), tooltip: '终端'),
          const SizedBox(width: 8),
          _TopIconButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SponsorPage())), icon: const Icon(Icons.volunteer_activism_outlined, size: 19), tooltip: '赞助'),
          const SizedBox(width: 8),
          _TopIconButton(onTap: onSettings, icon: const Icon(Icons.tune_rounded, size: 19), tooltip: '设置'),
        ]),
      ]),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final VoidCallback onTap;
  const _TopIconButton({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 34,
        height: 36,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Tooltip(message: tooltip, child: Center(child: icon)),
          ),
        ),
      );
}

class _EnvironmentDock extends StatelessWidget {
  const _EnvironmentDock();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final top = MediaQuery.paddingOf(context).top + 58;
    return Positioned(
      top: top,
      right: 14,
      child: _EnvSwitch(state: state),
    );
  }
}

class _EnvSwitch extends StatelessWidget {
  final AppState state;
  const _EnvSwitch({required this.state});
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent, hoverColor: Colors.transparent),
      child: PopupMenuButton<DevelopmentEnvironment>(
      clipBehavior: Clip.none,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: '开发环境',
      color: MoonGlass.panel(context),
      elevation: 10,
      shadowColor: Colors.black.withOpacity(.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: MoonColors.edge)),
      position: PopupMenuPosition.under,
      initialValue: state.developmentEnvironment,
      onSelected: (v) => context.read<AppState>().setDevelopmentEnvironment(v),
      itemBuilder: (_) => DevelopmentEnvironment.values.map((e) => PopupMenuItem(
        value: e,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: _EnvMenuItem(env: e, selected: e == state.developmentEnvironment),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: MoonColors.edge), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.045), blurRadius: 10, offset: const Offset(0, 3))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(state.developmentEnvironment == DevelopmentEnvironment.cloud ? Icons.cloud_outlined : Icons.laptop_mac_rounded, size: 12.5, color: MoonColors.muted),
          const SizedBox(width: 5),
          Text(state.developmentEnvironment.label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: MoonColors.text)),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: MoonColors.muted),
        ]),
      ),
      ),
    );
  }
}

class _EnvMenuItem extends StatelessWidget {
  final DevelopmentEnvironment env;
  final bool selected;
  const _EnvMenuItem({required this.env, required this.selected});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: selected ? const Color(0xFFF7F4FF) : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? const Color(0xFFE2D8FF) : Colors.transparent)),
        child: Row(children: [
          Icon(env == DevelopmentEnvironment.cloud ? Icons.cloud_outlined : Icons.laptop_mac_rounded, size: 18, color: selected ? MoonColors.accent : MoonColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(env.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: selected ? MoonColors.accent : MoonColors.text)),
            const SizedBox(height: 2),
            Text(env == DevelopmentEnvironment.cloud ? '优先使用服务器工具' : '优先使用本地工作区', style: const TextStyle(fontSize: 11, color: MoonColors.muted)),
          ])),
          if (selected) const Icon(Icons.check_circle_rounded, size: 17, color: MoonColors.accent),
        ]),
      );
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(color: selected ? MoonGlass.panel(context) : Colors.transparent, borderRadius: BorderRadius.circular(16), boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 6, offset: const Offset(0, 1))] : null),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? MoonColors.text : MoonColors.muted))),
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
        if (state.servers.isNotEmpty && state.activeServerId != null) Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text('已连接：${_serverName(state)}', style: const TextStyle(fontSize: 13, color: MoonColors.ok)),
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
              color: isUser ? MoonColors.accent.withOpacity(.13) : MoonGlass.panel(context),
              borderRadius: BorderRadius.circular(16),
              border: isUser ? null : Border.all(color: MoonColors.edge, width: .6),
              boxShadow: isUser ? null : [BoxShadow(color: Colors.black.withOpacity(.02), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!isUser && message.modelLabel?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(message.modelLabel!, style: const TextStyle(fontSize: 10, color: MoonColors.muted))),
              if (isLoadingAssistant) const _LoadingDots(),
              if (message.thinking?.isNotEmpty == true) _ThinkingBlock(thinking: message.thinking!, active: message.content.trim().isEmpty),
              if (message.content.isNotEmpty) MarkdownBody(
                data: message.content,
                selectable: false,
                builders: {'code': _CodeBuilder()},
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: const TextStyle(color: MoonColors.text, fontSize: 14, height: 1.45),
                  code: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: MoonColors.accent, backgroundColor: Color(0xFFF5F2FF)),
                  codeblockPadding: EdgeInsets.zero,
                  codeblockDecoration: const BoxDecoration(color: Colors.transparent),
                ),
              ),
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
    ListTile(dense: true, leading: const Icon(Icons.copy_rounded, size: 20), title: const Text('复制全部'), onTap: () { Clipboard.setData(ClipboardData(text: message.content)); Navigator.pop(context); }),
    ListTile(dense: true, leading: const Icon(Icons.select_all_rounded, size: 20), title: const Text('选择文本复制'), onTap: () { Navigator.pop(context); _showSelectableTextDialog(context, message.content); }),
    ListTile(dense: true, leading: const Icon(Icons.undo_rounded, size: 20), title: const Text('回滚到这里'), onTap: () { final t = state.rollbackToMessage(message.id); if (t != null) onRollback?.call(t); Navigator.pop(context); }),
    ListTile(dense: true, leading: const Icon(Icons.delete_outline_rounded, size: 20), title: const Text('删除此处及后续'), onTap: () { state.deleteMessage(message.id); Navigator.pop(context); }),
    if (!isUser) ListTile(dense: true, leading: const Icon(Icons.refresh_rounded, size: 20), title: const Text('重新生成'), onTap: () { Navigator.pop(context); state.regenerateAfter(message.id); }),
    if (isUser) ListTile(dense: true, leading: const Icon(Icons.edit_rounded, size: 20), title: const Text('编辑并重发'), onTap: () { final t = state.editAndResend(message.id); if (t != null) onRollback?.call(t); Navigator.pop(context); }),
  ])));
}

Future<void> _showSelectableTextDialog(BuildContext context, String text) async {
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .72),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('选择文本复制', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: 8),
          Expanded(child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.45)))),
        ]),
      ),
    ),
  );
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
  Widget build(BuildContext context) {
    final thinkingText = widget.thinking
        .replaceAll(RegExp(r'\n(?!\n)'), ' ')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
    final maxWidth = (MediaQuery.sizeOf(context).width * .72).clamp(240.0, 560.0);
    return Padding(
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
          width: maxWidth,
          margin: const EdgeInsets.only(left: 6, top: 4),
          padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4, right: 4),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: MoonColors.edge, width: 1.2))),
          child: Text(thinkingText, softWrap: true, textAlign: TextAlign.start, style: const TextStyle(fontSize: 12.5, color: MoonColors.muted, height: 1.55, letterSpacing: .1)),
        ),
      ]),
    );
  }
}

// ─── Markdown ───
class _CodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(dynamic element, TextStyle? preferredStyle) {
    if (element.tag != 'pre') return null;
    final text = element.textContent;
    return _HoverCopyCodeBlock(text: text);
  }
}

class _HoverCopyCodeBlock extends StatefulWidget {
  final String text;
  const _HoverCopyCodeBlock({required this.text});
  @override
  State<_HoverCopyCodeBlock> createState() => _HoverCopyCodeBlockState();
}

class _HoverCopyCodeBlockState extends State<_HoverCopyCodeBlock> {
  bool showCopy = false;
  void _setVisible(bool v) { if (mounted) setState(() => showCopy = v); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _setVisible(true),
    onLongPressStart: (_) => _setVisible(true),
    child: MouseRegion(
      onEnter: (_) => _setVisible(true),
      onExit: (_) => _setVisible(false),
      child: Stack(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
          decoration: BoxDecoration(color: const Color(0xFFF7F4FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2D8FF))),
          child: SelectableText(widget.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: MoonColors.text, height: 1.35)),
        ),
        const Positioned(
          top: 10,
          left: 10,
          child: Text('code', style: TextStyle(fontSize: 10, color: MoonColors.muted)),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: AnimatedOpacity(
            opacity: showCopy ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: IgnorePointer(
              ignoring: !showCopy,
              child: Material(
                color: MoonGlass.enabled(context) ? MoonGlass.panel(context) : Colors.white.withOpacity(.92),
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.text));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('代码已复制'), duration: Duration(milliseconds: 900)));
                  },
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.copy_rounded, size: 15, color: MoonColors.muted)),
                ),
              ),
            ),
          ),
        ),
      ]),
    ),
  );
}

// ─── Tool Card ───
class _ToolCard extends StatefulWidget {
  final ToolCallRecord call;
  const _ToolCard({required this.call});
  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final done = {'done', 'rejected', 'error', 'running'}.contains(call.status);
    final color = call.status == 'error' ? MoonColors.danger : call.status == 'done' ? MoonColors.ok : call.status == 'running' ? MoonColors.warn : MoonColors.accent;
    final mode = context.watch<AppState>().permissionMode;
    final hasOutput = call.output?.trim().isNotEmpty == true;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: MoonGlass.panel2(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => open = !open),
          child: Row(children: [
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: MoonColors.muted),
            const SizedBox(width: 4),
            Icon(Icons.build_circle_outlined, size: 15, color: color),
            const SizedBox(width: 5),
            Expanded(child: Text('工具调用 · ${call.tool}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
            Text(call.status, style: TextStyle(fontSize: 10, color: color)),
          ]),
        ),
        if (hasOutput) const Padding(
          padding: EdgeInsets.only(left: 25, top: 3),
          child: Text('灰色内容为工具返回结果', style: TextStyle(fontSize: 10.5, color: MoonColors.muted)),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          const Text('调用参数', style: TextStyle(fontSize: 10.5, color: MoonColors.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('${call.arguments}', maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          if (hasOutput) Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFF1F1F4), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE1E1E6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('工具返回内容', style: TextStyle(fontSize: 10.5, color: MoonColors.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(call.output!, maxLines: 12, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF666673), height: 1.35)),
            ]),
          ),
        ],
        if (!done) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
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
  Widget build(BuildContext context) => _TinyDropdown<ToolPermissionMode>(
    value: value,
    labels: const {
      ToolPermissionMode.askEveryTime: '每次询问',
      ToolPermissionMode.autoAll: '自动批准',
    },
    onChanged: (v) { if (v != null) context.read<AppState>().setPermissionMode(v); },
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
      decoration: BoxDecoration(color: MoonGlass.panel2(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
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
    final serverLabel = _serverName(state);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        if (state.agentMode == AgentMode.code && state.todoPlan != null && !state.todoPlan!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 5),
            child: _TodoCapsule(plan: state.todoPlan!),
          ),
        Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(28), border: Border.all(color: MoonColors.edge), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.045), blurRadius: 16, offset: const Offset(0, 5))]),
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
            _ModelPill(label: cfg.model, onTap: () => _showQuickModelSwitch(context, state, cfg)),
            const SizedBox(width: 6),
            _ComposerPill(icon: Icons.cloud_outlined, label: serverLabel, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen(fullPage: true)))),
            const SizedBox(width: 6),
            _ComposerPill(icon: Icons.hub_outlined, label: 'GitHub', active: state.github.isConnected, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GitHubSettingsScreen()))),
            const Spacer(),
            SizedBox(height: 38, width: 38, child: IconButton.filled(onPressed: state.generationActive ? () => context.read<AppState>().cancelGeneration() : (state.busy ? null : onSend), padding: EdgeInsets.zero, style: IconButton.styleFrom(backgroundColor: state.generationActive ? MoonColors.warn : (state.busy ? MoonColors.muted : MoonColors.accent)), icon: Icon(state.generationActive ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 20))),
          ]),
        ]),
      ),
      ]),
    );
  }
}

class _TodoCapsule extends StatelessWidget {
  final AgentTodoPlan plan;
  const _TodoCapsule({required this.plan});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _showTodoSheet(context, plan),
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: const Color(0xFFEFF7FF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFB9DFFF)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 3))]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.checklist_rounded, size: 14, color: Color(0xFF3487C8)),
        const SizedBox(width: 5),
        Text('${plan.doneCount}/${plan.totalCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF256EA8))),
      ]),
    ),
  );
}

Future<void> _showTodoSheet(BuildContext context, AgentTodoPlan plan) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('任务目标', style: TextStyle(fontSize: 12, color: MoonColors.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(plan.goal.isEmpty ? '当前 Code 任务' : plan.goal, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('进度：${plan.doneCount} / ${plan.totalCount}', style: const TextStyle(fontSize: 12, color: MoonColors.muted)),
        const SizedBox(height: 8),
        Flexible(child: ListView.builder(shrinkWrap: true, itemCount: plan.items.length, itemBuilder: (_, i) {
          final item = plan.items[i];
          final icon = item.done ? Icons.check_circle_rounded : item.active ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded;
          final color = item.done ? MoonColors.ok : item.active ? MoonColors.accent : MoonColors.muted;
          final label = item.done ? '已完成' : item.active ? '正在进行' : '未完成';
          return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), Text(label, style: TextStyle(fontSize: 11, color: color))])),
          ]));
        })),
      ])),
    ),
  );
}

Future<void> _showQuickModelSwitch(BuildContext context, AppState state, AiServiceConfig cfg) async {
  final models = cfg.enabledModels.isNotEmpty ? cfg.enabledModels : [cfg.model];
  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 10), child: Text('切换模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        for (final m in models) Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(context, m),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(color: m == cfg.model ? const Color(0xFFF2EEFF) : MoonColors.panel2, borderRadius: BorderRadius.circular(12), border: Border.all(color: m == cfg.model ? MoonColors.accent : MoonColors.edge)),
              child: Row(children: [Expanded(child: Text(m, style: const TextStyle(fontSize: 13))), if (m == cfg.model) const Icon(Icons.check_rounded, size: 18, color: MoonColors.accent)]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AiConfigPage())); }, icon: const Icon(Icons.tune_rounded, size: 17), label: const Text('管理模型配置')),
      ])),
    ),
  );
  if (selected != null && selected != cfg.model) {
    await state.saveAiConfig(AiServiceConfig(
      id: cfg.id,
      name: cfg.name,
      provider: cfg.provider,
      endpoint: cfg.endpoint,
      apiKey: cfg.apiKey,
      model: selected,
      availableModels: cfg.availableModels,
      enabledModels: cfg.enabledModels,
      summaryThreshold: cfg.summaryThreshold,
      streamOutput: cfg.streamOutput,
      temperature: cfg.temperature,
      maxTokens: cfg.maxTokens,
      headers: cfg.headers,
      apiMode: cfg.apiMode,
      permissionMode: cfg.permissionMode,
    ));
  }
}

String _serverName(AppState state) {
  if (state.activeServerId == null || state.servers.isEmpty) return 'Cloud';
  for (final s in state.servers) {
    if (s.id == state.activeServerId) return s.name;
  }
  return 'Cloud';
}

class _LiveCodeOverlay extends StatefulWidget {
  const _LiveCodeOverlay();
  @override
  State<_LiveCodeOverlay> createState() => _LiveCodeOverlayState();
}

class _LiveCodeOverlayState extends State<_LiveCodeOverlay> {
  Offset pos = const Offset(18, 96);
  Size size = const Size(320, 360);
  bool minimized = false;
  bool showDiff = false;

  @override
  Widget build(BuildContext context) {
    final change = context.watch<AppState>().liveCodeChange;
    if (change == null) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);
    if (minimized) {
      return Positioned(
        left: pos.dx.clamp(0, screen.width - 56),
        top: pos.dy.clamp(0, screen.height - 56),
        child: GestureDetector(
          onPanUpdate: (d) => setState(() => pos += d.delta),
          onTap: () => setState(() => minimized = false),
          child: Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF5746D8), Color(0xFF8C7BFF)]), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.18), blurRadius: 16)]), child: const Center(child: Icon(Icons.nightlight_round, color: Colors.white, size: 25))),
        ),
      );
    }
    final w = size.width.clamp(260, screen.width - 20).toDouble();
    final h = size.height.clamp(240, screen.height - 90).toDouble();
    return Positioned(
      left: pos.dx.clamp(8, screen.width - w - 8),
      top: pos.dy.clamp(8, screen.height - h - 8),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: Colors.white.withOpacity(.98), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFD6D8E0)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Stack(children: [
            Column(children: [
              GestureDetector(
                onPanUpdate: (d) => setState(() => pos += d.delta),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 9, 8, 8),
                  decoration: const BoxDecoration(color: Color(0xFFF2F3F7), borderRadius: BorderRadius.vertical(top: Radius.circular(10)), border: Border(bottom: BorderSide(color: Color(0xFFD6D8E0)))),
                  child: Row(children: [
                    const Icon(Icons.nightlight_round, size: 15, color: MoonColors.accent), const SizedBox(width: 6), const Text('AI 正在编码', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MoonColors.accent)),
                    const Spacer(),
                    IconButton(onPressed: () => setState(() => minimized = true), icon: const Icon(Icons.remove_rounded, size: 18), padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 28, height: 28)),
                    IconButton(onPressed: () => context.read<AppState>().clearLiveCodeChange(), icon: const Icon(Icons.close_rounded, size: 18), padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 28, height: 28)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 5),
                child: Row(children: [
                  Icon(_fileIcon(change.fileName), size: 16, color: MoonColors.accent),
                  const SizedBox(width: 6),
                  Expanded(child: Text(change.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                  Text('(+${change.addedLines} -${change.removedLines}, ${change.byteDelta >= 0 ? '+' : ''}${change.byteDelta}B)', style: const TextStyle(fontSize: 10.5, color: MoonColors.muted)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  _LiveTab(label: '代码', selected: !showDiff, onTap: () => setState(() => showDiff = false)),
                  const SizedBox(width: 8),
                  _LiveTab(label: 'Diff', selected: showDiff, onTap: () => setState(() => showDiff = true)),
                ]),
              ),
              Expanded(child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFBFAFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: MoonColors.edge)),
                child: SingleChildScrollView(child: showDiff ? _DiffView(oldText: change.oldText, newText: change.newText) : SelectableText(change.newText, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.35))),
              )),
            ]),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => size = Size(size.width + d.delta.dx, size.height + d.delta.dy)),
                child: Container(width: 28, height: 28, alignment: Alignment.bottomRight, padding: const EdgeInsets.all(4), child: const Icon(Icons.drag_handle_rounded, size: 18, color: MoonColors.muted)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.flutter_dash_rounded;
    if (name.endsWith('.json') || name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.data_object_rounded;
    if (name.endsWith('.md')) return Icons.article_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _LiveTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LiveTab({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: selected ? MoonColors.accent.withOpacity(.12) : MoonColors.panel2, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? MoonColors.accent.withOpacity(.35) : MoonColors.edge)), child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? MoonColors.accent : MoonColors.muted))));
}

class _DiffView extends StatelessWidget {
  final String oldText;
  final String newText;
  const _DiffView({required this.oldText, required this.newText});
  @override
  Widget build(BuildContext context) {
    final oldLines = oldText.isEmpty ? <String>[] : oldText.split('\n');
    final newLines = newText.isEmpty ? <String>[] : newText.split('\n');
    var prefix = 0;
    while (prefix < oldLines.length && prefix < newLines.length && oldLines[prefix] == newLines[prefix]) { prefix++; }
    var oldSuffix = oldLines.length - 1;
    var newSuffix = newLines.length - 1;
    while (oldSuffix >= prefix && newSuffix >= prefix && oldLines[oldSuffix] == newLines[newSuffix]) { oldSuffix--; newSuffix--; }
    final spans = <Widget>[];
    for (var i = 0; i < prefix && i < 20; i++) { spans.add(_DiffLine('  ${oldLines[i]}', MoonColors.text)); }
    for (var i = prefix; i <= oldSuffix; i++) { if (i >= 0 && i < oldLines.length) spans.add(_DiffLine('- ${oldLines[i]}', MoonColors.danger)); }
    for (var i = prefix; i <= newSuffix; i++) { if (i >= 0 && i < newLines.length) spans.add(_DiffLine('+ ${newLines[i]}', MoonColors.ok)); }
    for (var i = newSuffix + 1; i < newLines.length && spans.length < 80; i++) { spans.add(_DiffLine('  ${newLines[i]}', MoonColors.text)); }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: spans.isEmpty ? const [Text('无可显示 diff')] : spans);
  }
}

class _DiffLine extends StatelessWidget {
  final String text;
  final Color color;
  const _DiffLine(this.text, this.color);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.35, color: color));
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
