// Чистая логика панели без интерфейса: разбор ввода, даты, повторы, форматирование.
// Перенесено из panel/core.py; формат данных совместим с Python-версией.
import 'dart:math' as math;

// ---------- даты ----------

/// Дата без времени (полночь по местному времени).
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Разница в днях между датами без учёта перехода на летнее время.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// 0 — понедельник … 6 — воскресенье, как weekday() в Python.
int wd(DateTime d) => d.weekday - 1;

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? tryIso(Object? s) {
  if (s is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final r = DateTime(y, mo, d);
  return (r.year == y && r.month == mo && r.day == d) ? r : null;
}

DateTime fromIso(String s) => tryIso(s)!;

bool validDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1) return false;
  return d <= daysInMonth(y, m);
}

int daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;

int dayOfYear(DateTime d) => daysBetween(DateTime(d.year, 1, 1), d) + 1;

String two(int n) => n.toString().padLeft(2, '0');

String nowStr([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${iso(n)} ${two(n.hour)}:${two(n.minute)}';
}

/// Понедельник недели — ключ целей недели.
String weekKey(DateTime d) => iso(addDays(d, -wd(d)));

// ---------- словари ----------

const monthsNom = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август',
  'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const monthsGen = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
  'сентября', 'октября', 'ноября', 'декабря'];
const weekdays = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
const wdShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const wdAcc = ['понедельник', 'вторник', 'среду', 'четверг', 'пятницу', 'субботу', 'воскресенье'];
const wdDatPl = ['по понедельникам', 'по вторникам', 'по средам', 'по четвергам', 'по пятницам',
  'по субботам', 'по воскресеньям'];
const wdFrom = ['с понедельника', 'со вторника', 'со среды', 'с четверга', 'с пятницы', 'с субботы',
  'с воскресенья'];

const blockNames = {
  'calendar': 'Календарь',
  'goals': 'Цели недели',
  'tasks': 'Задачи',
  'future': 'Будущие задачи',
  'week': 'Неделя',
  'pomo': 'Помодоро',
  'notes': 'Заметки',
  'stats': 'Итоги недели',
  'events': 'События',
};

const fixedHolidays = {
  '1-1': 'Новогодние каникулы', '1-2': 'Новогодние каникулы', '1-3': 'Новогодние каникулы',
  '1-4': 'Новогодние каникулы', '1-5': 'Новогодние каникулы', '1-6': 'Новогодние каникулы',
  '1-7': 'Рождество Христово', '1-8': 'Новогодние каникулы',
  '2-23': 'День защитника Отечества', '3-8': 'Международный женский день',
  '5-1': 'Праздник Весны и Труда', '5-9': 'День Победы',
  '6-12': 'День России', '11-4': 'День народного единства',
};

/// Приоритеты: (значение, название). Цвет задаёт интерфейс.
const priorities = <(String?, String)>[(null, 'Нет'), ('low', 'Низкий'), ('medium', 'Средний'), ('high', 'Высокий')];
const prioRank = {'high': 0, 'medium': 1, 'low': 2};

/// Матрица Эйзенхауэра: квадрант → (действие, описание).
const eis = {
  'q1': ('Сделать сейчас', 'важно и срочно'),
  'q2': ('Запланировать', 'важно, не срочно'),
  'q3': ('Делегировать', 'срочно, не важно'),
  'q4': ('Отложить', 'не важно, не срочно'),
};
const eisOrder = {'q1': 0, 'q2': 1, 'q3': 2, 'q4': 3};

const sorts = {'manual': 'Мой порядок', 'priority': 'По приоритету', 'eis': 'По матрице', 'deadline': 'По дедлайну'};
const filters = {
  'all': 'Все задачи',
  'q1': 'Только «Сделать сейчас»',
  'q2': 'Только «Запланировать»',
  'q3': 'Только «Делегировать»',
  'q4': 'Только «Отложить»',
  'none': 'Без квадранта',
};

const wdTokens = {
  'пн': 0, 'пон': 0, 'понедельник': 0, 'вт': 1, 'вторник': 1, 'ср': 2, 'среда': 2, 'среду': 2,
  'чт': 3, 'четверг': 3, 'пт': 4, 'пятница': 4, 'пятницу': 4, 'сб': 5, 'суббота': 5,
  'субботу': 5, 'вс': 6, 'воскресенье': 6,
};

const goalsLimit = 5;
const remindBefore = 10; // минут до задачи со временем
const undoDepth = 50;
const futureMaxRows = 60;
const matrixMaxRows = 80;

// ---------- текст ----------

String plural(int n, String one, String few, String many) {
  final a = n.abs();
  if (a % 10 == 1 && a % 100 != 11) return '$n $one';
  if (a % 10 >= 2 && a % 10 <= 4 && !(a % 100 >= 12 && a % 100 <= 14)) return '$n $few';
  return '$n $many';
}

String pluralDays(int n) => plural(n, 'день', 'дня', 'дней');

String short(String text, int n) => text.length <= n ? text : '${text.substring(0, n - 1)}…';

String fmtEst(int minutes) {
  if (minutes < 60) return '$minutes мин';
  var s = (minutes / 60).toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '${s.replaceAll('.', ',')} ч';
}

String estToken(int minutes) => minutes % 60 == 0 ? '~${minutes ~/ 60}ч' : '~$minutesм';

String shortDate(DateTime d, DateTime today) {
  final s = '${two(d.day)}.${two(d.month)}';
  return d.year == today.year ? s : '$s.${d.year}';
}

/// «Завтра · вт, 13 октября».
String dateTitle(DateTime d, DateTime today) {
  final n = daysBetween(today, d);
  final rel = const {0: 'Сегодня', 1: 'Завтра', 2: 'Послезавтра', -1: 'Вчера'}[n] ??
      (n > 0 ? 'Через ${pluralDays(n)}' : '${pluralDays(-n)} назад');
  var tail = '${wdShort[wd(d)].toLowerCase()}, ${d.day} ${monthsGen[d.month - 1]}';
  if (d.year != today.year) tail += ' ${d.year}';
  return '$rel · $tail';
}

/// «завтра», «послезавтра», «пн 16.11» — дата у будущей задачи.
String futureDateText(DateTime d, DateTime today) {
  final n = daysBetween(today, d);
  if (n == 0) return 'сегодня';
  if (n == 1) return 'завтра';
  if (n == 2) return 'послезавтра';
  return '${wdShort[wd(d)].toLowerCase()} ${shortDate(d, today)}';
}

String dayLong(DateTime d) => '${d.day} ${monthsGen[d.month - 1]}';

// ---------- метки ----------

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _utf8(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      out.add(r);
    } else if (r < 0x800) {
      out..add(0xC0 | (r >> 6))..add(0x80 | (r & 0x3F));
    } else if (r < 0x10000) {
      out..add(0xE0 | (r >> 12))..add(0x80 | ((r >> 6) & 0x3F))..add(0x80 | (r & 0x3F));
    } else {
      out
        ..add(0xF0 | (r >> 18))
        ..add(0x80 | ((r >> 12) & 0x3F))
        ..add(0x80 | ((r >> 6) & 0x3F))
        ..add(0x80 | (r & 0x3F));
    }
  }
  return out;
}

/// Индекс цвета метки — тот же, что в Python-версии (crc32 от UTF-8).
int tagColorIndex(String tag, int paletteSize) => _crc32(_utf8(tag)) % paletteSize;

// ---------- разбор ввода ----------

final _prioPrefix = RegExp(r'^\s*!+\s*(.+)$', dotAll: true);
final _timePrefix = RegExp(r'^\s*([01]?\d|2[0-3])[:.]([0-5]\d)\s+(.+)$', dotAll: true);
final _quadRe = RegExp(r'(?<!\S)!!([1-4])(?!\S)');
final _tagRe = RegExp(r'(?<!\S)#([\p{L}\p{N}_-]+)', unicode: true);
final _estRe = RegExp(r'(?<!\S)~\s*(\d+(?:[.,]\d+)?)\s*(ч|час|часа|часов|h|м|мин|m)?(?!\S)',
    caseSensitive: false, unicode: true);
final _deadlineRe = RegExp(r'(?<!\S)до\s+(\S+)\s*$', caseSensitive: false, unicode: true);
final eventRe = RegExp(r'^(.+?)\s+(\d{1,2})\.(\d{1,2})(?:\.(\d{2}|\d{4}))?\s*$');
final listMarker = RegExp(r'^\s*(?:[-*•·–—▪►]+|\d+[.)]|\[[ xXхХ]?\])\s*(?:\[[ xXхХ]?\]\s*)?');
final linkRe = RegExp(
    r'"[A-Za-z]:\\[^"\n]+"|https?://[^\s<>"]+|www\.[^\s<>"]+|[A-Za-z]:\\[^\s<>"|?*]+|\\\\[^\s<>"|?*]+');

/// «! 14:00 Созвон» → ("Созвон", prio, "14:00").
(String, bool, String?) parseTaskText(String raw) {
  var text = raw.trim();
  var prio = false;
  String? time;
  for (var i = 0; i < 2; i++) {
    var m = _prioPrefix.firstMatch(text);
    if (m != null) {
      prio = true;
      text = m[1]!.trim();
    }
    m = _timePrefix.firstMatch(text);
    if (m != null) {
      time = '${two(int.parse(m[1]!))}:${m[2]}';
      text = m[3]!.trim();
    }
  }
  return (text, prio, time);
}

/// «15.11», «15.11.2026», «2026-11-15», «+3», «завтра», «пт» → дата или null.
/// Дата без года, которая в этом году уже прошла, — следующий год.
DateTime? parseDate(String text, DateTime today) {
  var s = text.trim().toLowerCase();
  while (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return null;
  const rel = {'сегодня': 0, 'завтра': 1, 'послезавтра': 2};
  if (rel.containsKey(s)) return addDays(today, rel[s]!);
  var m = RegExp(r'^\+(\d{1,3})$').firstMatch(s);
  if (m != null) return addDays(today, int.parse(m[1]!));
  if (wdTokens.containsKey(s)) {
    var delta = (wdTokens[s]! - wd(today)) % 7;
    if (delta == 0) delta = 7;
    return addDays(today, delta);
  }
  m = RegExp(r'^(\d{1,2})[./](\d{1,2})(?:[./](\d{2}|\d{4}))?$').firstMatch(s);
  if (m != null) {
    final day = int.parse(m[1]!), mon = int.parse(m[2]!), year = m[3];
    if (year != null) {
      final y = int.parse(year) + (year.length == 2 ? 2000 : 0);
      return validDate(y, mon, day) ? DateTime(y, mon, day) : null;
    }
    if (!validDate(today.year, mon, day)) {
      // 29.02 в невисокосный год — может подойти следующий
      return validDate(today.year + 1, mon, day) ? DateTime(today.year + 1, mon, day) : null;
    }
    final d = DateTime(today.year, mon, day);
    if (!d.isBefore(today)) return d;
    return validDate(today.year + 1, mon, day) ? DateTime(today.year + 1, mon, day) : null;
  }
  m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (m != null) {
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    return validDate(y, mo, d) ? DateTime(y, mo, d) : null;
  }
  return null;
}

class Extras {
  Extras(this.tags, this.est, this.deadline);
  final List<String> tags;
  final int? est;
  final DateTime? deadline;
}

/// Метки «#дом», оценка «~30м»/«~2ч» и дедлайн «до пт» в конце текста.
/// Оценка без единицы: до 8 включительно — часы, больше — минуты.
(String, Extras) parseExtras(String text, DateTime today) {
  final tags = <String>[];
  for (final m in _tagRe.allMatches(text)) {
    final tg = m[1]!.toLowerCase();
    if (!tags.contains(tg)) tags.add(tg);
  }
  text = text.replaceAll(_tagRe, '');
  int? est;
  final em = _estRe.firstMatch(text);
  if (em != null) {
    final v = double.parse(em[1]!.replaceAll(',', '.'));
    final unit = (em[2] ?? '').toLowerCase();
    final hours = unit.startsWith('ч') || unit.startsWith('h') || (unit.isEmpty && v <= 8);
    est = hours ? (v * 60).round() : v.round();
    text = text.substring(0, em.start) + text.substring(em.end);
  }
  DateTime? deadline;
  final stripped = text.trimRight();
  final dm = _deadlineRe.firstMatch(stripped);
  if (dm != null) {
    final d = parseDate(dm[1]!, today);
    if (d != null) {
      deadline = d;
      text = stripped.substring(0, dm.start);
    }
  }
  final clean = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return (clean, Extras(tags, (est == null || est == 0) ? null : est, deadline));
}

const _dateWords = {'сегодня': 0, 'завтра': 1, 'послезавтра': 2};

final Map<String, int> _wdPrefix = () {
  final m = <String, int>{};
  const shorts = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  for (var i = 0; i < 7; i++) {
    final prep = i == 1 ? 'во' : 'в';
    m[shorts[i]] = i;
    m['в ${shorts[i]}'] = i;
    m['во ${shorts[i]}'] = i;
    m['$prep ${wdAcc[i]}'] = i;
  }
  return m;
}();
final List<String> _wdPrefixByLen = _wdPrefix.keys.toList()..sort((a, b) => b.length.compareTo(a.length));

/// «завтра Купить хлеб» → (дата, "Купить хлеб"); дата только в начале строки.
(DateTime?, String) parseDatePrefix(String text, DateTime today) {
  final low = text.toLowerCase();
  for (final phrase in _wdPrefixByLen) {
    if (low.startsWith('$phrase ') && text.substring(phrase.length).trim().isNotEmpty) {
      var delta = (_wdPrefix[phrase]! - wd(today)) % 7;
      if (delta == 0) delta = 7;
      return (addDays(today, delta), text.substring(phrase.length).trim());
    }
  }
  final m = RegExp(r'^(\S+)\s+(.+)$', dotAll: true).firstMatch(text);
  if (m == null) return (null, text);
  var tok = m[1]!.toLowerCase();
  while (tok.endsWith(',')) {
    tok = tok.substring(0, tok.length - 1);
  }
  final rest = m[2]!.trim();
  if (_dateWords.containsKey(tok)) return (addDays(today, _dateWords[tok]!), rest);
  if (RegExp(r'^\+\d{1,3}$').hasMatch(tok) ||
      RegExp(r'^\d{1,2}[./]\d{1,2}(?:[./](?:\d{2}|\d{4}))?$').hasMatch(tok)) {
    final d = parseDate(tok, today);
    if (d != null) return (d, rest);
  }
  return (null, text);
}

class Quick {
  DateTime? date;
  bool prio = false;
  String? time;
  String? eis;
  List<String> tags = [];
  int? est;
  DateTime? deadline;
  String text = '';
}

/// Быстрый ввод одной строкой: дата, «!», время, «!!1…4», #метки, ~оценка, «до …».
Quick parseQuick(String raw, DateTime today, {bool allowDate = true}) {
  var text = raw.trim();
  final q = Quick();
  final qm = _quadRe.firstMatch(text);
  if (qm != null) {
    q.eis = 'q${qm[1]}';
    text = (text.substring(0, qm.start) + text.substring(qm.end)).trim();
  }
  for (var i = 0; i < 4; i++) {
    var changed = false;
    final pm = _prioPrefix.firstMatch(text);
    if (pm != null && !q.prio) {
      q.prio = true;
      text = pm[1]!.trim();
      changed = true;
    }
    if (allowDate && q.date == null) {
      final (d, rest) = parseDatePrefix(text, today);
      if (d != null) {
        q.date = d;
        text = rest;
        changed = true;
      }
    }
    final tm = _timePrefix.firstMatch(text);
    if (tm != null && q.time == null) {
      q.time = '${two(int.parse(tm[1]!))}:${tm[2]}';
      text = tm[3]!.trim();
      changed = true;
    }
    if (!changed) break;
  }
  final (clean, ex) = parseExtras(text, today);
  q
    ..tags = ex.tags
    ..est = ex.est
    ..deadline = ex.deadline
    ..text = clean;
  return q;
}

/// «Купить билеты 20.11» → ("Купить билеты", дата). Дата — последнее слово.
(String, DateTime?) splitTaskDate(String raw, DateTime today) {
  final m = RegExp(r'^(.*\S)\s+(\S+)$', dotAll: true).firstMatch(raw.trim());
  if (m != null) {
    final d = parseDate(m[2]!, today);
    if (d != null) return (m[1]!, d);
  }
  return (raw.trim(), null);
}

/// Строки, вставленные списком: убираем маркеры «- », «1.», «[ ]».
List<String> pastedLines(String text) => text
    .split(RegExp(r'\r?\n'))
    .map((l) => l.replaceFirst(listMarker, '').trim())
    .where((l) => l.isNotEmpty)
    .toList();

// ---------- повторы ----------

/// daily, weekdays, w{день}, d{N}, W{N}:{день}, m{число}, m{k}:{день}, mL{день}.
bool ruleMatches(String? rule, DateTime d, [DateTime? start]) {
  if (rule == null || rule.isEmpty) return false;
  if (rule == 'daily') return true;
  if (rule == 'weekdays') return wd(d) < 5;
  start ??= d;
  try {
    if (rule.startsWith('d')) {
      final n = math.max(1, int.parse(rule.substring(1)));
      return !d.isBefore(start) && daysBetween(start, d) % n == 0;
    }
    if (rule.startsWith('W')) {
      final p = rule.substring(1).split(':').map(int.parse).toList();
      final n = p[0], w = p[1];
      if (wd(d) != w || d.isBefore(start)) return false;
      final weeks = daysBetween(addDays(start, -wd(start)), addDays(d, -wd(d))) ~/ 7;
      return weeks % math.max(1, n) == 0;
    }
    if (rule.startsWith('w')) return wd(d) == int.parse(rule.substring(1));
    if (rule.startsWith('mL')) {
      return wd(d) == int.parse(rule.substring(2)) && addDays(d, 7).month != d.month;
    }
    if (rule.startsWith('m') && rule.contains(':')) {
      final p = rule.substring(1).split(':').map(int.parse).toList();
      return wd(d) == p[1] && (d.day - 1) ~/ 7 + 1 == p[0];
    }
    if (rule.startsWith('m')) {
      final day = int.parse(rule.substring(1));
      return d.day == math.min(day, daysInMonth(d.year, d.month));
    }
  } on FormatException {
    return false;
  }
  return false;
}

const _wdGender = [0, 0, 1, 0, 1, 1, 2]; // м, м, ж, м, ж, ж, ср
const _ordinals = {
  1: ['первый', 'первую', 'первое'],
  2: ['второй', 'вторую', 'второе'],
  3: ['третий', 'третью', 'третье'],
  4: ['четвёртый', 'четвёртую', 'четвёртое'],
};
const _lastForms = ['последний', 'последнюю', 'последнее'];
const ordLabels = ['1-й', '2-й', '3-й', '4-й', 'последний'];
const basicRules = ['daily', 'weekdays'];

String ruleText(String? rule) {
  if (rule == null || rule.isEmpty) return '';
  if (rule == 'daily') return 'каждый день';
  if (rule == 'weekdays') return 'по будням';
  try {
    if (rule.startsWith('d')) {
      final n = int.parse(rule.substring(1));
      return n == 1 ? 'каждый день' : 'каждые ${pluralDays(n)}';
    }
    if (rule.startsWith('W')) {
      final p = rule.substring(1).split(':').map(int.parse).toList();
      if (p[0] == 1) return wdDatPl[p[1]];
      return 'каждые ${plural(p[0], 'неделю', 'недели', 'недель')} ${p[1] == 1 ? 'во' : 'в'} ${wdAcc[p[1]]}';
    }
    if (rule.startsWith('w')) return wdDatPl[int.parse(rule.substring(1))];
    if (rule.startsWith('mL')) {
      final w = int.parse(rule.substring(2));
      return 'в ${_lastForms[_wdGender[w]]} ${wdAcc[w]} месяца';
    }
    if (rule.startsWith('m') && rule.contains(':')) {
      final p = rule.substring(1).split(':').map(int.parse).toList();
      return '${p[0] == 2 ? 'во' : 'в'} ${_ordinals[p[0]]![_wdGender[p[1]]]} ${wdAcc[p[1]]} месяца';
    }
    if (rule.startsWith('m')) return '${int.parse(rule.substring(1))}-го числа каждого месяца';
  } on Object {
    return '';
  }
  return '';
}

// ---------- выходные ----------

/// Дни, задачи которых в выходной не переносятся: последний рабочий день и выходные после него
/// до вчерашнего. В рабочий день — пусто.
List<DateTime> holdDates(DateTime today, bool Function(DateTime) isOff, {int maxBack = 14}) {
  if (!isOff(today)) return [];
  final dates = <DateTime>[];
  var d = addDays(today, -1);
  while (isOff(d)) {
    dates.add(d);
    d = addDays(d, -1);
    if (dates.length > maxBack) return [];
  }
  dates.add(d);
  dates.sort();
  return dates;
}

/// Вид дня: 'work' | 'off' | 'short' | 'moved' и название праздника.
(String, String) dayInfo(DateTime d, {Map<String, dynamic>? prodcal, bool useProdCal = true}) {
  final name = fixedHolidays['${d.month}-${d.day}'] ?? '';
  final cal = useProdCal ? prodcal?['${d.year}'] : null;
  if (cal is String && cal.length >= dayOfYear(d)) {
    final code = cal[dayOfYear(d) - 1];
    if (code == '1') return ('off', name);
    if (code == '2') return ('short', '');
    if (wd(d) >= 5) return ('moved', '');
    return ('work', '');
  }
  if (wd(d) >= 5) return ('off', name);
  if (useProdCal && name.isNotEmpty) return ('off', name);
  return ('work', '');
}

// ---------- дедлайн ----------

/// Текст значка дедлайна и уровень: 'danger' | 'warn' | 'muted'.
(String, String)? deadlineBadge(Map t, DateTime today) {
  final d = tryIso(t['deadline']);
  if (d == null) return null;
  final n = daysBetween(today, d);
  if (n < 0) return ('просрочен на ${pluralDays(-n)}', 'danger');
  if (n == 0) return ('дедлайн сегодня', 'danger');
  if (n == 1) return ('дедлайн завтра', 'danger');
  if (n <= 3) return ('до ${wdShort[wd(d)].toLowerCase()} ${shortDate(d, today)}', 'warn');
  return ('до ${shortDate(d, today)}', 'muted');
}

/// «не закрыта с 20 ноября · 3 дня».
String? carriedNote(Map t, DateTime today) {
  final src = tryIso(t['from']);
  final date = tryIso(t['date']);
  if (src == null || date == null || !src.isBefore(date)) return null;
  final days = daysBetween(src, date);
  var when = '${src.day} ${monthsGen[src.month - 1]}';
  if (src.year != today.year) when += ' ${src.year}';
  var note = 'не закрыта с $when';
  if (days > 1) note += ', ${pluralDays(days)}';
  return note;
}

/// Строка для редактирования задачи одной строкой (как в Python edit_task).
String taskEditLine(Map t, DateTime today) {
  final b = StringBuffer();
  if (t['priority'] == 'high') b.write('! ');
  if (t['time'] != null) b.write('${t['time']} ');
  b.write(t['text']);
  if (t['est'] is int) b.write(' ${estToken(t['est'] as int)}');
  for (final g in (t['tags'] as List?) ?? const []) {
    b.write(' #$g');
  }
  final dl = tryIso(t['deadline']);
  if (dl != null) b.write(' до ${shortDate(dl, today)}');
  return b.toString();
}
