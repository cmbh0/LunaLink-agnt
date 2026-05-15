import 'dart:math' as math;
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
      extendBodyBehindAppBar: true,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: Stack(children: [
        const Positioned.fill(child: _MoonBackdrop()),
        Positioned.fill(child: SafeArea(child: child)),
      ]),
    );
  }
}

class _MoonBackdrop extends StatefulWidget {
  const _MoonBackdrop();
  @override
  State<_MoonBackdrop> createState() => _MoonBackdropState();
}

class _MoonBackdropState extends State<_MoonBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() { super.initState(); controller = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat(); }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (_, __) => DecoratedBox(
    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF07142D), Color(0xFF08101F), MoonColors.bg])),
    child: CustomPaint(painter: _SkyPainter(controller.value)),
  ));
}

class _SkyPainter extends CustomPainter {
  final double t;
  _SkyPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final moonPaint = Paint()..shader = const RadialGradient(colors: [Color(0xFFF4F7FF), Color(0x77A9C8FF), Color(0x00172A55)]).createShader(Rect.fromCircle(center: Offset(size.width * .82, size.height * .12), radius: 92));
    canvas.drawCircle(Offset(size.width * .82, size.height * .12), 92, moonPaint);
    final star = Paint()..color = MoonColors.moon.withOpacity(.16);
    for (var i = 0; i < 76; i++) {
      final x = ((i * 97 + t * 18) % math.max(size.width, 1)).toDouble();
      final y = ((i * 151) % math.max(size.height, 1)).toDouble();
      final pulse = .55 + .45 * math.sin((t * math.pi * 2) + i);
      canvas.drawCircle(Offset(x, y), (i % 3 + 1) * .55 * pulse, star);
    }
    final flow = Paint()..shader = LinearGradient(colors: [Colors.transparent, MoonColors.accent.withOpacity(.20), Colors.transparent]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))..strokeWidth = 1.4..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final path = Path();
      final y = size.height * (.25 + i * .13) + math.sin(t * math.pi * 2 + i) * 18;
      path.moveTo(-40, y);
      path.cubicTo(size.width * .25, y - 35, size.width * .58, y + 42, size.width + 40, y - 10);
      canvas.drawPath(path, flow);
    }
    final meteor = Paint()
      ..shader = LinearGradient(colors: [Colors.transparent, MoonColors.moon.withOpacity(.8)]).createShader(const Rect.fromLTWH(0, 0, 180, 80))
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final mx = size.width * (1.15 - t * 1.45);
    final my = size.height * (.18 + t * .38);
    canvas.drawLine(Offset(mx, my), Offset(mx + 92, my - 38), meteor);
  }
  @override
  bool shouldRepaint(covariant _SkyPainter oldDelegate) => oldDelegate.t != t;
}
