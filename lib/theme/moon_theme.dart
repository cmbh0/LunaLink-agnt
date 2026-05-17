import 'package:flutter/material.dart';

class MoonColors {
  static const bg = Color(0xFFFFFFFF);
  static const panel = Colors.white;
  static const panel2 = Color(0xFFF6F7FB);
  static const edge = Color(0xFFE8EAF0);
  static const text = Color(0xFF17181C);
  static const muted = Color(0xFF7C8492);
  static const moon = Color(0xFF111111);
  static const accent = Color(0xFF5B2CCB);
  static const purple = Color(0xFF5B2CCB);
  static const danger = Color(0xFFD32F2F);
  static const ok = Color(0xFF2E7D32);
  static const warn = Color(0xFFF57C00);
}

class MoonTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: MoonColors.accent);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MoonColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: MoonColors.bg,
        foregroundColor: MoonColors.text,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardTheme(
        color: MoonColors.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: MoonColors.edge),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MoonColors.panel2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MoonColors.accent),
        ),
      ),
    );
  }
}

class MoonSelectOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const MoonSelectOption({required this.value, required this.label, this.icon});
}

class MoonSelectField<T> extends StatelessWidget {
  final T? value;
  final String label;
  final List<MoonSelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final bool dense;
  const MoonSelectField({super.key, required this.value, required this.label, required this.options, required this.onChanged, this.dense = false});

  @override
  Widget build(BuildContext context) {
    MoonSelectOption<T>? current;
    for (final option in options) {
      if (option.value == value) current = option;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final selected = await showModalBottomSheet<T>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 10), child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MoonColors.text))),
              for (final item in options) Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, item.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(color: item.value == value ? const Color(0xFFF7F4FF) : MoonColors.panel2, borderRadius: BorderRadius.circular(14), border: Border.all(color: item.value == value ? const Color(0xFFE2D8FF) : MoonColors.edge)),
                    child: Row(children: [
                      if (item.icon != null) ...[Icon(item.icon, size: 18, color: item.value == value ? MoonColors.accent : MoonColors.muted), const SizedBox(width: 10)],
                      Expanded(child: Text(item.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: item.value == value ? MoonColors.accent : MoonColors.text))),
                      if (item.value == value) const Icon(Icons.check_rounded, size: 18, color: MoonColors.accent),
                    ]),
                  ),
                ),
              ),
            ])),
          ),
        );
        onChanged(selected);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: dense, suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20)),
        child: Text(current?.label ?? '未选择', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MoonColors.text)),
      ),
    );
  }
}
