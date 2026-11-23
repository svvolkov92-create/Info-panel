import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart' show ResizeEdge;

import '../core/core.dart';
import '../core/model.dart';
import 'blocks.dart';
import 'desktop.dart';
import 'scope.dart';
import 'tasks_block.dart';
import 'theme.dart';
import 'widgets.dart';
import 'windows.dart';

/// Вся панель: шапка с часами и блоки. В окне шириной от 720 — две колонки.
class PanelView extends StatelessWidget {
  const PanelView({super.key, this.desk});
  final DesktopWindow? desk;

  static const rightColumn = {'tasks', 'future', 'week'};

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final gap = m.s['ui_compact'] == false ? 10.0 : 6.0;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 720 && (desk == null || !desk!.widgetMode || c.maxWidth >= 900);
      final keys = m.visibleBlocks;
      if (m.focusActive) {
        return ListView(padding: EdgeInsets.all(gap + 2), children: [Header(desk: desk), SizedBox(height: gap), const FocusView()]);
      }
      if (!wide) {
        return Scrollbar(
          child: ListView(padding: EdgeInsets.fromLTRB(gap + 2, gap + 2, gap + 2, gap + 12), children: [
            Header(desk: desk),
            SizedBox(height: gap),
            for (final k in keys) BlockCard(blockKey: k, gap: gap),
          ]),
        );
      }
      final left = keys.where((k) => !rightColumn.contains(k)).toList();
      final right = keys.where(rightColumn.contains).toList();
      return Padding(
        padding: EdgeInsets.all(gap + 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Header(desk: desk),
          SizedBox(height: gap),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 340,
                child: Scrollbar(child: ListView(children: [for (final k in left) BlockCard(blockKey: k, gap: gap)])),
              ),
              SizedBox(width: gap + 4),
              Expanded(
                child: Scrollbar(child: ListView(children: [for (final k in right) BlockCard(blockKey: k, gap: gap)])),
              ),
            ]),
          ),
        ]),
      );
    });
  }
}

/// Шапка: часы, дата, поиск, меню, настройки; у виджета — перетаскивание и закрытие.
class Header extends StatelessWidget {
  const Header({super.key, this.desk});
  final DesktopWindow? desk;

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final compact = m.s['ui_compact'] != false;
    final head = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: m.clock,
            builder: (_, now, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${two(now.hour)}:${two(now.minute)}',
                  style: TextStyle(fontSize: compact ? 32 : 42, fontWeight: FontWeight.w300, height: 1, color: C.fg)),
              SizedBox(height: compact ? 3 : 6),
              Text('${weekdays[wd(now)]}, ${dayLong(now)} ${now.year}', style: T.small.copyWith(color: C.muted)),
            ]),
          ),
        ),
        IconBtn(Icons.search, 'Поиск задач (Ctrl+F)', () => sc.actions.openSearch(context)),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Меню',
          icon: const Icon(Icons.more_horiz, size: 18, color: C.muted),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 220),
          onSelected: (f) => f(),
          itemBuilder: (_) => [
            PopupMenuItem(value: () => sc.actions.openWeek(context), child: const Text('Неделя')),
            PopupMenuItem(value: () => sc.actions.openMatrix(context), child: const Text('Матрица Эйзенхауэра')),
            PopupMenuItem(value: () => _templates(context), child: const Text('Шаблоны…')),
            PopupMenuItem(value: () => sc.actions.openWeeklyReview(context), child: const Text('Обзор недели')),
            PopupMenuItem(value: () => sc.actions.openUnload(context), child: const Text('Разгрузить выбранный день…')),
            PopupMenuItem(value: m.clearDone, child: const Text('Убрать выполненные за выбранный день')),
            const PopupMenuDivider(),
            PopupMenuItem(value: m.undo, child: const Text('Отменить (Ctrl+Z)')),
            PopupMenuItem(value: m.redo, child: const Text('Повторить (Ctrl+Y)')),
            PopupMenuItem(value: () => _toggleAll(m), child: const Text('Свернуть или развернуть все блоки')),
            const PopupMenuDivider(),
            PopupMenuItem(value: () => sc.actions.openSettings(context), child: const Text('Настройки…')),
          ],
        ),
        IconBtn(Icons.tune, 'Настройки', () => sc.actions.openSettings(context)),
        if (desk != null && desk!.widgetMode)
          IconBtn(Icons.close, desk!.hasTray ? 'Скрыть в трей (вернуть — щелчок по значку)' : 'Закрыть панель', desk!.close),
      ]),
    );
    if (desk == null || !desk!.widgetMode) return head;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(onPanStart: (_) => desk!.startDrag(), child: head),
    );
  }

  void _toggleAll(PanelModel m) {
    final keys = m.visibleBlocks;
    final collapse = !keys.every(m.collapsed);
    for (final k in keys) {
      (m.s['collapsed'] as Map)[k] = collapse;
    }
    m.touch();
  }

  Future<void> _templates(BuildContext context) async {
    final items = templateMenu(context);
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final f = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx + 20, pos.dy + 40, pos.dx + 300, pos.dy),
      items: items,
    );
    f?.call();
  }
}

/// Блок панели: заголовок со стрелкой сворачивания и сводкой, тело.
class BlockCard extends StatelessWidget {
  const BlockCard({super.key, required this.blockKey, required this.gap});
  final String blockKey;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final shut = m.collapsed(blockKey);
    final compact = m.s['ui_compact'] != false;
    final (Widget title, Widget? trailing, Widget body) = switch (blockKey) {
      'calendar' => (const Text('Календарь', style: T.title), null, const CalendarBlock()),
      'goals' => (
          const Text('Цели недели', style: T.title),
          _count(m.weekGoals().where((g) => g['done'] == true).length, m.weekGoals().length),
          const GoalsBlock()
        ),
      'tasks' => (const TasksHeader(), null, const TasksBlock()),
      'future' => (const Text('Будущие задачи', style: T.title), _num(m.futureTasks().length), const FutureBlock()),
      'week' => (
          const Text('Неделя', style: T.title),
          IconBtn(Icons.open_in_full, 'Открыть неделю крупно', () => sc.actions.openWeek(context), size: 13),
          Padding(padding: const EdgeInsets.only(top: 6), child: WeekStrip(start: m.today)),
        ),
      'pomo' => (const PomoHeader(), null, const PomoBlock()),
      'notes' => (const Text('Заметки', style: T.title), null, const NotesBlock()),
      'stats' => (const Text('Итоги недели', style: T.title), null, const StatsBlock()),
      'events' => (const Text('События', style: T.title), null, const EventsBlock()),
      _ => (Text(blockKey), null, const SizedBox.shrink()),
    };
    final summary = shut ? _summary(m) : null;
    return Container(
      margin: EdgeInsets.only(bottom: gap),
      padding: compact ? const EdgeInsets.fromLTRB(8, 5, 10, 7) : const EdgeInsets.fromLTRB(10, 8, 12, 10),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => m.toggleCollapsed(blockKey),
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            AnimatedRotation(
              turns: shut ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.expand_more, size: 16, color: C.muted),
            ),
            const SizedBox(width: 2),
            Expanded(child: title),
            if (summary != null) Padding(padding: const EdgeInsets.only(left: 6), child: Text(summary, style: T.tiny)),
            if (!shut && trailing != null) trailing,
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: shut ? const SizedBox(width: double.infinity) : body,
        ),
      ]),
    );
  }

  Widget _count(int a, int b) => Text(b == 0 ? '' : '$a/$b', style: T.tiny);
  Widget _num(int n) => Text(n == 0 ? '' : '$n', style: T.tiny);

  String? _summary(PanelModel m) {
    switch (blockKey) {
      case 'calendar':
        return '${dayLong(m.today)}, ${wdShort[wd(m.today)].toLowerCase()}';
      case 'future':
        final f = m.futureTasks();
        return f.isEmpty ? null : 'ближайшая ${futureDateText(fromIso(f.first['date'] as String), m.today)}, ${f.length}';
      case 'events':
        final e = m.events;
        if (e.isEmpty) return null;
        final n = daysBetween(m.today, fromIso(e.first['date'] as String));
        return '${short(e.first['title'] as String, 18)}, ${n == 0 ? 'сегодня' : 'через ${pluralDays(n)}'}';
      case 'goals':
        final g = m.weekGoals();
        return g.isEmpty ? null : '${g.where((x) => x['done'] == true).length} из ${g.length}';
      case 'notes':
        final first = '${m.data['notes'] ?? ''}'.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        return first.isEmpty ? null : short(first.trim(), 24);
      case 'week':
        final total = [for (var i = 0; i < 7; i++) m.loadMinutes(addDays(m.today, i))].fold<int>(0, (a, b) => a + b);
        return total == 0 ? null : fmtEst(total);
    }
    return null;
  }
}

/// Уголки для изменения размера виджета без рамки.
class ResizeGrips extends StatelessWidget {
  const ResizeGrips({super.key, required this.desk});
  final DesktopWindow desk;

  @override
  Widget build(BuildContext context) {
    Widget grip(ResizeEdge edge, MouseCursor cursor, Alignment al, IconData icon) => Align(
          alignment: al,
          child: MouseRegion(
            cursor: cursor,
            child: GestureDetector(
              onPanStart: (_) => desk.startResize(edge),
              child: SizedBox(width: 16, height: 16, child: Icon(icon, size: 10, color: C.faint)),
            ),
          ),
        );
    return Stack(children: [
      grip(ResizeEdge.bottomRight, SystemMouseCursors.resizeDownRight, Alignment.bottomRight, Icons.south_east),
      grip(ResizeEdge.bottomLeft, SystemMouseCursors.resizeDownLeft, Alignment.bottomLeft, Icons.south_west),
    ]);
  }
}

/// Всплывающие уведомления в углу панели: напоминания, конец помидора.
class Toasts extends StatefulWidget {
  const Toasts({super.key, required this.onOpen});
  final void Function(String id) onOpen;
  @override
  State<Toasts> createState() => _ToastsState();
}

class _ToastsState extends State<Toasts> {
  final items = <(int, Notice)>[];
  StreamSubscription<Notice>? sub;
  int seq = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sub ??= Scope.of(context).m.notices.listen((n) {
      final id = ++seq;
      setState(() => items.add((id, n)));
      Timer(Duration(seconds: n.seconds ?? (n.kind == 'remind' ? 120 : 25)), () => _close(id));
    });
  }

  void _close(int id) {
    if (mounted) setState(() => items.removeWhere((x) => x.$1 == id));
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (id, n) in items)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: levelColor(n.kind == 'remind' ? 'accent' : n.kind), width: 4)),
                boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: InkWell(
                onTap: () => _close(id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, style: T.title.copyWith(color: levelColor(n.kind == 'remind' ? 'accent' : n.kind))),
                    Text(n.text, style: T.norm),
                    if (n.actions.isNotEmpty)
                      Wrap(children: [
                        for (final (label, f) in n.actions)
                          Btn(label, () {
                            f();
                            _close(id);
                          }, pad: 4),
                      ]),
                    if (n.taskId != null)
                      Wrap(children: [
                        Btn('через 10 мин', () {
                          m.snooze(n.taskId!, 10);
                          _close(id);
                        }, pad: 4),
                        Btn('через час', () {
                          m.snooze(n.taskId!, 60);
                          _close(id);
                        }, pad: 4),
                        Btn('завтра', () {
                          m.snoozeTomorrow(n.taskId!);
                          _close(id);
                        }, pad: 4),
                        Btn('открыть', () {
                          _close(id);
                          widget.onOpen(n.taskId!);
                        }, pad: 4),
                      ]),
                    Text('нажмите, чтобы закрыть', style: T.tiny.copyWith(color: C.faint, fontSize: 10)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
