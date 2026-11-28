import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'scope.dart';
import 'task_menu.dart';
import 'tasks_block.dart';
import 'theme.dart';
import 'widgets.dart';

// ===================== календарь =====================

/// Компактный календарь: число, точки нагрузки, флажок дедлайна, подсказка с задачами дня.
class CalendarBlock extends StatelessWidget {
  const CalendarBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final first = m.viewMonth;
    final start = addDays(first, -wd(first));
    final weeks = ((wd(first) + daysInMonth(first.year, first.month)) / 7).ceil();
    final load = <String, int>{};
    final deadlines = <String>{};
    for (final x in m.tasks) {
      final t = x as Json;
      if (t['done'] == true) continue;
      if (t['date'] is String) load[t['date'] as String] = (load[t['date']] ?? 0) + 1;
      if (t['deadline'] != null) deadlines.add(t['deadline'] as String);
    }
    final events = {for (final e in m.events) e['date'] as String};
    return Column(children: [
      Row(children: [
        IconBtn(Icons.chevron_left, 'Предыдущий месяц', () => m.shiftMonth(-1), size: 16),
        Expanded(
          child: Center(child: Text('${monthsNom[first.month - 1]} ${first.year}', style: T.small.copyWith(fontWeight: FontWeight.w500))),
        ),
        if (first.year != m.today.year || first.month != m.today.month || m.selected != m.today)
          Btn('сегодня', m.goToday, size: 11),
        IconBtn(Icons.chevron_right, 'Следующий месяц', () => m.shiftMonth(1), size: 16),
      ]),
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(child: Text(wdShort[i], style: TextStyle(fontSize: 10, color: i > 4 ? C.danger : C.muted))),
          ),
      ]),
      for (var w = 0; w < weeks; w++)
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _Day(
                d: addDays(start, w * 7 + i),
                inMonth: addDays(start, w * 7 + i).month == first.month,
                load: load[iso(addDays(start, w * 7 + i))] ?? 0,
                deadline: deadlines.contains(iso(addDays(start, w * 7 + i))),
                event: events.contains(iso(addDays(start, w * 7 + i))),
              ),
            ),
        ]),
    ]);
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.d, required this.inMonth, required this.load, required this.deadline, required this.event});
  final DateTime d;
  final bool inMonth;
  final int load;
  final bool deadline;
  final bool event;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final isToday = d == m.today, isSel = d == m.selected;
    final (kind, holiday) = m.dayKind(d);
    var fg = kind == 'off' ? C.danger : kind == 'short' ? C.warn : C.fg;
    if (!inMonth) fg = C.faint;
    if (d.isBefore(m.today) && inMonth && !isToday) fg = fg.withValues(alpha: 0.55);
    if (isToday) fg = C.onAccent;
    final cell = DragTarget<DragTask>(
      onWillAcceptWithDetails: (_) => !d.isBefore(m.today),
      onAcceptWithDetails: (dd) => m.moveTaskDate(dd.data.id, d),
      builder: (context, cand, _) => InkWell(
        onTap: () => m.selectDay(d),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 24,
          margin: const EdgeInsets.all(0.5),
          decoration: BoxDecoration(
            color: cand.isNotEmpty ? C.warn : isToday ? C.accent : null,
            borderRadius: BorderRadius.circular(5),
            border: isSel && !isToday ? Border.all(color: C.accent) : null,
          ),
          child: Stack(children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('${d.day}',
                    style: TextStyle(fontSize: 12, color: fg, fontWeight: isToday || load > 0 ? FontWeight.w600 : FontWeight.w400)),
              ),
            ),
            if (load > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 2,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var k = 0; k < math.min(load, 3); k++)
                    Container(
                      width: 3,
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 0.7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? C.onAccent : (load > 3 ? C.warn : C.muted),
                      ),
                    ),
                ]),
              ),
            if (deadline)
              Positioned(top: 1, right: 2, child: Icon(Icons.flag, size: 8, color: isToday ? C.onAccent : C.danger)),
            if (event && !deadline)
              Positioned(top: 2, right: 2, child: Container(width: 4, height: 4, decoration: BoxDecoration(color: isToday ? C.onAccent : C.accent, shape: BoxShape.circle))),
          ]),
        ),
      ),
    );
    final items = m.tasksFor(d);
    final evs = m.events.where((e) => e['date'] == iso(d));
    return Tooltip(
      waitDuration: const Duration(milliseconds: 450),
      richMessage: TextSpan(style: TextStyle(fontSize: 12, color: C.fg, height: 1.4), children: [
        TextSpan(text: '${weekdays[wd(d)]}, ${dayLong(d)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (holiday.isNotEmpty) TextSpan(text: '\n$holiday', style: TextStyle(color: C.danger)),
        if (kind == 'short') TextSpan(text: '\nСокращённый рабочий день', style: TextStyle(color: C.warn)),
        if (kind == 'moved') TextSpan(text: '\nРабочий день (перенос выходного)', style: TextStyle(color: C.warn)),
        for (final e in evs) TextSpan(text: '\n★ ${e['title']}', style: TextStyle(color: C.accent)),
        for (final t in items.take(8))
          TextSpan(
            text: '\n${t['done'] == true ? '✓' : '•'} ${short(taskLine(t), 44)}',
            style: TextStyle(color: t['done'] == true ? C.muted : (prioColor[t['priority']] ?? C.fg)),
          ),
        if (items.length > 8) TextSpan(text: '\nи ещё ${items.length - 8}', style: TextStyle(color: C.muted)),
        if (items.isEmpty) TextSpan(text: '\nЗадач нет', style: TextStyle(color: C.faint)),
      ]),
      child: cell,
    );
  }
}

// ===================== цели недели =====================

class GoalsBlock extends StatelessWidget {
  const GoalsBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final goals = m.weekGoals();
    final prev = goals.isEmpty ? m.prevWeekOpenGoals() : <Json>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (goals.length < goalsLimit)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Field(
            hint: 'Цель недели и Enter (до $goalsLimit)',
            onSubmitOk: (v) {
              final err = m.addGoal(v);
              if (err != null) m.flash(err, 'warn');
              return err == null;
            },
          ),
        ),
      for (final g in goals) _GoalRow(g: g),
      if (goals.isEmpty && prev.isNotEmpty) Btn('Перенести с прошлой недели: ${prev.length}', m.carryGoals, pad: 0),
      if (goals.isEmpty && prev.isEmpty)
        Text('3–5 главных результатов недели. Задачи привязываются к целям в карточке.', style: T.tiny.copyWith(color: C.faint)),
    ]);
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.g});
  final Json g;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final id = g['id'] as String;
    final done = g['done'] == true;
    final (dn, tot) = m.goalProgress(id);
    final menu = MenuController();
    return MenuAnchor(
      controller: menu,
      style: MenuStyle(backgroundColor: WidgetStatePropertyAll(C.card)),
      menuChildren: [
        MenuItemButton(onPressed: () => m.setSetting('filter', 'goal:$id'), child: const Text('Показать задачи этой цели')),
        MenuItemButton(
          onPressed: () => inputDialog(context, 'Цель недели', 'Новое название цели.', [('Цель', g['text'] as String)], (v) {
            if (v[0].isEmpty) return 'Название не может быть пустым';
            m.renameGoal(id, v[0]);
            return null;
          }),
          child: const Text('Переименовать…'),
        ),
        MenuItemButton(onPressed: () => m.moveGoals([g], addDays(m.today, 7)), child: const Text('Перенести на следующую неделю')),
        MenuItemButton(onPressed: () => m.deleteGoal(id), child: Text('Удалить цель', style: TextStyle(color: C.danger))),
      ],
      child: GestureDetector(
        onSecondaryTapDown: (d) => menu.open(position: d.localPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            InkWell(
              onTap: () => m.toggleGoal(id),
              child: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 15, color: done ? C.ok : C.rest),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => m.setSetting('filter', 'goal:$id'),
                child: Text(g['text'] as String, style: T.small.copyWith(color: done ? C.muted : C.fg)),
              ),
            ),
            if (tot > 0) ...[
              Text('$dn/$tot', style: T.tiny),
              const SizedBox(width: 4),
              SizedBox(
                width: 40,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(value: dn / tot, minHeight: 4, backgroundColor: C.faint, color: C.ok),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ===================== будущие задачи =====================

class FutureBlock extends StatefulWidget {
  const FutureBlock({super.key});
  @override
  State<FutureBlock> createState() => _FutureBlockState();
}

class _FutureBlockState extends State<FutureBlock> {
  String? hint;
  Timer? _hintTimer;

  void _hint(String? h) {
    setState(() => hint = h);
    _hintTimer?.cancel();
    if (h != null) _hintTimer = Timer(const Duration(seconds: 5), () => mounted ? setState(() => hint = null) : null);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final list = m.futureTasks();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Field(
          hint: 'Задача и дата: «Купить билеты 20.11»',
          onSubmitOk: (v) {
            final err = m.addFuture(v);
            _hint(err);
            return err == null;
          },
          onPasteLines: (lines) => _hint(m.addFutureLines(lines)),
          clearOnSubmit: true,
        ),
      ),
      if (hint != null) Text(hint!, style: T.tiny.copyWith(color: C.danger)),
      if (list.isEmpty) Text('Нет запланированных задач', style: T.small.copyWith(color: C.faint)),
      for (final t in list.take(futureMaxRows)) _FutureRow(t: t),
      if (list.length > futureMaxRows)
        Btn('и ещё ${plural(list.length - futureMaxRows, 'задача', 'задачи', 'задач')} — открыть неделю',
            () => sc.actions.openWeek(context), color: C.muted, size: 11, pad: 0),
    ]);
  }
}

class _FutureRow extends StatefulWidget {
  const _FutureRow({required this.t});
  final Json t;
  @override
  State<_FutureRow> createState() => _FutureRowState();
}

class _FutureRowState extends State<_FutureRow> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final t = widget.t;
    final id = t['id'] as String;
    final d = dayOf(t, m.today);
    final prio = prioColor[t['priority']];
    final row = MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: () => sc.actions.openCard(context, id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          decoration: BoxDecoration(color: hover ? C.hover : null, borderRadius: BorderRadius.circular(4)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 3, height: 14, margin: const EdgeInsets.only(right: 5, top: 2), color: prio ?? Colors.transparent),
            if (t['time'] != null) Padding(padding: const EdgeInsets.only(right: 5), child: Text(t['time'] as String, style: T.small.copyWith(color: C.muted))),
            Expanded(child: Text(t['text'] as String, style: T.small)),
            if (hover) IconBtn(Icons.close_rounded, 'Удалить', () => m.deleteTask(id), color: C.danger, size: 13),
            InkWell(
              onTap: () => m.selectDay(d),
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 1),
                child: Text(futureDateText(d, m.today), style: T.tiny),
              ),
            ),
          ]),
        ),
      ),
    );
    return DragTarget<DragTask>(
      onWillAcceptWithDetails: (dd) => dd.data.id != id,
      onAcceptWithDetails: (dd) => m.moveTaskDate(dd.data.id, d),
      builder: (_, cand, __) => Container(
        color: cand.isNotEmpty ? C.warn.withValues(alpha: 0.3) : null,
        child: TaskMenu(
          id: id,
          child: Draggable<DragTask>(
            data: DragTask(id),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: DragChip(text: t['text'] as String),
            child: row,
          ),
        ),
      ),
    );
  }
}

// ===================== неделя =====================

Color heatColor(int minutes, int limit) {
  if (minutes == 0) return C.card;
  if (minutes > limit) return C.heat[2];
  if (minutes > limit * 0.6) return C.heat[1];
  return C.heat[0];
}

/// Семь дней, начиная с today; фон — по сумме оценок задач.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.start, this.compact = true});
  final DateTime start;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final limit = m.dayHoursMinutes();
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 7; i++)
          Expanded(child: Builder(builder: (context) {
            final d = addDays(start, i);
            final items = m.tasksFor(d);
            final sorted = [...items.where((t) => t['done'] != true), ...items.where((t) => t['done'] == true)];
            final load = m.loadMinutes(d);
            final isToday = d == m.today;
            final off = m.isOff(d);
            final limitItems = compact ? 5 : 60;
            return DragTarget<DragTask>(
              onWillAcceptWithDetails: (_) => !d.isBefore(m.today),
              onAcceptWithDetails: (dd) => m.moveTaskDate(dd.data.id, d),
              builder: (context, cand, _) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: EdgeInsets.all(compact ? 2 : 5),
                constraints: BoxConstraints(minHeight: compact ? 48 : 260),
                decoration: BoxDecoration(
                  color: cand.isNotEmpty ? C.warn.withValues(alpha: 0.35) : heatColor(load, limit),
                  borderRadius: BorderRadius.circular(5),
                  border: isToday ? Border.all(color: C.accent) : null,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  InkWell(
                    onTap: () => m.selectDay(d),
                    child: Column(children: [
                      Text(compact ? wdShort[wd(d)] : '${wdShort[wd(d)]} ${d.day}',
                          style: TextStyle(fontSize: compact ? 10 : 13, color: isToday ? C.accent : (off ? C.danger : C.muted), fontWeight: compact ? null : FontWeight.w600)),
                      if (compact) Text('${d.day}', style: TextStyle(fontSize: 12, color: isToday ? C.accent : C.fg, fontWeight: FontWeight.w600)),
                      if (load > 0)
                        Text(fmtEst(load), style: TextStyle(fontSize: compact ? 9 : 11, color: load > limit ? C.danger : C.muted)),
                    ]),
                  ),
                  const SizedBox(height: 2),
                  for (final t in sorted.take(limitItems)) _WeekItem(t: t, compact: compact),
                  if (sorted.length > limitItems) Center(child: Text('+${sorted.length - limitItems}', style: T.tiny)),
                ]),
              ),
            );
          })),
      ]),
    );
  }
}

class _WeekItem extends StatelessWidget {
  const _WeekItem({required this.t, required this.compact});
  final Json t;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final id = t['id'] as String;
    final done = t['done'] == true;
    final color = prioColor[t['priority']];
    final item = Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 5, vertical: compact ? 1 : 3),
      decoration: BoxDecoration(
        color: done ? C.bg : (color != null ? mix(C.card, color, 0.35) : const Color(0x33000000)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        compact ? t['text'] as String : '${done ? '✓ ' : ''}${taskLine(t)}',
        maxLines: compact ? 1 : 3,
        overflow: compact ? TextOverflow.clip : TextOverflow.ellipsis,
        softWrap: !compact,
        style: TextStyle(fontSize: compact ? 9.5 : 12, color: done ? C.faint : C.fg),
      ),
    );
    return Tooltip(
      message: compact ? taskLine(t) : '',
      child: TaskMenu(
        id: id,
        child: Draggable<DragTask>(
          data: DragTask(id),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: DragChip(text: t['text'] as String),
          child: InkWell(onTap: () => sc.actions.openCard(context, id), child: item),
        ),
      ),
    );
  }
}

// ===================== помодоро =====================

class PomoHeader extends StatelessWidget {
  const PomoHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    return ValueListenableBuilder(
      valueListenable: m.clock,
      builder: (_, __, ___) => Row(children: [
        Text(m.pomoModeName, style: T.title.copyWith(color: m.pomoMode == 'work' ? C.accent : C.rest)),
        if (m.collapsed('pomo')) ...[
          const SizedBox(width: 8),
          Text('${m.pomoClock}${m.pomoRunning ? '' : ', пауза'}', style: T.small.copyWith(color: C.muted)),
        ],
        const Spacer(),
        if (m.pomosToday > 0) Text('сегодня: ${m.pomosToday} ●', style: T.tiny),
      ]),
    );
  }
}

class PomoBlock extends StatelessWidget {
  const PomoBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final t = m.findTask(m.s['pomo_task'] as String?);
    final every = math.max(1, (m.s['cycle'] as num? ?? 4).toInt());
    final inCycle = ((m.cycleCount()['n'] as num?) ?? 0).toInt() % every;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (t != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text('→ ${t['text']}', style: T.small.copyWith(color: C.muted), overflow: TextOverflow.ellipsis)),
            IconBtn(Icons.close, 'Отвязать задачу', () => m.linkPomo(null), size: 13),
          ]),
        ),
      Row(children: [
        ValueListenableBuilder(
          valueListenable: m.clock,
          builder: (_, __, ___) => Text(m.pomoClock, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: C.fg)),
        ),
        const Spacer(),
        Btn(m.pomoRunning ? 'Пауза' : 'Старт', m.pomoToggle, size: 13, bold: true),
        IconBtn(Icons.replay, 'Сбросить', m.pomoReset, size: 15),
        IconBtn(Icons.skip_next, 'Пропустить', m.pomoSkip, size: 15),
      ]),
      Row(children: [
        Expanded(
          child: Text('${'●' * inCycle}${'○' * (every - inCycle)}  до длинного перерыва',
              style: T.tiny.copyWith(color: C.faint), overflow: TextOverflow.ellipsis),
        ),
        for (final (w, b, l) in const [(25, 5, 15), (50, 10, 20), (15, 3, 10)])
          Btn('$w/$b', () => m.setPomo(work: w, brk: b, long: l),
              color: m.s['work'] == w && m.s['break'] == b ? C.accent : C.faint, size: 10, pad: 3),
      ]),
    ]);
  }
}

/// Режим фокуса: вместо панели — только таймер и задача.
class FocusView extends StatelessWidget {
  const FocusView({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final t = m.findTask(m.s['pomo_task'] as String?);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(10)),
      child: ValueListenableBuilder(
        valueListenable: m.clock,
        builder: (_, __, ___) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m.pomoModeName}${m.pomoRunning ? '' : ', пауза'}', style: T.small.copyWith(color: C.accent)),
          Text(m.pomoClock, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: C.fg)),
          Text(t != null ? t['text'] as String : 'Без привязки к задаче', style: T.norm.copyWith(color: t != null ? C.fg : C.faint)),
          const SizedBox(height: 8),
          Row(children: [
            Btn(m.pomoRunning ? 'Пауза' : 'Продолжить', m.pomoToggle, bold: true),
            Btn('Стоп', m.pomoReset, color: C.muted),
            const Spacer(),
            Btn('Показать панель', m.exitFocus, color: C.muted),
          ]),
        ]),
      ),
    );
  }
}

// ===================== заметки =====================

class NotesBlock extends StatefulWidget {
  const NotesBlock({super.key});
  @override
  State<NotesBlock> createState() => _NotesBlockState();
}

class _NotesBlockState extends State<NotesBlock> {
  final ctl = TextEditingController();
  Timer? _save;
  String state = '';
  PanelModel? _m;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_m == null) {
      _m = Scope.of(context).m;
      ctl.text = '${_m!.data['notes'] ?? ''}';
    }
  }

  @override
  void dispose() {
    if (_save?.isActive == true) {
      _save!.cancel();
      _m?.setNotes(ctl.text); // несохранённый текст не теряем при сворачивании блока
    }
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final links = linkRe.allMatches(ctl.text).map((x) => x[0]!).toSet().take(6).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 6),
      TextField(
        controller: ctl,
        minLines: 3,
        maxLines: 10,
        style: T.small,
        decoration: const InputDecoration(hintText: 'Заметки. Ссылки и пути к файлам появятся ниже — их можно открыть.'),
        onChanged: (_) {
          setState(() => state = '…');
          _save?.cancel();
          _save = Timer(const Duration(milliseconds: 800), () {
            sc.m.setNotes(ctl.text);
            if (mounted) setState(() => state = 'сохранено');
          });
        },
      ),
      if (links.isNotEmpty || state.isNotEmpty)
        Wrap(spacing: 6, children: [
          for (final l in links)
            InkWell(
              onTap: () => sc.actions.openTarget(l),
              child: Text(short(l.replaceAll('"', ''), 36),
                  style: T.tiny.copyWith(color: C.accent, decoration: TextDecoration.underline, decorationColor: C.accent)),
            ),
          if (state.isNotEmpty) Text(state, style: T.tiny.copyWith(color: C.faint)),
        ]),
    ]);
  }
}

// ===================== итоги недели =====================

class StatsBlock extends StatelessWidget {
  const StatsBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final chart = m.weekChart();
    final top = chart.fold<int>(1, (a, x) => math.max(a, math.max(x.$2, x.$3)));
    final by = m.s['stats_by'] ?? 'task';
    final stats = m.pomoStats();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 6),
      Row(children: [
        Text('■ ', style: T.tiny.copyWith(color: C.ok)),
        Text('задачи ${chart.fold<int>(0, (a, x) => a + x.$2)}', style: T.tiny),
        const SizedBox(width: 10),
        Text('■ ', style: T.tiny.copyWith(color: C.accent)),
        Text('помидоры ${chart.fold<int>(0, (a, x) => a + x.$3)}', style: T.tiny),
      ]),
      const SizedBox(height: 4),
      SizedBox(
        height: 64,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (d, dn, pm) in chart)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _bar(dn, top, C.ok),
                  const SizedBox(width: 2),
                  _bar(pm, top, C.accent),
                ]),
                const SizedBox(height: 2),
                Text(wdShort[wd(d)], style: TextStyle(fontSize: 10, color: d == m.today ? C.accent : C.muted)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Помидоры за 7 дней:', style: T.tiny),
        Btn('по задачам', () => m.setSetting('stats_by', 'task'), color: by == 'task' ? C.accent : C.faint, size: 11, pad: 4),
        Btn('по меткам', () => m.setSetting('stats_by', 'tag'), color: by == 'tag' ? C.accent : C.faint, size: 11, pad: 4),
      ]),
      if (stats.isEmpty) Text('Пока нет — запустите помидор из карточки задачи', style: T.tiny.copyWith(color: C.faint)),
      for (final (name, n) in stats)
        Row(children: [
          Expanded(
            child: Text(short(name, 30),
                style: T.tiny.copyWith(color: name.startsWith('#') ? tagColor(name.substring(1)) : C.fg)),
          ),
          Container(width: math.max(4, 60.0 * n / stats.first.$2), height: 4, color: C.accent),
          SizedBox(width: 22, child: Text('$n', style: T.tiny, textAlign: TextAlign.right)),
        ]),
    ]);
  }

  Widget _bar(int v, int top, Color c) => Container(
        width: 7,
        height: v == 0 ? 1 : math.max(2, 44.0 * v / top),
        color: v == 0 ? C.faint : c,
      );
}

// ===================== события =====================

class EventsBlock extends StatefulWidget {
  const EventsBlock({super.key});
  @override
  State<EventsBlock> createState() => _EventsBlockState();
}

class _EventsBlockState extends State<EventsBlock> {
  String? error;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final evs = m.events;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Field(
          hint: 'Событие ДД.ММ и Enter',
          onSubmitOk: (v) {
            setState(() => error = m.addEvent(v));
            return error == null;
          },
        ),
      ),
      if (error != null) Text(error!, style: T.tiny.copyWith(color: C.danger)),
      if (evs.isEmpty) Text('Нет событий', style: T.small.copyWith(color: C.faint)),
      for (final e in evs) _EventRow(e: e),
    ]);
  }
}

class _EventRow extends StatefulWidget {
  const _EventRow({required this.e});
  final Json e;
  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final d = fromIso(widget.e['date'] as String);
    final n = daysBetween(m.today, d);
    final (whenText, color) = n == 0
        ? ('сегодня', C.ok)
        : n == 1
            ? ('завтра', C.warn)
            : ('через ${pluralDays(n)}', n <= 3 ? C.warn : C.muted);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(child: Text(widget.e['title'] as String, style: T.small, overflow: TextOverflow.ellipsis)),
          Text(' ${two(d.day)}.${two(d.month)} ', style: T.tiny.copyWith(color: C.faint)),
          Text(whenText, style: T.small.copyWith(color: color)),
          SizedBox(
            width: 18,
            child: hover ? IconBtn(Icons.close, 'Удалить', () => m.deleteEvent(widget.e['id'] as String), color: C.danger, size: 12) : null,
          ),
        ]),
      ),
    );
  }
}
