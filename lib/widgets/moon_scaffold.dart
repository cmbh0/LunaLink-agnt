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
        drawerScrimColor: Colors.black.withOpacity(.10),
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
      width: MediaQuery.sizeOf(context).width * .68,
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
          child: Row(children: [
            const Expanded(child: Text('对话历史', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
            IconButton.filledTonal(onPressed: () => context.read<AppState>().newConversation(), icon: const Icon(Icons.add_rounded, size: 20)),
          ]),
        ),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: state.conversations.length,
          itemBuilder: (context, i) {
            final c = state.conversations[i];
            final selected = c.id == state.conversationId;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Dismissible(
                key: ValueKey(c.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async => false,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    _HistoryAction(icon: Icons.vertical_align_top_rounded, label: '置顶', onTap: () => context.read<AppState>().pinConversation(c.id)),
                    _HistoryAction(icon: Icons.arrow_upward_rounded, label: '上移', onTap: () => context.read<AppState>().moveConversationUp(c.id)),
                    _HistoryAction(icon: Icons.delete_outline_rounded, label: '删除', danger: true, onTap: () => context.read<AppState>().deleteConversation(c.id)),
                  ]),
                ),
                child: ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: const Color(0xFFF0ECFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(c.updatedAt.toLocal().toString().split('.').first, style: const TextStyle(fontSize: 11)),
                  onTap: () {
                    context.read<AppState>().switchConversation(c.id);
                    Navigator.pop(context);
                  },
                ),
              ),
            );
          },
        )),
      ])),
    );
  }
}

class _HistoryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _HistoryAction({required this.icon, required this.label, required this.onTap, this.danger = false});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17, color: danger ? Colors.red : Colors.black87), Text(label, style: TextStyle(fontSize: 10, color: danger ? Colors.red : Colors.black87))]),
    ),
  );
}