import 'dart:async';

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Карточка задачи: всё о задаче в одном окне, разделы сворачиваются, содержимое прокручивается.
class TaskCard extends StatefulWidget {
  const TaskCard({super.key, required this.id});
  final String id;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  final title = TextEditingController();
  final titleFocus = FocusNode();
  final note = TextEditingController();
  Timer? _noteTimer;
  PanelModel? _m;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_m == null) {
      _m = Scope.of(context).m;
      final t = _m!.findTask(widget.id);
      title.text = '${t?['text'] ?? ''}';
      note.text = '${t?['note'] ?? ''}';
      titleFocus.addListener(() {
        if (!titleFocus.hasFocus) _saveTitle();
      });
    }
  }

  void _saveTitle() => _m?.setTitle(widget.id, title.text);

  @override
  void dispose() {
    // сохраняем после закрытия окна: во время разборки дерева виджетов перерисовка запрещена
    final m = _m, id = widget.id, titleText = title.text, noteText = note.text;
    final notePending = _noteTimer?.isActive == true;
    _noteTimer?.cancel();
    Future.microtask(() {
      if (m == null) return;
      if (notePending) m.setNote(id, noteText);
      m.setTitle(id, titleText);
    });
    title.dispose();
    note.dispose();
    titleFocus.dispose();
    super.dispose();
  }

  bool _closed(String key) => ((_m!.s['card_collapsed'] as List?) ?? const []).contains(key);

  void _toggle(String key) {
    final list = (_m!.s['card_collapsed'] as List?) ?? [];
    if (list.contains(key)) {
      list.remove(key);
    } else {
      list.add(key);
    }
    _m!.setSetting('card_collapsed', list);
  }

  Widget section(String key, String label, Widget body) {
    final closed = _closed(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => _toggle(key),
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(children: [
            Icon(closed ? Icons.chevron_right : Icons.expand_more, size: 16, color: C.muted),
            const SizedBox(width: 2),
            Text(label, style: T.tiny),
          ]),
        ),
      ),
      if (!closed) body,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final a = sc.actions;
    final id = widget.id;
    final t = m.findTask(id);
    if (t == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final done = t['done'] == true;
    final d = fromIso(t['date'] as String);
    final today = m.today;
    final monday = addDays(today, 7 - wd(today));
    final rule = m.ruleOf(t);
    final w = wd(d);
    final est = (t['est'] as num?)?.round();
    final spent = (t['spent'] as num?)?.round();
    final ratio = m.estRatio();
    final carried = carriedNote(t, today);
    final goals = m.weekGoals(d);
    final subs = [for (final x in (t['subs'] as List?) ?? const []) x as Json];
    final moves = ((t['moves'] as num?) ?? 0).toInt(), carries = ((t['carries'] as num?) ?? 0).toInt();
    final linked = m.s['pomo_task'] == id;
    final other = linked ? null : m.findTask(m.s['pomo_task'] as String?);

    return Dialog(
      backgroundColor: C.bg,
      insetPadding: const EdgeInsets.all(10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 760),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: title,
                  focusNode: titleFocus,
                  style: T.title.copyWith(fontSize: 16),
                  onSubmitted: (_) => _saveTitle(),
                  decoration: const InputDecoration(filled: false, border: InputBorder.none, enabledBorder: InputBorder.none),
                ),
              ),
              IconBtn(Icons.close, 'Закрыть (Esc)', () => Navigator.pop(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Pill(done ? '✓ Выполнена' : 'Не выполнена', done, () => m.toggleTask(id), color: C.ok),
              if (carried != null && !done) Text(carried, style: T.tiny.copyWith(color: C.warn, fontStyle: FontStyle.italic)),
            ]),
          ),
          Flexible(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  section('when', 'Когда', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dateTitle(d, today), style: T.norm),
                    const SizedBox(height: 4),
                    Wrap(children: [
                      for (final (label, day) in [
                        ('Сегодня', today),
                        ('Завтра', addDays(today, 1)),
                        ('Пн', monday),
                        ('+неделя', addDays(d, 7)),
                      ])
                        Pill(label, day == d, () => m.moveTaskDate(id, day)),
                      Pill('Дата…', false, () => a.askDate(context, id)),
                    ]),
                    Wrap(children: [
                      Pill(t['time'] != null ? 'Время: ${t['time']}' : 'Время…', t['time'] != null, () => a.askTime(context, id)),
                      for (final (label, value) in [('Без повтора', null), ('Каждый день', 'daily'), ('По будням', 'weekdays'), ('Каждую неделю', 'w$w')])
                        Pill(label, rule == value, () => m.setRepeat(id, value), color: C.rest),
                      if (rule != null && !basicRules.contains(rule) && rule != 'w$w')
                        Pill('↻ ${ruleText(rule)}', true, () => a.askRepeat(context, id), color: C.rest)
                      else
                        Pill('Другое…', false, () => a.askRepeat(context, id), color: C.rest),
                    ]),
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (t['deadline'] != null) ...[
                        Pill('Дедлайн: ${wdShort[wd(fromIso(t['deadline'] as String))].toLowerCase()}, ${dayLong(fromIso(t['deadline'] as String))}',
                            true, () => a.askDeadline(context, id), color: levelColor(deadlineBadge(t, today)!.$2)),
                        Pill('Убрать', false, () => m.setDeadline(id, null), color: C.danger),
                      ] else
                        Pill('Дедлайн…', false, () => a.askDeadline(context, id), color: C.danger),
                    ]),
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Padding(padding: const EdgeInsets.only(right: 4, bottom: 4), child: Text('Оценка:', style: T.small.copyWith(color: C.muted))),
                      for (final (mins, label) in const [(null, '—'), (15, '15 мин'), (30, '30 мин'), (60, '1 ч'), (120, '2 ч'), (240, '4 ч')])
                        Pill(label, est == mins, () => m.setEst(id, mins)),
                      if (est != null && ![15, 30, 60, 120, 240].contains(est)) Pill(fmtEst(est), true, () => a.askEst(context, id)),
                      Pill('Другое…', false, () => a.askEst(context, id)),
                    ]),
                  ])),
                  section('prio', 'Приоритет', Wrap(children: [
                    for (final p in priorities)
                      Pill(p.$2, t['priority'] == p.$1, () => m.setField(id, 'priority', p.$1), color: prioColor[p.$1] ?? C.faint),
                  ])),
                  section('eis', 'Матрица Эйзенхауэра', _matrix(m, t)),
                  section('tags', 'Метки', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(children: [
                      for (final g in (t['tags'] as List?) ?? const [])
                        Pill('#$g  ×', true, () => m.removeTag(id, '$g'), color: tagColor('$g')),
                    ]),
                    Field(
                      hint: '#метка и Enter (можно несколько)',
                      style: T.small,
                      onSubmit: (v) {
                        final tags = v.replaceAll(',', ' ').split(RegExp(r'\s+')).map((x) => x.replaceAll('#', '').toLowerCase()).where((x) => x.isNotEmpty).toList();
                        if (tags.isNotEmpty) m.addTags(id, tags);
                      },
                    ),
                  ])),
                  section('goal', 'Цель недели', goals.isEmpty
                      ? Text('На эту неделю целей нет — их задают в блоке «Цели недели»', style: T.tiny.copyWith(color: C.faint))
                      : Wrap(children: [
                          Pill('Нет', t['goal'] == null, () => m.setField(id, 'goal', null), color: C.rest),
                          for (final g in goals)
                            Pill(short(g['text'] as String, 22), t['goal'] == g['id'], () => m.setField(id, 'goal', g['id']), color: C.rest),
                        ])),
                  section('pomo', 'Помодоро', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (linked)
                      ValueListenableBuilder(
                        valueListenable: m.clock,
                        builder: (_, __, ___) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8, bottom: 4),
                            child: Text('${m.pomoModeName}  ${m.pomoClock}', style: T.title.copyWith(color: m.pomoMode == 'work' ? C.accent : C.rest)),
                          ),
                          Pill(m.pomoRunning ? 'Пауза' : '▶ Продолжить', false, m.pomoToggle),
                          Pill('Сброс', false, m.pomoReset),
                          Pill('Отвязать', false, () => m.linkPomo(null)),
                        ]),
                      )
                    else
                      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Pill('▶ Запустить помодоро', false, () => m.linkPomo(id)),
                        if (other != null) Text('сейчас идёт: ${short(other['text'] as String, 22)}', style: T.tiny.copyWith(color: C.faint)),
                      ]),
                    if (t['pomos'] is num) Text('Помидоров по задаче: ${t['pomos']}', style: T.tiny),
                    if (spent != null)
                      Text('По факту: ${fmtEst(spent)}${est != null ? ' из оценки ${fmtEst(est)}' : ''}',
                          style: T.tiny.copyWith(color: est != null && spent > est ? C.warn : C.muted)),
                    if (est != null && ratio != null && (ratio - 1).abs() > 0.15)
                      Text('С поправкой на ваш опыт (×${ratio.toStringAsFixed(1).replaceAll('.', ',')}) ≈ ${fmtEst((est * ratio).round())}',
                          style: T.tiny.copyWith(color: C.faint)),
                  ])),
                  section('subs', 'Подзадачи', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final sb in subs)
                      InkWell(
                        onTap: () => m.toggleSub(id, sb['id'] as String),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(sb['done'] == true ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: sb['done'] == true ? C.ok : C.muted),
                            const SizedBox(width: 6),
                            Expanded(child: Text(sb['text'] as String, style: T.small.copyWith(color: sb['done'] == true ? C.muted : C.fg))),
                            IconBtn(Icons.close, 'Удалить подзадачу', () => m.deleteSub(id, sb['id'] as String), color: C.faint, size: 12),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Field(
                      hint: 'Подзадача и Enter',
                      style: T.small,
                      onSubmit: (v) => m.addSubtasks(id, [v]),
                      onPasteLines: (l) => m.addSubtasks(id, l),
                    ),
                  ])),
                  section('note', 'Заметка (ссылки и пути к файлам можно открыть)', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: note,
                      minLines: 4,
                      maxLines: 12,
                      style: T.small,
                      onChanged: (_) {
                        setState(() {});
                        _noteTimer?.cancel();
                        _noteTimer = Timer(const Duration(milliseconds: 700), () => m.setNote(id, note.text));
                      },
                    ),
                    Wrap(spacing: 8, children: [
                      for (final l in linkRe.allMatches(note.text).map((x) => x[0]!).toSet())
                        InkWell(
                          onTap: () => a.openTarget(l),
                          child: Text(short(l.replaceAll('"', ''), 44),
                              style: T.tiny.copyWith(color: C.accent, decoration: TextDecoration.underline, decorationColor: C.accent)),
                        ),
                    ]),
                  ])),
                  section('hist', 'История', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_created(t), style: T.tiny),
                    if (moves + carries > 0)
                      Text(
                        'Переносилась ${plural(moves + carries, 'раз', 'раза', 'раз')}: вручную $moves, автоматически $carries'
                        '${moves + carries >= 3 ? '. Может, разбить задачу или отказаться от неё?' : ''}',
                        style: T.tiny.copyWith(color: moves + carries >= 3 ? C.warn : C.muted),
                      ),
                    if (done && t['done_at'] != null) Text('Выполнена: ${_dmy(t['done_at'] as String)}', style: T.tiny.copyWith(color: C.ok)),
                    for (final e in ((t['log'] as List?) ?? const []).reversed.take(6))
                      Text('${_logAt('${(e as List)[0]}')}  ${e[1]}', style: T.tiny.copyWith(color: C.faint)),
                  ])),
                ]),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              Btn('Удалить', () {
                Navigator.pop(context);
                m.deleteTask(id);
              }, color: C.danger),
              Btn('В шаблон…', () => a.askTemplateName(context, [m.templateItem(t, d)], short(t['text'] as String, 30)), color: C.muted),
              const Spacer(),
              Btn('Закрыть', () => Navigator.pop(context), bold: true),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _matrix(PanelModel m, Json t) {
    final id = t['id'] as String;
    Widget cell(String q) {
      final sel = t['eis'] == q;
      final color = eisColor[q]!;
      return Expanded(
        child: InkWell(
          onTap: () => m.setField(id, 'eis', sel ? null : q),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: mix(C.card, color, sel ? 0.55 : 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: sel ? color : Colors.transparent),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eis[q]!.$1, style: T.small.copyWith(color: sel ? C.fg : C.muted, fontWeight: sel ? FontWeight.w600 : null)),
              Text(eis[q]!.$2, style: T.tiny.copyWith(fontSize: 10)),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [cell('q1'), cell('q2')]),
      Row(children: [cell('q3'), cell('q4')]),
      Text(t['eis'] == null ? 'Щёлкните квадрант. Повторный щелчок снимает отметку.' : 'Сейчас: ${eis[t['eis']]!.$1.toLowerCase()} (${eis[t['eis']]!.$2})',
          style: T.tiny.copyWith(color: C.faint)),
    ]);
  }

  static String _dmy(String isoDate) => '${isoDate.substring(8, 10)}.${isoDate.substring(5, 7)}.${isoDate.substring(0, 4)}';

  static String _logAt(String at) => at.length >= 16 ? '${at.substring(8, 10)}.${at.substring(5, 7)} ${at.substring(11, 16)}' : at;

  static String _created(Json t) {
    final c = '${t['created'] ?? ''}';
    if (c.length < 16) return 'Создана: до появления истории';
    return 'Создана: ${_dmy(c.substring(0, 10))} ${c.substring(11, 16)}';
  }
}
