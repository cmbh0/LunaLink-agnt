import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class MoonScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  const MoonScaffold({super.key, required this.child, this.appBar, this.floatingActionButton});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        drawer: const _ConversationDrawer(),
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        body: SafeArea(child: child),
      );
}

class _ConversationDrawer extends StatelessWidget {
  const _ConversationDrawer();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Drawer(
      width: MediaQuery.sizeOf(context).width * .72,
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Expanded(child: Text('对话历史', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            IconButton.filledTonal(onPressed: () => context.read<AppState>().newConversation(), icon: const Icon(Icons.add_rounded)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: ListView.builder(
          itemCount: state.conversations.length,
          itemBuilder: (context, i) {
            final c = state.conversations[i];
            final selected = c.id == state.conversationId;
            return ListTile(
              selected: selected,
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(c.updatedAt.toLocal().toString().split('.').first),
              onTap: () {
                context.read<AppState>().switchConversation(c.id);
                Navigator.pop(context);
              },
            );
          },
        )),
      ])),
    );
  }
}
