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
        theme: MoonTheme.light,
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => const HomeShell(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: SlideTransition(position: Tween(begin: const Offset(0, .025), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: child),
          ),
        ),
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