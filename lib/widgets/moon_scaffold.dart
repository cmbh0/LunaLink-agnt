import 'package:flutter/material.dart';
import '../theme/moon_theme.dart';

class MoonScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  const MoonScaffold({super.key, required this.child, this.appBar, this.floatingActionButton});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          const Positioned.fill(child: _MoonBackdrop()),
          Positioned.fill(child: SafeArea(child: child)),
        ],
      ),
    );
  }
}

class _MoonBackdrop extends StatelessWidget {
  const _MoonBackdrop();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.1,
          colors: [Color(0xFF1B2440), MoonColors.bg],
        ),
      ),
      child: CustomPaint(painter: _ParticlePainter()),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = MoonColors.moon.withOpacity(.18);
    for (var i = 0; i < 42; i++) {
      final x = (i * 73 % size.width.toInt()).toDouble();
      final y = (i * 127 % size.height.toInt()).toDouble();
      canvas.drawCircle(Offset(x, y), (i % 3 + 1) * .7, paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
