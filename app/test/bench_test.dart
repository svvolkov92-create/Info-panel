import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_panel/core/core.dart';
import 'package:desktop_panel/core/model.dart';
import 'package:desktop_panel/core/storage.dart';
import 'package:desktop_panel/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Замеры на больших данных. Печатает время операций; падает, только если что-то совсем медленно.
final now = DateTime(2026, 11, 23, 9);

Map<String, dynamic> bigData(int n) {
  final r = math.Random(1);
  final today = dayOnly(now);
  final tasks = <Map<String, dynamic>>[];
  for (var i = 0; i < n; i++) {
    final off = r.nextInt(90) - 25; // прошлое, сегодня, будущее
    final d = addDays(today, off);
    final done = off < 0 ? r.nextDouble() < 0.8 : r.nextDouble() < 0.2;
    tasks.add({
      'id': 't$i',
      'text': 'Задача номер $i ${['отчёт', 'звонок', 'письмо', 'встреча'][i % 4]}',
      'date': iso(d),
      'done': done,
      if (done) 'done_at': iso(d),
      if (i % 3 == 0) 'eis': 'q${1 + i % 4}',
      if (i % 5 == 0) 'priority': ['low', 'medium', 'high'][i % 3],
      if (i % 4 == 0) 'est': 30 + (i % 6) * 30,
      if (i % 7 == 0) 'tags': ['работа', 'дом'][i % 2] == 'работа' ? ['работа'] : ['дом', 'семья'],
      if (i % 9 == 0) 'deadline': iso(addDays(d, 3)),
      if (i % 11 == 0) 'note': 'Заметка к задаче $i со ссылкой https://example.com/$i',
      if (i % 13 == 0) 'subs': [for (var k = 0; k < 4; k++) {'id': 's$i$k', 'text': 'шаг $k', 'done': k < 2}],
      if (i % 2 == 0) 'time': '${(8 + i % 10).toString().padLeft(2, '0')}:${(i % 2 == 0 ? '00' : '30')}',
      'log': [for (var k = 0; k < 5; k++) ['2026-11-0${k + 1} 10:00', 'перенесена на 0${k + 2}.11']],
    });
  }
  return {
    'tasks': tasks,
    'recurring': [for (var i = 0; i < 30; i++) {'id': 'r$i', 'text': 'Повтор $i', 'rule': 'weekdays', 'last': iso(today), 'start': '2026-01-01'}],
    'events': [for (var i = 0; i < 20; i++) {'id': 'e$i', 'title': 'Событие $i', 'date': iso(addDays(today, i * 3))}],
    'pomo_log': [for (var i = 0; i < 500; i++) {'date': iso(addDays(today, -(i % 50))), 'text': 'Задача ${i % 20}', 'min': 25, 'tags': ['работа']}],
    'notes': 'x' * 5000,
    'settings': {'review': false, 'prod_cal': false},
  };
}

double ms(Stopwatch sw) => sw.elapsedMicroseconds / 1000;

void report(String name, double v) {
  // ignore: avoid_print
  print('BENCH ${name.padRight(42)} ${v.toStringAsFixed(2).padLeft(9)} ms');
}

void main() {
  for (final n in [500, 3000]) {
    test('модель: $n задач', () {
      final dir = Directory.systemTemp.createTempSync('bench');
      final data = bigData(n);
      final m = PanelModel(storage: Storage(dirPath: dir.path), clock: () => now, network: false);
      var sw = Stopwatch()..start();
      m.load(demo: jsonDecode(jsonEncode(data)) as Map<String, dynamic>);
      report('[$n] загрузка и перенос', ms(sw));

      sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        m.viewTasks(m.today);
      }
      report('[$n] список дня (×1)', ms(sw) / 100);

      sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        m.futureTasks();
      }
      report('[$n] будущие задачи (×1)', ms(sw) / 20);

      final ids = m.viewTasks(m.today).map((t) => t['id'] as String).toList();
      sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        m.toggleTask(ids[i % ids.length]);
      }
      report('[$n] отметить выполненной (×1)', ms(sw) / 20);

      sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        m.undo();
      }
      report('[$n] отмена (×1)', ms(sw) / 10);

      sw = Stopwatch()..start();
      m.search('отчёт работа');
      report('[$n] поиск', ms(sw));

      sw = Stopwatch()..start();
      m.flushSave();
      report('[$n] запись файла', ms(sw));
      final size = File('${dir.path}/data.json').lengthSync();
      report('[$n] размер data.json, КБ', size / 1024);
      final undoBytes = m.histUndo.fold<int>(0, (a, s) => a + s.length * 2) + m.histRedo.fold<int>(0, (a, s) => a + s.length * 2);
      report('[$n] память истории отмены, МБ (${m.histUndo.length + m.histRedo.length} шагов)', undoBytes / 1024 / 1024);
      m.dispose();
    });
  }

  for (final n in [500, 3000]) {
    testWidgets('интерфейс: $n задач', (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('bench_ui');
      final m = PanelModel(storage: Storage(dirPath: dir.path), clock: () => now, network: false);
      m.load(demo: jsonDecode(jsonEncode(bigData(n))) as Map<String, dynamic>);

      var sw = Stopwatch()..start();
      await tester.pumpWidget(PanelApp(m: m));
      await tester.pump();
      report('[$n] первый показ панели', ms(sw));

      final ids = m.viewTasks(m.today).map((t) => t['id'] as String).toList();
      sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        m.toggleTask(ids[i]);
        await tester.pump();
      }
      report('[$n] отметка + перерисовка (×1)', ms(sw) / 10);

      sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        m.selectDay(addDays(m.today, i % 5));
        await tester.pump();
      }
      report('[$n] выбор дня + перерисовка (×1)', ms(sw) / 10);

      sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        m.clock.value = now.add(Duration(seconds: i + 1));
        await tester.pump();
      }
      report('[$n] тик часов (×1)', ms(sw) / 10);

      await tester.pump(const Duration(seconds: 10));
      m.dispose();
    });
  }
}
