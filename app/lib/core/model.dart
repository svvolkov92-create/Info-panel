// Состояние и действия панели. Перенесено из mixin-ов Python-версии (tasks, planning, pomodoro,
// blocks, calendar_view). Данные — те же JSON-словари, что в data.json, без промежуточных классов:
// так файл остаётся совместимым с Python-версией, и неизвестные поля не теряются.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'core.dart';
import 'storage.dart';

typedef Json = Map<String, dynamic>;

const blockOrder = ['calendar', 'goals', 'tasks', 'future', 'week', 'pomo', 'notes', 'stats', 'events'];

Json defaultSettings() => {
      'x': null, 'y': 80, 'alpha': 0.94, 'topmost': false,
      'work': 25, 'break': 5, 'long': 15, 'cycle': 4, 'auto_break': false,
      'pinned': false, 'anchor': 'free', 'tasks_max': 260,
      'size_fixed': false, 'w': null, 'h': null,
      'order': List<String>.from(blockOrder), 'hidden_blocks': <String>[],
      'collapsed': {for (final k in blockOrder) k: false},
      'prod_cal': true, 'pomo_task': null,
      'block_h': <String, dynamic>{},
      'sort': 'manual', 'filter': 'all', 'q1_limit': 5, 'day_hours': 8,
      'review': true, 'review_date': '', 'focus_mode': true, 'stats_by': 'task',
      'weekly_review': true, 'review_week': '',
      'click_through': false, 'ct_hint_shown': false,
      'task_font': 10, 'task_gap': 1, 'weekend_hold': true, 'card_collapsed': <String>[],
      'desktop_layer': false, 'desk_hint_shown': false, 'desk_confirmed': false,
      'sounds': {
        'work': {'file': 'default', 'vol': 80},
        'break': {'file': 'default', 'vol': 80},
      },
      // настройки Flutter-версии; Python-версия их просто хранит
      'ui_mode': 'widget', // widget | window
      'ui_scale': 0.85,
      'ui_compact': true,
      'gtd': true,
      'ui_layer': 'normal', // normal | top | bottom | desktop
      'ui_bounds': null, // [x, y, w, h] виджета
      'ui_bounds_window': null, // [x, y, w, h] окна
      'autostart': false,
    };

String newId() {
  final r = math.Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Уведомление для интерфейса: напоминание, конец помидора и т. п.
class Notice {
  Notice(this.title, this.text, {this.kind = 'info', this.taskId, this.sound, this.actions = const [], this.seconds});
  final String title;
  final String text;
  final String kind; // info | remind | rest | danger | warn
  final String? taskId;
  final String? sound; // work | break | null — системный
  final List<(String, void Function())> actions; // кнопки, после нажатия уведомление закрывается
  final int? seconds; // сколько показывать
}

class PanelModel extends ChangeNotifier {
  PanelModel({Storage? storage, DateTime Function()? clock, this.network = true})
      : storage = storage ?? Storage(),
        _now = clock ?? DateTime.now;

  final Storage storage;
  final bool network; // false — без загрузки производственного календаря (тесты)
  final DateTime Function() _now;

  Json data = {};
  Json get s => data['settings'] as Json;
  List get tasks => data['tasks'] as List;
  List get recurring => data['recurring'] as List;

  /// Выбранная клавиатурой задача и задача, которая правится одной строкой.
  String? kbSel;
  String? editing;

  void setKbSel(String? id) {
    kbSel = id;
    notifyListeners();
  }

  void setEditing(String? id) {
    editing = id;
    notifyListeners();
  }

  late DateTime today;
  late DateTime selected;
  late DateTime viewMonth; // первое число показанного месяца
  Set<String> holdIso = {};

  /// Часы и таймер помодоро: обновляются каждую секунду без перерисовки всей панели.
  final ValueNotifier<DateTime> clock = ValueNotifier(DateTime.now());

  /// Короткое сообщение на месте счётчика задач («добавлено: 3»).
  final ValueNotifier<(String, String)?> status = ValueNotifier(null);
  Timer? _statusTimer;

  /// Полоска «Выполнена … — Отменить».
  final ValueNotifier<String?> undoBar = ValueNotifier(null);
  Timer? _undoTimer;

  final _notices = StreamController<Notice>.broadcast();
  Stream<Notice> get notices => _notices.stream;

  void notice(Notice n) => _notices.add(n);

  /// Утренний разбор и обзор недели — интерфейс открывает окна по этому сигналу.
  final _reviews = StreamController<String>.broadcast();
  Stream<String> get reviews => _reviews.stream;

  Timer? _saveTimer;
  Timer? _tick;
  final Set<int> _fetching = {};

  // ===================== загрузка =====================
  void load({Json? demo}) {
    final d = <String, dynamic>{
      'tasks': [], 'recurring': [], 'events': [], 'notes': '',
      'pomodoros': <String, dynamic>{}, 'pomo_cycle': <String, dynamic>{}, 'prodcal': <String, dynamic>{},
      'pomo_log': [], 'goals': <String, dynamic>{}, 'templates': [], 'settings': defaultSettings(),
    };
    final loaded = demo ?? storage.read();
    if (loaded != null) {
      try {
        for (final k in ['tasks', 'recurring', 'events', 'notes', 'pomodoros', 'pomo_cycle', 'prodcal',
          'pomo_log', 'goals', 'templates']) {
          if (loaded.containsKey(k) && loaded[k] != null) d[k] = loaded[k];
        }
        // ключи, которых Python-версия не знает, тоже сохраняем
        for (final e in loaded.entries) {
          d.putIfAbsent(e.key, () => e.value);
        }
        final st = d['settings'] as Json;
        final collapsed = Map<String, dynamic>.from(st['collapsed'] as Map);
        final ls = loaded['settings'];
        if (ls is Map) st.addAll(Map<String, dynamic>.from(ls));
        if (st['collapsed'] is Map) collapsed.addAll(Map<String, dynamic>.from(st['collapsed'] as Map));
        st['collapsed'] = collapsed;
        final order = [for (final k in (st['order'] as List? ?? const [])) if (blockOrder.contains(k)) k as String];
        for (var i = 0; i < blockOrder.length; i++) {
          final k = blockOrder[i];
          if (!order.contains(k)) {
            final prev = i > 0 ? blockOrder[i - 1] : null;
            final at = prev != null && order.contains(prev) ? order.indexOf(prev) + 1 : order.length;
            order.insert(at, k);
          }
        }
        st['order'] = order;
        for (final k in defaultSettings().keys) {
          st.putIfAbsent(k, () => defaultSettings()[k]);
        }
        for (final t in [...d['tasks'] as List, ...d['recurring'] as List]) {
          if (t is Map && t.remove('prio') == true) t.putIfAbsent('priority', () => 'high');
        }
        d['tasks'] = sanitizeTasks(d['tasks'] as List);
        // события с испорченной датой отбрасываем, иначе не отрисуется вся панель
        d['events'] = [
          for (final e in d['events'] as List)
            if (e is Map && tryIso(e['date']) != null && '${e['title'] ?? ''}'.isNotEmpty) Map<String, dynamic>.from(e)
            else if (e != null) ...(() {
              storage.logError('Пропущено событие с испорченной датой: ${short('$e', 200)}');
              return const [];
            })(),
        ];
      } catch (e, st) {
        storage.blocked = true; // данные устроены неожиданно — не перезаписываем, пока не разберёмся
        storage.logError('Не удалось разобрать данные, сохранение отключено:\n$e\n$st');
      }
    }
    // Единый вид данных, как после чтения файла: обычные списки и словари без «узких» типов.
    // Иначе данные, собранные в коде (демо, старые версии), падали бы при добавлении элементов.
    data = jsonDecode(jsonEncode(d)) as Json;
    today = dayOnly(_now());
    selected = today;
    viewMonth = DateTime(today.year, today.month);
    carryOverTasks();
    _committed = _undoState();
    fetchProdcal(today.year);
  }

  List sanitizeTasks(List raw) {
    final todayIso = iso(dayOnly(_now()));
    final fixed = [];
    final seen = <String>{};
    for (final x in raw) {
      if (x is! Map) {
        storage.logError('Пропущена непонятная запись в задачах: ${short('$x', 200)}');
        continue;
      }
      final t = Map<String, dynamic>.from(x);
      if (t['id'] is! String || (t['id'] as String).isEmpty || seen.contains(t['id'])) t['id'] = newId();
      seen.add(t['id'] as String);
      t['text'] = '${t['text'] ?? ''}'.isEmpty ? '(без названия)' : '${t['text']}';
      t['done'] = t['done'] == true;
      if (tryIso(t['date']) == null && gtdLists.containsKey(t['list'])) {
        t.remove('date'); // задача GTD-списка живёт без даты, пока её не поставят в календарь
      } else if (tryIso(t['date']) == null) {
        storage.logError('У задачи «${short(t['text'] as String, 60)}» испорчена дата ${t['date']} — поставил сегодня');
        t['date'] = todayIso;
      }
      for (final key in ['deadline', 'from', 'done_at']) {
        if (t.containsKey(key) && tryIso(t[key]) == null) t.remove(key);
      }
      if (t.containsKey('snooze') && DateTime.tryParse('${t['snooze']}') == null) t.remove('snooze');
      if (t['time'] != null && !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('${t['time']}')) t.remove('time');
      if (t['subs'] is List) {
        t['subs'] = [for (final sb in t['subs'] as List) if (sb is Map) Map<String, dynamic>.from(sb)];
      }
      if (t['log'] is List) t['log'] = List.from(t['log'] as List);
      if (t['tags'] is List) t['tags'] = [for (final g in t['tags'] as List) '$g'];
      if (t['est'] is num) t['est'] = (t['est'] as num).round();
      fixed.add(t);
    }
    return fixed;
  }

  // ===================== таймер =====================
  void start() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
    maybeMorningReview();
  }

  @override
  void dispose() {
    _tick?.cancel();
    flushSave();
    super.dispose();
  }

  void _onTick() {
    final now = _now();
    try {
      if (clock.value.second != now.second || clock.value.minute != now.minute) clock.value = now;
      if (dayOnly(now) != today) {
        final wasToday = selected == today;
        today = dayOnly(now);
        if (wasToday) {
          selected = today;
          viewMonth = DateTime(today.year, today.month);
        }
        carryOverTasks();
        histUndo.clear();
        histRedo.clear();
        _committed = _undoState();
        notifyListeners();
        maybeMorningReview();
      }
      if (pomoRunning && !now.isBefore(pomoEnd)) {
        pomoRunning = false;
        pomoFinish();
      }
      checkReminders(now);
      maybeWeeklyReview(now);
    } catch (e, st) {
      storage.logError('Ошибка таймера:\n$e\n$st');
    }
  }

  // ===================== поиск и выборка =====================
  Json? findTask(String? id) {
    if (id == null) return null;
    for (final t in tasks) {
      if ((t as Json)['id'] == id) return t;
    }
    return null;
  }

  Json? findRec(Object? id) {
    if (id == null) return null;
    for (final r in recurring) {
      if ((r as Json)['id'] == id) return r;
    }
    return null;
  }

  (String, String) dayKind(DateTime d) =>
      dayInfo(d, prodcal: data['prodcal'] as Json?, useProdCal: s['prod_cal'] == true);

  bool isOff(DateTime d) => dayKind(d).$1 == 'off';

  DateTime? updateHold() {
    final days = s['weekend_hold'] != false ? holdDates(today, isOff) : <DateTime>[];
    holdIso = days.map(iso).toSet();
    if (holdIso.isEmpty) return null;
    return days.first;
  }

  /// Задача последнего рабочего дня, которая в выходные висит в «сегодня».
  bool held(Json t) => holdIso.contains(t['date']) && (t['date'] as String).compareTo(iso(today)) < 0;

  // Индекс задач по датам: строится один раз после изменения, а не перебором всех задач на каждый день.
  Map<String, List<Json>>? _byDate;
  List<Json>? _future;

  /// Сбросить кэши: вызывается при любом изменении задач.
  void invalidate() {
    _byDate = null;
    _future = null;
  }

  @override
  void notifyListeners() {
    invalidate();
    super.notifyListeners();
  }

  Map<String, List<Json>> get _index {
    final idx = _byDate;
    if (idx != null) return idx;
    final built = <String, List<Json>>{};
    for (final x in tasks) {
      final d = (x as Json)['date'];
      if (d is String) (built[d] ??= []).add(x);
    }
    return _byDate = built;
  }

  List<Json> tasksFor(DateTime d) {
    final key = iso(d);
    final todayIso = iso(today);
    final items = <Json>[...?_index[key]];
    if (d == today && holdIso.isNotEmpty) {
      // задачи последнего рабочего дня висят в «сегодня» до конца выходных
      final held = <Json>[
        for (final h in holdIso)
          if (h != key)
            for (final t in _index[h] ?? const <Json>[])
              if (t['done'] != true || t['done_at'] == todayIso) t,
      ];
      if (held.isNotEmpty) {
        final order = {for (var i = 0; i < tasks.length; i++) identityHashCode(tasks[i]): i};
        items
          ..addAll(held)
          ..sort((a, b) => order[identityHashCode(a)]! - order[identityHashCode(b)]!);
      }
    }
    final timed = stableSorted(items.where((t) => t['time'] != null).toList(),
        (a, b) => (a['time'] as String).compareTo(b['time'] as String));
    return [...timed, ...items.where((t) => t['time'] == null)];
  }

  /// Задачи, которые в прошедший день d висели незакрытыми и были перенесены дальше.
  List<Json> carriedThrough(DateTime d) {
    if (!d.isBefore(today)) return [];
    final key = iso(d);
    return [
      for (final x in tasks)
        if ((x as Json)['from'] is String &&
            x['date'] is String &&
            (x['from'] as String).compareTo(key) <= 0 &&
            key.compareTo(x['date'] as String) < 0)
          x,
    ];
  }

  List<Json> viewTasks(DateTime d) {
    var items = tasksFor(d);
    final f = '${s['filter']}';
    if (eis.containsKey(f)) {
      items = items.where((t) => t['eis'] == f).toList();
    } else if (f == 'none') {
      items = items.where((t) => !eis.containsKey(t['eis'])).toList();
    } else if (f.startsWith('#')) {
      items = items.where((t) => ((t['tags'] as List?) ?? const []).contains(f.substring(1))).toList();
    } else if (f.startsWith('goal:')) {
      items = items.where((t) => t['goal'] == f.substring(5)).toList();
    }
    int pr(Json t) => prioRank[t['priority']] ?? 3;
    int eo(Json t) => eisOrder[t['eis']] ?? 4;
    // сортировка устойчивая: при равенстве сохраняется ваш порядок, как в Python-версии
    switch (s['sort']) {
      case 'priority':
        return stableSorted(items, (a, b) => pr(a) != pr(b) ? pr(a) - pr(b) : eo(a) - eo(b));
      case 'eis':
        return stableSorted(items, (a, b) => eo(a) != eo(b) ? eo(a) - eo(b) : pr(a) - pr(b));
      case 'deadline':
        return stableSorted(items, (a, b) {
          final c = '${a['deadline'] ?? '9999-12-31'}'.compareTo('${b['deadline'] ?? '9999-12-31'}');
          return c != 0 ? c : pr(a) - pr(b);
        });
    }
    return items;
  }

  List<Json> futureTasks() => _future ??= _computeFuture();

  List<Json> _computeFuture() {
    final t0 = iso(today);
    final list = <Json>[
      for (final t in tasks)
        if ((t as Json)['date'] is String && (t['date'] as String).compareTo(t0) > 0 && t['done'] != true) t,
    ];
    return stableSorted(list, (a, b) {
      final c = (a['date'] as String).compareTo(b['date'] as String);
      if (c != 0) return c;
      if (a['time'] != null && b['time'] != null) return (a['time'] as String).compareTo(b['time'] as String);
      if (a['time'] != null) return -1;
      if (b['time'] != null) return 1;
      return 0;
    });
  }

  int loadMinutes(DateTime d) =>
      tasksFor(d).where((t) => t['done'] != true).fold(0, (n, t) => n + ((t['est'] as num?)?.round() ?? 0));

  int dayHoursMinutes() => ((s['day_hours'] as num? ?? 8) * 60).round();

  // ===================== перенос, повторы =====================
  void carryOverTasks() {
    final t0 = iso(today);
    final holdStart = updateHold();
    final target = holdStart != null ? iso(holdStart) : t0;
    final kept = [];
    for (final x in tasks) {
      final t = x as Json;
      if (t['date'] is! String) {
        kept.add(t); // входящие, следующие действия и т. п. — без даты, не переносятся
        continue;
      }
      if (t['done'] != true && (t['date'] as String).compareTo(target) < 0) {
        t.putIfAbsent('from', () => t['date']);
        t['date'] = target;
        t.remove('reminded');
        t['carries'] = ((t['carries'] as num?) ?? 0).toInt() + 1;
        addLog(t, 'не закрыта — перенесена${target == t0 ? '' : ' (ждёт конца выходных)'}');
      }
      kept.add(t);
    }
    data['tasks'] = kept;
    invalidate();
    archiveMonthly();
    generateRecurring();
    applyAutoUrgency();
    data['events'] = [for (final e in data['events'] as List) if ('${(e as Map)['date']}'.compareTo(t0) >= 0) e];
    final keepFrom = iso(addDays(today, -60));
    data['pomo_log'] = [for (final x in data['pomo_log'] as List) if ('${(x as Map)['date']}'.compareTo(keepFrom) >= 0) x];
    save();
  }

  void generateRecurring() {
    final t0 = iso(today);
    for (final x in recurring) {
      final r = x as Json;
      final start = tryIso(r['start']);
      if (!ruleMatches(r['rule'] as String?, today, start) || '${r['last'] ?? ''}'.compareTo(t0) >= 0) continue;
      if (tasks.any((t) => (t as Json)['rec'] == r['id'] && t['done'] != true)) continue;
      tasks.add(<String, dynamic>{
        'id': newId(), 'text': r['text'], 'date': t0, 'done': false,
        'priority': r['priority'], 'eis': r['eis'], 'time': r['time'], 'rec': r['id'],
        'created': nowStr(_now()), 'log': [[nowStr(_now()), 'создана повтором']],
      }..removeWhere((k, v) => v == null));
      r['last'] = t0;
    }
    invalidate();
  }

  void applyAutoUrgency() {
    for (final x in tasks) {
      final t = x as Json;
      if (t['done'] == true || t['deadline'] == null || !(t['eis'] == 'q2' || t['eis'] == 'q4')) continue;
      final dl = tryIso(t['deadline']);
      if (dl != null && daysBetween(today, dl) <= 2) {
        t['eis'] = t['eis'] == 'q2' ? 'q1' : 'q3';
        addLog(t, 'стала срочной: близко дедлайн');
      }
    }
  }

  void addLog(Json t, String what) {
    final log = (t['log'] as List?) ?? [];
    log.add([nowStr(_now()), what]);
    if (log.length > 30) log.removeRange(0, log.length - 30);
    t['log'] = log;
  }

  // ===================== создание и правка =====================
  Json newTask(String raw, {DateTime? date}) {
    final q = parseQuick(raw, today, allowDate: date == null);
    final day = date ?? q.date ?? selected;
    final t = <String, dynamic>{
      'id': newId(), 'text': q.text.isEmpty ? raw.trim() : q.text,
      'date': iso(day), 'done': false, 'created': nowStr(_now()),
    };
    if (q.prio) t['priority'] = 'high';
    if (q.time != null) t['time'] = q.time;
    if (q.eis != null) t['eis'] = q.eis;
    applyExtras(t, Extras(q.tags, q.est, q.deadline), replace: false);
    addLog(t, 'создана');
    return t;
  }

  void applyExtras(Json t, Extras ex, {required bool replace}) {
    if (replace || ex.tags.isNotEmpty) {
      final tags = replace
          ? ex.tags
          : {...((t['tags'] as List?) ?? const []).map((e) => '$e'), ...ex.tags}.toList();
      if (tags.isNotEmpty) {
        t['tags'] = tags;
      } else {
        t.remove('tags');
      }
    }
    if (replace || ex.est != null) {
      if (ex.est != null) {
        t['est'] = ex.est;
      } else {
        t.remove('est');
      }
    }
    if (replace || ex.deadline != null) {
      if (ex.deadline != null) {
        t['deadline'] = iso(ex.deadline!);
      } else {
        t.remove('deadline');
      }
    }
  }

  /// Добавляет задачу из строки ввода. Возвращает дату, если она отличается от выбранной.
  DateTime? addTask(String raw) {
    if (raw.trim().isEmpty) return null;
    final t = newTask(raw);
    tasks.add(t);
    afterTasksChanged();
    if (t['date'] != iso(selected)) {
      final d = fromIso(t['date'] as String);
      flash('→ на ${wdShort[wd(d)].toLowerCase()}, ${dayLong(d)}');
      return d;
    }
    return null;
  }

  void addTasks(List<String> lines) {
    for (final l in lines) {
      tasks.add(newTask(l));
    }
    afterTasksChanged();
    flash('добавлено: ${lines.length}', 'ok');
  }

  /// Будущая задача: «Купить билеты 20.11». Возвращает текст ошибки или null.
  String? addFuture(String raw) {
    if (raw.trim().isEmpty) return null;
    final (text, d) = splitTaskDate(raw, today);
    if (d == null) return 'Добавьте дату в конце: «… 20.11», «… +3», «… пт», «… завтра»';
    if (d.isBefore(today)) return 'Эта дата уже прошла';
    tasks.add(newTask(text, date: d));
    afterTasksChanged();
    return null;
  }

  String? addFutureLines(List<String> lines) {
    var added = 0, skipped = 0;
    for (final l in lines) {
      final (text, d) = splitTaskDate(l, today);
      if (d != null && !d.isBefore(today)) {
        tasks.add(newTask(text, date: d));
        added++;
      } else {
        skipped++;
      }
    }
    if (added > 0) afterTasksChanged();
    return skipped > 0 ? 'Без даты в конце строки пропущено: $skipped' : null;
  }

  void toggleTask(String id) {
    final t = findTask(id);
    if (t == null) return;
    t['done'] = t['done'] != true;
    if (t['done'] == true) {
      t['done_at'] = iso(today);
      t['date'] ??= iso(today); // сделанное действие без даты попадает в сегодняшний день
      addLog(t, 'выполнена');
    } else {
      t.remove('done_at');
      addLog(t, 'снова открыта');
    }
    afterTasksChanged();
    if (t['done'] == true) showUndo('Выполнена «${short(t['text'] as String, 22)}»');
  }

  void deleteTask(String id) {
    final t = findTask(id);
    if (t == null) return;
    tasks.remove(t);
    if (s['pomo_task'] == id) s['pomo_task'] = null;
    afterTasksChanged();
    showUndo('Удалена «${short(t['text'] as String, 22)}»');
  }

  void moveTaskDate(String id, DateTime d) {
    final t = findTask(id);
    if (t == null || t['date'] == iso(d)) return;
    t['date'] = iso(d);
    _leaveList(t);
    t.remove('from');
    t.remove('reminded');
    t.remove('snooze');
    t['moves'] = ((t['moves'] as num?) ?? 0).toInt() + 1;
    addLog(t, 'перенесена на ${shortDate(d, today)}');
    afterTasksChanged();
    showUndo('Перенесена на ${d.isAfter(today) ? futureDateText(d, today) : d == today ? 'сегодня' : shortDate(d, today)}');
  }

  /// Сегодняшняя и просроченная задача — на завтра, будущая — на день позже своей даты.
  DateTime nextDayFor(String id) {
    final t = findTask(id);
    final d = tryIso(t?['date']) ?? today;
    return addDays(d.isAfter(today) ? d : today, 1);
  }

  void setField(String id, String key, Object? value) {
    final t = findTask(id);
    if (t == null) return;
    if (value != null) {
      t[key] = value;
    } else {
      t.remove(key);
    }
    final r = findRec(t['rec']);
    if (r != null && (key == 'priority' || key == 'eis')) r[key] = value;
    if (key == 'priority') addLog(t, 'приоритет: ${priorities.firstWhere((p) => p.$1 == value).$2.toLowerCase()}');
    if (key == 'eis') addLog(t, value == null ? 'квадрант снят' : 'квадрант: ${eis[value]!.$1.toLowerCase()}');
    afterTasksChanged();
  }

  void setTime(String id, String? value) {
    final t = findTask(id);
    if (t == null) return;
    if (value != null && value.isNotEmpty) {
      t['time'] = value;
    } else {
      t.remove('time');
    }
    t.remove('reminded');
    final r = findRec(t['rec']);
    if (r != null) r['time'] = t['time'];
    afterTasksChanged();
  }

  void setDeadline(String id, DateTime? d) {
    final t = findTask(id);
    if (t == null) return;
    if (d != null) {
      t['deadline'] = iso(d);
      addLog(t, 'дедлайн ${shortDate(d, today)}');
    } else {
      t.remove('deadline');
      addLog(t, 'дедлайн снят');
    }
    afterTasksChanged();
  }

  void setEst(String id, int? minutes) {
    final t = findTask(id);
    if (t == null) return;
    if (minutes != null && minutes > 0) {
      t['est'] = minutes;
    } else {
      t.remove('est');
    }
    afterTasksChanged();
  }

  void addTags(String id, List<String> tags) {
    final t = findTask(id);
    if (t == null) return;
    t['tags'] = {...((t['tags'] as List?) ?? const []).map((e) => '$e'), ...tags}.toList();
    afterTasksChanged();
  }

  void removeTag(String id, String tag) {
    final t = findTask(id);
    if (t == null) return;
    final tags = [for (final g in (t['tags'] as List?) ?? const []) if (g != tag) g];
    if (tags.isEmpty) {
      t.remove('tags');
    } else {
      t['tags'] = tags;
    }
    afterTasksChanged();
  }

  void setTitle(String id, String raw) {
    final t = findTask(id);
    if (t == null || raw.trim().isEmpty || raw.trim() == t['text']) return;
    final (text, ex) = parseExtras(raw.trim(), today);
    applyExtras(t, ex, replace: false);
    t['text'] = text.isEmpty ? t['text'] : text;
    final r = findRec(t['rec']);
    if (r != null) r['text'] = t['text'];
    afterTasksChanged();
  }

  void setNote(String id, String text) {
    final t = findTask(id);
    if (t == null) return;
    if (text.trim().isNotEmpty) {
      t['note'] = text;
    } else {
      t.remove('note');
    }
    commitUndo();
    save();
    notifyListeners();
  }

  /// Правка одной строкой: «! 14:00 Текст ~2ч #метка до пт». Пустая строка удаляет задачу.
  void editTask(String id, String raw) {
    final t = findTask(id);
    if (t == null) return;
    if (raw.trim().isEmpty) {
      deleteTask(id);
      return;
    }
    final (text0, prio, time) = parseTaskText(raw);
    final (text, ex) = parseExtras(text0.isEmpty ? raw.trim() : text0, today);
    applyExtras(t, ex, replace: true);
    if (time != t['time']) t.remove('reminded');
    t['text'] = text.isEmpty ? raw.trim() : text;
    if (prio) {
      t['priority'] = 'high';
    } else if (t['priority'] == 'high') {
      t.remove('priority');
    }
    if (time != null) {
      t['time'] = time;
    } else {
      t.remove('time');
    }
    final r = findRec(t['rec']);
    if (r != null) {
      r['text'] = t['text'];
      r['priority'] = t['priority'];
      r['time'] = t['time'];
    }
    afterTasksChanged();
  }

  void setRepeat(String id, String? rule) {
    final t = findTask(id);
    if (t == null) return;
    final r = findRec(t['rec']);
    if (rule == null) {
      if (r != null) {
        recurring.remove(r);
        for (final x in tasks) {
          if ((x as Json)['rec'] == r['id']) x.remove('rec');
        }
      }
    } else if (r != null) {
      r['rule'] = rule;
      r['start'] = t['date'] ?? iso(today);
    } else {
      final rid = newId();
      recurring.add(<String, dynamic>{
        'id': rid, 'text': t['text'], 'rule': rule, 'priority': t['priority'], 'eis': t['eis'],
        'time': t['time'], 'last': t['date'] ?? iso(today), 'start': t['date'] ?? iso(today),
      });
      t['rec'] = rid;
    }
    afterTasksChanged();
  }

  String? ruleOf(Json t) => findRec(t['rec'])?['rule'] as String?;

  void toggleOpen(String id) {
    final t = findTask(id);
    if (t == null) return;
    t['open'] = t['open'] != true;
    afterTasksChanged(undoable: false);
  }

  void addSubtasks(String id, List<String> lines) {
    final t = findTask(id);
    if (t == null) return;
    final subs = (t['subs'] as List?) ?? [];
    for (final l in lines) {
      if (l.trim().isNotEmpty) subs.add(<String, dynamic>{'id': newId(), 'text': l.trim(), 'done': false});
    }
    t['subs'] = subs;
    afterTasksChanged();
  }

  void toggleSub(String id, String sid) {
    final t = findTask(id);
    for (final x in (t?['subs'] as List?) ?? const []) {
      if ((x as Map)['id'] == sid) x['done'] = x['done'] != true;
    }
    afterTasksChanged();
  }

  void deleteSub(String id, String sid) {
    final t = findTask(id);
    if (t == null) return;
    t['subs'] = [for (final x in (t['subs'] as List?) ?? const []) if ((x as Map)['id'] != sid) x];
    afterTasksChanged();
  }

  /// Ручной порядок: ставим задачу перед beforeId (или в конец дня).
  void moveTaskOrder(String id, String? beforeId) {
    final t = findTask(id);
    if (t == null || id == beforeId) return;
    if (s['sort'] != 'manual' || s['filter'] != 'all') {
      if (t['date'] != iso(selected)) moveTaskDate(id, selected);
      return;
    }
    if (t['date'] != iso(selected)) {
      t['date'] = iso(selected);
      _leaveList(t);
      t.remove('from');
      t.remove('reminded');
      t['moves'] = ((t['moves'] as num?) ?? 0).toInt() + 1;
      addLog(t, 'перенесена на ${shortDate(selected, today)}');
      invalidate();
    }
    final ids = viewTasks(selected).map((x) => x['id']).where((x) => x != id).toList();
    tasks.remove(t);
    if (beforeId != null && findTask(beforeId) != null) {
      tasks.insert(tasks.indexWhere((x) => (x as Json)['id'] == beforeId), t);
    } else {
      final last = tasks.lastIndexWhere((x) => ids.contains((x as Json)['id']));
      tasks.insert(last + 1, t);
    }
    afterTasksChanged();
  }

  /// Незакрытые задачи дня src переносятся на dst одним шагом отмены.
  void pullTasks(DateTime src, DateTime dst) {
    final moved = tasksFor(src).where((t) => t['done'] != true).toList();
    for (final t in moved) {
      t['date'] = iso(dst);
      t.remove('from');
      t.remove('reminded');
      t['moves'] = ((t['moves'] as num?) ?? 0).toInt() + 1;
      addLog(t, 'перенесена на ${shortDate(dst, today)}');
    }
    if (moved.isNotEmpty) {
      afterTasksChanged();
      showUndo('Взято ${plural(moved.length, 'задача', 'задачи', 'задач')}');
    }
  }

  void clearDone() {
    final key = iso(selected);
    data['tasks'] = [for (final t in tasks) if (!((t as Json)['date'] == key && t['done'] == true)) t];
    afterTasksChanged();
  }

  // ===================== после изменений =====================
  void afterTasksChanged({bool undoable = true}) {
    invalidate();
    hideUndo();
    applyAutoUrgency();
    if (undoable) {
      commitUndo();
    } else {
      rebaseUndo();
    }
    save();
    notifyListeners();
  }

  void touch() {
    save();
    notifyListeners();
  }

  void save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), flushSave);
  }

  void flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    storage.write(data);
  }

  void flash(String text, [String color = 'accent']) {
    status.value = (text, color);
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(milliseconds: 2500), () => status.value = null);
  }

  void showUndo(String text) {
    undoBar.value = text;
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 6), hideUndo);
  }

  void hideUndo() {
    _undoTimer?.cancel();
    undoBar.value = null;
  }

  // ===================== отмена и повтор =====================
  // История хранится сжатой (как zlib в Python-версии): на 3000 задачах это мегабайты вместо сотни.
  final List<Object> histUndo = [];
  final List<Object> histRedo = [];
  String _committed = '';

  String _undoState() => jsonEncode({'tasks': data['tasks'], 'recurring': data['recurring'], 'goals': data['goals']});

  void commitUndo() {
    final st = _undoState();
    if (st != _committed) {
      histUndo.add(storage.pack(_committed));
      if (histUndo.length > undoDepth) histUndo.removeAt(0);
      histRedo.clear();
      _committed = st;
    }
  }

  /// Служебные изменения (напоминания, помидоры, перенос дня) не становятся шагом отмены.
  void rebaseUndo() => _committed = _undoState();

  void undo() => _step(histUndo, histRedo, 'Отменено', 'Нечего отменять');

  void redo() => _step(histRedo, histUndo, 'Повторено', 'Нечего повторять');

  void _step(List<Object> src, List<Object> dst, String doneText, String emptyText) {
    commitUndo();
    if (src.isEmpty) {
      flash(emptyText, 'muted');
      return;
    }
    dst.add(storage.pack(_committed));
    _committed = storage.unpack(src.removeLast());
    final restored = jsonDecode(_committed) as Json;
    data['tasks'] = restored['tasks'] ?? [];
    data['recurring'] = restored['recurring'] ?? [];
    data['goals'] = restored['goals'] ?? <String, dynamic>{};
    invalidate();
    if (s['pomo_task'] != null && findTask(s['pomo_task'] as String?) == null) s['pomo_task'] = null;
    hideUndo();
    save();
    notifyListeners();
    flash(doneText);
  }

  // ===================== цели недели =====================
  List<Json> weekGoals([DateTime? d, bool create = false]) {
    final key = weekKey(d ?? today);
    final goals = data['goals'] as Json;
    if (create) goals.putIfAbsent(key, () => []);
    return [for (final g in (goals[key] as List?) ?? const []) g as Json];
  }

  Json? findGoal(Object? id) {
    if (id == null) return null;
    for (final list in (data['goals'] as Json).values) {
      for (final g in list as List) {
        if ((g as Json)['id'] == id) return g;
      }
    }
    return null;
  }

  (int, int) goalProgress(String id) {
    final linked = tasks.where((t) => (t as Json)['goal'] == id);
    return (linked.where((t) => (t as Json)['done'] == true).length, linked.length);
  }

  String? addGoal(String text) {
    if (text.trim().isEmpty) return null;
    final key = weekKey(today);
    final goals = data['goals'] as Json;
    final list = (goals[key] as List?) ?? [];
    if (list.length >= goalsLimit) return 'не больше $goalsLimit';
    list.add(<String, dynamic>{'id': newId(), 'text': text.trim(), 'done': false});
    goals[key] = list;
    afterTasksChanged();
    return null;
  }

  void toggleGoal(String id) {
    final g = findGoal(id);
    if (g == null) return;
    g['done'] = g['done'] != true;
    afterTasksChanged();
  }

  void renameGoal(String id, String text) {
    final g = findGoal(id);
    if (g == null || text.trim().isEmpty) return;
    g['text'] = text.trim();
    afterTasksChanged();
  }

  void deleteGoal(String id) {
    for (final list in (data['goals'] as Json).values) {
      (list as List).removeWhere((g) => (g as Json)['id'] == id);
    }
    for (final t in tasks) {
      if ((t as Json)['goal'] == id) t.remove('goal');
    }
    afterTasksChanged();
  }

  void moveGoals(List<Json> goals, DateTime toDay) {
    final ids = goals.map((g) => g['id']).toSet();
    final all = data['goals'] as Json;
    final moving = [for (final list in all.values) for (final g in list as List) if (ids.contains((g as Json)['id'])) g];
    for (final list in all.values) {
      (list as List).removeWhere((g) => ids.contains((g as Json)['id']));
    }
    final key = weekKey(toDay);
    all[key] = [...((all[key] as List?) ?? const []), ...moving];
    all.removeWhere((k, v) => v is List && v.isEmpty);
    afterTasksChanged();
  }

  List<Json> prevWeekOpenGoals() => weekGoals(addDays(today, -7)).where((g) => g['done'] != true).toList();

  void carryGoals() {
    final prev = prevWeekOpenGoals();
    if (prev.isNotEmpty) moveGoals(prev, today);
  }

  // ===================== шаблоны =====================
  Json templateItem(Json t, DateTime base) {
    final td = tryIso(t['date']);
    final item = <String, dynamic>{'text': t['text'], 'offset': td == null ? 0 : daysBetween(base, td)};
    for (final k in ['priority', 'eis', 'est', 'time']) {
      if (t[k] != null) item[k] = t[k];
    }
    if (t['tags'] is List && (t['tags'] as List).isNotEmpty) item['tags'] = List.from(t['tags'] as List);
    if (t['subs'] is List && (t['subs'] as List).isNotEmpty) {
      item['subs'] = [for (final x in t['subs'] as List) (x as Map)['text']];
    }
    return item;
  }

  List<Json> get templates => [for (final x in data['templates'] as List) x as Json];

  void addTemplate(String name, List<Json> items) {
    (data['templates'] as List).add(<String, dynamic>{'id': newId(), 'name': name, 'items': items});
    touch();
    flash('шаблон «${short(name, 20)}» сохранён', 'ok');
  }

  List<Json> dayTemplateItems() => [for (final t in tasksFor(selected)) templateItem(t, selected)];

  void applyTemplate(String id) {
    final tpl = templates.where((x) => x['id'] == id).firstOrNull;
    if (tpl == null) return;
    for (final x in tpl['items'] as List) {
      final item = x as Json;
      var day = addDays(selected, (item['offset'] as num? ?? 0).toInt());
      if (day.isBefore(today)) day = today;
      final t = <String, dynamic>{'id': newId(), 'text': item['text'], 'date': iso(day), 'done': false, 'created': nowStr(_now())};
      for (final k in ['priority', 'eis', 'est', 'time']) {
        if (item[k] != null) t[k] = item[k];
      }
      if (item['tags'] is List) t['tags'] = List.from(item['tags'] as List);
      if (item['subs'] is List) {
        t['subs'] = [for (final sb in item['subs'] as List) <String, dynamic>{'id': newId(), 'text': sb, 'done': false}];
      }
      addLog(t, 'из шаблона «${tpl['name']}»');
      tasks.add(t);
    }
    afterTasksChanged();
    flash('из шаблона: ${(tpl['items'] as List).length}', 'ok');
  }

  void deleteTemplate(String id) {
    (data['templates'] as List).removeWhere((x) => (x as Json)['id'] == id);
    touch();
  }

  // ===================== события и заметки =====================
  List<Json> get events {
    final list = [for (final e in data['events'] as List) e as Json];
    list.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    return list;
  }

  String? addEvent(String raw) {
    final m = eventRe.firstMatch(raw.trim());
    if (m == null) return 'Формат: «Отпуск 15.11» или «Дедлайн 01.12.2026»';
    final title = m[1]!.trim();
    final day = int.parse(m[2]!), mon = int.parse(m[3]!);
    DateTime d;
    if (m[4] != null) {
      final y = int.parse(m[4]!) + (m[4]!.length == 2 ? 2000 : 0);
      if (!validDate(y, mon, day)) return 'Такой даты нет';
      d = DateTime(y, mon, day);
    } else {
      if (!validDate(today.year, mon, day) && !validDate(today.year + 1, mon, day)) return 'Такой даты нет';
      d = validDate(today.year, mon, day) ? DateTime(today.year, mon, day) : DateTime(today.year + 1, mon, day);
      if (d.isBefore(today) && validDate(today.year + 1, mon, day)) d = DateTime(today.year + 1, mon, day);
    }
    if (d.isBefore(today)) return 'Эта дата уже прошла';
    (data['events'] as List).add(<String, dynamic>{'id': newId(), 'title': title, 'date': iso(d)});
    touch();
    return null;
  }

  void deleteEvent(String id) {
    (data['events'] as List).removeWhere((e) => (e as Json)['id'] == id);
    touch();
  }

  void setNotes(String text) {
    data['notes'] = text;
    save();
  }

  // ===================== производственный календарь =====================
  Future<void> fetchProdcal(int year) async {
    if (s['prod_cal'] != true || (data['prodcal'] as Json).containsKey('$year') || _fetching.contains(year)) return;
    if (!Storage.persistent || !network) return;
    _fetching.add(year);
    try {
      final txt = await storage.fetchText('https://isdayoff.ru/api/getdata?year=$year&cc=ru&pre=1');
      if (txt != null && RegExp(r'^[0-9]{365,366}$').hasMatch(txt)) {
        (data['prodcal'] as Json)['$year'] = txt;
        save();
        final before = holdIso;
        updateHold();
        if (before.length != holdIso.length) carryOverTasks();
        notifyListeners();
      }
    } catch (e) {
      storage.logError('Производственный календарь $year не загрузился: $e');
    } finally {
      _fetching.remove(year);
    }
  }

  // ===================== календарь =====================
  void selectDay(DateTime d) {
    selected = dayOnly(d);
    viewMonth = DateTime(d.year, d.month);
    fetchProdcal(d.year);
    notifyListeners();
  }

  void shiftMonth(int delta) {
    viewMonth = DateTime(viewMonth.year, viewMonth.month + delta);
    fetchProdcal(viewMonth.year);
    notifyListeners();
  }

  void goToday() => selectDay(today);

  // ===================== помодоро =====================
  String pomoMode = 'work'; // work | break | long
  bool pomoRunning = false;
  DateTime pomoEnd = DateTime.now();
  int? _pomoLeft;
  bool focusSuppressed = false;

  int pomoMinutes(String mode) => ((s[mode == 'work' ? 'work' : mode == 'break' ? 'break' : 'long'] as num?) ?? 25).toInt();

  int get pomoLeft {
    if (pomoRunning) return math.max(0, (pomoEnd.difference(_now()).inMilliseconds / 1000).round());
    return _pomoLeft ?? pomoMinutes(pomoMode) * 60;
  }

  String get pomoClock {
    final l = pomoLeft;
    return '${two(l ~/ 60)}:${two(l % 60)}';
  }

  String get pomoModeName => const {'work': 'Фокус', 'break': 'Перерыв', 'long': 'Длинный перерыв'}[pomoMode]!;

  bool get focusActive => pomoRunning && pomoMode == 'work' && s['focus_mode'] == true && !focusSuppressed;

  Json cycleCount() {
    final c = data['pomo_cycle'] as Json;
    if (c['date'] != iso(today)) {
      c
        ..clear()
        ..['date'] = iso(today)
        ..['n'] = 0;
    }
    return c;
  }

  int get pomosToday => ((data['pomodoros'] as Json)[iso(today)] as num? ?? 0).toInt();

  void pomoToggle() {
    if (pomoRunning) {
      _pomoLeft = pomoLeft;
      pomoRunning = false;
    } else {
      pomoEnd = _now().add(Duration(seconds: pomoLeft));
      pomoRunning = true;
    }
    notifyListeners();
  }

  void pomoReset() {
    pomoRunning = false;
    _pomoLeft = pomoMinutes(pomoMode) * 60;
    focusSuppressed = false;
    notifyListeners();
  }

  void pomoSkip() {
    pomoMode = pomoMode == 'work' ? 'break' : 'work';
    pomoReset();
  }

  void exitFocus() {
    focusSuppressed = true;
    notifyListeners();
  }

  void linkPomo(String? id) {
    s['pomo_task'] = id;
    save();
    if (id != null && !pomoRunning) {
      pomoMode = 'work';
      pomoReset();
      pomoToggle();
    }
    notifyListeners();
  }

  void pomoFinish() {
    if (pomoMode == 'work') {
      final key = iso(today);
      final pomos = data['pomodoros'] as Json;
      pomos[key] = ((pomos[key] as num?) ?? 0).toInt() + 1;
      final t = findTask(s['pomo_task'] as String?);
      final minutes = pomoMinutes('work');
      if (t != null) {
        t['pomos'] = ((t['pomos'] as num?) ?? 0).toInt() + 1;
        t['spent'] = ((t['spent'] as num?) ?? 0).toInt() + minutes;
      }
      (data['pomo_log'] as List).add(<String, dynamic>{
        'date': key, 'task': t?['id'], 'text': t?['text'] ?? '', 'min': minutes,
        'tags': t != null ? List.from((t['tags'] as List?) ?? const []) : [],
      });
      rebaseUndo();
      final c = cycleCount();
      c['n'] = ((c['n'] as num?) ?? 0).toInt() + 1;
      pomoMode = (c['n'] as int) % math.max(1, (s['cycle'] as num? ?? 4).toInt()) == 0 ? 'long' : 'break';
      save();
      pomoReset();
      final title = pomoMode == 'long' ? 'Длинный перерыв' : 'Перерыв';
      _notices.add(Notice('$title: ${pomoMinutes(pomoMode)} мин', 'Помидор готов. Отдохните.', kind: 'rest', sound: 'work'));
      if (s['auto_break'] == true) pomoToggle();
    } else {
      pomoMode = 'work';
      pomoReset();
      _notices.add(Notice('Перерыв закончился', 'Можно начинать следующий помидор.', sound: 'break'));
    }
  }

  void setPomo({int? work, int? brk, int? long, int? cycle}) {
    if (work != null) s['work'] = work;
    if (brk != null) s['break'] = brk;
    if (long != null) s['long'] = long;
    if (cycle != null) s['cycle'] = cycle;
    save();
    if (!pomoRunning) pomoReset();
    notifyListeners();
  }

  /// Во сколько раз факт (по помидорам) больше оценки — по выполненным задачам, если их ≥ 3.
  double? estRatio() {
    final pairs = [
      for (final x in tasks)
        if ((x as Json)['done'] == true && x['est'] is num && x['spent'] is num && (x['est'] as num) > 0)
          (x['spent'] as num, x['est'] as num),
    ];
    if (pairs.length < 3) return null;
    return pairs.fold<num>(0, (a, p) => a + p.$1) / pairs.fold<num>(0, (a, p) => a + p.$2);
  }

  // ===================== напоминания =====================
  void checkReminders(DateTime now) {
    final t0 = iso(today);
    for (final x in List.of(tasks)) {
      final t = x as Json;
      if (t['done'] == true) continue;
      if (t['snooze'] != null) {
        final at = DateTime.tryParse('${t['snooze']}');
        if (at != null && !now.isBefore(at)) {
          t.remove('snooze');
          rebaseUndo();
          save();
          _notices.add(Notice('Напоминание', t['text'] as String, kind: 'remind', taskId: t['id'] as String));
        }
        continue;
      }
      if (t['date'] != t0 || t['time'] == null || t['reminded'] == t['time']) continue;
      final hm = (t['time'] as String).split(':').map(int.parse).toList();
      final due = DateTime(today.year, today.month, today.day, hm[0], hm[1]);
      if (!now.isBefore(due.subtract(const Duration(minutes: remindBefore)))) {
        t['reminded'] = t['time'];
        rebaseUndo();
        save();
        if (!now.isAfter(due.add(const Duration(minutes: 1)))) {
          final mins = math.max(0, due.difference(now).inSeconds ~/ 60);
          final when = mins == 0 ? 'Сейчас' : 'Через ${plural(mins, 'минуту', 'минуты', 'минут')}';
          _notices.add(Notice('$when, ${t['time']}', t['text'] as String, kind: 'remind', taskId: t['id'] as String));
        }
      }
    }
  }

  void snooze(String id, int minutes) {
    final t = findTask(id);
    if (t == null) return;
    final at = _now().add(Duration(minutes: minutes));
    t['snooze'] = '${iso(at)}T${two(at.hour)}:${two(at.minute)}';
    rebaseUndo();
    save();
  }

  void snoozeTomorrow(String id) {
    final t = findTask(id);
    if (t == null) return;
    final d = tryIso(t['date']) ?? today;
    final tomorrow = addDays(today, 1);
    moveTaskDate(id, d.isAfter(tomorrow) ? d : tomorrow);
  }

  // ===================== обзоры =====================
  bool carried(Json t) =>
      t['date'] == iso(today) && t['done'] != true && '${t['from'] ?? iso(today)}'.compareTo(iso(today)) < 0;

  /// Разбор хвостов ждёт, пока интерфейс будет готов его показать.
  bool pendingMorningReview = false;

  void maybeMorningReview() {
    final t0 = iso(today);
    if (s['review'] == false || s['review_date'] == t0) return;
    s['review_date'] = t0;
    save();
    if (tasks.any((t) => carried(t as Json))) {
      pendingMorningReview = true;
      _reviews.add('morning');
    }
  }

  void maybeWeeklyReview(DateTime now) {
    if (s['weekly_review'] == false || wd(now) != 4 || now.hour < 15) return;
    final wk = weekKey(today);
    if (s['review_week'] == wk) return;
    s['review_week'] = wk;
    save();
    _reviews.add('weekly');
  }

  // ===================== настройки =====================
  void setSetting(String key, Object? value) {
    s[key] = value;
    save();
    notifyListeners();
  }

  /// Числовая настройка; длительности помодоро сразу сбрасывают остановленный таймер.
  void setPomoOrSetting(String key, int value) {
    if (const ['work', 'break', 'long', 'cycle'].contains(key)) {
      s[key] = value;
      save();
      if (!pomoRunning) pomoReset();
      notifyListeners();
    } else {
      setSetting(key, value);
    }
  }

  bool collapsed(String key) => (s['collapsed'] as Map)[key] == true;

  void toggleCollapsed(String key) {
    (s['collapsed'] as Map)[key] = !collapsed(key);
    save();
    notifyListeners();
  }

  List<String> get visibleBlocks => [
        for (final k in (s['order'] as List)) if (!((s['hidden_blocks'] as List).contains(k))) k as String,
      ];

  void setBlockHidden(String key, bool hidden) {
    final list = s['hidden_blocks'] as List;
    list.remove(key);
    if (hidden) list.add(key);
    touch();
  }

  void moveBlock(String key, int delta) {
    final order = s['order'] as List;
    final i = order.indexOf(key);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= order.length) return;
    order
      ..removeAt(i)
      ..insert(j, key);
    touch();
  }

  // ===================== статистика =====================
  /// Помидоры за 7 дней: по задачам или по меткам.
  List<(String, int)> pomoStats() {
    final since = iso(addDays(today, -6));
    final by = s['stats_by'] ?? 'task';
    final counts = <String, int>{};
    for (final x in data['pomo_log'] as List) {
      final e = x as Json;
      if ('${e['date']}'.compareTo(since) < 0) continue;
      final keys = by == 'task'
          ? ['${(e['text'] as String?)?.isNotEmpty == true ? e['text'] : 'без задачи'}']
          : [for (final g in (e['tags'] as List?) ?? const []) '#$g'];
      for (final k in keys.isEmpty ? ['без метки'] : keys) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final list = counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2 - a.$2);
    return list.take(5).toList();
  }

  /// Выполнено задач и помидоров по дням за последние 7 дней.
  List<(DateTime, int, int)> weekChart() {
    final days = [for (var i = 0; i < 7; i++) addDays(today, i - 6)];
    final done = {for (final d in days) iso(d): 0};
    for (final x in tasks) {
      final t = x as Json;
      if (t['done'] == true) {
        final key = '${t['done_at'] ?? t['date']}';
        if (done.containsKey(key)) done[key] = done[key]! + 1;
      }
    }
    final pom = data['pomodoros'] as Json;
    return [for (final d in days) (d, done[iso(d)]!, ((pom[iso(d)] as num?) ?? 0).toInt())];
  }

  List<String> allTags() {
    final set = <String>{};
    for (final t in tasks) {
      for (final g in ((t as Json)['tags'] as List?) ?? const []) {
        set.add('$g');
      }
    }
    return set.toList()..sort();
  }

  // ===================== архив =====================
  /// Раз в месяц выполненные задачи старше 30 дней переезжают из data.json в archive.json.
  /// В рабочем файле остаётся не больше двух месяцев сделанного — панель не тяжелеет с годами.
  void archiveMonthly({bool force = false}) {
    final month = iso(today).substring(0, 7);
    if (!force && s['archive_month'] == month) return;
    final cutoff = iso(addDays(today, -30));
    bool old(Json t) => t['done'] == true && '${t['date'] ?? t['done_at'] ?? ''}'.compareTo(cutoff) < 0;
    final out = [for (final t in tasks) if (old(t as Json)) t];
    if (out.isNotEmpty) {
      _arch = null;
      if (!storage.appendArchive(out)) return; // не записали архив — ничего не трогаем, попробуем завтра
      data['tasks'] = [for (final t in tasks) if (!old(t as Json)) t];
      invalidate();
    }
    s['archive_month'] = month;
    s['archive_count'] = ((s['archive_count'] as num?) ?? 0).toInt() + out.length;
    save();
  }

  /// Поиск по архиву: файл читается только здесь. Новые сверху.
  List<dynamic>? _arch;

  List<Json> searchArchive(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    final found = [
      for (final x in _arch ??= storage.readArchive())
        if (x is Map && words.every(_hay(x as Json).contains)) x,
    ];
    return stableSorted(found, (a, b) => '${b['date']}'.compareTo('${a['date']}'));
  }

  /// Задача из архива — снова в работу: копия на сегодня.
  void repeatFromArchive(Json t) {
    final n = newTask('${t['text']}', date: today);
    for (final k in ['tags', 'est', 'priority', 'note']) {
      if (t[k] != null) n[k] = jsonDecode(jsonEncode(t[k]));
    }
    tasks.add(n);
    afterTasksChanged();
    flash('Добавлена на сегодня', 'ok');
  }

  String _hay(Json t) => [
        t['text'], t['note'] ?? '',
        for (final x in (t['subs'] as List?) ?? const []) (x as Map)['text'],
        for (final g in (t['tags'] as List?) ?? const []) '#$g',
      ].join('\n').toLowerCase();

  // ===================== GTD =====================
  /// Раздел в режиме окна: 'panel' — обычная панель, иначе раздел GTD.
  String gtdView = 'panel';

  void setGtdView(String v) {
    gtdView = v;
    notifyListeners();
  }

  List<Json> gtdList(String list) => stableSorted(
        [for (final t in tasks) if ((t as Json)['list'] == list && t['done'] != true) t],
        (a, b) => '${a['created'] ?? ''}'.compareTo('${b['created'] ?? ''}'),
      );

  int get inboxCount => tasks.where((t) => (t as Json)['list'] == 'inbox' && t['done'] != true).length;

  /// Задача во входящие: без даты. Метки, @контексты, оценку и дедлайн разбираем, дату — нет.
  Json addInbox(String raw) {
    final q = parseQuick(raw, today, allowDate: false);
    final t = <String, dynamic>{
      'id': newId(), 'text': q.text.isEmpty ? raw.trim() : q.text, 'done': false,
      'list': 'inbox', 'created': nowStr(_now()),
    };
    if (q.prio) t['priority'] = 'high';
    if (q.eis != null) t['eis'] = q.eis;
    applyExtras(t, Extras(q.tags, q.est, q.deadline), replace: false);
    addLog(t, 'во входящие');
    tasks.add(t);
    afterTasksChanged();
    return t;
  }

  void addInboxLines(List<String> lines) {
    for (final l in lines) {
      final q = parseQuick(l, today, allowDate: false);
      final t = <String, dynamic>{'id': newId(), 'text': q.text.isEmpty ? l : q.text, 'done': false, 'list': 'inbox', 'created': nowStr(_now())};
      applyExtras(t, Extras(q.tags, q.est, q.deadline), replace: false);
      tasks.add(t);
    }
    afterTasksChanged();
    flash('во входящие: ${lines.length}', 'ok');
  }

  /// Перевести задачу в GTD-список (без даты). list == null — вернуть в календарь на выбранный день.
  void setList(String id, String? list) {
    final t = findTask(id);
    if (t == null) return;
    if (list == null) {
      _leaveList(t);
      if (t['date'] is String) {
        afterTasksChanged();
      } else {
        moveTaskDate(id, selected);
      }
      return;
    }
    t['list'] = list;
    for (final k in ['date', 'from', 'reminded', 'snooze', 'carries']) {
      t.remove(k);
    }
    if (list != 'waiting') {
      t.remove('waiting_for');
      t.remove('waiting_since');
    }
    addLog(t, 'в список «${gtdLists[list]}»');
    afterTasksChanged();
  }

  void _leaveList(Json t) {
    if (t.remove('list') != null) {
      t.remove('waiting_for');
      t.remove('waiting_since');
    }
  }

  void delegate(String id, String who) {
    final t = findTask(id);
    if (t == null) return;
    setList(id, 'waiting');
    t['waiting_for'] = who.trim();
    t['waiting_since'] = iso(today);
    addLog(t, 'делегирована: ${who.trim()}');
    afterTasksChanged();
  }

  List<String> contexts() {
    final set = <String>{'@компьютер', '@телефон', '@дом', '@город'};
    for (final t in tasks) {
      for (final g in ((t as Json)['tags'] as List?) ?? const []) {
        if ('$g'.startsWith('@')) set.add('$g');
      }
    }
    return set.toList()..sort();
  }

  void toggleContext(String id, String ctx) {
    final t = findTask(id);
    if (t == null) return;
    final tags = [for (final g in (t['tags'] as List?) ?? const []) '$g'];
    if (tags.contains(ctx)) {
      tags.remove(ctx);
    } else {
      tags.add(ctx);
    }
    if (tags.isEmpty) {
      t.remove('tags');
    } else {
      t['tags'] = tags;
    }
    afterTasksChanged();
  }

  // ---- проекты ----
  List<Json> get projects => [for (final p in (data['projects'] as List?) ?? const []) p as Json];

  List<Json> projectsBy(String status) => projects.where((p) => (p['status'] ?? 'active') == status).toList();

  Json? findProject(Object? id) => id == null ? null : projects.where((p) => p['id'] == id).firstOrNull;

  String addProject(String title, {String status = 'active'}) {
    final p = <String, dynamic>{'id': newId(), 'title': title.trim(), 'status': status, 'created': nowStr(_now())};
    ((data['projects'] as List?) ?? (data['projects'] = [])).add(p);
    afterTasksChanged();
    return p['id'] as String;
  }

  void renameProject(String id, String title) {
    final p = findProject(id);
    if (p == null || title.trim().isEmpty) return;
    p['title'] = title.trim();
    afterTasksChanged();
  }

  void setProjectStatus(String id, String status) {
    final p = findProject(id);
    if (p == null) return;
    p['status'] = status;
    if (status == 'done') {
      p['done_at'] = iso(today);
    } else {
      p.remove('done_at');
    }
    afterTasksChanged();
  }

  void deleteProject(String id) {
    (data['projects'] as List?)?.removeWhere((p) => (p as Json)['id'] == id);
    for (final t in tasks) {
      if ((t as Json)['project'] == id) t.remove('project');
    }
    afterTasksChanged();
  }

  List<Json> projectTasks(String id) => [for (final t in tasks) if ((t as Json)['project'] == id) t];

  /// Незакрытые шаги проекта: и без даты, и в календаре.
  List<Json> projectOpen(String id) => projectTasks(id).where((t) => t['done'] != true).toList();

  bool projectStuck(String id) => projectOpen(id).isEmpty;

  void addProjectAction(String projectId, String raw) {
    if (raw.trim().isEmpty) return;
    final q = parseQuick(raw, today);
    final t = newTask(raw, date: q.date == null ? today : null);
    if (q.date == null) {
      t.remove('date');
      t['list'] = 'next';
    }
    t['project'] = projectId;
    tasks.add(t);
    afterTasksChanged();
  }

  /// Задача превращается в проект: название проекта — текст задачи, сама задача удаляется.
  String taskToProject(String id) {
    final t = findTask(id);
    final pid = addProject('${t?['text'] ?? 'Новый проект'}');
    if (t != null) {
      tasks.remove(t);
      afterTasksChanged();
    }
    return pid;
  }

  void gtdReviewDone() => setSetting('gtd_review_week', weekKey(today));

  List<Json> search(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    final found = [for (final t in tasks) if (words.every(_hay(t as Json).contains)) t as Json];
    found.sort((a, b) {
      final d = (a['done'] == true ? 1 : 0) - (b['done'] == true ? 1 : 0);
      return d != 0 ? d : '${a['date']}'.compareTo('${b['date']}');
    });
    return found;
  }
}

/// Устойчивая сортировка: равные элементы сохраняют исходный порядок (List.sort в Dart этого не обещает).
List<T> stableSorted<T>(List<T> list, int Function(T, T) cmp) {
  final idx = List<int>.generate(list.length, (i) => i);
  idx.sort((a, b) {
    final c = cmp(list[a], list[b]);
    return c != 0 ? c : a - b;
  });
  return [for (final i in idx) list[i]];
}
