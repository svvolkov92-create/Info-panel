import 'package:flutter/material.dart';

import '../core/core.dart';
import '../core/model.dart';
import '../core/storage.dart';
import 'desktop.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Все настройки в одном окне: вид, блоки, помодоро, планирование.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, this.desk});
  final DesktopWindow? desk;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    final s = m.s;
    double numOf(String k, double d) => ((s[k] as num?) ?? d).toDouble();

    Widget slider(String label, double value, double min, double max, int div, String text, void Function(double) set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [Expanded(child: Text(label, style: T.small)), Text(text, style: T.small.copyWith(color: C.muted))]),
            SliderTheme(
              data: const SliderThemeData(trackHeight: 3, overlayShape: RoundSliderOverlayShape(overlayRadius: 10)),
              child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: div, onChanged: set),
            ),
          ],
        );

    Widget check(String label, String key, {bool def = true}) => InkWell(
          onTap: () => m.setSetting(key, (s[key] ?? def) != true),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon((s[key] ?? def) == true ? Icons.check_box : Icons.check_box_outline_blank, size: 16,
                  color: (s[key] ?? def) == true ? C.accent : C.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: T.small)),
            ]),
          ),
        );

    Widget stepper(String label, String key, int min, int max, {int step = 1, String unit = ''}) {
      final v = ((s[key] as num?) ?? min).toInt();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: T.small)),
          IconBtn(Icons.remove, 'Меньше', v - step >= min ? () => m.setPomoOrSetting(key, v - step) : null, size: 14),
          SizedBox(width: 44, child: Text('$v$unit', style: T.small, textAlign: TextAlign.center)),
          IconBtn(Icons.add, 'Больше', v + step <= max ? () => m.setPomoOrSetting(key, v + step) : null, size: 14),
        ]),
      );
    }

    final layer = '${s['ui_layer'] ?? 'normal'}';
    return Dialog(
      backgroundColor: C.bg,
      insetPadding: const EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 780),
        child: ListenableBuilder(
          listenable: m,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(children: [
                Expanded(child: Text('Настройки', style: T.title.copyWith(fontSize: 16))),
                IconBtn(Icons.close, 'Закрыть', () => Navigator.pop(context)),
              ]),
            ),
            Flexible(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SectionLabel('Вид'),
                    Text('Оформление', style: T.small),
                    const SizedBox(height: 4),
                    Wrap(children: [
                      for (final e in palettes.entries) _ThemeChip(keyName: e.key, p: e.value, selected: C.name == e.key),
                    ]),
                    const SizedBox(height: 8),
                    if (isDesktop) ...[
                      Text('Как показывать панель', style: T.small),
                      const SizedBox(height: 4),
                      Wrap(children: [
                        Pill('Виджет на рабочем столе', s['ui_mode'] != 'window', () => desk?.setMode('widget')),
                        Pill('Обычное окно', s['ui_mode'] == 'window', () => desk?.setMode('window')),
                      ]),
                      Text('При переключении панель перезапустится.', style: T.tiny.copyWith(color: C.faint)),
                      const SizedBox(height: 8),
                      Text('Где держать', style: T.small),
                      const SizedBox(height: 4),
                      Wrap(children: [
                        Pill('Под ярлыками', layer == 'desktop', () => desk?.setLayer('desktop')),
                        Pill('Под окнами', layer == 'bottom', () => desk?.setLayer('bottom')),
                        Pill('Обычно', layer == 'normal', () => desk?.setLayer('normal')),
                        Pill('Поверх всех окон', layer == 'top', () => desk?.setLayer('top')),
                      ]),
                      slider('Непрозрачность', numOf('alpha', 1), 0.3, 1, 14, '${(numOf('alpha', 1) * 100).round()} %', (v) => desk?.setOpacity(v)),
                    ],
                    slider('Масштаб', numOf('ui_scale', 0.85), 0.6, 1.4, 16, '${(numOf('ui_scale', 0.85) * 100).round()} %',
                        (v) => m.setSetting('ui_scale', (v * 20).round() / 20)),
                    check('Компактно: меньше отступов', 'ui_compact'),
                    check('GTD: входящие, проекты, «жду» (в окне — колонка слева)', 'gtd'),
                    slider('Шрифт задач', numOf('task_font', 10), 8, 16, 8, '${numOf('task_font', 10).round()}',
                        (v) => m.setSetting('task_font', v.round())),
                    slider('Отступ между задачами', numOf('task_gap', 1), 0, 8, 8, '${numOf('task_gap', 1).round()} px',
                        (v) => m.setSetting('task_gap', v.round())),
                    const SectionLabel('Блоки: видимость и порядок'),
                    for (final k in (s['order'] as List).cast<String>())
                      Row(children: [
                        InkWell(
                          onTap: () => m.setBlockHidden(k, !(s['hidden_blocks'] as List).contains(k)),
                          child: Icon(!(s['hidden_blocks'] as List).contains(k) ? Icons.check_box : Icons.check_box_outline_blank,
                              size: 16, color: !(s['hidden_blocks'] as List).contains(k) ? C.accent : C.muted),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(blockNames[k] ?? k, style: T.small)),
                        IconBtn(Icons.arrow_upward, 'Выше', () => m.moveBlock(k, -1), size: 13),
                        IconBtn(Icons.arrow_downward, 'Ниже', () => m.moveBlock(k, 1), size: 13),
                      ]),
                    const SectionLabel('Помодоро'),
                    stepper('Работа', 'work', 1, 180, unit: ' мин'),
                    stepper('Перерыв', 'break', 1, 60, unit: ' мин'),
                    stepper('Длинный перерыв', 'long', 1, 90, unit: ' мин'),
                    stepper('Длинный после помидоров', 'cycle', 1, 12),
                    check('Сразу начинать перерыв', 'auto_break', def: false),
                    check('Режим фокуса во время работы', 'focus_mode'),
                    const SectionLabel('Звуки помодоро'),
                    for (final (kind, label) in const [('work', 'Конец работы'), ('break', 'Конец перерыва')]) _soundRow(m, kind, label),
                    const SectionLabel('Планирование'),
                    stepper('Лимит «Сделать сейчас»', 'q1_limit', 1, 50),
                    stepper('Рабочих часов в дне', 'day_hours', 1, 24),
                    check('В выходные задачи последнего рабочего дня не переносятся', 'weekend_hold'),
                    check('Производственный календарь РФ (праздники, переносы)', 'prod_cal'),
                    check('Утренний разбор незакрытых задач', 'review'),
                    check('Обзор недели по пятницам после 15:00', 'weekly_review'),
                    if (isDesktop) ...[
                      const SectionLabel('Система'),
                      InkWell(
                        onTap: () => desk?.setClickThrough(s['click_through'] != true),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Icon(s['click_through'] == true ? Icons.check_box : Icons.check_box_outline_blank, size: 16,
                                color: s['click_through'] == true ? C.accent : C.muted),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Сквозные клики: панель не мешает щёлкать по рабочему столу, нажимать — с зажатым Ctrl', style: T.small)),
                          ]),
                        ),
                      ),
                      _AutostartRow(),
                    ],
                    if (Storage.persistent) ...[
                      const SectionLabel('Данные'),
                      Text('Папка: ${m.storage.dataDir}', style: T.tiny),
                      Wrap(spacing: 12, children: [
                        Btn('Открыть папку с данными', () => m.storage.openExternal(m.storage.dataDir), pad: 0),
                        Btn('Журнал ошибок', () => m.storage.openExternal(m.storage.logPath), color: C.muted),
                      ]),
                      const SizedBox(height: 4),
                      Text('Архив: выполненные задачи старше 30 дней раз в месяц уходят в archive.json. '
                          'Ищутся через поиск с галочкой «и в архиве». Перенесено всего: ${s['archive_count'] ?? 0}.',
                          style: T.tiny),
                      Btn('Архивировать сейчас', () {
                        final before = m.tasks.length;
                        m.archiveMonthly(force: true);
                        m.flash('В архив: ${before - m.tasks.length}', 'ok');
                      }, pad: 0),
                    ],
                    const SectionLabel('О программе'),
                    Text('Информационная панель 2.0. Данные совместимы с прежней версией.', style: T.tiny),
                    Text('Сегодня ${dayLong(m.today)} ${m.today.year}', style: T.tiny.copyWith(color: C.faint)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

Widget _soundRow(PanelModel m, String kind, String label) {
  final sounds = (m.s['sounds'] as Map?) ?? {};
  final cfg = (sounds[kind] as Map?) ?? {'file': 'default'};
  final cur = '${cfg['file'] ?? 'default'}';
  final files = m.storage.systemSounds();
  String nameOf(String path) {
    final n = path.split(RegExp(r'[\\/]')).last;
    return n.toLowerCase().endsWith('.wav') ? n.substring(0, n.length - 4) : n;
  }

  final items = <String>['default', 'none', ...files, if (cur != 'default' && cur != 'none' && !files.contains(cur)) cur];
  return Row(children: [
    SizedBox(width: 130, child: Text(label, style: T.small)),
    Expanded(
      child: DropdownButton<String>(
        value: cur,
        isExpanded: true,
        isDense: true,
        dropdownColor: C.card,
        items: [
          for (final f in items)
            DropdownMenuItem(
              value: f,
              child: Text(f == 'default' ? 'Системный звук' : f == 'none' ? 'Без звука' : nameOf(f), style: T.small, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          final all = Map<String, dynamic>.from(sounds);
          all[kind] = {...Map<String, dynamic>.from(cfg), 'file': v};
          m.setSetting('sounds', all);
        },
      ),
    ),
    IconBtn(Icons.play_arrow_rounded, 'Послушать', () => m.storage.playSound(cur), color: C.accent),
  ]);
}

class _AutostartRow extends StatefulWidget {
  @override
  State<_AutostartRow> createState() => _AutostartRowState();
}

class _AutostartRowState extends State<_AutostartRow> {
  bool? on;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    on ??= m.storage.autostartEnabled();
    return InkWell(
      onTap: () {
        m.storage.setAutostart(!on!);
        setState(() => on = m.storage.autostartEnabled());
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(on! ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: on! ? C.accent : C.muted),
          const SizedBox(width: 8),
          Expanded(child: Text('Запускать вместе с Windows', style: T.small)),
        ]),
      ),
    );
  }
}

/// Выбор темы: образец фона, плашки и акцента, название.
class _ThemeChip extends StatelessWidget {
  const _ThemeChip({required this.keyName, required this.p, required this.selected});
  final String keyName;
  final Palette p;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final m = Scope.of(context).m;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: InkWell(
        onTap: () => m.setSetting('ui_theme', keyName),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? C.accent : C.faint, width: selected ? 2 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 26,
              height: 18,
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(p.cardRadius > 0 ? 3 : 0)),
              alignment: Alignment.center,
              child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 8),
            Text(p.title, style: TextStyle(fontSize: 12, color: p.fg)),
          ]),
        ),
      ),
    );
  }
}
