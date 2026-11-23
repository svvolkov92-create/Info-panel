import 'package:flutter/material.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'blocks.dart';
import 'scope.dart';
import 'task_menu.dart';
import 'tasks_block.dart';
import 'theme.dart';
import 'widgets.dart';

/// Каркас окна-диалога: заголовок, крестик, прокручиваемое содержимое.
class Frame extends StatelessWidget {
  const Frame({super.key, required this.title, required this.child, this.maxWidth = 640, this.actions = const [], this.top});
  final String title;
  final Widget child;
  final double maxWidth;
  final List<Widget> actions;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.bg,
      insetPadding: const EdgeInsets.all(10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 820),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
            child: Row(children: [
              Expanded(child: Text(title, style: T.title.copyWith(fontSize: 15))),
              ...actions,
              IconBtn(Icons.close, 'Закрыть (Esc)', () => Navigator.pop(context)),
            ]),
          ),
          if (top != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: top),
          Flexible(
            child: Scrollbar(
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 14), child: child),
            ),
          ),
        ]),
      ),
    );
  }
}

// ===================== неделя =====================

class WeekWindow extends StatefulWidget {
  const WeekWindow({super.key, this.start});
  final DateTime? start;
  @override
  State<WeekWindow> createState() => _WeekWindowState();
}

class _WeekWindowState extends State<WeekWindow> {
  DateTime? start;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final monday = addDays(m.today, -wd(m.today));
    final s = start ?? widget.start ?? monday;
    final end = addDays(s, 6);
    final span = s.month == end.month
        ? '${s.day} – ${end.day} ${monthsGen[end.month - 1]} ${end.year}'
        : '${s.day} ${monthsGen[s.month - 1]} – ${end.day} ${monthsGen[end.month - 1]} ${end.year}';
    return Frame(
      title: 'Неделя',
      maxWidth: 1100,
      top: Row(children: [
        IconBtn(Icons.chevron_left, 'Предыдущая неделя', () => setState(() => start = addDays(s, -7))),
        Text(span, style: T.title),
        IconBtn(Icons.chevron_right, 'Следующая неделя', () => setState(() => start = addDays(s, 7))),
        if (s != monday) Btn('Эта неделя', () => setState(() => start = monday)),
        const Spacer(),
        Flexible(child: Text('Перетаскивайте задачи между днями, щелчок — карточка', style: T.tiny.copyWith(color: C.faint), overflow: TextOverflow.ellipsis)),
      ]),
      child: Padding(padding: const EdgeInsets.only(top: 6), child: WeekStrip(start: s, compact: false)),
    );
  }
}

// ===================== матрица =====================

class MatrixWindow extends StatefulWidget {
  const MatrixWindow({super.key});
  @override
  State<MatrixWindow> createState() => _MatrixWindowState();
}

class _MatrixWindowState extends State<MatrixWindow> {
  String scope = 'week';
  static const scopes = {'today': 'Сегодня', 'week': 'Неделя', 'all': 'Все незакрытые'};

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final groups = <String, List<Json>>{'q1': [], 'q2': [], 'q3': [], 'q4': [], 'none': []};
    final list = [
      for (final x in m.tasks)
        if ((x as Json)['done'] != true &&
            (scope == 'all' ||
                (scope == 'today' && x['date'] == iso(m.today)) ||
                (scope == 'week' && daysBetween(m.today, fromIso(x['date'] as String)) >= 0 && daysBetween(m.today, fromIso(x['date'] as String)) <= 6)))
          x,
    ]..sort((a, b) {
        final c = (a['date'] as String).compareTo(b['date'] as String);
        return c != 0 ? c : (prioRank[a['priority']] ?? 3) - (prioRank[b['priority']] ?? 3);
      });
    for (final t in list) {
      groups[eis.containsKey(t['eis']) ? t['eis'] as String : 'none']!.add(t);
    }
    Widget quad(String q) {
      final color = q == 'none' ? C.faint : eisColor[q]!;
      final items = groups[q]!;
      return DragTarget<DragTask>(
        onAcceptWithDetails: (dd) => m.setField(dd.data.id, 'eis', q == 'none' ? null : q),
        builder: (context, cand, _) => Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.all(8),
          constraints: BoxConstraints(minHeight: q == 'none' ? 60 : 170),
          decoration: BoxDecoration(
            color: cand.isNotEmpty ? mix(C.card, color, 0.3) : C.card,
            borderRadius: BorderRadius.circular(8),
            border: Border(top: BorderSide(color: color, width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(q == 'none' ? 'Без отметки' : eis[q]!.$1, style: T.title.copyWith(color: q == 'none' ? C.muted : color)),
              const SizedBox(width: 6),
              Expanded(child: Text(q == 'none' ? 'перетащите в нужный квадрант' : eis[q]!.$2, style: T.tiny.copyWith(color: C.faint), overflow: TextOverflow.ellipsis)),
              Text(items.isEmpty ? '' : '${items.length}', style: T.small.copyWith(color: C.muted)),
            ]),
            const SizedBox(height: 4),
            if (items.isEmpty) Text('пусто', style: T.small.copyWith(color: C.faint)),
            for (final t in items.take(matrixMaxRows)) _MatrixItem(t: t),
            if (items.length > matrixMaxRows) Text('и ещё ${items.length - matrixMaxRows} — сузьте период', style: T.tiny),
          ]),
        ),
      );
    }

    return Frame(
      title: 'Матрица Эйзенхауэра',
      maxWidth: 980,
      top: Row(children: [
        for (final e in scopes.entries) Pill(e.value, scope == e.key, () => setState(() => scope = e.key)),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: quad('q1')), Expanded(child: quad('q2'))])),
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: quad('q3')), Expanded(child: quad('q4'))])),
        quad('none'),
      ]),
    );
  }
}

class _MatrixItem extends StatelessWidget {
  const _MatrixItem({required this.t});
  final Json t;
  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final id = t['id'] as String;
    final d = fromIso(t['date'] as String);
    final badge = deadlineBadge(t, m.today);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 3, height: 14, margin: const EdgeInsets.only(right: 5, top: 2), color: prioColor[t['priority']] ?? Colors.transparent),
        SizedBox(width: 66, child: Text(d == m.today ? 'сегодня' : futureDateText(d, m.today), style: T.tiny.copyWith(color: C.faint))),
        Expanded(child: Text(taskLine(t), style: T.small)),
        if (badge != null) Text(badge.$1, style: T.tiny.copyWith(color: levelColor(badge.$2))),
      ]),
    );
    return TaskMenu(
      id: id,
      child: Draggable<DragTask>(
        data: DragTask(id),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: DragChip(text: t['text'] as String),
        child: InkWell(onTap: () => sc.actions.openCard(context, id), child: row),
      ),
    );
  }
}

// ===================== поиск =====================

class SearchWindow extends StatefulWidget {
  const SearchWindow({super.key});
  @override
  State<SearchWindow> createState() => _SearchWindowState();
}

class _SearchWindowState extends State<SearchWindow> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final found = m.search(q);
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    void go(Json t) {
      m.selectDay(fromIso(t['date'] as String));
      Navigator.pop(context);
      sc.actions.openCard(context, t['id'] as String);
    }

    return Frame(
      title: 'Поиск задач',
      maxWidth: 560,
      top: Field(
        hint: 'Текст, заметка, подзадача или #метка',
        autofocus: true,
        clearOnSubmit: false,
        onChanged: (v) => setState(() => q = v),
        onSubmit: (_) {
          if (found.isNotEmpty) go(found.first);
        },
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 4),
        Text(
          words.isEmpty
              ? 'Ищу по всем задачам: сегодняшним, будущим и выполненным за 30 дней'
              : 'Найдено: ${found.length}${found.length > 100 ? ' (показаны первые 100)' : ''}',
          style: T.tiny,
        ),
        for (final t in found.take(100))
          InkWell(
            onTap: () => go(t),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(t['done'] == true ? Icons.check_circle : Icons.circle_outlined, size: 14, color: t['done'] == true ? C.ok : C.muted),
                  SizedBox(
                    width: 78,
                    child: Text(' ${fromIso(t['date'] as String) == m.today ? 'сегодня' : futureDateText(fromIso(t['date'] as String), m.today)}',
                        style: T.tiny.copyWith(color: fromIso(t['date'] as String).isBefore(m.today) ? C.faint : C.accent)),
                  ),
                  Expanded(child: Text(t['text'] as String, style: T.small.copyWith(color: t['done'] == true ? C.muted : C.fg))),
                ]),
                if (_snippet(t, words) != null)
                  Padding(padding: const EdgeInsets.only(left: 92), child: Text(_snippet(t, words)!, style: T.tiny.copyWith(color: C.faint))),
              ]),
            ),
          ),
      ]),
    );
  }

  String? _snippet(Json t, List<String> words) {
    final note = '${t['note'] ?? ''}';
    final low = note.toLowerCase();
    final positions = [for (final w in words) if (low.contains(w)) low.indexOf(w)];
    if (positions.isEmpty) return null;
    final pos = positions.reduce((a, b) => a < b ? a : b);
    final start = pos > 25 ? pos - 25 : 0;
    final end = (start + 80).clamp(0, note.length);
    return '${start > 0 ? '…' : ''}${note.substring(start, end).replaceAll('\n', ' ')}…';
  }
}

// ===================== разбор задач =====================

/// Список задач с кнопками «сегодня / завтра / дата / удалить» (утренний разбор, разгрузка дня).
class ReviewDialog extends StatefulWidget {
  const ReviewDialog({super.key, required this.title, required this.hint, required this.keep, this.order, this.keepLabel});
  final String title;
  final String hint;
  final bool Function(Json) keep;
  final int Function(Json, Json)? order;
  final String? keepLabel;

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final kept = <String>{};

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final items = [for (final t in m.tasks) if (widget.keep(t as Json) && !kept.contains(t['id'])) t];
    if (widget.order != null) items.sort(widget.order);
    final tomorrow = addDays(m.today, 1);
    return Frame(
      title: widget.title,
      maxWidth: 600,
      actions: [Btn('Готово', () => Navigator.pop(context), bold: true)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.hint, style: T.small.copyWith(color: C.muted)),
        const SizedBox(height: 8),
        if (items.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Center(child: Text('Всё разобрано ✓', style: T.norm.copyWith(color: C.ok)))),
        for (final t in items)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Container(width: 3, height: 28, margin: const EdgeInsets.only(right: 6), color: prioColor[t['priority']] ?? Colors.transparent),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['text'] as String, style: T.norm),
                  Text(
                    [
                      carriedNote(t, m.today),
                      if (eis.containsKey(t['eis'])) eis[t['eis']]!.$1,
                      if (t['est'] is num) fmtEst((t['est'] as num).round()),
                      deadlineBadge(t, m.today)?.$1,
                    ].whereType<String>().join(', '),
                    style: T.tiny,
                  ),
                ]),
              ),
              if (widget.keepLabel != null) Btn(widget.keepLabel!, () => setState(() => kept.add(t['id'] as String)), color: C.ok),
              Btn('Завтра', () => m.moveTaskDate(t['id'] as String, tomorrow)),
              Btn('Дата…', () => sc.actions.askDate(context, t['id'] as String)),
              Btn('Удалить', () => m.deleteTask(t['id'] as String), color: C.danger),
            ]),
          ),
      ]),
    );
  }
}

// ===================== обзор недели =====================

class WeeklyReview extends StatelessWidget {
  const WeeklyReview({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final start = addDays(m.today, -wd(m.today));
    final end = addDays(start, 6);
    final sIso = iso(start), eIso = iso(end), tIso = iso(m.today);
    final tasks = [for (final t in m.tasks) t as Json];
    final done = tasks.where((t) => t['done'] == true && '${t['done_at'] ?? ''}'.compareTo(sIso) >= 0 && '${t['done_at'] ?? ''}'.compareTo(eIso) <= 0).toList();
    final byDay = [for (var i = 0; i < 7; i++) done.where((t) => t['done_at'] == iso(addDays(start, i))).length];
    final stillOpen = tasks.where((t) => t['done'] != true && (t['date'] as String).compareTo(sIso) >= 0 && (t['date'] as String).compareTo(tIso) <= 0).length;
    var moves = 0;
    for (final t in tasks) {
      for (final e in (t['log'] as List?) ?? const []) {
        final at = '${(e as List)[0]}';
        if (at.length >= 10 && at.substring(0, 10).compareTo(sIso) >= 0 && at.substring(0, 10).compareTo(eIso) <= 0 && '${e[1]}'.contains('перенесена')) moves++;
      }
    }
    int moved(Json t) => ((t['moves'] as num?) ?? 0).toInt() + ((t['carries'] as num?) ?? 0).toInt();
    final chronic = tasks.where((t) => t['done'] != true && moved(t) >= 3).toList()..sort((a, b) => moved(b) - moved(a));
    final pomos = [for (var i = 0; i < 7; i++) ((m.data['pomodoros'] as Json)[iso(addDays(start, i))] as num? ?? 0).toInt()].fold<int>(0, (a, b) => a + b);
    final logs = [for (final x in m.data['pomo_log'] as List) if ('${(x as Json)['date']}'.compareTo(sIso) >= 0 && '${x['date']}'.compareTo(eIso) <= 0) x];
    final minutes = logs.fold<int>(0, (a, x) => a + ((x['min'] as num?) ?? 25).toInt());
    final byTag = <String, int>{};
    for (final x in logs) {
      final tags = [for (final g in (x['tags'] as List?) ?? const []) '$g'];
      for (final g in tags.isEmpty ? ['без метки'] : tags) {
        byTag[g] = (byTag[g] ?? 0) + ((x['min'] as num?) ?? 25).toInt();
      }
    }
    final tagList = byTag.entries.toList()..sort((a, b) => b.value - a.value);
    final goals = m.weekGoals();
    final undone = goals.where((g) => g['done'] != true).toList();
    final ratio = m.estRatio();
    final span = start.month == end.month
        ? '${start.day} – ${end.day} ${monthsGen[end.month - 1]}'
        : '${start.day} ${monthsGen[start.month - 1]} – ${end.day} ${monthsGen[end.month - 1]}';

    return Frame(
      title: 'Обзор недели, $span',
      maxWidth: 560,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('Сделано'),
        Text('Выполнено задач: ${done.length}', style: T.norm.copyWith(color: done.isEmpty ? C.muted : C.ok)),
        Text([for (var i = 0; i < 7; i++) '${wdShort[i].toLowerCase()} ${byDay[i]}'].join('   '), style: T.tiny.copyWith(color: C.faint)),
        if (stillOpen > 0) Text('Не закрыто из запланированного: $stillOpen', style: T.small.copyWith(color: C.warn)),
        const SectionLabel('Переносы'),
        Text('Переносов за неделю: $moves', style: T.small.copyWith(color: C.muted)),
        if (chronic.isNotEmpty) Text('Часто переносятся — разбить, делегировать или отказаться?', style: T.small.copyWith(color: C.warn)),
        for (final t in chronic.take(5))
          InkWell(onTap: () => sc.actions.openCard(context, t['id'] as String), child: Text('  → ${moved(t)}  ${short(t['text'] as String, 50)}', style: T.small)),
        const SectionLabel('Фокус'),
        Text('Помидоров: $pomos${minutes > 0 ? ', ${fmtEst(minutes)} работы' : ''}', style: T.small.copyWith(color: C.accent)),
        for (final e in tagList.take(5))
          Text('  ${e.key == 'без метки' ? e.key : '#${e.key}'}: ${fmtEst(e.value)}', style: T.small.copyWith(color: e.key == 'без метки' ? C.muted : tagColor(e.key))),
        const SectionLabel('Цели недели'),
        if (goals.isEmpty) Text('Целей на неделю не было', style: T.small.copyWith(color: C.faint)),
        for (final g in goals)
          Builder(builder: (_) {
            final (dn, tot) = m.goalProgress(g['id'] as String);
            return Text('${g['done'] == true ? '✓' : '○'} ${short(g['text'] as String, 40)}${tot > 0 ? ', задач $dn/$tot' : ''}',
                style: T.small.copyWith(color: g['done'] == true ? C.ok : C.fg));
          }),
        const SectionLabel('Оценки времени'),
        Text(
          ratio == null
              ? 'Мало данных: нужны хотя бы 3 выполненные задачи с оценкой и помидорами'
              : (ratio - 1).abs() <= 0.15
                  ? 'Оценки точные — фактическое время в пределах ±15%'
                  : 'Задачи занимают в среднем в ${ratio.toStringAsFixed(1).replaceAll('.', ',')} раза ${ratio > 1 ? 'больше' : 'меньше'} оценки',
          style: T.small.copyWith(color: ratio == null ? C.faint : ((ratio - 1).abs() <= 0.15 ? C.ok : C.warn)),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [
          Btn('Спланировать следующую неделю', () {
            Navigator.pop(context);
            sc.actions.openWeek(context, start: addDays(start, 7));
          }, bold: true),
          if (undone.isNotEmpty)
            Btn('Перенести незавершённые цели (${undone.length})', () {
              m.moveGoals(undone, addDays(start, 7));
              Navigator.pop(context);
            }, color: C.muted),
        ]),
      ]),
    );
  }
}

// ===================== повтор =====================

class RepeatDialog extends StatefulWidget {
  const RepeatDialog({super.key, required this.id});
  final String id;
  @override
  State<RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<RepeatDialog> {
  String mode = 'days';
  int nDays = 2, nWeeks = 2, mday = 1, wdW = 0, wdM = 0, ord = 0;
  bool inited = false;

  void _init(PanelModel m) {
    final t = m.findTask(widget.id)!;
    final d = fromIso(t['date'] as String);
    mday = d.day;
    wdW = wdM = wd(d);
    ord = ((d.day - 1) ~/ 7).clamp(0, 3);
    final cur = m.ruleOf(t) ?? '';
    try {
      if (cur.startsWith('d')) {
        mode = 'days';
        nDays = int.parse(cur.substring(1));
      } else if (cur.startsWith('W')) {
        final p = cur.substring(1).split(':');
        mode = 'weeks';
        nWeeks = int.parse(p[0]);
        wdW = int.parse(p[1]);
      } else if (cur.startsWith('mL')) {
        mode = 'monthwd';
        ord = 4;
        wdM = int.parse(cur.substring(2));
      } else if (cur.startsWith('m') && cur.contains(':')) {
        final p = cur.substring(1).split(':');
        mode = 'monthwd';
        ord = int.parse(p[0]) - 1;
        wdM = int.parse(p[1]);
      } else if (cur.startsWith('m')) {
        mode = 'monthday';
        mday = int.parse(cur.substring(1));
      } else if (cur.startsWith('w')) {
        mode = 'weeks';
        nWeeks = 1;
        wdW = int.parse(cur.substring(1));
      }
    } on FormatException {
      mode = 'days';
    }
    inited = true;
  }

  String get rule => switch (mode) {
        'days' => nDays == 1 ? 'daily' : 'd$nDays',
        'weeks' => nWeeks == 1 ? 'w$wdW' : 'W$nWeeks:$wdW',
        'monthday' => 'm$mday',
        _ => ord == 4 ? 'mL$wdM' : 'm${ord + 1}:$wdM',
      };

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final t = m.findTask(widget.id);
    if (t == null) return const SizedBox.shrink();
    if (!inited) _init(m);
    Widget num(int v, int lo, int hi, void Function(int) set) => SizedBox(
          width: 70,
          child: DropdownButton<int>(
            value: v.clamp(lo, hi),
            isDense: true,
            dropdownColor: C.card,
            items: [for (var i = lo; i <= hi; i++) DropdownMenuItem(value: i, child: Text('$i', style: T.small))],
            onChanged: (x) => setState(() => set(x!)),
          ),
        );
    Widget wdPick(int v, void Function(int) set) => DropdownButton<int>(
          value: v,
          isDense: true,
          dropdownColor: C.card,
          items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(weekdays[i], style: T.small))],
          onChanged: (x) => setState(() => set(x!)),
        );
    Widget radio(String value, List<Widget> row) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            InkWell(
              onTap: () => setState(() => mode = value),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(mode == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16, color: mode == value ? C.accent : C.muted),
              ),
            ),
            ...row,
          ]),
        );
    return AlertDialog(
      backgroundColor: C.bg,
      title: Text('Повтор: «${short(t['text'] as String, 36)}»', style: T.title.copyWith(fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        radio('days', [Text('Каждые ', style: T.small), num(nDays, 1, 365, (x) => nDays = x), Text(' дн.', style: T.small)]),
        radio('weeks', [Text('Каждые ', style: T.small), num(nWeeks, 1, 52, (x) => nWeeks = x), Text(' нед., в ', style: T.small), wdPick(wdW, (x) => wdW = x)]),
        radio('monthday', [Text('Каждый месяц, ', style: T.small), num(mday, 1, 31, (x) => mday = x), Text('-го числа', style: T.small)]),
        radio('monthwd', [
          Text('Каждый месяц, в ', style: T.small),
          DropdownButton<int>(
            value: ord,
            isDense: true,
            dropdownColor: C.card,
            items: [for (var i = 0; i < 5; i++) DropdownMenuItem(value: i, child: Text(ordLabels[i], style: T.small))],
            onChanged: (x) => setState(() => ord = x!),
          ),
          const SizedBox(width: 6),
          wdPick(wdM, (x) => wdM = x),
        ]),
        const SizedBox(height: 8),
        Text('↻ ${ruleText(rule)}', style: T.small.copyWith(color: C.rest)),
      ]),
      actions: [
        Btn('Отмена', () => Navigator.pop(context), color: C.muted, size: 13),
        Btn('Сохранить', () {
          m.setRepeat(widget.id, rule);
          Navigator.pop(context);
        }, size: 13, bold: true),
      ],
    );
  }
}

// ===================== шаблоны =====================

/// Меню шаблонов: применить к выбранному дню, сохранить день, удалить.
List<PopupMenuEntry<VoidCallback>> templateMenu(BuildContext context) {
  final sc = Scope.of(context);
  final m = sc.m;
  final day = dayLong(m.selected);
  return [
    if (m.templates.isEmpty) const PopupMenuItem(enabled: false, child: Text('Шаблонов пока нет')),
    for (final tpl in m.templates)
      PopupMenuItem(
        value: () => m.applyTemplate(tpl['id'] as String),
        child: Text('Добавить на $day: ${tpl['name']} (${(tpl['items'] as List).length})'),
      ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: () {
        final items = m.dayTemplateItems();
        if (items.isEmpty) {
          m.flash('В выбранном дне нет задач', 'muted');
          return;
        }
        sc.actions.askTemplateName(context, items, 'День ${wdShort[wd(m.selected)].toLowerCase()}');
      },
      child: const Text('Сохранить выбранный день как шаблон…'),
    ),
    for (final tpl in m.templates)
      PopupMenuItem(
        value: () => m.deleteTemplate(tpl['id'] as String),
        child: Text('Удалить шаблон «${tpl['name']}»', style: const TextStyle(color: C.danger)),
      ),
  ];
}
