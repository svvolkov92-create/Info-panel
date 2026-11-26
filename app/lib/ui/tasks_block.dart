import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'scope.dart';
import 'task_menu.dart';
import 'theme.dart';
import 'widgets.dart';

/// Заголовок блока «Задачи»: название дня, дата, загрузка, счётчик.
class TasksHeader extends StatelessWidget {
  const TasksHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final d = m.selected;
    final title = d == m.today
        ? 'Задачи на сегодня'
        : d == addDays(m.today, 1)
            ? 'Задачи на завтра'
            : 'Задачи на ${dayLong(d)}';
    final dateText = (d == m.today || d == addDays(m.today, 1))
        ? '${dayLong(d)}, ${wdShort[wd(d)].toLowerCase()}'
        : wdShort[wd(d)].toLowerCase() + (d.year != m.today.year ? ', ${d.year}' : '');
    final all = m.tasksFor(d);
    final done = all.where((t) => t['done'] == true).length;
    // в прошлом дне перенесённые задачи считаются несделанными: «всё сделано» — только если ничего не перенеслось
    final total = all.length + m.carriedThrough(d).length;
    final est = m.loadMinutes(d);
    final limit = m.dayHoursMinutes();
    final hours = '${(m.s['day_hours'] as num? ?? 8)}'.replaceAll('.0', '').replaceAll('.', ',');
    return LayoutBuilder(builder: (context, c) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Flexible(child: Text(title, style: T.title, overflow: TextOverflow.ellipsis)),
      if (c.maxWidth > 420) ...[const SizedBox(width: 6), Text(dateText, style: T.tiny)],
      const Spacer(),
      if (est > 0) ...[
        Text('${fmtEst(est)} из $hours ч', style: T.tiny.copyWith(color: est > limit ? C.danger : C.muted)),
        const SizedBox(width: 8),
      ],
      ValueListenableBuilder(
        valueListenable: m.status,
        builder: (_, st, __) {
          if (st != null) return Text(st.$1, style: T.tiny.copyWith(color: levelColor(st.$2)));
          if (total > 0 && done == total) return Text('всё сделано ✓ $done', style: T.tiny.copyWith(color: C.ok));
          return Text(total == 0 ? '' : 'сделано $done из $total', style: T.tiny);
        },
      ),
    ]));
  }
}

class TasksBlock extends StatefulWidget {
  const TasksBlock({super.key});
  @override
  State<TasksBlock> createState() => _TasksBlockState();
}

class _TasksBlockState extends State<TasksBlock> {
  final entry = TextEditingController();
  bool cheat = false;
  String? subFocus; // у какой задачи открыть поле подзадачи

  @override
  void dispose() {
    entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final d = m.selected;
    final all = m.tasksFor(d);
    final items = m.viewTasks(d);
    final est = m.loadMinutes(d);
    final limit = m.dayHoursMinutes();
    final undone = all.where((t) => t['done'] != true);
    final q1 = undone.where((t) => t['eis'] == 'q1').length;
    final q1Limit = (m.s['q1_limit'] as num? ?? 5).toInt();
    final over = <String>[
      if (q1 > q1Limit) '«Сделать сейчас»: $q1 при лимите $q1Limit',
      if (est > limit) 'запланировано ${fmtEst(est)} из ${fmtEst(limit)}',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (est > 0 && limit > 0)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (est / limit).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: C.faint,
              color: est > limit ? C.danger : C.accent,
            ),
          ),
        ),
      const SizedBox(height: 6),
      Field(
        controller: entry,
        hint: 'Новая задача и Enter, или Ctrl+V списком',
        onChanged: (_) => setState(() {}),
        onSubmit: (v) {
          final moved = m.addTask(v);
          if (moved != null) setState(() {});
        },
        onPasteLines: m.addTasks,
        suffix: IconBtn(Icons.help_outline, 'Шпаргалка быстрого ввода', () => setState(() => cheat = !cheat),
            color: cheat ? C.accent : C.muted, size: 15),
      ),
      QuickPreview(text: entry.text),
      if (cheat) CheatSheet(onPick: (ex) => setState(() {
        entry.text = ex;
        entry.selection = TextSelection.collapsed(offset: ex.length);
        cheat = false;
      })),
      _controls(m),
      if (over.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: mix(C.card, C.warn, 0.18), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(child: Text('Перегруз: ${over.join('; ')}', style: T.tiny.copyWith(color: C.warn))),
            Btn('Разгрузить…', () => sc.actions.openUnload(context), color: C.warn, size: 11),
          ]),
        ),
      if (items.isEmpty) _empty(context, m, d, all.isNotEmpty),
      for (final t in items)
        TaskRow(
          key: ValueKey(t['id']),
          t: t,
          editing: m.editing == t['id'],
          selected: m.kbSel == t['id'],
          focusSub: subFocus == t['id'],
          onEdit: () => m.setEditing(t['id'] as String),
          onEditDone: () => m.setEditing(null),
          onSubs: () {
            if (t['open'] != true) m.toggleOpen(t['id'] as String);
            setState(() => subFocus = t['id'] as String);
          },
        ),
      if (items.isNotEmpty) _dropEnd(m),
      ..._carried(context, m, d),
      ValueListenableBuilder(
        valueListenable: m.undoBar,
        builder: (_, text, __) => text == null
            ? const SizedBox.shrink()
            : Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: C.hover, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Expanded(child: Text(text, style: T.small, overflow: TextOverflow.ellipsis)),
                  Btn('Отменить', m.undo, size: 12, bold: true),
                ]),
              ),
      ),
    ]);
  }

  Widget _controls(PanelModel m) {
    final f = '${m.s['filter']}';
    String filterLabel;
    if (filters.containsKey(f)) {
      filterLabel = filters[f]!;
    } else if (f.startsWith('goal:')) {
      final g = m.findGoal(f.substring(5));
      filterLabel = g == null ? filters['all']! : 'цель: ${short(g['text'] as String, 18)}';
    } else {
      filterLabel = f;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        PopupMenuButton<String>(
          tooltip: 'Сортировка',
          onSelected: (v) => m.setSetting('sort', v),
          itemBuilder: (_) => [
            for (final e in sorts.entries) CheckedPopupMenuItem(value: e.key, checked: m.s['sort'] == e.key, child: Text(e.value)),
          ],
          child: Text('↕ ${sorts[m.s['sort']] ?? ''}', style: T.tiny.copyWith(color: m.s['sort'] == 'manual' ? C.muted : C.accent)),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          tooltip: 'Фильтр',
          onSelected: (v) => m.setSetting('filter', v),
          itemBuilder: (_) => [
            for (final e in filters.entries) CheckedPopupMenuItem(value: e.key, checked: f == e.key, child: Text(e.value)),
            if (m.weekGoals().isNotEmpty) const PopupMenuDivider(),
            for (final g in m.weekGoals())
              CheckedPopupMenuItem(value: 'goal:${g['id']}', checked: f == 'goal:${g['id']}', child: Text('цель: ${short(g['text'] as String, 30)}')),
            if (m.allTags().isNotEmpty) const PopupMenuDivider(),
            for (final g in m.allTags()) CheckedPopupMenuItem(value: '#$g', checked: f == '#$g', child: Text(tagLabel('$g'))),
          ],
          child: Text('$filterLabel', style: T.tiny.copyWith(color: f == 'all' ? C.muted : C.warn)),
        ),
      ]),
    );
  }

  /// Прошедший день: что не успелось и куда переехало.
  List<Widget> _carried(BuildContext context, PanelModel m, DateTime d) {
    final list = m.carriedThrough(d);
    if (list.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text('Не успелось, перенесено: ${list.length}', style: T.tiny.copyWith(color: C.warn)),
      ),
      for (final t in list)
        InkWell(
          onTap: () => Scope.of(context).actions.openCard(context, t['id'] as String),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 16, child: Icon(Icons.arrow_forward, size: 13, color: C.warn)),
              const SizedBox(width: 4),
              Expanded(child: Text(t['text'] as String, style: T.norm.copyWith(color: C.muted))),
              Text(
                t['done'] == true
                    ? 'выполнена ${t['done_at'] is String ? shortDate(fromIso(t['done_at'] as String), m.today) : ''}'
                    : 'теперь ${futureDateText(fromIso(t['date'] as String), m.today)}',
                style: T.tiny.copyWith(color: t['done'] == true ? C.ok : C.muted),
              ),
            ]),
          ),
        ),
    ];
  }

  /// Бросить задачу ниже последней — в конец списка.
  Widget _dropEnd(PanelModel m) => DragTarget<DragTask>(
        onAcceptWithDetails: (dd) => m.moveTaskOrder(dd.data.id, null),
        builder: (_, cand, __) => Container(height: 10, color: cand.isNotEmpty ? C.accent.withValues(alpha: 0.4) : null),
      );

  Widget _empty(BuildContext context, PanelModel m, DateTime d, bool filtered) {
    if (filtered) {
      return Row(children: [
        Text('Нет задач по этому фильтру', style: T.small.copyWith(color: C.faint)),
        Btn('Показать все', () => m.setSetting('filter', 'all')),
      ]);
    }
    final next = addDays(d, 1);
    final later = d.isBefore(m.today) ? <Json>[] : m.tasksFor(next).where((t) => t['done'] != true).toList();
    if (later.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('Пока пусто — впишите задачу выше', style: T.small.copyWith(color: C.faint)),
      );
    }
    final when = d == m.today ? 'сегодня' : 'этот день';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('На $when пусто. На следующий день ${plural(later.length, 'задача', 'задачи', 'задач')}.', style: T.small),
        Row(children: [
          Btn('Взять на $when', () => m.pullTasks(next, d), pad: 0),
          const SizedBox(width: 10),
          Btn('Матрица', () => Scope.of(context).actions.openMatrix(context), color: C.muted),
        ]),
      ]),
    );
  }
}

/// Распознанные части быстрого ввода — цветными плашками.
class QuickPreview extends StatelessWidget {
  const QuickPreview({super.key, required this.text, this.allowDate = true});
  final String text;
  final bool allowDate;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final q = parseQuick(text, m.today, allowDate: allowDate);
    final parts = <(String, Color)>[
      if (q.date != null) (dateTitle(q.date!, m.today), C.accent),
      if (q.time != null) (q.time!, C.accent),
      if (q.prio) ('высокий приоритет', C.danger),
      if (q.eis != null) (eis[q.eis]!.$1, eisColor[q.eis]!),
      if (q.est != null) (fmtEst(q.est!), C.muted),
      for (final g in q.tags) (tagLabel(g), tagColor(g)),
      if (q.deadline != null) ('до ${shortDate(q.deadline!, m.today)}', C.warn),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 4, runSpacing: 3, children: [
          for (final (label, color) in parts)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: mix(C.card, color, 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(fontSize: 11, color: color)),
            ),
        ]),
        if (q.text.isNotEmpty && q.text != text.trim())
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('Название: ${q.text}', style: T.tiny)),
      ]),
    );
  }
}

class CheatSheet extends StatelessWidget {
  const CheatSheet({super.key, required this.onPick});
  final void Function(String) onPick;

  static const rows = [
    ('пт отчёт', 'на пятницу'),
    ('завтра 9:30 врач', 'дата и время'),
    ('25.12 подарки', 'на число'),
    ('! договор', 'высокий приоритет'),
    ('!!1 договор', 'квадрант «Сделать сейчас»'),
    ('билеты #дом ~30м', 'метка и оценка'),
    ('отчёт до пт', 'дедлайн'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: C.faint)),
      child: Column(children: [
        for (final (ex, what) in rows)
          InkWell(
            onTap: () => onPick(ex),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(children: [
                SizedBox(width: 130, child: Text(ex, style: T.small.copyWith(color: C.accent))),
                Expanded(child: Text(what, style: T.tiny)),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Щёлкните пример, чтобы вставить его в поле', style: T.tiny.copyWith(color: C.faint)),
        ),
      ]),
    );
  }
}

/// Строка задачи в списке дня.
class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.t,
    required this.editing,
    required this.onEdit,
    required this.onEditDone,
    required this.onSubs,
    this.focusSub = false,
    this.selected = false,
  });

  final Json t;
  final bool editing;
  final bool selected;
  final bool focusSub;
  final VoidCallback onEdit;
  final VoidCallback onEditDone;
  final VoidCallback onSubs;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool hover = false;
  late final TextEditingController edit = TextEditingController();
  final editFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    editFocus.addListener(() {
      if (!editFocus.hasFocus && widget.editing) _finishEdit(save: true);
    });
  }

  @override
  void dispose() {
    edit.dispose();
    editFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.editing && edit.text.isEmpty) _startEdit();
  }

  @override
  void didUpdateWidget(TaskRow old) {
    super.didUpdateWidget(old);
    if (widget.editing && !old.editing) _startEdit();
  }

  void _startEdit() {
    final m = Scope.of(context).m;
    edit.text = taskEditLine(widget.t, m.today);
    edit.selection = TextSelection(baseOffset: 0, extentOffset: edit.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) => editFocus.requestFocus());
  }

  void _finishEdit({required bool save}) {
    if (!widget.editing) return;
    final m = Scope.of(context).m;
    if (save) m.editTask(widget.t['id'] as String, edit.text);
    widget.onEditDone();
  }

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final t = widget.t;
    final id = t['id'] as String;
    final done = t['done'] == true;
    final note = carriedNote(t, m.today);
    final carried = note != null && !done;
    final gap = (m.s['task_gap'] as num? ?? 1).toDouble();
    final font = (m.s['task_font'] as num? ?? 10).toDouble() + 3;
    final prio = prioColor[t['priority']];

    final meta = <(String, Color, VoidCallback?)>[];
    if (eis.containsKey(t['eis'])) meta.add((eis[t['eis']]!.$1, done ? C.muted : eisColor[t['eis']]!, () => sc.actions.openCard(context, id)));
    final badge = deadlineBadge(t, m.today);
    if (badge != null && !done) meta.add((badge.$1, levelColor(badge.$2), () => sc.actions.askDeadline(context, id)));
    if (t['est'] is num) meta.add((fmtEst((t['est'] as num).round()), C.muted, () => sc.actions.askEst(context, id)));
    for (final g in (t['tags'] as List?) ?? const []) {
      meta.add((tagLabel('$g'), tagColor('$g'), () => m.setSetting('filter', '#$g')));
    }
    final goal = m.findGoal(t['goal']);
    if (goal != null) meta.add(('цель: ${short(goal['text'] as String, 16)}', C.rest, () => m.setSetting('filter', 'goal:${goal['id']}')));
    final subs = [for (final x in (t['subs'] as List?) ?? const []) x as Json];
    if (subs.isNotEmpty) {
      final sd = subs.where((x) => x['done'] == true).length;
      meta.add(('$sd/${subs.length} ${t['open'] == true ? 'подзадач, скрыть' : 'подзадач'}', sd == subs.length ? C.ok : C.muted, () => m.toggleOpen(id)));
    }
    final rule = m.ruleOf(t);
    if (rule != null) meta.add(('↻ ${ruleText(rule)}', C.muted, null));
    if (t['pomos'] is num) meta.add(('● ${t['pomos']}', C.accent, null));
    if (m.s['pomo_task'] == id) meta.add(('в помодоро', C.rest, null));
    if ('${t['note'] ?? ''}'.trim().isNotEmpty) meta.add(('заметка', C.muted, () => sc.actions.openCard(context, id)));
    final moved = ((t['moves'] as num?) ?? 0).toInt() + ((t['carries'] as num?) ?? 0).toInt();
    if (moved >= 3 && !done) meta.add(('→ $moved', C.warn, () => sc.actions.openCard(context, id)));

    Widget titleArea;
    if (widget.editing) {
      titleArea = CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _finishEdit(save: false)},
        child: TextField(
          controller: edit,
          focusNode: editFocus,
          style: TextStyle(fontSize: font, color: C.fg),
          onSubmitted: (_) => _finishEdit(save: true),
          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 5)),
        ),
      );
    } else {
      titleArea = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t['text'] as String, style: TextStyle(fontSize: font, color: done ? C.muted : C.fg, height: 1.25)),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Wrap(spacing: 8, runSpacing: 0, children: [
              for (final (label, color, onTap) in meta)
                onTap == null
                    ? Text(label, style: TextStyle(fontSize: font - 2.5, color: color))
                    : InkWell(onTap: onTap, child: Text(label, style: TextStyle(fontSize: font - 2.5, color: color))),
            ]),
          ),
        if (note != null)
          Text(note, style: TextStyle(fontSize: font - 2, color: done ? C.faint : C.warn, fontStyle: FontStyle.italic))
        else if (m.held(t))
          Text(wdFrom[wd(dayOf(t, m.today))],
              style: TextStyle(fontSize: font - 2, color: C.faint, fontStyle: FontStyle.italic)),
      ]);
    }

    final row = MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Stack(children: [
       Container(
        margin: EdgeInsets.symmetric(vertical: gap),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        decoration: BoxDecoration(
            color: widget.selected ? C.selected : (hover ? C.hover : null), borderRadius: BorderRadius.circular(5)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 16,
            child: carried
                ? InkWell(onTap: () => m.toggleTask(id), child: Icon(Icons.arrow_forward, size: font, color: C.warn))
                : null,
          ),
          InkWell(
            onTap: () => m.toggleTask(id),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.only(top: 1, right: 5),
              child: Icon(done ? Icons.check_circle : Icons.circle_outlined, size: font + 2, color: done ? C.ok : C.muted),
            ),
          ),
          if (t['time'] != null)
            SizedBox(
              width: font * 3.3,
              child: Text(t['time'] as String, style: TextStyle(fontSize: font, color: done ? C.faint : C.muted, height: 1.25)),
            ),
          Expanded(child: InkWell(onTap: widget.editing ? null : () => sc.actions.openCard(context, id), child: titleArea)),
          // точка приоритета — всегда на своём месте, чтобы строка не меняла ширину
          SizedBox(
            width: 12,
            child: prio != null && !done
                ? Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(color: prio, shape: BoxShape.circle)),
                  )
                : null,
          ),
        ]),
      ),
       // значки действий появляются поверх правого края строки и не сдвигают текст
       if (hover && !widget.editing)
         Positioned(
           right: 2,
           top: gap + 1,
           child: Container(
             decoration: BoxDecoration(color: widget.selected ? C.selected : C.hover, borderRadius: BorderRadius.circular(5)),
             child: Row(mainAxisSize: MainAxisSize.min, children: [
               if (!done) IconBtn(Icons.play_arrow_rounded, 'Помидор', () => m.linkPomo(id), color: C.ok, size: 15),
               if (!done) IconBtn(Icons.redo_rounded, 'На следующий день', () => m.moveTaskDate(id, m.nextDayFor(id)), color: C.accent, size: 15),
               IconBtn(Icons.close_rounded, 'Удалить', () => m.deleteTask(id), color: C.danger, size: 15),
             ]),
           ),
         ),
      ]),
    );

    // предпросмотр заметки и подзадач при наведении — без открытия карточки
    final noteText = '${t['note'] ?? ''}'.trim();
    final rowWithTip = (noteText.isEmpty && subs.isEmpty) || widget.editing
        ? row
        : Tooltip(
            waitDuration: const Duration(milliseconds: 650),
            preferBelow: true,
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 340),
            richMessage: TextSpan(style: const TextStyle(fontSize: 12, color: C.fg, height: 1.4), children: [
              if (noteText.isNotEmpty) TextSpan(text: short(noteText, 300)),
              if (noteText.isNotEmpty && subs.isNotEmpty) const TextSpan(text: '\n'),
              for (final sb in subs)
                TextSpan(
                  text: '\n${sb['done'] == true ? '✓' : '•'}  ${sb['text']}',
                  style: TextStyle(color: sb['done'] == true ? C.muted : C.fg),
                ),
            ]),
            child: row,
          );
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      rowWithTip,
      if (t['open'] == true && !widget.editing) _subs(m, id, subs, font),
    ]);

    return DragTarget<DragTask>(
      onWillAcceptWithDetails: (dd) => dd.data.id != id,
      onAcceptWithDetails: (dd) => m.moveTaskOrder(dd.data.id, id),
      builder: (context, cand, _) => Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cand.isNotEmpty ? C.accent : Colors.transparent, width: 2))),
        child: TaskMenu(
          id: id,
          onEdit: widget.onEdit,
          onSubs: widget.onSubs,
          child: widget.editing
              ? body
              : Draggable<DragTask>(
                  data: DragTask(id),
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: DragChip(text: t['text'] as String),
                  childWhenDragging: Opacity(opacity: 0.4, child: body),
                  child: body,
                ),
        ),
      ),
    );
  }

  Widget _subs(PanelModel m, String id, List<Json> subs, double font) {
    return Padding(
      padding: const EdgeInsets.only(left: 36, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final sb in subs)
          InkWell(
            onTap: () => m.toggleSub(id, sb['id'] as String),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(sb['done'] == true ? Icons.check_box : Icons.check_box_outline_blank,
                  size: font, color: sb['done'] == true ? C.ok : C.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(sb['text'] as String,
                    style: TextStyle(fontSize: font - 1, color: sb['done'] == true ? C.muted : C.fg)),
              ),
              InkWell(onTap: () => m.deleteSub(id, sb['id'] as String), child: const Icon(Icons.close, size: 12, color: C.faint)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Field(
            hint: 'Подзадача и Enter',
            autofocus: widget.focusSub,
            style: TextStyle(fontSize: font - 1, color: C.fg),
            onSubmit: (v) => m.addSubtasks(id, [v]),
            onPasteLines: (lines) => m.addSubtasks(id, lines),
          ),
        ),
      ]),
    );
  }
}

/// Плашка, которая едет за курсором при перетаскивании задачи.
class DragChip extends StatelessWidget {
  const DragChip({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.only(left: 12, top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: C.selected.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(5)),
          child: Text(short(text, 40), style: T.norm),
        ),
      );
}
