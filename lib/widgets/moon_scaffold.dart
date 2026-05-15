import 'package:flutter/material.dart';

class MoonScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  const MoonScaffold({super.key, required this.child, this.appBar, this.floatingActionButton});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        body: SafeArea(child: child),
      );
}
