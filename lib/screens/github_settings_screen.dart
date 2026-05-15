import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_models.dart';
import '../services/app_state.dart';

class GitHubSettingsScreen extends StatefulWidget {
  const GitHubSettingsScreen({super.key});
  @override
  State<GitHubSettingsScreen> createState() => _GitHubSettingsScreenState();
}

class _GitHubSettingsScreenState extends State<GitHubSettingsScreen> {
  late final TextEditingController token;
  bool autoApprove = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().github;
    token = TextEditingController(text: cfg.token);
    autoApprove = cfg.autoApprove;
  }

  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<AppState>().saveGitHubConfig(GitHubConfig(token: token.text.trim(), autoApprove: autoApprove));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GitHub 配置已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('连接 GitHub')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(state.github.isConnected ? '已配置 Token' : '未连接 GitHub', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Token 仅保存在本地，用于仓库管理、文件提交、创建/删除仓库等操作。危险操作会生成工具调用卡片，需用户批准；也可以开启自动批准。'),
        ]))),
        const SizedBox(height: 12),
        TextField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'GitHub Token')),
        const SizedBox(height: 8),
        SwitchListTile(value: autoApprove, onChanged: (v) => setState(() => autoApprove = v), title: const Text('自动批准 GitHub 工具调用'), subtitle: const Text('开启后 AI 可自动执行 GitHub 操作；删除仓库等高风险操作仍建议手动确认。')),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: const Text('保存配置')),
        const SizedBox(height: 22),
        const Text('可用能力规划', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const ListTile(leading: Icon(Icons.add_box_outlined), title: Text('创建仓库')),
        const ListTile(leading: Icon(Icons.delete_outline), title: Text('删除仓库')),
        const ListTile(leading: Icon(Icons.upload_file_outlined), title: Text('提交/更新文件')),
        const ListTile(leading: Icon(Icons.call_split_outlined), title: Text('分支、Issue、PR 管理')),
      ]),
    );
  }
}