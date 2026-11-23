import 'package:flutter/material.dart';

import '../core/core.dart';

/// Палитра Python-версии (panel/core.py): та же тёмная тема.
class C {
  static const bg = Color(0xFF1E1F24);
  static const card = Color(0xFF272830);
  static const hover = Color(0xFF34363F);
  static const fg = Color(0xFFE8E8EC);
  static const muted = Color(0xFF8B8D98);
  static const faint = Color(0xFF55576A);
  static const accent = Color(0xFF7AA2F7);
  static const ok = Color(0xFF9ECE6A);
  static const rest = Color(0xFF73DACA);
  static const warn = Color(0xFFE0AF68);
  static const danger = Color(0xFFF7768E);
  static const onAccent = Color(0xFF1E1F24);
  static const selected = Color(0xFF3B3E52);
}

const tagPalette = [
  Color(0xFF7AA2F7), Color(0xFF9ECE6A), Color(0xFFE0AF68), Color(0xFFBB9AF7),
  Color(0xFF73DACA), Color(0xFFFF9E64), Color(0xFFF7768E), Color(0xFF2AC3DE),
];

Color tagColor(String tag) => tagPalette[tagColorIndex(tag, tagPalette.length)];

Color mix(Color a, Color b, double k) => Color.lerp(a, b, k)!;

const prioColor = {'low': C.accent, 'medium': C.warn, 'high': C.danger};
const eisColor = {'q1': C.danger, 'q2': C.accent, 'q3': C.warn, 'q4': C.muted};

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
    colorScheme: const ColorScheme.dark(primary: C.accent, secondary: C.rest, surface: C.card, error: C.danger),
    dividerColor: C.faint,
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(color: C.bg, border: Border.all(color: C.faint), borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: C.fg, fontSize: 12),
    ),
    popupMenuTheme: const PopupMenuThemeData(color: C.card, textStyle: TextStyle(color: C.fg, fontSize: 13)),
    dialogTheme: const DialogThemeData(backgroundColor: C.bg),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: C.bg,
      hintStyle: const TextStyle(color: C.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: C.faint)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: C.faint)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: C.accent)),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.fg, selectionColor: C.selected),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? C.accent : C.faint),
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(3),
    ),
  );
}

class T {
  static const tiny = TextStyle(fontSize: 11, color: C.muted);
  static const small = TextStyle(fontSize: 12, color: C.fg);
  static const norm = TextStyle(fontSize: 13, color: C.fg);
  static const title = TextStyle(fontSize: 13, color: C.fg, fontWeight: FontWeight.w600);
}
