import 'package:flutter/material.dart';

import '../core/core.dart';

/// Набор цветов одной темы оформления.
class Palette {
  const Palette({
    required this.title, required this.bg, required this.card, required this.hover, required this.fg,
    required this.muted, required this.faint, required this.accent, required this.ok, required this.rest,
    required this.warn, required this.danger, required this.onAccent, required this.selected,
    required this.tags, required this.heat, this.cardRadius = 8,
  });
  final String title;
  final Color bg, card, hover, fg, muted, faint, accent, ok, rest, warn, danger, onAccent, selected;
  final List<Color> tags;
  final List<Color> heat; // загрузка дня в полосе недели: норма, плотно, перебор
  final double cardRadius;
}

const palettes = <String, Palette>{
  // Палитра Python-версии (panel/core.py)
  'classic': Palette(
    title: 'Классическая',
    bg: Color(0xFF1E1F24), card: Color(0xFF272830), hover: Color(0xFF34363F), fg: Color(0xFFE8E8EC),
    muted: Color(0xFF8B8D98), faint: Color(0xFF55576A), accent: Color(0xFF7AA2F7), ok: Color(0xFF9ECE6A),
    rest: Color(0xFF73DACA), warn: Color(0xFFE0AF68), danger: Color(0xFFF7768E), onAccent: Color(0xFF1E1F24),
    selected: Color(0xFF3B3E52),
    tags: [
      Color(0xFF7AA2F7), Color(0xFF9ECE6A), Color(0xFFE0AF68), Color(0xFFBB9AF7),
      Color(0xFF73DACA), Color(0xFFFF9E64), Color(0xFFF7768E), Color(0xFF2AC3DE),
    ],
    heat: [Color(0xFF2E3A52), Color(0xFF443C2E), Color(0xFF4A2F3A)],
  ),
  // «Уголёк»: почти чёрный фон с тёплым оттенком и единственный оранжевый акцент (по образцу Cron)
  'ember': Palette(
    title: 'Уголёк',
    bg: Color(0xFF0F0D0A), card: Color(0xFF161412), hover: Color(0xFF221F1B), fg: Color(0xFFF2F0ED),
    muted: Color(0xFF9A948D), faint: Color(0xFF57514B), accent: Color(0xFFFF4700), ok: Color(0xFFCCCCCC),
    rest: Color(0xFFB3ACA4), warn: Color(0xFFFF8A50), danger: Color(0xFFFF4700), onAccent: Color(0xFFFFFFFF),
    selected: Color(0xFF451E0E),
    tags: [
      Color(0xFFCCCCCC), Color(0xFFFF8A50), Color(0xFFA39C94), Color(0xFFE8C4AE),
      Color(0xFFFF4700), Color(0xFF8F8780), Color(0xFFD9A27F), Color(0xFFBDB6AF),
    ],
    heat: [Color(0xFF241F1B), Color(0xFF3A2416), Color(0xFF5A2410)],
    cardRadius: 0,
  ),
};

/// Цвета текущей темы. Меняются целиком через [C.apply]; интерфейс после этого перестраивается.
class C {
  static String name = 'classic';
  static Color bg = palettes['classic']!.bg;
  static Color card = palettes['classic']!.card;
  static Color hover = palettes['classic']!.hover;
  static Color fg = palettes['classic']!.fg;
  static Color muted = palettes['classic']!.muted;
  static Color faint = palettes['classic']!.faint;
  static Color accent = palettes['classic']!.accent;
  static Color ok = palettes['classic']!.ok;
  static Color rest = palettes['classic']!.rest;
  static Color warn = palettes['classic']!.warn;
  static Color danger = palettes['classic']!.danger;
  static Color onAccent = palettes['classic']!.onAccent;
  static Color selected = palettes['classic']!.selected;
  static List<Color> tags = palettes['classic']!.tags;
  static List<Color> heat = palettes['classic']!.heat;
  static double cardRadius = 8;

  static void apply(String? key) {
    final p = palettes[key] ?? palettes['classic']!;
    name = palettes.containsKey(key) ? key! : 'classic';
    bg = p.bg;
    card = p.card;
    hover = p.hover;
    fg = p.fg;
    muted = p.muted;
    faint = p.faint;
    accent = p.accent;
    ok = p.ok;
    rest = p.rest;
    warn = p.warn;
    danger = p.danger;
    onAccent = p.onAccent;
    selected = p.selected;
    tags = p.tags;
    heat = p.heat;
    cardRadius = p.cardRadius;
  }
}

Color tagColor(String tag) => C.tags[tagColorIndex(tag, C.tags.length)];

Color mix(Color a, Color b, double k) => Color.lerp(a, b, k)!;

Map<String, Color> get prioColor => {'low': C.accent, 'medium': C.warn, 'high': C.danger};
Map<String, Color> get eisColor => {'q1': C.danger, 'q2': C.accent, 'q3': C.warn, 'q4': C.muted};

Color levelColor(String level) => switch (level) {
      'danger' => C.danger,
      'warn' => C.warn,
      'ok' => C.ok,
      'accent' => C.accent,
      'rest' => C.rest,
      _ => C.muted,
    };

ThemeData buildTheme({required bool compact}) {
  return ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: C.bg,
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    colorScheme: ColorScheme.dark(primary: C.accent, secondary: C.rest, surface: C.card, error: C.danger),
    dividerColor: C.faint,
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(color: C.bg, border: Border.all(color: C.faint), borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(color: C.fg, fontSize: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(color: C.card, textStyle: TextStyle(color: C.fg, fontSize: 13)),
    dialogTheme: DialogThemeData(backgroundColor: C.bg),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: C.bg,
      hintStyle: TextStyle(color: C.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: C.faint)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: C.faint)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: C.accent)),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: C.fg, selectionColor: C.selected),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? C.accent : C.faint),
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(3),
    ),
  );
}

class T {
  static TextStyle get tiny => TextStyle(fontSize: 11, color: C.muted);
  static TextStyle get small => TextStyle(fontSize: 12, color: C.fg);
  static TextStyle get norm => TextStyle(fontSize: 13, color: C.fg);
  static TextStyle get title => TextStyle(fontSize: 13, color: C.fg, fontWeight: FontWeight.w600);
}
