import 'package:flutter/material.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'scope.dart';
import 'task_menu.dart';
import 'theme.dart';
import 'widgets.dart';
import 'windows.dart';

/// Разделы GTD: ключ, название, значок.
const gtdViews = [
  ('inbox', 'Входящие', Icons.inbox_outlined),
  ('process', 'Разбор', Icons.call_split),
  ('next', 'Следующие действия', Icons.play_arrow_outlined),
  ('projects', 'Проекты', Icons.folder_outlined),
  ('waiting', 'Жду', Icons.hourglass_empty),
  ('someday', 'Когда-нибудь', Icons.cloud_outlined),
  ('review', 'Еженедельный обзор', Icons.checklist),
];

int? gtdCount(PanelModel m, String view) => switch (view) {
      'inbox' || 'process' => m.inboxCount,
      'next' || 'waiting' || 'someday' => m.gtdList(view).length,
      'projects' => m.projectsBy('active').length,
      _ => null,
    };

/// Левая колонка режима окна: панель и разделы GTD.
class GtdRail extends StatelessWidget {
  const GtdRail({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    Widget item(String key, String label, IconData icon, {int? count, Color? countColor}) {
      final sel = m.gtdView == key;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: InkWell(
          onTap: () => m.setGtdView(key),
          borderRadius: BorderRadius.circular(6),
          hoverColor: C.hover,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: sel ? C.selected : null, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Icon(icon, size: 15, color: sel ? C.accent : C.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: T.small.copyWith(color: sel ? C.fg : C.muted), overflow: TextOverflow.ellipsis)),
              if (count != null && count > 0) Text('$count', style: T.tiny.copyWith(color: countColor ?? C.muted)),
            ]),
          ),
        ),
      );
    }

    final stuck = m.projectsBy('active').where((p) => m.projectStuck(p['id'] as String)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      item('panel', 'Панель', Icons.dashboard_outlined),
      const SizedBox(height: 6),
      for (final (key, label, icon) in gtdViews)
        item(key, label, icon,
            count: key == 'process' ? null : gtdCount(m, key),
            countColor: key == 'inbox' ? C.accent : (key == 'projects' && stuck > 0 ? C.warn : null)),
      if (m.s['gtd_review_week'] != weekKey(m.today) && m.today.weekday >= 5)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
          child: Text('Обзор этой недели ещё не сделан', style: T.tiny.copyWith(color: C.warn)),
        ),
    ]);
  }
}

/// Окно GTD для режима виджета: вкладки сверху, содержимое раздела ниже.
class GtdWindow extends StatefulWidget {
  const GtdWindow({super.key, this.view = 'inbox'});
  final String view;

  @override
  State<GtdWindow> createState() => _GtdWindowState();
}

class _GtdWindowState extends State<GtdWindow> {
  late String view = widget.view;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    return Frame(
      title: 'GTD',
      maxWidth: 680,
      top: Wrap(children: [
        for (final (key, label, _) in gtdViews)
          Pill('$label${(gtdCount(m, key) ?? 0) > 0 && key != 'process' ? ' ${gtdCount(m, key)}' : ''}', view == key,
              () => setState(() => view = key)),
      ]),
      child: GtdView(view: view, onGo: (v) => setState(() => view = v), inWindow: true),
    );
  }
}

/// Содержимое раздела GTD.
class GtdView extends StatelessWidget {
  const GtdView({super.key, required this.view, required this.onGo, this.inWindow = false});
  final String view;
  final void Function(String) onGo;
  final bool inWindow;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      'inbox' => _Inbox(onGo: onGo),
      'process' => _Process(onGo: onGo),
      'next' => const _Next(),
      'projects' => const _Projects(),
      'waiting' => const _Waiting(),
      'someday' => const _Someday(),
      'review' => _Review(onGo: onGo, inWindow: inWindow),
      _ => const SizedBox.shrink(),
    };
  }
}

// ===================== общие части =====================

Widget _title(String text, String hint) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: T.title.copyWith(fontSize: 15)),
        const SizedBox(height: 2),
        Text(hint, style: T.tiny),
      ]),
    );

Widget _empty(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text, style: T.small.copyWith(color: C.faint)),
    );

Future<void> askDelegate(BuildContext context, String id) {
  final m = Scope.of(context).m;
  final t = m.findTask(id);
  return inputDialog(context, 'Поручить', '«${short('${t?['text']}', 40)}»\nКому поручено? Задача уйдёт в список «Жду».',
      [('Кто', '${t?['waiting_for'] ?? ''}')], (v) {
    if (v[0].isEmpty) return 'Напишите, кому поручено';
    m.delegate(id, v[0]);
    return null;
  }, okText: 'Поручить');
}

Future<void> askProject(BuildContext context, {String? fromTask}) {
  final m = Scope.of(context).m;
  final t = m.findTask(fromTask);
  return inputDialog(context, 'Новый проект', 'Проект — результат, для которого нужно больше одного шага.',
      [('Название', '${t?['text'] ?? ''}')], (v) {
    if (v[0].isEmpty) return 'Напишите название проекта';
    if (fromTask != null) {
      final pid = m.taskToProject(fromTask);
      m.renameProject(pid, v[0]);
    } else {
      m.addProject(v[0]);
    }
    return null;
  }, okText: 'Создать');
}

/// Строка задачи в списках GTD: отметка, текст, контексты, проект, кнопки справа.
class GtdRow extends StatelessWidget {
  const GtdRow({super.key, required this.t, this.actions = const [], this.extra});
  final Json t;
  final List<Widget> actions;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final id = t['id'] as String;
    final done = t['done'] == true;
    final project = m.findProject(t['project']);
    final tags = [for (final g in (t['tags'] as List?) ?? const []) '$g'];
    final dated = t['date'] is String;
    return TaskMenu(
      id: id,
      child: InkWell(
        onTap: () => sc.actions.openCard(context, id),
        hoverColor: C.hover,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: () => m.toggleTask(id),
              child: Padding(
                padding: const EdgeInsets.only(top: 1, right: 6),
                child: Icon(done ? Icons.check_circle : Icons.circle_outlined, size: 15, color: done ? C.ok : C.muted),
              ),
            ),
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                Text(t['text'] as String,
                    style: T.norm.copyWith(color: done ? C.muted : C.fg, decoration: done ? TextDecoration.lineThrough : null)),
                for (final g in tags) Text(tagLabel(g), style: T.tiny.copyWith(color: tagColor(g))),
                if (project != null) Text('▪ ${short(project['title'] as String, 28)}', style: T.tiny.copyWith(color: C.rest)),
                if (t['est'] is num) Text(fmtEst((t['est'] as num).round()), style: T.tiny),
                if (dated) Text(futureDateText(fromIso(t['date'] as String), m.today), style: T.tiny.copyWith(color: C.accent)),
                if (extra != null) Text(extra!, style: T.tiny.copyWith(color: C.warn)),
              ]),
            ),
            ...actions,
          ]),
        ),
      ),
    );
  }
}

// ===================== входящие =====================

class _Inbox extends StatelessWidget {
  const _Inbox({required this.onGo});
  final void Function(String) onGo;

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final items = m.gtdList('inbox');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Входящие', 'Всё, что пришло в голову, — сюда без раздумий. Дата не нужна: решите потом, при разборе.'),
      Field(
        hint: 'Мысль, дело, идея — и Enter',
        onSubmit: (v) {
          if (v.trim().isNotEmpty) m.addInbox(v);
        },
        onPasteLines: m.addInboxLines,
      ),
      const SizedBox(height: 8),
      if (items.isEmpty)
        _empty('Входящие пусты — голова свободна.')
      else ...[
        Row(children: [
          Expanded(child: Text(plural(items.length, 'запись', 'записи', 'записей'), style: T.tiny)),
          Btn('Разобрать по одной', () => onGo('process'), bold: true),
        ]),
        for (final t in items)
          GtdRow(t: t, actions: [
            Btn('Сегодня', () => m.moveTaskDate(t['id'] as String, m.today), size: 11, pad: 4),
            Btn('Следующее', () => m.setList(t['id'] as String, 'next'), size: 11, pad: 4),
            IconBtn(Icons.delete_outline, 'Удалить', () => m.deleteTask(t['id'] as String), size: 14),
          ]),
      ],
    ]);
  }
}

// ===================== разбор по одной =====================

class _Process extends StatefulWidget {
  const _Process({required this.onGo});
  final void Function(String) onGo;

  @override
  State<_Process> createState() => _ProcessState();
}

class _ProcessState extends State<_Process> {
  final skipped = <String>{};

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m, a = sc.actions;
    final items = m.gtdList('inbox');
    final rest = items.where((t) => !skipped.contains(t['id'])).toList();
    if (rest.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('Разбор входящих', 'По одной записи: решите, что это и куда.'),
        _empty(items.isEmpty ? 'Разбирать нечего — входящие пусты.' : 'Остались только пропущенные записи.'),
        Wrap(children: [
          if (skipped.isNotEmpty) Btn('Пройти пропущенные ещё раз', () => setState(skipped.clear)),
          Btn('К следующим действиям', () => widget.onGo('next')),
        ]),
      ]);
    }
    final t = rest.first;
    final id = t['id'] as String;
    final contexts = m.contexts();
    final tags = [for (final g in (t['tags'] as List?) ?? const []) '$g'];

    Widget step(String question, List<Widget> buttons) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(question, style: T.small.copyWith(color: C.muted)),
            const SizedBox(height: 3),
            Wrap(children: buttons),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Разбор входящих', 'Осталось ${rest.length}. Решение по записи принимается один раз — потом она уходит из входящих.'),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => a.openCard(context, id),
            child: Text(t['text'] as String, style: T.title.copyWith(fontSize: 16)),
          ),
          if (t['created'] != null) Text('записано ${t['created']}', style: T.tiny.copyWith(color: C.faint)),
          step('Где это делать? Отметьте до решения (необязательно)', [
            for (final c in contexts) Pill(c, tags.contains(c), () => m.toggleContext(id, c), color: tagColor(c)),
          ]),
          step('Нужно что-то делать?', [
            Pill('Нет — удалить', false, () => m.deleteTask(id), color: C.danger),
            Pill('Когда-нибудь, может быть', false, () => m.setList(id, 'someday'), color: C.rest),
          ]),
          step('Займёт меньше двух минут?', [
            Pill('Сделал сразу ✓', false, () => m.toggleTask(id), color: C.ok),
          ]),
          step('Сделает кто-то другой?', [
            Pill('Поручить…', false, () => askDelegate(context, id), color: C.warn),
          ]),
          step('Делаю сам — когда?', [
            Pill('Сегодня', false, () => m.moveTaskDate(id, m.today)),
            Pill('Завтра', false, () => m.moveTaskDate(id, addDays(m.today, 1))),
            Pill('Дата…', false, () => a.askDate(context, id)),
            Pill('Как только смогу → следующие действия', false, () => m.setList(id, 'next')),
          ]),
          step('Это несколько шагов?', [
            Pill('Сделать проектом…', false, () => askProject(context, fromTask: id), color: C.rest),
            for (final p in m.projectsBy('active').take(6))
              Pill('шаг проекта «${short(p['title'] as String, 18)}»', false, () {
                m.setField(id, 'project', p['id']);
                m.setList(id, 'next');
              }, color: C.rest),
          ]),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: Btn('Пропустить', () => setState(() => skipped.add(id)), color: C.muted)),
        ]),
      ),
    ]);
  }
}

// ===================== следующие действия =====================

class _Next extends StatefulWidget {
  const _Next();

  @override
  State<_Next> createState() => _NextState();
}

class _NextState extends State<_Next> {
  String? ctx;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final items = m.gtdList('next');
    String ctxOf(Json t) =>
        [for (final g in (t['tags'] as List?) ?? const []) '$g'].firstWhere((g) => g.startsWith('@'), orElse: () => 'без контекста');
    final groups = <String, List<Json>>{};
    for (final t in items) {
      (groups[ctxOf(t)] ??= []).add(t);
    }
    final keys = groups.keys.toList()..sort((a, b) => a == 'без контекста' ? 1 : (b == 'без контекста' ? -1 : a.compareTo(b)));
    final shown = ctx == null ? keys : keys.where((k) => k == ctx).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Следующие действия', 'Дела без даты: берите отсюда, когда есть время и вы в нужном месте. Контекст — «@телефон» в тексте.'),
      Field(
        hint: 'Действие @контекст и Enter',
        onSubmit: (v) {
          if (v.trim().isEmpty) return;
          final t = m.addInbox(v);
          m.setList(t['id'] as String, 'next');
        },
      ),
      const SizedBox(height: 6),
      if (keys.length > 1)
        Wrap(children: [
          Pill('Все ${items.length}', ctx == null, () => setState(() => ctx = null)),
          for (final k in keys) Pill('$k ${groups[k]!.length}', ctx == k, () => setState(() => ctx = ctx == k ? null : k), color: tagColor(k)),
        ]),
      if (items.isEmpty) _empty('Пока пусто. Сюда попадают дела из разбора входящих и шаги проектов без даты.'),
      for (final k in shown) ...[
        SectionLabel(k),
        for (final t in groups[k]!)
          GtdRow(t: t, actions: [
            Btn('Сегодня', () => m.moveTaskDate(t['id'] as String, m.today), size: 11, pad: 4),
          ]),
      ],
    ]);
  }
}

// ===================== проекты =====================

class _Projects extends StatefulWidget {
  const _Projects();

  @override
  State<_Projects> createState() => _ProjectsState();
}

class _ProjectsState extends State<_Projects> {
  final closed = <String>{};
  bool showDone = false;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final active = m.projectsBy('active');
    final someday = m.projectsBy('someday');
    final done = m.projectsBy('done');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Проекты', 'Результат, для которого нужно больше одного шага. У каждого активного проекта должен быть следующий шаг.'),
      Field(hint: 'Новый проект и Enter', onSubmit: (v) {
        if (v.trim().isNotEmpty) m.addProject(v);
      }),
      const SizedBox(height: 6),
      if (active.isEmpty) _empty('Активных проектов нет.'),
      for (final p in active) _project(context, m, p),
      if (someday.isNotEmpty) ...[
        const SectionLabel('Отложены на когда-нибудь'),
        for (final p in someday)
          Row(children: [
            Expanded(child: Text(p['title'] as String, style: T.small.copyWith(color: C.muted))),
            Btn('Начать', () => m.setProjectStatus(p['id'] as String, 'active'), size: 11),
            IconBtn(Icons.delete_outline, 'Удалить проект', () => _delete(context, m, p), size: 14),
          ]),
      ],
      if (done.isNotEmpty) ...[
        InkWell(
          onTap: () => setState(() => showDone = !showDone),
          child: SectionLabel('${showDone ? '▾' : '▸'} Завершённые: ${done.length}'),
        ),
        if (showDone)
          for (final p in done)
            Row(children: [
              Expanded(child: Text('✓ ${p['title']}', style: T.small.copyWith(color: C.faint))),
              Btn('Вернуть', () => m.setProjectStatus(p['id'] as String, 'active'), size: 11, color: C.muted),
            ]),
      ],
    ]);
  }

  Future<void> _delete(BuildContext context, PanelModel m, Json p) async {
    final n = m.projectOpen(p['id'] as String).length;
    if (await confirmDialog(context, 'Удалить проект?',
        '«${p['title']}»${n > 0 ? '\nЕго шаги ($n) останутся задачами без проекта.' : ''}',
        yes: 'Удалить')) {
      m.deleteProject(p['id'] as String);
    }
  }

  Widget _project(BuildContext context, PanelModel m, Json p) {
    final pid = p['id'] as String;
    final open = m.projectOpen(pid);
    final doneCount = m.projectTasks(pid).length - open.length;
    final stuck = open.isEmpty;
    final expanded = !closed.contains(pid);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(6),
        border: stuck ? Border.all(color: C.warn.withValues(alpha: 0.6)) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          InkWell(
            onTap: () => setState(() => expanded ? closed.add(pid) : closed.remove(pid)),
            child: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 16, color: C.muted),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              Text(p['title'] as String, style: T.title),
              Text(stuck ? 'нет следующего шага' : '${plural(open.length, 'шаг', 'шага', 'шагов')}${doneCount > 0 ? ', сделано $doneCount' : ''}',
                  style: T.tiny.copyWith(color: stuck ? C.warn : C.muted)),
            ]),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'Действия с проектом',
            icon: const Icon(Icons.more_horiz, size: 16, color: C.muted),
            padding: EdgeInsets.zero,
            onSelected: (f) => f(),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: () => inputDialog(context, 'Переименовать проект', '', [('Название', '${p['title']}')], (v) {
                        if (v[0].isEmpty) return 'Название не может быть пустым';
                        m.renameProject(pid, v[0]);
                        return null;
                      }),
                  child: const Text('Переименовать…')),
              PopupMenuItem(value: () => m.setProjectStatus(pid, 'done'), child: const Text('Завершить')),
              PopupMenuItem(value: () => m.setProjectStatus(pid, 'someday'), child: const Text('Отложить на когда-нибудь')),
              PopupMenuItem(value: () => _delete(context, m, p), child: const Text('Удалить', style: TextStyle(color: C.danger))),
            ],
          ),
        ]),
        if (expanded) ...[
          for (final t in open) GtdRow(t: t),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2),
            child: Field(
              hint: stuck ? 'Какой следующий шаг? Enter' : 'Ещё шаг (с датой: «пт Замер») и Enter',
              style: T.small,
              onSubmit: (v) => m.addProjectAction(pid, v),
            ),
          ),
        ],
      ]),
    );
  }
}

// ===================== жду =====================

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final items = m.gtdList('waiting');
    final groups = <String, List<Json>>{};
    for (final t in items) {
      final who = '${t['waiting_for'] ?? ''}'.trim();
      (groups[who.isEmpty ? 'не указано' : who] ??= []).add(t);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Жду', 'Поручено другим. Когда ждёте больше недели — пора напомнить.'),
      if (items.isEmpty) _empty('Никого не ждёте. Поручить задачу можно в разборе входящих или в меню задачи.'),
      for (final e in groups.entries) ...[
        SectionLabel(e.key),
        for (final t in e.value)
          Builder(builder: (context) {
            final since = tryIso(t['waiting_since']);
            final days = since == null ? null : daysBetween(since, m.today);
            return GtdRow(
              t: t,
              extra: days == null ? null : (days == 0 ? 'с сегодня' : pluralDays(days)),
              actions: [
                Btn('Получено', () => m.toggleTask(t['id'] as String), size: 11, pad: 4, color: C.ok),
                Btn('Напомнить сегодня', () => m.moveTaskDate(t['id'] as String, m.today), size: 11, pad: 4,
                    color: (days ?? 0) >= 7 ? C.warn : C.accent),
              ],
            );
          }),
      ],
    ]);
  }
}

// ===================== когда-нибудь =====================

class _Someday extends StatelessWidget {
  const _Someday();

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final items = m.gtdList('someday');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Когда-нибудь, может быть', 'Идеи и желания без обязательств. Раз в неделю просматривайте: может, что-то пора начать.'),
      Field(hint: 'Идея и Enter', onSubmit: (v) {
        if (v.trim().isEmpty) return;
        final t = m.addInbox(v);
        m.setList(t['id'] as String, 'someday');
      }),
      const SizedBox(height: 6),
      if (items.isEmpty) _empty('Пусто.'),
      for (final t in items)
        GtdRow(t: t, actions: [
          Btn('В следующие', () => m.setList(t['id'] as String, 'next'), size: 11, pad: 4),
          IconBtn(Icons.delete_outline, 'Удалить', () => m.deleteTask(t['id'] as String), size: 14),
        ]),
    ]);
  }
}

// ===================== еженедельный обзор =====================

class _Review extends StatefulWidget {
  const _Review({required this.onGo, required this.inWindow});
  final void Function(String) onGo;
  final bool inWindow;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  final checked = <int>{};

  @override
  Widget build(BuildContext context) {
    final sc = Scope.of(context);
    final m = sc.m;
    final stuck = m.projectsBy('active').where((p) => m.projectStuck(p['id'] as String)).toList();
    final late = m.gtdList('waiting').where((t) {
      final s = tryIso(t['waiting_since']);
      return s != null && daysBetween(s, m.today) >= 7;
    }).toList();
    final doneThisWeek = m.s['gtd_review_week'] == weekKey(m.today);

    final steps = <(String, String, Widget?)>[
      ('Соберите всё во входящие', 'Записки, письма, мысли из головы — всё, что висит незакрытым.',
          Field(hint: 'Ещё одно во входящие и Enter', style: T.small, onSubmit: (v) {
            if (v.trim().isNotEmpty) m.addInbox(v);
          })),
      ('Разберите входящие до нуля', m.inboxCount == 0 ? 'Входящие пусты.' : 'Во входящих ${m.inboxCount}.',
          m.inboxCount == 0 ? null : Btn('К разбору', () => widget.onGo('process'))),
      ('Просмотрите календарь', 'Прошлая неделя — что не доделано? Следующая — к чему готовиться?',
          Btn('Открыть неделю', () => sc.actions.openWeek(context))),
      ('Пройдите следующие действия', 'Вычеркните сделанное и неактуальное: ${m.gtdList('next').length} в списке.',
          Btn('Открыть список', () => widget.onGo('next'))),
      ('У каждого проекта есть следующий шаг', stuck.isEmpty ? 'Все активные проекты с шагами.' : 'Без следующего шага: ${stuck.length}.',
          stuck.isEmpty
              ? null
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final p in stuck)
                    Row(children: [
                      SizedBox(width: 150, child: Text(short(p['title'] as String, 24), style: T.small.copyWith(color: C.warn))),
                      Expanded(
                        child: Field(hint: 'Следующий шаг и Enter', style: T.small, onSubmit: (v) => m.addProjectAction(p['id'] as String, v)),
                      ),
                    ]),
                ])),
      ('Проверьте, кого ждёте', late.isEmpty ? 'Ждёте не дольше недели.' : 'Ждёте неделю и больше: ${late.length} — напомните.',
          late.isEmpty
              ? null
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final t in late)
                    GtdRow(t: t, extra: '${t['waiting_for'] ?? ''}', actions: [
                      Btn('Напомнить сегодня', () => m.moveTaskDate(t['id'] as String, m.today), size: 11, pad: 4),
                    ]),
                ])),
      ('Загляните в «Когда-нибудь»', 'Может, что-то пора начать: ${m.gtdList('someday').length} в списке.',
          Btn('Открыть список', () => widget.onGo('someday'))),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Еженедельный обзор', doneThisWeek ? 'На этой неделе обзор уже сделан.' : 'Полчаса раз в неделю, чтобы системе можно было доверять.'),
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: () => setState(() => checked.contains(i) ? checked.remove(i) : checked.add(i)),
              child: Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Icon(checked.contains(i) ? Icons.check_box : Icons.check_box_outline_blank, size: 16,
                    color: checked.contains(i) ? C.ok : C.muted),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(steps[i].$1, style: T.title.copyWith(color: checked.contains(i) ? C.muted : C.fg)),
                Text(steps[i].$2, style: T.tiny),
                if (steps[i].$3 != null && !checked.contains(i))
                  Padding(padding: const EdgeInsets.only(top: 3), child: Align(alignment: Alignment.centerLeft, child: steps[i].$3)),
              ]),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: Btn(doneThisWeek ? 'Обзор сделан ✓' : 'Обзор завершён', doneThisWeek
            ? null
            : () {
                m.gtdReviewDone();
                m.flash('Обзор недели отмечен', 'ok');
              }, bold: true),
      ),
    ]);
  }
}
