import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/agent_chat_screen.dart';
import 'services/app_state.dart';
import 'theme/moon_theme.dart';
import 'widgets/moon_scaffold.dart';

void main() => runApp(const LunaLinkApp());

class LunaLinkApp extends StatelessWidget {
  const LunaLinkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..loadPersistedState(),
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
  Widget build(BuildContext context) => const MoonScaffold(child: AgentChatScreen(embedded: true));
}