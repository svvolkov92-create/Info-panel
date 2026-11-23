// Прототип информационной панели на Flutter: только внешний вид и поведение интерфейса.
// Данные тестовые и живут в памяти; сохранения нет.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

// На Windows (и других ПК) панель — виджет без рамки; в браузере — обычная страница-витрина.
final bool isDesktop = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

// Настройки вида. Хранятся в SharedPreferences (на Windows — в реестре пользователя).
class Settings extends ChangeNotifier {
  double scale = 0.85;
  bool compact = true;
  double opacity = 1.0;
  String layer = 'normal'; // normal / top / bottom
  Set<String> hidden = {};
  Rect? bounds;
  SharedPreferences? _prefs;

  static const blocks = {
    'calendar': 'Календарь',
    'goals': 'Цели недели',
    'future': 'Будущие задачи',
    'week': 'Неделя',
    'pomo': 'Фокус',
  };

  Future<void> load() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      scale = p.getDouble('scale') ?? scale;
      compact = p.getBool('compact') ?? compact;
      opacity = p.getDouble('opacity') ?? opacity;
      layer = p.getString('layer') ?? layer;
      hidden = (p.getStringList('hidden') ?? []).toSet();
      final b = p.getStringList('bounds');
      if (b != null && b.length == 4) {
        final v = b.map(double.tryParse).toList();
        if (!v.contains(null)) bounds = Rect.fromLTWH(v[0]!, v[1]!, v[2]!, v[3]!);
      }
    } catch (e) {
      debugPrint('settings load failed: $e'); // без сохранённых настроек панель работает с умолчаниями
    }
  }

  void update(void Function(Settings s) f) {
    f(this);
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    p.setDouble('scale', scale);
    p.setBool('compact', compact);
    p.setDouble('opacity', opacity);
    p.setString('layer', layer);
    p.setStringList('hidden', hidden.toList());
  }

  void saveBounds(Rect r) {
    bounds = r;
    _prefs?.setStringList('bounds', [r.left, r.top, r.width, r.height].map((x) => x.toString()).toList());
  }
}

final settings = Settings();

Future<void> applyWindowLayer() async {
  if (!isDesktop) return;
  await windowManager.setAlwaysOnTop(settings.layer == 'top');
  await windowManager.setAlwaysOnBottom(settings.layer == 'bottom');
  await windowManager.setOpacity(settings.opacity);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(340, 860),
      minimumSize: Size(240, 260),
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: P.panel,
      title: 'Информационная панель',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      final b = settings.bounds;
      if (b != null) {
        await windowManager.setBounds(b);
      } else {
        await windowManager.setAlignment(Alignment.topRight);
      }
      await applyWindowLayer();
      await windowManager.show();
    });
  }
  runApp(const ProtoApp());
}

// Масштаб всего интерфейса: раскладываем в увеличенной «логической» области и сжимаем при отрисовке.
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

// Палитра текущей панели (panel/core.py), чтобы сравнивать с Tkinter один в один.
class P {
  static const bg = Color(0xFF16171B);
  static const panel = Color(0xFF1E1F24);
  static const card = Color(0xFF272830);
  static const hover = Color(0xFF30323C);
  static const fg = Color(0xFFE6E6EB);
  static const muted = Color(0xFF8B8D98);
  static const faint = Color(0xFF55576A);
  static const accent = Color(0xFF7AA2F7);
  static const warn = Color(0xFFE0AF68);
  static const ok = Color(0xFF9ECE6A);
  static const danger = Color(0xFFF7768E);
  static const rest = Color(0xFFBB9AF7);
}

Color mix(Color a, Color b, double k) => Color.lerp(a, b, k)!;

const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
  'сентября', 'октября', 'ноября', 'декабря'];
const monthsNom = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август',
  'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const wdShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
const wdFull = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];

const eisNames = {
  'q1': ('Сделать сейчас', P.danger),
  'q2': ('Запланировать', P.accent),
  'q3': ('Делегировать', P.warn),
  'q4': ('Отложить', P.muted),
};

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String ddmm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
String fmtEst(int m) => m < 60 ? '$m мин' : '${(m / 60).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} ч';
String plural(int n, String one, String few, String many) {
  if (n % 10 == 1 && n % 100 != 11) return '$n $one';
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) return '$n $few';
  return '$n $many';
}

class Sub {
  Sub(this.text, [this.done = false]);
  String text;
  bool done;
}

class Task {
  Task(this.text, this.date,
      {this.time, this.eis, this.est = 0, this.tags = const [], this.deadline, this.note = '',
      List<Sub>? subs, this.carriedFrom, this.priority})
      : subs = subs ?? [];
  String text;
  DateTime date;
  String? time;
  String? eis;
  int est;
  List<String> tags;
  DateTime? deadline;
  String note;
  List<Sub> subs;
  DateTime? carriedFrom;
  String? priority; // high / mid / low
  bool done = false;
}

final today = dayOnly(DateTime.now());
DateTime plus(int days) => today.add(Duration(days: days));

List<Task> demoTasks() => [
      Task('Квартальный отчёт', today, time: '10:00', eis: 'q1', est: 240, tags: ['работа'],
          deadline: plus(4), priority: 'high',
          note: 'Шаблон прошлого квартала лежит в папке «Отчёты». Цифры по отделам — у Марины.',
          subs: [Sub('Выгрузка из 1С', true), Sub('Сводная по отделам'), Sub('Комментарий директору')]),
      Task('Договор юристам', today, eis: 'q1', est: 90, tags: ['работа'], priority: 'mid'),
      Task('Сверить счета за октябрь', today, carriedFrom: plus(-3)),
      Task('Купить билеты в Казань', today, est: 30, tags: ['дом']),
      Task('Созвон с Олей', today, time: '19:00'),
      Task('Разобрать почту', today)..done = true,
      Task('Позвонить родителям', plus(1)),
      Task('Встреча с подрядчиком', plus(2), time: '10:00', est: 60),
      Task('Оплатить хостинг', plus(2), deadline: plus(2)),
      Task('Записаться к стоматологу', plus(3), eis: 'q2'),
      Task('План на декабрь', plus(4), eis: 'q2', est: 120),
      Task('Обновить резюме', plus(4), est: 180),
      Task('Еженедельный отчёт', plus(4), est: 120, deadline: plus(4)),
      Task('Подарок к Новому году', plus(9)),
    ];

// Разбор быстрого ввода — упрощённая копия parse_quick, чтобы показать «фишки».
class Parsed {
  final List<(String, Color)> chips = [];
  String title = '';
}

Parsed parseQuick(String raw) {
  final p = Parsed();
  var rest = ' $raw ';
  void take(RegExp re, (String, Color) Function(Match) chip) {
    rest = rest.replaceAllMapped(re, (m) {
      p.chips.add(chip(m));
      return ' ';
    });
  }

  const wd = {'пн': 0, 'вт': 1, 'ср': 2, 'чт': 3, 'пт': 4, 'сб': 5, 'вс': 6};
  take(RegExp(r' до (\d{1,2}\.\d{1,2}|пн|вт|ср|чт|пт|сб|вс)(?= )'), (m) => ('до ${m[1]}', P.warn));
  take(RegExp(r' (\d{1,2})\.(\d{1,2})(?= )'), (m) => ('${m[1]!.padLeft(2, '0')}.${m[2]!.padLeft(2, '0')}', P.accent));
  take(RegExp(r' (пн|вт|ср|чт|пт|сб|вс|завтра)(?= )'), (m) {
    if (m[1] == 'завтра') return ('завтра', P.accent);
    var n = (wd[m[1]]! - today.weekday + 1) % 7;
    if (n == 0) n = 7;
    final d = plus(n);
    return ('${wdShort[d.weekday - 1]} ${ddmm(d)}', P.accent);
  });
  take(RegExp(r' (\d{1,2}:\d{2})(?= )'), (m) => (m[1]!, P.accent));
  take(RegExp(r' !!([1-4])(?= )'), (m) => (eisNames['q${m[1]}']!.$1, eisNames['q${m[1]}']!.$2));
  take(RegExp(r' ~(\d+)(м|мин|ч)(?= )'), (m) {
    final n = int.parse(m[1]!);
    return (fmtEst(m[2] == 'ч' ? n * 60 : n), P.muted);
  });
  take(RegExp(r' #(\S+)(?= )'), (m) => ('#${m[1]}', P.rest));
  p.title = rest.trim().replaceAll(RegExp(r'\s+'), ' ');
  return p;
}

class ProtoApp extends StatelessWidget {
  const ProtoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: settings, builder: (context, _) => MaterialApp(
      title: 'Информационная панель — прототип',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Scaled(scale: settings.scale, child: child!),
      theme: ThemeData(
        brightness: Brightness.dark,
        visualDensity: settings.compact ? VisualDensity.compact : VisualDensity.standard,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: P.bg,
        colorScheme: const ColorScheme.dark(primary: P.accent, surface: P.card),
        tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
      ),
      home: const Home(),
    ));
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WindowListener {
  final tasks = demoTasks();
  DateTime selected = today;
  final collapsed = <String>{};
  late Timer clock;
  DateTime now = DateTime.now();
  int pomoLeft = 25 * 60;
  bool pomoRunning = false;

  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        now = DateTime.now();
        if (pomoRunning && pomoLeft > 0) pomoLeft--;
      });
    });
    if (isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    clock.cancel();
    if (isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _rememberBounds() async => settings.saveBounds(await windowManager.getBounds());

  @override
  void onWindowMoved() => _rememberBounds();

  @override
  void onWindowResized() => _rememberBounds();

  double get gap => settings.compact ? 6 : 10;

  List<Task> tasksOn(DateTime d) => tasks.where((t) => t.date == d).toList();
  int hoursLoad(DateTime d) => tasksOn(d).where((t) => !t.done).fold(0, (s, t) => s + t.est);

  void toast(String text, VoidCallback undo) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(color: P.fg)),
      backgroundColor: P.hover,
      behavior: SnackBarBehavior.floating,
      width: isDesktop ? null : 360,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Отменить', textColor: P.accent, onPressed: () => setState(undo)),
    ));
  }

  void toggle(Task t) {
    setState(() => t.done = !t.done);
    if (t.done) toast('Выполнена «${t.text}»', () => t.done = false);
  }

  void remove(Task t) {
    final i = tasks.indexOf(t);
    setState(() => tasks.remove(t));
    toast('Удалена «${t.text}»', () => tasks.insert(i, t));
  }

  void moveNext(Task t) {
    final old = t.date;
    setState(() => t.date = (t.date.isBefore(today) ? today : t.date).add(const Duration(days: 1)));
    toast('Перенесена на ${futureLabel(t.date)}', () => t.date = old);
  }

  void addTask(String raw) {
    final p = parseQuick(raw);
    if (p.title.isEmpty) return;
    setState(() => tasks.add(Task(p.title, selected)));
  }

  void openCard(Task t) {
    showDialog(context: context, builder: (_) => TaskCard(task: t, onChanged: () => setState(() {})));
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      // виджет: панель на всё окно, снизу справа — уголок для изменения размера
      return Scaffold(
        backgroundColor: P.panel,
        body: Stack(children: [
          Positioned.fill(child: _panel()),
          Positioned(
            right: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: GestureDetector(
                onPanStart: (_) => windowManager.startResizing(ResizeEdge.bottomRight),
                child: const SizedBox(
                    width: 16, height: 16, child: Icon(Icons.south_east, size: 11, color: P.faint)),
              ),
            ),
          ),
        ]),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final panel = SizedBox(width: 400, child: _panel());
    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.all(20), child: panel),
                Expanded(child: _showcase()),
              ])
            : Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: panel)),
      ),
    );
  }

  // Справа — то, что в панели открывается отдельными окнами.
  Widget _showcase() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 20, 24, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Прототип на Flutter', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text(
            'Слева — панель как на рабочем столе. Наведите на задачу, чтобы увидеть заметку и подзадачи; '
            'щёлкните — откроется карточка. «?» в поле ввода — шпаргалка.',
            style: TextStyle(color: P.muted, height: 1.4)),
        const SizedBox(height: 20),
        WeekWindow(tasks: tasks, onOpen: openCard),
      ]),
    );
  }

  Widget _panel() {
    final r = isDesktop ? 0.0 : 14.0;
    return Container(
      decoration: BoxDecoration(
        color: P.panel,
        borderRadius: BorderRadius.circular(r),
        boxShadow: isDesktop
            ? null
            : const [BoxShadow(color: Color(0x88000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: ListView(padding: EdgeInsets.fromLTRB(gap + 2, gap + 4, gap + 2, gap + 2), children: [
          _clock(),
          SizedBox(height: gap),
          if (!settings.hidden.contains('calendar')) _block('calendar', 'Календарь', _calendar(),
              summary: '${today.day} ${months[today.month - 1]}, ${wdShort[today.weekday - 1]}'),
          if (!settings.hidden.contains('goals')) _block('goals', 'Цели недели', _goals(), trailing: const Text('1/3', style: TextStyle(color: P.muted, fontSize: 12))),
          _block('tasks', '', TasksBlock(state: this)),
          if (!settings.hidden.contains('future')) _block('future', 'Будущие задачи', _future(),
              trailing: Text('${tasks.where((t) => t.date.isAfter(today) && !t.done).length}',
                  style: const TextStyle(color: P.muted, fontSize: 12))),
          if (!settings.hidden.contains('week'))
            _block('week', 'Неделя', WeekStrip(tasks: tasks),
                trailing: InkWell(
                  onTap: _openWeek,
                  child: const Padding(
                      padding: EdgeInsets.all(2), child: Icon(Icons.open_in_full, size: 14, color: P.muted)),
                )),
          if (!settings.hidden.contains('pomo')) _block('pomo', 'Фокус', _pomo(),
              titleColor: P.accent, summary: '${_clockText(pomoLeft)}${pomoRunning ? '' : ', пауза'}'),
        ]),
      ),
    );
  }

  String _clockText(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _openWeek() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: WeekWindow(tasks: tasks, onOpen: openCard)),
      ),
    );
  }

  Widget _headerButton(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 16, color: P.muted)),
        ),
      );

  Widget _clock() {
    final hh = now.hour.toString().padLeft(2, '0'), mm = now.minute.toString().padLeft(2, '0');
    final head = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$hh:$mm',
                style: TextStyle(fontSize: settings.compact ? 32 : 44, fontWeight: FontWeight.w300, height: 1)),
            SizedBox(height: settings.compact ? 3 : 6),
            Text('${wdFull[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}',
                style: const TextStyle(color: P.muted, fontSize: 12)),
          ]),
        ),
        _headerButton(Icons.tune, 'Настройки вида', () => showDialog(context: context, builder: (_) => const SettingsDialog())),
        if (isDesktop) _headerButton(Icons.close, 'Закрыть панель', () => windowManager.close()),
      ]),
    );
    if (!isDesktop) return head;
    // за шапку с часами виджет перетаскивается по экрану
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(onPanStart: (_) => windowManager.startDragging(), child: head),
    );
  }

  Widget _block(String key, String title, Widget body,
      {Widget? trailing, String? summary, Color titleColor = P.fg}) {
    final shut = collapsed.contains(key);
    return Container(
      margin: EdgeInsets.only(bottom: gap),
      padding: settings.compact ? const EdgeInsets.fromLTRB(10, 5, 10, 7) : const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title.isNotEmpty)
          InkWell(
            onTap: () => setState(() => shut ? collapsed.remove(key) : collapsed.add(key)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                AnimatedRotation(
                    turns: shut ? -0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 18, color: P.muted)),
                const SizedBox(width: 4),
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: titleColor)),
                const Spacer(),
                if (shut && summary != null) Text(summary, style: const TextStyle(color: P.muted, fontSize: 12)),
                if (!shut && trailing != null) trailing,
              ]),
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: shut && title.isNotEmpty ? const SizedBox(width: double.infinity) : body,
        ),
      ]),
    );
  }

  // ---------- календарь с нагрузкой ----------
  Widget _calendar() {
    final first = DateTime(today.year, today.month, 1);
    final lead = first.weekday - 1;
    final daysIn = DateTime(today.year, today.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < 7; i++)
        Center(
            child: Text(['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][i],
                style: TextStyle(fontSize: 11, color: i > 4 ? P.danger : P.muted))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var n = 1; n <= daysIn; n++) _calDay(DateTime(today.year, today.month, n)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(children: [
        Text('${monthsNom[today.month - 1]} ${today.year}', style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.35,
          children: cells,
        ),
      ]),
    );
  }

  Widget _calDay(DateTime d) {
    final dayTasks = tasksOn(d).where((t) => !t.done).toList();
    final deadline = tasks.any((t) => t.deadline == d && !t.done);
    final isToday = d == today, isSel = d == selected, weekend = d.weekday > 5;
    final n = dayTasks.length;
    final cell = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => selected = d),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: isToday ? P.accent : (isSel ? P.hover : null),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(children: [
          Center(
              child: Text('${d.day}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                      color: isToday ? P.bg : (d.isBefore(today) ? P.faint : (weekend ? P.danger : P.fg))))),
          if (n > 0)
            Positioned(
              bottom: 3,
              left: 0,
              right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var k = 0; k < (n > 3 ? 3 : n); k++)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: isToday ? P.bg : (n > 3 ? P.warn : P.muted)),
                  ),
              ]),
            ),
          if (deadline)
            const Positioned(top: 1, right: 2, child: Icon(Icons.flag, size: 9, color: P.danger)),
        ]),
      ),
    );
    if (n == 0) return cell;
    return Tooltip(
      richMessage: TextSpan(children: [
        TextSpan(text: '${d.day} ${months[d.month - 1]}\n', style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final t in dayTasks) TextSpan(text: '• ${t.text}\n'),
      ]),
      decoration: BoxDecoration(color: P.panel, border: Border.all(color: P.faint), borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(color: P.fg, fontSize: 12, height: 1.4),
      child: cell,
    );
  }

  Widget _goals() {
    Widget g(String text, bool done, String prog) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? P.ok : P.rest),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: done ? P.muted : P.fg, fontSize: 13))),
            Text(prog, style: const TextStyle(color: P.muted, fontSize: 12)),
          ]),
        );
    return Column(children: [
      g('Сдать квартальный отчёт', true, ''),
      g('Запустить рассылку', false, '2/5'),
      g('Подготовить отпуск', false, '0/2'),
    ]);
  }

  String futureLabel(DateTime d) {
    final n = d.difference(today).inDays;
    if (n == 1) return 'завтра';
    if (n == 2) return 'послезавтра';
    return '${wdShort[d.weekday - 1]} ${ddmm(d)}';
  }

  Widget _future() {
    final list = tasks.where((t) => t.date.isAfter(today) && !t.done).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return Column(children: [
      for (final t in list)
        InkWell(
          onTap: () => openCard(t),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(children: [
              if (t.time != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(t.time!, style: const TextStyle(color: P.muted, fontSize: 13)),
                ),
              Expanded(child: Text(t.text, style: const TextStyle(fontSize: 13))),
              Text(futureLabel(t.date), style: const TextStyle(color: P.muted, fontSize: 12)),
            ]),
          ),
        ),
    ]);
  }

  Widget _pomo() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Text(_clockText(pomoLeft), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w300)),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: P.accent, foregroundColor: P.bg),
          onPressed: () => setState(() => pomoRunning = !pomoRunning),
          child: Text(pomoRunning ? 'Пауза' : 'Старт'),
        ),
        IconButton(
          tooltip: 'Сбросить',
          onPressed: () => setState(() {
            pomoRunning = false;
            pomoLeft = 25 * 60;
          }),
          icon: const Icon(Icons.replay, color: P.muted, size: 20),
        ),
      ]),
    );
  }
}

// ---------- блок «Задачи на сегодня» ----------
class TasksBlock extends StatefulWidget {
  const TasksBlock({super.key, required this.state});
  final _HomeState state;
  @override
  State<TasksBlock> createState() => _TasksBlockState();
}

class _TasksBlockState extends State<TasksBlock> {
  final ctl = TextEditingController();
  bool cheat = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final d = s.selected;
    final items = s.tasksOn(d);
    final done = items.where((t) => t.done).length;
    final est = s.hoursLoad(d);
    const limit = 8 * 60;
    final over = est > limit;
    final title = d == today
        ? 'Задачи на сегодня'
        : d == today.add(const Duration(days: 1))
            ? 'Задачи на завтра'
            : 'Задачи на ${d.day} ${months[d.month - 1]}';
    final parsed = parseQuick(ctl.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 6),
          Text('${d.day} ${months[d.month - 1]}, ${wdShort[d.weekday - 1]}',
              style: const TextStyle(color: P.muted, fontSize: 12)),
          const Spacer(),
          if (est > 0)
            Text('${fmtEst(est)} из 8 ч', style: TextStyle(color: over ? P.danger : P.muted, fontSize: 12)),
          const SizedBox(width: 10),
          Text(items.isNotEmpty && done == items.length ? 'всё сделано' : (items.isEmpty ? '' : '$done из ${items.length}'),
              style: TextStyle(color: items.isNotEmpty && done == items.length ? P.ok : P.muted, fontSize: 12)),
        ]),
      ),
      if (est > 0)
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: est / limit > 1 ? 1 : est / limit,
            minHeight: 3,
            backgroundColor: P.faint,
            color: over ? P.danger : P.accent,
          ),
        ),
      const SizedBox(height: 8),
      TextField(
        controller: ctl,
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          s.addTask(v);
          ctl.clear();
          setState(() {});
        },
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Новая задача и Enter',
          hintStyle: const TextStyle(color: P.muted),
          filled: true,
          fillColor: P.panel,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: P.faint)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: P.faint)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: P.accent)),
          suffixIcon: IconButton(
            tooltip: 'Шпаргалка быстрого ввода',
            icon: Icon(Icons.help_outline, size: 18, color: cheat ? P.accent : P.muted),
            onPressed: () => setState(() => cheat = !cheat),
          ),
        ),
      ),
      if (parsed.chips.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (text, color) in parsed.chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: mix(P.card, color, 0.2), borderRadius: BorderRadius.circular(10)),
              child: Text(text, style: TextStyle(color: color, fontSize: 11)),
            ),
        ]),
        if (parsed.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Название: ${parsed.title}', style: const TextStyle(color: P.muted, fontSize: 11)),
          ),
      ],
      AnimatedSize(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.topCenter,
        child: cheat ? _cheatSheet() : const SizedBox(width: double.infinity),
      ),
      const SizedBox(height: 6),
      for (final t in items) TaskRow(task: t, state: s),
      if (items.isEmpty) _empty(s, d),
    ]);
  }

  Widget _cheatSheet() {
    const rows = [
      ('пт отчёт', 'на пятницу'),
      ('25.11 15:00 врач', 'дата и время'),
      ('!!1 договор', 'квадрант «Сделать сейчас»'),
      ('#дом ~30м билеты', 'метка и оценка'),
      ('до пт отчёт', 'дедлайн'),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: P.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: P.faint)),
      child: Column(children: [
        for (final (ex, what) in rows)
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() {
              ctl.text = ex;
              cheat = false;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(children: [
                SizedBox(width: 140, child: Text(ex, style: const TextStyle(color: P.accent, fontSize: 12))),
                Expanded(child: Text(what, style: const TextStyle(color: P.muted, fontSize: 12))),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _empty(_HomeState s, DateTime d) {
    final next = d.add(const Duration(days: 1));
    final later = s.tasksOn(next).where((t) => !t.done).toList();
    if (later.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('Пока пусто — впишите задачу выше', style: TextStyle(color: P.faint, fontSize: 13)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Пусто. На следующий день ${plural(later.length, 'задача', 'задачи', 'задач')}.',
            style: const TextStyle(fontSize: 13)),
        TextButton(
          onPressed: () => s.setState(() {
            for (final t in later) {
              t.date = d;
            }
          }),
          child: const Text('Взять на этот день'),
        ),
      ]),
    );
  }
}

class TaskRow extends StatefulWidget {
  const TaskRow({super.key, required this.task, required this.state});
  final Task task;
  final _HomeState state;
  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.task, s = widget.state;
    final meta = <(String, Color)>[
      if (t.eis != null) (eisNames[t.eis]!.$1, t.done ? P.muted : eisNames[t.eis]!.$2),
      if (t.deadline != null && !t.done) ('дедлайн ${s.futureLabel(t.deadline!)}', P.warn),
      if (t.est > 0) (fmtEst(t.est), P.muted),
      for (final g in t.tags) ('#$g', P.rest),
      if (t.subs.isNotEmpty) ('${t.subs.where((x) => x.done).length}/${t.subs.length} подзадач', P.muted),
      if (t.note.isNotEmpty) ('заметка', P.muted),
    ];
    final prio = {'high': P.danger, 'mid': P.warn, 'low': P.accent}[t.priority];
    final row = MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: EdgeInsets.symmetric(vertical: settings.compact ? 2 : 4, horizontal: 2),
        decoration: BoxDecoration(color: hover ? P.hover : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: InkWell(
          onTap: () => s.openCard(t),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 18,
              child: t.carriedFrom != null && !t.done
                  ? const Icon(Icons.arrow_forward, size: 15, color: P.warn)
                  : null,
            ),
            InkWell(
              onTap: () => s.toggle(t),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(t.done ? Icons.check_circle : Icons.circle_outlined,
                      key: ValueKey(t.done), size: 18, color: t.done ? P.ok : P.muted),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (t.time != null)
              SizedBox(width: 42, child: Text(t.time!, style: const TextStyle(color: P.muted, fontSize: 13))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.text, style: TextStyle(fontSize: 13.5, color: t.done ? P.muted : P.fg)),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(spacing: 8, children: [
                      for (final (text, color) in meta) Text(text, style: TextStyle(color: color, fontSize: 11)),
                    ]),
                  ),
                if (t.carriedFrom != null && !t.done)
                  Text('не закрыта с ${t.carriedFrom!.day} ${months[t.carriedFrom!.month - 1]}',
                      style: const TextStyle(color: P.warn, fontSize: 11, fontStyle: FontStyle.italic)),
              ]),
            ),
            if (prio != null && !t.done && !hover)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Container(width: 6, height: 6, decoration: BoxDecoration(color: prio, shape: BoxShape.circle)),
              ),
            if (hover) ...[
              if (!t.done) _icon(Icons.play_arrow_rounded, P.ok, 'Помидор', () {}),
              if (!t.done) _icon(Icons.redo_rounded, P.accent, 'На следующий день', () => s.moveNext(t)),
              _icon(Icons.close_rounded, P.danger, 'Удалить', () => s.remove(t)),
            ],
          ]),
        ),
      ),
    );
    if (t.note.isEmpty && t.subs.isEmpty) return row;
    // предпросмотр заметки и подзадач при наведении
    return Tooltip(
      waitDuration: const Duration(milliseconds: 600),
      preferBelow: true,
      verticalOffset: 18,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: P.panel, border: Border.all(color: P.faint), borderRadius: BorderRadius.circular(8)),
      richMessage: TextSpan(style: const TextStyle(color: P.fg, fontSize: 12, height: 1.45), children: [
        if (t.note.isNotEmpty) TextSpan(text: '${t.note}\n'),
        if (t.note.isNotEmpty && t.subs.isNotEmpty) const TextSpan(text: '\n'),
        for (final x in t.subs)
          TextSpan(
              text: '${x.done ? 'готово' : '•'}  ${x.text}\n',
              style: TextStyle(color: x.done ? P.muted : P.fg)),
      ]),
      child: row,
    );
  }

  Widget _icon(IconData i, Color c, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(padding: const EdgeInsets.all(2), child: Icon(i, size: 17, color: c)),
        ),
      );
}

// ---------- неделя с раскраской по нагрузке ----------
Color heat(int minutes) {
  if (minutes == 0) return P.panel;
  if (minutes > 8 * 60) return const Color(0xFF5A3640);
  if (minutes > 5 * 60) return const Color(0xFF4A4234);
  return const Color(0xFF2F3B4F);
}

List<DateTime> weekDays() {
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
}

class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.tasks});
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        for (final d in weekDays())
          Expanded(child: Builder(builder: (_) {
            final load = tasks.where((t) => t.date == d && !t.done).fold(0, (s, t) => s + t.est);
            final n = tasks.where((t) => t.date == d && !t.done).length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: heat(load),
                borderRadius: BorderRadius.circular(6),
                border: d == today ? Border.all(color: P.accent) : null,
              ),
              child: Column(children: [
                Text(wdShort[d.weekday - 1], style: TextStyle(fontSize: 11, color: d.weekday > 5 ? P.danger : P.muted)),
                Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w600, color: d == today ? P.accent : P.fg)),
                const SizedBox(height: 2),
                Text(load > 0 ? fmtEst(load) : (n > 0 ? plural(n, 'задача', 'задачи', 'задач') : ''),
                    style: TextStyle(fontSize: 10, color: load > 8 * 60 ? P.danger : P.muted)),
              ]),
            );
          })),
      ]),
    );
  }
}

class WeekWindow extends StatelessWidget {
  const WeekWindow({super.key, required this.tasks, required this.onOpen});
  final List<Task> tasks;
  final void Function(Task) onOpen;

  @override
  Widget build(BuildContext context) {
    final days = weekDays();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: P.panel, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Неделя ${days.first.day} – ${days.last.day} ${months[days.last.month - 1]}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('Цвет дня — по сумме оценок задач: спокойный, плотный, перегруженный',
            style: TextStyle(color: P.muted, fontSize: 12)),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final d in days)
              Expanded(child: Builder(builder: (_) {
                final list = tasks.where((t) => t.date == d).toList();
                final load = list.where((t) => !t.done).fold(0, (s, t) => s + t.est);
                return Container(
                  constraints: const BoxConstraints(minHeight: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: heat(load) == P.panel ? P.card : heat(load),
                    borderRadius: BorderRadius.circular(8),
                    border: d == today ? Border.all(color: P.accent) : null,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${wdShort[d.weekday - 1]} ${d.day}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600, color: d == today ? P.accent : P.fg)),
                    Text(load > 0 ? fmtEst(load) : ' ',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: load > 8 * 60 ? P.danger : P.muted)),
                    const SizedBox(height: 6),
                    for (final t in list)
                      InkWell(
                        onTap: () => onOpen(t),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(5)),
                          child: Text(t.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: t.done ? P.muted : P.fg)),
                        ),
                      ),
                  ]),
                );
              })),
          ]),
        ),
      ]),
    );
  }
}

// ---------- карточка задачи ----------
class TaskCard extends StatefulWidget {
  const TaskCard({super.key, required this.task, required this.onChanged});
  final Task task;
  final VoidCallback onChanged;
  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  final shut = <String>{};

  void upd(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  Widget section(String key, String title, Widget body) {
    final closed = shut.contains(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => closed ? shut.remove(key) : shut.add(key)),
        child: Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(children: [
            Icon(closed ? Icons.chevron_right : Icons.expand_more, size: 16, color: P.muted),
            const SizedBox(width: 4),
            Text(title, style: const TextStyle(color: P.muted, fontSize: 12)),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.topCenter,
        child: closed ? const SizedBox(width: double.infinity) : body,
      ),
    ]);
  }

  Widget chip(String text, bool on, VoidCallback tap, {Color? color}) => Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: ChoiceChip(
          label: Text(text),
          selected: on,
          onSelected: (_) => tap(),
          showCheckmark: false,
          selectedColor: color ?? P.accent,
          backgroundColor: P.card,
          labelStyle: TextStyle(color: on ? P.bg : P.fg, fontSize: 12),
          side: BorderSide(color: on ? Colors.transparent : P.faint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return Dialog(
      backgroundColor: P.panel,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
            child: Row(children: [
              Expanded(child: Text(t.text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: P.muted)),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: P.card, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Text('25:00', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: P.accent)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(t.est > 0 ? 'оценка ${fmtEst(t.est)}' : 'без оценки',
                            style: const TextStyle(color: P.muted, fontSize: 12))),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: P.accent, foregroundColor: P.bg),
                      onPressed: () {},
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Помидор'),
                    ),
                  ]),
                ),
                section('when', 'Когда', Wrap(children: [
                  for (final (label, days) in [('Сегодня', 0), ('Завтра', 1), ('Через неделю', 7)])
                    chip(label, t.date == today.add(Duration(days: days)),
                        () => upd(() => t.date = today.add(Duration(days: days)))),
                ])),
                section('prio', 'Приоритет', Wrap(children: [
                  for (final (label, key, c) in [
                    ('Нет', null, P.faint),
                    ('Низкий', 'low', P.accent),
                    ('Средний', 'mid', P.warn),
                    ('Высокий', 'high', P.danger)
                  ])
                    chip(label, t.priority == key, () => upd(() => t.priority = key), color: c),
                ])),
                section('eis', 'Матрица Эйзенхауэра', GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 3.2,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: [
                    for (final e in eisNames.entries)
                      InkWell(
                        onTap: () => upd(() => t.eis = t.eis == e.key ? null : e.key),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: t.eis == e.key ? mix(P.card, e.value.$2, 0.35) : P.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: t.eis == e.key ? e.value.$2 : Colors.transparent),
                          ),
                          child: Text(e.value.$1, style: TextStyle(color: t.eis == e.key ? P.fg : P.muted, fontSize: 13)),
                        ),
                      ),
                  ],
                )),
                section('subs', 'Подзадачи', Column(children: [
                  for (final x in t.subs)
                    CheckboxListTile(
                      value: x.done,
                      onChanged: (v) => upd(() => x.done = v ?? false),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: P.ok,
                      title: Text(x.text, style: TextStyle(fontSize: 13, color: x.done ? P.muted : P.fg)),
                    ),
                  if (t.subs.isEmpty) const Text('Подзадач нет', style: TextStyle(color: P.faint, fontSize: 13)),
                ])),
                section('note', 'Заметка', TextFormField(
                  initialValue: t.note,
                  onChanged: (v) => upd(() => t.note = v),
                  maxLines: 5,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: P.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                )),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}


// ---------- настройки вида ----------
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        Widget label(String t) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(t, style: const TextStyle(color: P.muted, fontSize: 12)));
        return Dialog(
          backgroundColor: P.panel,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Expanded(child: Text('Вид панели', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: P.muted, size: 18)),
                ]),
                label('Масштаб: ${(settings.scale * 100).round()} %'),
                Slider(
                  value: settings.scale,
                  min: 0.6,
                  max: 1.2,
                  divisions: 12,
                  onChanged: (v) => settings.update((s) => s.scale = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Компактно: меньше отступов'),
                  value: settings.compact,
                  onChanged: (v) => settings.update((s) => s.compact = v),
                ),
                if (isDesktop) ...[
                  label('Прозрачность: ${(settings.opacity * 100).round()} %'),
                  Slider(
                    value: settings.opacity,
                    min: 0.5,
                    max: 1.0,
                    divisions: 10,
                    onChanged: (v) {
                      settings.update((s) => s.opacity = v);
                      windowManager.setOpacity(v);
                    },
                  ),
                  label('Где держать панель'),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'bottom', label: Text('На столе')),
                      ButtonSegment(value: 'normal', label: Text('Обычно')),
                      ButtonSegment(value: 'top', label: Text('Поверх')),
                    ],
                    selected: {settings.layer},
                    onSelectionChanged: (v) {
                      settings.update((s) => s.layer = v.first);
                      applyWindowLayer();
                    },
                  ),
                ],
                label('Блоки'),
                for (final e in Settings.blocks.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(e.value),
                    value: !settings.hidden.contains(e.key),
                    onChanged: (v) => settings.update((s) => v == true ? s.hidden.remove(e.key) : s.hidden.add(e.key)),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
