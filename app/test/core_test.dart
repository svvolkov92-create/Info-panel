import 'dart:io';

import 'package:desktop_panel/core/core.dart';
import 'package:desktop_panel/core/model.dart';
import 'package:desktop_panel/core/storage.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 11, 23); // понедельник

PanelModel makeModel({DateTime? now, Map<String, dynamic>? demo}) {
  final dir = Directory.systemTemp.createTempSync('panel_test');
  final m = PanelModel(storage: Storage(dirPath: dir.path), clock: () => now ?? today.add(const Duration(hours: 9)), network: false);
  m.load(demo: demo ?? {'tasks': []});
  return m;
}

void main() {
  group('даты', () {
    test('parseDate', () {
      expect(parseDate('25.11', today), DateTime(2026, 11, 25));
      expect(parseDate('01.01', today), DateTime(2027, 1, 1));
      expect(parseDate('+3', today), DateTime(2026, 11, 26));
      expect(parseDate('завтра', today), DateTime(2026, 11, 24));
      expect(parseDate('пн', today), DateTime(2026, 11, 30));
      expect(parseDate('пт', today), DateTime(2026, 11, 27));
      expect(parseDate('31.02', today), isNull);
      expect(parseDate('2026-12-05', today), DateTime(2026, 12, 5));
      expect(parseDate('15.03.27', today), DateTime(2027, 3, 15));
    });

    test('dateTitle и futureDateText', () {
      expect(dateTitle(DateTime(2026, 11, 24), today), 'Завтра · вт, 24 ноября');
      expect(futureDateText(DateTime(2026, 11, 25), today), 'послезавтра');
      expect(futureDateText(DateTime(2026, 11, 30), today), 'пн 30.11');
    });

    test('daysBetween через переход времени', () {
      expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });
  });

  group('разбор ввода', () {
    test('время, метки, оценка', () {
      final q = parseQuick('15:00 отчёт #работа ~2ч', today);
      expect(q.time, '15:00');
      expect(q.tags, ['работа']);
      expect(q.est, 120);
      expect(q.text, 'отчёт');
    });

    test('дата в начале, квадрант, приоритет, дедлайн', () {
      final q = parseQuick('! завтра 9.30 договор !!1 до пт', today);
      expect(q.prio, isTrue);
      expect(q.date, DateTime(2026, 11, 24));
      expect(q.time, '09:30');
      expect(q.eis, 'q1');
      expect(q.deadline, DateTime(2026, 11, 27));
      expect(q.text, 'договор');
    });

    test('точка: дата или время', () {
      expect(parseQuick('25.11 врач', today).date, DateTime(2026, 11, 25));
      expect(parseQuick('14.00 врач', today).time, '14:00');
    });

    test('«во вторник» и «в среду»', () {
      expect(parseQuick('во вторник созвон', today).date, DateTime(2026, 11, 24));
      expect(parseQuick('в среду созвон', today).date, DateTime(2026, 11, 25));
    });

    test('оценка без единицы', () {
      expect(parseExtras('x ~2', today).$2.est, 120);
      expect(parseExtras('x ~45', today).$2.est, 45);
      expect(parseExtras('x ~1,5ч', today).$2.est, 90);
    });

    test('вставка списком', () {
      expect(pastedLines('- один\n2) два\n[ ] три\n\n'), ['один', 'два', 'три']);
    });

    test('будущая задача с датой в конце', () {
      final (text, d) = splitTaskDate('Купить билеты 20.12', today);
      expect(text, 'Купить билеты');
      expect(d, DateTime(2026, 12, 20));
    });
  });

  group('повторы', () {
    test('правила', () {
      expect(ruleMatches('weekdays', today), isTrue);
      expect(ruleMatches('w0', today), isTrue);
      expect(ruleMatches('d3', DateTime(2026, 11, 26), today), isTrue);
      expect(ruleMatches('d3', DateTime(2026, 11, 25), today), isFalse);
      expect(ruleMatches('W2:0', DateTime(2026, 12, 7), today), isTrue);
      expect(ruleMatches('W2:0', DateTime(2026, 11, 30), today), isFalse);
      expect(ruleMatches('m31', DateTime(2026, 11, 30)), isTrue);
      expect(ruleMatches('m4:0', today), isTrue); // 4-й понедельник ноября 2026
      expect(ruleMatches('mL0', DateTime(2026, 11, 30)), isTrue);
    });

    test('тексты правил', () {
      expect(ruleText('W2:1'), 'каждые 2 недели во вторник');
      expect(ruleText('m2:4'), 'во вторую пятницу месяца');
      expect(ruleText('mL6'), 'в последнее воскресенье месяца');
    });
  });

  group('выходные', () {
    bool off(DateTime d) => d.weekday >= 6;
    test('в субботу держим пятницу', () {
      expect(holdDates(DateTime(2026, 11, 28), off), [DateTime(2026, 11, 27)]);
      expect(holdDates(DateTime(2026, 11, 29), off), [DateTime(2026, 11, 27), DateTime(2026, 11, 28)]);
      expect(holdDates(today, off), isEmpty);
    });
  });

  group('склонения и форматы', () {
    test('plural и fmtEst', () {
      expect(plural(1, 'задача', 'задачи', 'задач'), '1 задача');
      expect(plural(12, 'задача', 'задачи', 'задач'), '12 задач');
      expect(plural(22, 'задача', 'задачи', 'задач'), '22 задачи');
      expect(fmtEst(90), '1,5 ч');
      expect(fmtEst(120), '2 ч');
      expect(fmtEst(30), '30 мин');
    });

    test('цвет метки как в Python (crc32)', () {
      // zlib.crc32('работа'.encode()) % 8 == 4 в Python
      expect(tagColorIndex('работа', 8), 4);
    });
  });

  group('модель', () {
    test('добавление, выполнение, отмена', () {
      final m = makeModel();
      m.addTask('отчёт ~2ч #работа');
      expect(m.tasksFor(today).length, 1);
      final id = m.tasksFor(today).first['id'] as String;
      m.toggleTask(id);
      expect(m.findTask(id)!['done'], isTrue);
      m.undo();
      expect(m.findTask(id)!['done'], isFalse);
      m.redo();
      expect(m.findTask(id)!['done'], isTrue);
    });

    test('перенос незакрытых на сегодня с пометкой', () {
      final m = makeModel(demo: {
        'tasks': [
          {'id': 'a', 'text': 'старая', 'date': '2026-11-20', 'done': false},
          {'id': 'b', 'text': 'сделана', 'date': '2026-11-20', 'done': true},
        ],
      });
      expect(m.findTask('a')!['date'], '2026-11-23');
      expect(m.findTask('a')!['from'], '2026-11-20');
      expect(m.findTask('b')!['date'], '2026-11-20');
      expect(carriedNote(m.findTask('a')!, today), 'не закрыта с 20 ноября, 3 дня');
      // в прошедших днях перенесённая задача видна как «не успелось»
      expect(m.carriedThrough(DateTime(2026, 11, 20)).map((t) => t['id']), ['a']);
      expect(m.carriedThrough(DateTime(2026, 11, 22)).map((t) => t['id']), ['a']);
      expect(m.carriedThrough(DateTime(2026, 11, 19)), isEmpty);
      expect(m.carriedThrough(today), isEmpty);
    });

    test('в субботу задачи пятницы не переносятся, но видны сегодня', () {
      final sat = DateTime(2026, 11, 28, 10);
      final m = makeModel(now: sat, demo: {
        'tasks': [
          {'id': 'a', 'text': 'пятничная', 'date': '2026-11-27', 'done': false},
          {'id': 'b', 'text': 'четверговая', 'date': '2026-11-26', 'done': false},
        ],
        'settings': {'prod_cal': false},
      });
      expect(m.findTask('a')!['date'], '2026-11-27');
      expect(m.findTask('b')!['date'], '2026-11-27');
      expect(m.tasksFor(DateTime(2026, 11, 28)).map((t) => t['id']), containsAll(['a', 'b']));
    });

    test('повторяющаяся задача создаётся раз в день', () {
      final m = makeModel(demo: {
        'tasks': [],
        'recurring': [
          {'id': 'r', 'text': 'планёрка', 'rule': 'weekdays', 'last': '2026-11-20', 'start': '2026-11-02'},
        ],
      });
      expect(m.tasksFor(today).where((t) => t['rec'] == 'r').length, 1);
      m.generateRecurring();
      expect(m.tasksFor(today).where((t) => t['rec'] == 'r').length, 1);
    });

    test('авто-срочность при близком дедлайне', () {
      final m = makeModel(demo: {
        'tasks': [
          {'id': 'a', 'text': 'x', 'date': '2026-11-23', 'done': false, 'eis': 'q2', 'deadline': '2026-11-25'},
        ],
      });
      expect(m.findTask('a')!['eis'], 'q1');
    });

    test('правка одной строкой', () {
      final m = makeModel();
      m.addTask('черновик');
      final id = m.tasksFor(today).first['id'] as String;
      m.editTask(id, '! 14:00 договор ~30м #юр до пт');
      final t = m.findTask(id)!;
      expect(t['text'], 'договор');
      expect(t['priority'], 'high');
      expect(t['time'], '14:00');
      expect(t['est'], 30);
      expect(t['tags'], ['юр']);
      expect(t['deadline'], '2026-11-27');
      expect(taskEditLine(t, today), '! 14:00 договор ~30м #юр до 27.11');
    });

    test('сохранение и чтение файла', () {
      final dir = Directory.systemTemp.createTempSync('panel_io');
      final st = Storage(dirPath: dir.path);
      final m = PanelModel(storage: st, clock: () => today, network: false)..load();
      m.addTask('сохранить');
      m.flushSave();
      final m2 = PanelModel(storage: Storage(dirPath: dir.path), clock: () => today, network: false)..load();
      expect(m2.tasks.length, 1);
      // испорченный файл уходит в сторону, данные берутся из копии
      m.addTask('ещё');
      m.flushSave();
      File('${dir.path}/data.json').writeAsStringSync('{oops');
      final st3 = Storage(dirPath: dir.path);
      final m3 = PanelModel(storage: st3, clock: () => today, network: false)..load();
      expect(st3.corrupt, isNotNull);
      expect(m3.tasks.length, 1);
    });

    test('цели недели и прогресс', () {
      final m = makeModel();
      m.addGoal('рассылка');
      final g = m.weekGoals().first;
      m.addTask('письмо');
      final id = m.tasksFor(today).first['id'] as String;
      m.setField(id, 'goal', g['id']);
      m.toggleTask(id);
      expect(m.goalProgress(g['id'] as String), (1, 1));
    });

    test('шаблон дня', () {
      final m = makeModel();
      m.addTask('a ~1ч');
      m.addTemplate('день', m.dayTemplateItems());
      m.selectDay(addDays(today, 2));
      m.applyTemplate(m.templates.first['id'] as String);
      expect(m.tasksFor(addDays(today, 2)).first['est'], 60);
    });

    test('напоминание за 10 минут', () async {
      final m = makeModel(demo: {
        'tasks': [
          {'id': 'a', 'text': 'созвон', 'date': '2026-11-23', 'done': false, 'time': '10:00'},
        ],
      });
      final got = <Notice>[];
      final sub = m.notices.listen(got.add);
      m.checkReminders(DateTime(2026, 11, 23, 9, 51));
      await Future<void>.delayed(Duration.zero);
      expect(got.length, 1);
      expect(got.first.title, startsWith('Через 9 минут'));
      m.checkReminders(DateTime(2026, 11, 23, 9, 55));
      await Future<void>.delayed(Duration.zero);
      expect(got.length, 1);
      await sub.cancel();
    });

    test('испорченные события и задачи не ломают загрузку', () {
      final m = makeModel(demo: {
        'tasks': [
          {'id': 'a', 'text': 'x', 'date': 'вчера', 'done': false, 'deadline': '32.13'},
          'мусор',
        ],
        'events': [
          {'id': 'e1', 'title': 'Отпуск', 'date': '2026-12-01'},
          {'id': 'e2', 'title': 'Сломанное', 'date': '2026-13-45'},
          'мусор',
        ],
      });
      expect(m.tasks.length, 1);
      expect(m.findTask('a')!['date'], '2026-11-23');
      expect(m.findTask('a')!.containsKey('deadline'), isFalse);
      expect(m.events.map((e) => e['id']), ['e1']);
    });

    test('поиск по заметке и метке', () {
      final m = makeModel(demo: {
        'tasks': [
          {'id': 'a', 'text': 'отчёт', 'date': '2026-11-23', 'done': false, 'note': 'шаблон в папке', 'tags': ['работа']},
          {'id': 'b', 'text': 'хлеб', 'date': '2026-11-23', 'done': false},
        ],
      });
      expect(m.search('шаблон #работа').map((t) => t['id']), ['a']);
    });
  });
}
