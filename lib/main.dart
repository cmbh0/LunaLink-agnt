import 'dart:io';
import 'dart:ui';
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
      child: Consumer<AppState>(builder: (context, state, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LunaLink Agent',
        theme: state.uiBackgroundPath == null ? MoonTheme.light : MoonTheme.light.copyWith(scaffoldBackgroundColor: Colors.transparent, canvasColor: Colors.transparent, appBarTheme: MoonTheme.light.appBarTheme.copyWith(backgroundColor: Colors.white.withOpacity(.38))),
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
        builder: (context, child) {
          final bg = state.uiBackgroundPath;
          if (bg == null || bg.isEmpty) return child ?? const SizedBox.shrink();
          return Stack(children: [
            Positioned.fill(child: Image.file(File(bg), fit: BoxFit.cover)),
            Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: Container(color: Colors.white.withOpacity(.14)))),
            child ?? const SizedBox.shrink(),
          ]);
        },
        home: const HomeShell(),
      )),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});
  @override
  Widget build(BuildContext context) => const MoonScaffold(child: AgentChatScreen(embedded: true));
}