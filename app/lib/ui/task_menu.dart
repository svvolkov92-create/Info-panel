import 'package:flutter/material.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'scope.dart';
import 'theme.dart';

/// Правый клик по задаче — меню как в Python-версии (task_menu).
class TaskMenu extends StatefulWidget {
  const TaskMenu({super.key, required this.id, required this.child, this.onEdit, this.onSubs});
  final String id;
  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onSubs;

  @override
  State<TaskMenu> createState() => _TaskMenuState();
}

class _TaskMenuState extends State<TaskMenu> {
  final ctl = MenuController();
  bool built = false; // пункты меню строим только после первого открытия

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: ctl,
      style: const MenuStyle(backgroundColor: WidgetStatePropertyAll(C.card)),
      menuChildren: built ? taskMenuItems(context, widget.id, onEdit: widget.onEdit, onSubs: widget.onSubs) : const [],
      child: GestureDetector(
        onSecondaryTapDown: (d) {
          setState(() => built = true);
          WidgetsBinding.instance.addPostFrameCallback((_) => ctl.open(position: d.localPosition));
        },
        child: widget.child,
      ),
    );
  }
}

Widget _item(String label, VoidCallback? onTap, {Color color = C.fg, bool checked = false}) => MenuItemButton(
      onPressed: onTap,
      leadingIcon: checked ? const Icon(Icons.check, size: 14, color: C.accent) : const SizedBox(width: 14),
      child: Text(label, style: TextStyle(fontSize: 13, color: onTap == null ? C.faint : color)),
    );

Widget _sub(String label, List<Widget> children) => SubmenuButton(
      menuChildren: children,
      leadingIcon: const SizedBox(width: 14),
      child: Text(label, style: const TextStyle(fontSize: 13, color: C.fg)),
    );

List<Widget> taskMenuItems(BuildContext context, String id, {VoidCallback? onEdit, VoidCallback? onSubs}) {
  final sc = Scope.of(context);
  final m = sc.m, a = sc.actions;
  final t = m.findTask(id);
  if (t == null) return const [];
  final d = fromIso(t['date'] as String);
  final today = m.today;
  final tomorrow = addDays(today, 1);
  final monday = addDays(today, 7 - wd(today));
  final rule = m.ruleOf(t);
  final w = wd(d);
  final goals = m.weekGoals(d);
  return [
    _item('Открыть карточку…', () => a.openCard(context, id)),
    if (onEdit != null) _item('Изменить текст', onEdit),
    if (onSubs != null) _item('Добавить подзадачу', onSubs),
    const Divider(height: 6),
    if (d != today) _item('Перенести на сегодня', () => m.moveTaskDate(id, today)),
    if (d != tomorrow) _item('Перенести на завтра', () => m.moveTaskDate(id, tomorrow)),
    _item('Перенести на понедельник, ${dayLong(monday)}', () => m.moveTaskDate(id, monday)),
    _item('Перенести на дату…', () => a.askDate(context, id)),
    const Divider(height: 6),
    _sub('Приоритет', [
      for (final p in priorities) _item(p.$2, () => m.setField(id, 'priority', p.$1), checked: t['priority'] == p.$1),
    ]),
    _sub('Матрица Эйзенхауэра', [
      _item('Не задано', () => m.setField(id, 'eis', null), checked: t['eis'] == null),
      for (final e in eis.entries)
        _item('${e.value.$1} (${e.value.$2})', () => m.setField(id, 'eis', e.key), checked: t['eis'] == e.key),
    ]),
    _item(t['time'] == null ? 'Время и напоминание…' : 'Время: ${t['time']}…', () => a.askTime(context, id)),
    _item(t['deadline'] == null ? 'Дедлайн…' : 'Дедлайн: ${shortDate(fromIso(t['deadline'] as String), today)}…',
        () => a.askDeadline(context, id)),
    _item(t['est'] == null ? 'Оценка времени…' : 'Оценка: ${fmtEst((t['est'] as num).round())}…', () => a.askEst(context, id)),
    _sub('Повторять', [
      _item('Не повторять', () => m.setRepeat(id, null), checked: rule == null),
      _item('Каждый день', () => m.setRepeat(id, 'daily'), checked: rule == 'daily'),
      _item('По будням', () => m.setRepeat(id, 'weekdays'), checked: rule == 'weekdays'),
      _item('Каждую неделю (в ${wdAcc[w]})', () => m.setRepeat(id, 'w$w'), checked: rule == 'w$w'),
      if (rule != null && !basicRules.contains(rule) && rule != 'w$w')
        _item('↻ ${ruleText(rule)}', () => a.askRepeat(context, id), checked: true),
      _item('Другое правило…', () => a.askRepeat(context, id)),
    ]),
    if (goals.isNotEmpty)
      _sub('Цель недели', [
        _item('Нет', () => m.setField(id, 'goal', null), checked: t['goal'] == null),
        for (final g in goals)
          _item(short(g['text'] as String, 40), () => m.setField(id, 'goal', g['id']), checked: t['goal'] == g['id']),
      ]),
    if (m.s['pomo_task'] == id)
      _item('Отвязать от помодоро', () => m.linkPomo(null))
    else
      _item('Работать над ней (помодоро)', () => m.linkPomo(id)),
    _item('Сохранить как шаблон…',
        () => a.askTemplateName(context, [m.templateItem(t, d)], short(t['text'] as String, 30))),
    const Divider(height: 6),
    _item('Удалить', () => m.deleteTask(id), color: C.danger),
  ];
}

/// Значки задачи для подсказок и списков: время, текст, приоритет.
String taskLine(Json t) => '${t['time'] != null ? '${t['time']} ' : ''}${t['text']}';
