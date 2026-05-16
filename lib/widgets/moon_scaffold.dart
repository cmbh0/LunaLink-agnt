import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

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

class _ConversationDrawer extends StatefulWidget {
  const _ConversationDrawer();
  @override
  State<_ConversationDrawer> createState() => _ConversationDrawerState();
}

class _ConversationDrawerState extends State<_ConversationDrawer> {
  final opened = <String>{};
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Drawer(
      width: MediaQuery.sizeOf(context).width * .72,
      backgroundColor: const Color(0xFFFBFBFD),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
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
              child: Column(children: [
                ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: const Color(0xFFF0ECFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                  trailing: IconButton(icon: Icon(opened.contains(c.id) ? Icons.keyboard_arrow_right_rounded : Icons.keyboard_arrow_left_rounded), onPressed: () => setState(() { opened.contains(c.id) ? opened.remove(c.id) : opened.add(c.id); })),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(c.updatedAt.toLocal().toString().split('.').first, style: const TextStyle(fontSize: 11)),
                  onTap: () {
                    context.read<AppState>().switchConversation(c.id);
                    Navigator.pop(context);
                  },
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Container(
                    margin: const EdgeInsets.only(left: 12, right: 4, bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: MoonColors.edge),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      _HistoryAction(icon: Icons.vertical_align_top_rounded, label: '置顶', onTap: () => context.read<AppState>().pinConversation(c.id)),
                      _HistoryAction(icon: Icons.arrow_upward_rounded, label: '上移', onTap: () => context.read<AppState>().moveConversationUp(c.id)),
                      _HistoryAction(icon: Icons.arrow_downward_rounded, label: '下移', onTap: () => context.read<AppState>().moveConversationDown(c.id)),
                      _HistoryAction(icon: Icons.delete_outline_rounded, label: '删除', danger: true, onTap: () => context.read<AppState>().deleteConversation(c.id)),
                    ]),
                  ),
                  crossFadeState: opened.contains(c.id) ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
              ]),
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
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: danger ? Colors.red.withOpacity(.08) : MoonColors.panel2, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: danger ? Colors.red : MoonColors.text),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: danger ? Colors.red : MoonColors.muted, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}