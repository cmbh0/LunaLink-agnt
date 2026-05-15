import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/agent_chat_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/file_manager_screen.dart';
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

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: MoonScaffold(
        appBar: AppBar(
          title: const Text('LunaLink Agent'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.dns_rounded), text: '服务器'),
            Tab(icon: Icon(Icons.folder_rounded), text: '文件'),
            Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Agent'),
          ]),
        ),
        child: const TabBarView(children: [ConnectScreen(), FileManagerScreen(), AgentChatScreen()]),
      ),
    );
  }
}