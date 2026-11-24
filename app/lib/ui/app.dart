import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'desktop.dart';
import 'gtd.dart';
import 'panel.dart';
import 'scope.dart';
import 'settings.dart';
import 'system.dart';
import 'task_card.dart';
import 'theme.dart';
import 'widgets.dart';
import 'windows.dart';

class PanelApp extends StatefulWidget {
  const PanelApp({super.key, required this.m, this.desk, this.sys});
  final PanelModel m;
  final DesktopWindow? desk;
  final SystemIntegration? sys;

  @override
  State<PanelApp> createState() => _PanelAppState();
}

class _PanelAppState extends State<PanelApp> {
  late final AppActions actions = AppActions(widget.m, widget.desk);
  late final Widget home = Home(desk: widget.desk, actions: actions, sys: widget.sys);
  // Тема строится один раз на каждый режим плотности: новая тема при каждом изменении
  // заставляла бы перестраивать всё приложение.
  static final _themes = <bool, ThemeData>{};

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final compact = m.s['ui_compact'] != false;
        return MaterialApp(
          title: 'Информационная панель',
          debugShowCheckedModeBanner: false,
          theme: _themes[compact] ??= buildTheme(compact: compact),
          locale: const Locale('ru'),
          builder: (context, child) => Scope(
            m: m,
            actions: actions,
            child: Scaled(scale: ((m.s['ui_scale'] as num?) ?? 1).toDouble().clamp(0.5, 1.6), child: child!),
          ),
          home: home,
        );
      },
    );
  }
}

/// Масштаб всего интерфейса: раскладываем в большей «логической» области и сжимаем при отрисовке.
class Scaled extends StatelessWidget {
  const Scaled({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth / scale, c.maxHeight / scale);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: MediaQuery(data: MediaQuery.of(context).copyWith(size: size), child: child),
          ),
        ),
      );
    });
  }
}

class Home extends StatefulWidget {
  const Home({super.key, this.desk, required this.actions, this.sys});
  final DesktopWindow? desk;
  final AppActions actions;
  final SystemIntegration? sys;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  StreamSubscription<String>? reviews;
  StreamSubscription<Notice>? sounds;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = Scope.of(context).m;
    reviews ??= m.reviews.listen((kind) {
      if (!mounted) return;
      if (kind == 'morning') {
        m.pendingMorningReview = false;
        widget.actions.openMorningReview(context);
      }
      if (kind == 'weekly') widget.actions.openWeeklyReview(context);
    });
    sounds ??= m.notices.listen((n) {
      final sys = widget.sys;
      if (sys != null) {
        sys.notify(n);
      } else {
        SystemSound.play(SystemSoundType.alert);
      }
    });
    widget.sys?.onOpenTask = (id) {
      if (mounted) widget.actions.openCard(context, id);
    };
    widget.sys?.onSettings = () {
      if (mounted) widget.actions.openSettings(context);
    };
    // разбор хвостов при запуске: модель уже знает о нём, а окно открываем, когда интерфейс готов
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && m.pendingMorningReview) {
        m.pendingMorningReview = false;
        widget.actions.openMorningReview(context);
      }
    });
  }

  @override
  void dispose() {
    reviews?.cancel();
    sounds?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final m = Scope.of(context).m;
    final ctx = FocusManager.instance.primaryFocus?.context;
    final typing = ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyF) {
      widget.actions.openSearch(context);
      return KeyEventResult.handled;
    }
    if (typing) return KeyEventResult.ignored;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      shift ? m.redo() : m.undo();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      m.redo();
      return KeyEventResult.handled;
    }
    final ids = [for (final t in m.viewTasks(m.selected)) t['id'] as String];
    final sel = m.kbSel != null && ids.contains(m.kbSel) ? m.kbSel : null;
    String? neighbor() {
      if (sel == null || ids.length < 2) return null;
      final i = ids.indexOf(sel);
      return i + 1 < ids.length ? ids[i + 1] : ids[i - 1];
    }

    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      if (ids.isEmpty) return KeyEventResult.ignored;
      final step = k == LogicalKeyboardKey.arrowDown ? 1 : -1;
      if (ctrl && sel != null) {
        final t = m.findTask(sel)!;
        final d = addDays(dayOf(t, m.today), step);
        if (d.isBefore(m.today)) {
          m.flash('В прошлое не переносим', 'muted');
        } else {
          final nxt = neighbor();
          m.moveTaskDate(sel, d);
          m.setKbSel(nxt);
        }
        return KeyEventResult.handled;
      }
      final i = sel == null ? (step > 0 ? 0 : ids.length - 1) : (ids.indexOf(sel) + step).clamp(0, ids.length - 1);
      m.setKbSel(ids[i]);
      return KeyEventResult.handled;
    }
    if (sel == null) {
      if (k == LogicalKeyboardKey.escape) m.setKbSel(null);
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.space) {
      m.toggleTask(sel);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      widget.actions.openCard(context, sel);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      final nxt = neighbor();
      m.deleteTask(sel);
      m.setKbSel(nxt);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f2) {
      m.setEditing(sel);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      m.setKbSel(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final desk = widget.desk;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          Positioned.fill(child: PanelView(desk: desk)),
          if (desk != null && desk.widgetMode) Positioned.fill(child: ResizeGrips(desk: desk)),
          Positioned.fill(child: Toasts(onOpen: (id) => widget.actions.openCard(context, id))),
        ]),
      ),
    );
  }
}

/// Окна и диалоги. У виджета на время окна площадь раздвигается (DesktopWindow.withRoom).
class AppActions implements PanelActions {
  AppActions(this.m, this.desk);
  final PanelModel m;
  final DesktopWindow? desk;

  Future<T?> _show<T>(BuildContext context, Size need, Widget Function() child) {
    Future<T?> open() => showDialog<T>(
          context: context,
          builder: (_) => ListenableBuilder(listenable: m, builder: (_, __) => child()),
        );
    return desk != null ? desk!.withRoom<T>(need, open) : open();
  }

  @override
  void openCard(BuildContext context, String id) => _show(context, const Size(480, 760), () => TaskCard(id: id));

  @override
  void openWeek(BuildContext context, {DateTime? start}) => _show(context, const Size(1000, 560), () => WeekWindow(start: start));

  @override
  void openMatrix(BuildContext context) => _show(context, const Size(900, 720), () => const MatrixWindow());

  @override
  void openGtd(BuildContext context, String view) => _show(context, const Size(680, 760), () => GtdWindow(view: view));

  @override
  void openSearch(BuildContext context) => _show(context, const Size(540, 620), () => const SearchWindow());

  @override
  void openSettings(BuildContext context) => _show(context, const Size(460, 720), () => SettingsDialog(desk: desk));

  @override
  void openWeeklyReview(BuildContext context) => _show(context, const Size(560, 640), () => const WeeklyReview());

  @override
  void openUnload(BuildContext context) {
    final day = iso(m.selected);
    const order = {'q4': 0, 'q3': 1, null: 2, 'q2': 3, 'q1': 4};
    int rank(Json t) => order[eis.containsKey(t['eis']) ? t['eis'] : null] ?? 2;
    _show(
      context,
      const Size(600, 560),
      () => ReviewDialog(
        title: 'Разгрузить день',
        hint: '${dateTitle(m.selected, m.today)}. Перенесите часть задач — вверху то, что проще всего отложить.',
        keep: (t) => t['date'] == day && t['done'] != true,
        order: (a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : (prioRank[b['priority']] ?? 3) - (prioRank[a['priority']] ?? 3),
        keepLabel: 'Оставить',
      ),
    );
  }

  @override
  void openMorningReview(BuildContext context) {
    final n = m.tasks.where((t) => m.carried(t as Json)).length;
    if (n == 0) return;
    _show(
      context,
      const Size(600, 560),
      () => ReviewDialog(
        title: 'Доброе утро! Разберём хвосты',
        hint: 'С прошлых дней не закрыто: ${plural(n, 'задача', 'задачи', 'задач')}. Решите для каждой: сделать сегодня, перенести или удалить.',
        keep: m.carried,
        keepLabel: 'Сегодня',
      ),
    );
  }

  @override
  void openTarget(String target) {
    try {
      m.storage.openExternal(target);
    } catch (e) {
      m.storage.logError('Не открылось: $target\n$e');
      m.flash('Не получилось открыть', 'danger');
    }
  }

  @override
  Future<void> askDate(BuildContext context, String id) {
    final t = m.findTask(id);
    if (t == null) return Future.value();
    final d = dayOf(t, m.today);
    return inputDialog(context, 'Перенести задачу', '«${short(t['text'] as String, 40)}»\nНа какую дату? Например: 20.11, +3, пт, завтра.',
        [('Дата', '${two(d.day)}.${two(d.month)}.${d.year}')], (v) {
      final nd = parseDate(v[0], m.today);
      if (nd == null) return 'Не понял дату. Примеры: 20.11, 20.11.2026, +3, пт, завтра';
      if (nd.isBefore(m.today)) return 'Эта дата уже прошла';
      m.moveTaskDate(id, nd);
      return null;
    }, okText: 'Перенести');
  }

  @override
  Future<void> askTime(BuildContext context, String id) {
    final t = m.findTask(id);
    if (t == null) return Future.value();
    return inputDialog(context, 'Время задачи', 'Во сколько? За $remindBefore минут придёт напоминание.\nОставьте пустым, чтобы убрать время.',
        [('Время', '${t['time'] ?? ''}')], (v) {
      final s = v[0].replaceAll('.', ':');
      if (s.isEmpty) {
        m.setTime(id, null);
        return null;
      }
      final mm = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(s);
      if (mm == null) return 'Формат: 14:30';
      m.setTime(id, '${two(int.parse(mm[1]!))}:${mm[2]}');
      return null;
    });
  }

  @override
  Future<void> askDeadline(BuildContext context, String id) {
    final t = m.findTask(id);
    if (t == null) return Future.value();
    final cur = tryIso(t['deadline']);
    return inputDialog(context, 'Дедлайн',
        '«${short(t['text'] as String, 40)}»\nДо какого числа нужно сделать?\nПусто — убрать дедлайн. За 2 дня задача станет срочной.',
        [('Дедлайн', cur != null ? shortDate(cur, m.today) : '')], (v) {
      if (v[0].isEmpty) {
        m.setDeadline(id, null);
        return null;
      }
      final d = parseDate(v[0], m.today);
      if (d == null) return 'Не понял дату. Примеры: 20.11, +3, пт, завтра';
      m.setDeadline(id, d);
      return null;
    });
  }

  @override
  Future<void> askEst(BuildContext context, String id) {
    final t = m.findTask(id);
    if (t == null) return Future.value();
    final cur = t['est'] is num ? estToken((t['est'] as num).round()).substring(1) : '';
    return inputDialog(context, 'Оценка времени', 'Сколько займёт задача? Например: 45м, 1,5ч, 2ч.', [('Время', cur)], (v) {
      if (v[0].isEmpty) {
        m.setEst(id, null);
        return null;
      }
      final ex = parseExtras('x ~${v[0].replaceAll('~', '')}', m.today).$2;
      if (ex.est == null) return 'Примеры: 45м, 1,5ч, 2ч';
      m.setEst(id, ex.est);
      return null;
    });
  }

  @override
  Future<void> askRepeat(BuildContext context, String id) =>
      showDialog(context: context, builder: (_) => ListenableBuilder(listenable: m, builder: (_, __) => RepeatDialog(id: id)));

  @override
  Future<void> askTemplateName(BuildContext context, List<Map<String, dynamic>> items, String name) =>
      inputDialog(context, 'Новый шаблон', 'Задач в шаблоне: ${items.length}.\nКак его назвать?', [('Название', name)], (v) {
        if (v[0].isEmpty) return 'Введите название';
        m.addTemplate(v[0], items);
        return null;
      }, okText: 'Сохранить');
}

/// Тестовые данные для демо-страницы в браузере.
Json demoData(DateTime now) {
  final t = dayOnly(now);
  String d(int n) => iso(addDays(t, n));
  return {
    'tasks': [
      {'id': 'a', 'text': 'Квартальный отчёт', 'date': d(0), 'done': false, 'time': '10:00', 'eis': 'q1', 'est': 240, 'tags': ['работа'],
        'deadline': d(3), 'priority': 'high', 'note': 'Шаблон прошлого квартала лежит в папке «Отчёты». https://example.com/q3',
        'subs': [{'id': 's1', 'text': 'Выгрузка из 1С', 'done': true}, {'id': 's2', 'text': 'Сводная по отделам', 'done': false}]},
      {'id': 'b', 'text': 'Договор юристам', 'date': d(0), 'done': false, 'eis': 'q1', 'est': 90, 'tags': ['работа'], 'priority': 'medium'},
      {'id': 'c', 'text': 'Сверить счета за октябрь', 'date': d(-3), 'done': false},
      {'id': 'd', 'text': 'Купить билеты в Казань', 'date': d(0), 'done': false, 'est': 30, 'tags': ['дом']},
      {'id': 'e', 'text': 'Созвон с Олей', 'date': d(0), 'done': false, 'time': '19:00'},
      {'id': 'f', 'text': 'Разобрать почту', 'date': d(0), 'done': true, 'done_at': d(0)},
      {'id': 'g', 'text': 'Позвонить родителям', 'date': d(1), 'done': false},
      {'id': 'h', 'text': 'Встреча с подрядчиком', 'date': d(2), 'done': false, 'time': '10:00', 'est': 60},
      {'id': 'i', 'text': 'Оплатить хостинг', 'date': d(2), 'done': false, 'deadline': d(2)},
      {'id': 'j', 'text': 'План на декабрь', 'date': d(4), 'done': false, 'eis': 'q2', 'est': 300},
      {'id': 'k', 'text': 'Обновить резюме', 'date': d(4), 'done': false, 'est': 240, 'moves': 3},
    ],
    'goals': {weekKey(t): [
      {'id': 'g1', 'text': 'Сдать квартальный отчёт', 'done': false},
      {'id': 'g2', 'text': 'Запустить рассылку', 'done': true},
    ]},
    'events': [{'id': 'e1', 'title': 'Отпуск', 'date': d(12)}],
    'notes': 'Пароль от Wi-Fi у Марины\nhttps://isdayoff.ru',
    'settings': {'review': false},
  };
}
