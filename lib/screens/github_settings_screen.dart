import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class GitHubSettingsScreen extends StatefulWidget {
  const GitHubSettingsScreen({super.key});
  @override
  State<GitHubSettingsScreen> createState() => _GitHubSettingsScreenState();
}

class _GitHubSettingsScreenState extends State<GitHubSettingsScreen> {
  late final TextEditingController token;
  bool autoApprove = false;
  String? testResult;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().github;
    token = TextEditingController(text: cfg.token);
    autoApprove = cfg.autoApprove;
  }

  @override
  void dispose() { token.dispose(); super.dispose(); }

  Future<void> _save() async {
    await context.read<AppState>().saveGitHubConfig(GitHubConfig(token: token.text.trim(), autoApprove: autoApprove));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GitHub 配置已保存')));
  }

  Future<void> _test() async {
    setState(() { testing = true; testResult = null; });
    try {
      final result = await context.read<AppState>().testGitHubConnection();
      if (mounted) setState(() { testResult = '✅ $result'; testing = false; });
    } catch (e) {
      if (mounted) setState(() { testResult = '❌ $e'; testing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('GitHub 连接')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: MoonGlass.panel(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: MoonColors.edge)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('连接 GitHub', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('配置 Token 后，AI 可以帮你管理仓库：上传文件、修改代码、触发 CI/CD 构建等。\n\n所有操作由 AI 发起工具调用，你可以逐条批准或开启自动批准。', style: TextStyle(fontSize: 13, color: MoonColors.muted, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 16),
        TextField(controller: token, obscureText: true, decoration: InputDecoration(labelText: 'GitHub Personal Access Token', hintText: 'ghp_xxxx...', isDense: true, filled: true, fillColor: MoonGlass.panel2(context), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.edge)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.edge)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: MoonColors.accent)))),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: autoApprove,
          onChanged: (v) => setState(() => autoApprove = v),
          title: const Text('自动批准 GitHub 工具调用', style: TextStyle(fontSize: 14)),
          subtitle: const Text('开启后 AI 可直接执行 GitHub 操作，无需逐条确认。'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded, size: 18), label: const Text('保存'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: testing ? null : _test, icon: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded, size: 18), label: const Text('测试连接'))),
        ]),
        if (testResult != null) Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(12)), child: SelectableText(testResult!, style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF8F6FF), borderRadius: BorderRadius.circular(14), border: Border.all(color: MoonColors.edge)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI 可执行的 GitHub 操作', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('• 查看仓库信息\n• 创建/更新文件并提交\n• 触发 GitHub Actions 工作流\n• 查看构建运行记录\n• 更多能力持续扩展中...', style: TextStyle(fontSize: 13, color: MoonColors.muted, height: 1.6)),
          ]),
        ),
      ]),
    );
  }
}
