import 'dart:io';

import 'package:desktop_panel/core/model.dart';
import 'package:desktop_panel/core/storage.dart';
import 'package:desktop_panel/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Интерфейс на тестовых данных: открываем основные окна и проверяем, что ничего не падает.
void main() {
  final now = DateTime(2026, 11, 23, 9);

  PanelModel model() {
    final dir = Directory.systemTemp.createTempSync('panel_ui');
    final m = PanelModel(storage: Storage(dirPath: dir.path), clock: () => now, network: false);
    m.load(demo: demoData(now));
    return m;
  }

  Future<void> pump(WidgetTester tester, PanelModel m, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PanelApp(m: m));
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final size in const [Size(380, 1000), Size(1280, 820)]) {
    testWidgets('панель ${size.width.round()}px: блоки, карточка, окна', (tester) async {
      final m = model();
      await pump(tester, m, size);
      expect(find.text('Квартальный отчёт'), findsWidgets);
      expect(find.text('Будущие задачи'), findsOneWidget);

      // карточка задачи
      await tester.tap(find.text('Договор юристам').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Матрица Эйзенхауэра'), findsWidgets);
      await tester.tap(find.text('Высокий'));
      await tester.pumpAndSettle();
      expect(m.findTask('b')!['priority'], 'high');
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();

      // добавление задачи с распознаванием
      final entry = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Новая задача и Enter, или Ctrl+V списком');
      await tester.enterText(entry, 'завтра 15:00 отчёт ~2ч');
      await tester.pump();
      expect(find.textContaining('15:00'), findsWidgets);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(m.tasks.where((t) => (t as Map)['text'] == 'отчёт').length, 1);
      // после Enter поле остаётся в фокусе — следующую задачу можно вводить сразу
      final editable = tester.widget<EditableText>(find.descendant(of: entry, matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);

      // будущая задача без даты не пропадает: текст остаётся в поле, появляется подсказка
      final future = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Задача и дата: «Купить билеты 20.11»');
      final count = m.tasks.length;
      await tester.enterText(future, 'Позвонить в банк');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(m.tasks.length, count);
      expect(tester.widget<TextField>(future).controller?.text ?? find.text('Позвонить в банк').evaluate().length.toString(), isNot(''));
      expect(find.text('Позвонить в банк'), findsOneWidget);
      expect(find.textContaining('Добавьте дату в конце'), findsOneWidget);
      await tester.enterText(future, 'Позвонить в банк пт');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(m.tasks.length, count + 1);

      // меню: неделя, матрица, настройки
      for (final item in ['Неделя', 'Матрица Эйзенхауэра', 'Настройки…']) {
        await tester.tap(find.byTooltip('Меню'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(item).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
      }

      // щелчок по дню календаря меняет заголовок списка задач
      await tester.tap(find.text('25').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(m.selected, DateTime(2026, 11, 25));
      expect(find.text('Задачи на 25 ноября'), findsOneWidget);
      await tester.tap(find.text('сегодня').first);
      await tester.pumpAndSettle();
      expect(find.text('Задачи на сегодня'), findsOneWidget);

      // поиск: выбор задачи открывает её карточку
      await tester.tap(find.byTooltip('Поиск задач (Ctrl+F)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Текст, заметка, подзадача или #метка'), 'юристам');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Матрица Эйзенхауэра'), findsWidgets); // открыта карточка
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();

      // сворачивание блока
      await tester.tap(find.text('Календарь'));
      await tester.pumpAndSettle();
      expect(m.collapsed('calendar'), isTrue);

      // отметка выполнения и отмена
      final before = m.findTask('d')!['done'];
      m.toggleTask('d');
      await tester.pump();
      expect(find.text('Отменить'), findsOneWidget);
      m.undo();
      await tester.pump();
      expect(m.findTask('d')!['done'], before);

      await tester.pump(const Duration(seconds: 10)); // дождаться подсказок и отложенного сохранения
      m.dispose();
    });
  }
}
