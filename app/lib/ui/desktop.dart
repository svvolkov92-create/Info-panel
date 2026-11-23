import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/model.dart';
import 'theme.dart';

/// Панель на ПК: окно без рамки (виджет) или обычное окно. В браузере (демо) — ничего этого нет.
final bool isDesktop = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

class DesktopWindow with WindowListener {
  DesktopWindow(this.m);
  final PanelModel m;

  bool get widgetMode => m.s['ui_mode'] != 'window';
  String get _boundsKey => widgetMode ? 'ui_bounds' : 'ui_bounds_window';

  bool hasTray = false;
  Timer? _ctPoll;
  bool _ctIgnoring = false;

  Rect? _restore; // размер до временного расширения под большое окно
  int _room = 0;
  Timer? _boundsTimer;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    final widget = widgetMode;
    final options = WindowOptions(
      size: widget ? const Size(340, 860) : const Size(980, 760),
      minimumSize: const Size(240, 240),
      skipTaskbar: widget,
      titleBarStyle: widget ? TitleBarStyle.hidden : TitleBarStyle.normal,
      backgroundColor: C.bg,
      title: 'Информационная панель',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (widget) await windowManager.setAsFrameless();
      await _applyBounds();
      await applyLayer();
      await windowManager.show();
      if (!widget) await windowManager.focus();
    });
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    if (m.s['click_through'] == true) await setClickThrough(true);
  }

  Future<void> showPanel() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hidePanel() => windowManager.hide();

  Future<void> toggleVisible() async {
    if (await windowManager.isVisible()) {
      await hidePanel();
    } else {
      await showPanel();
    }
  }

  Future<void> quit() async {
    _boundsTimer?.cancel();
    _ctPoll?.cancel();
    await _saveBounds();
    m.flushSave();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  /// Сквозные клики: щелчки проходят сквозь панель на рабочий стол; с зажатым Ctrl панель снова кликабельна.
  Future<void> setClickThrough(bool on) async {
    m.setSetting('click_through', on);
    _ctPoll?.cancel();
    if (!on) {
      _ctIgnoring = false;
      await windowManager.setIgnoreMouseEvents(false);
      return;
    }
    _ctPoll = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      final ignore = !m.storage.ctrlPressed();
      if (ignore != _ctIgnoring) {
        _ctIgnoring = ignore;
        await windowManager.setIgnoreMouseEvents(ignore);
      }
    });
  }

  Future<void> _applyBounds() async {
    final b = m.s[_boundsKey];
    if (b is List && b.length == 4 && b.every((x) => x is num)) {
      final r = Rect.fromLTWH((b[0] as num).toDouble(), (b[1] as num).toDouble(), (b[2] as num).toDouble(), (b[3] as num).toDouble());
      // окно, ушедшее за пределы экранов (отключили монитор), возвращаем на место
      if (r.left > -10000 && r.top > -10000 && r.left < 20000 && r.top < 20000 && r.width >= 200 && r.height >= 200) {
        await windowManager.setBounds(r);
        return;
      }
    }
    await windowManager.setAlignment(widgetMode ? Alignment.topRight : Alignment.center);
  }

  bool embedded = false;

  Future<void> applyLayer() async {
    final layer = m.s['ui_layer'];
    if (layer == 'desktop') {
      if (embedded) return;
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setAlwaysOnBottom(false);
      await windowManager.setOpacity(1); // под ярлыками полупрозрачность невозможна
      embedded = m.storage.embedInDesktop();
      if (!embedded) {
        m.s['ui_layer'] = 'bottom';
        m.save();
        m.notice(Notice('Не получилось', 'Не нашёл слой рабочего стола под ярлыками в этой версии Windows. '
            'Панель оставлена «под окнами». Подробности в журнале ошибок.', kind: 'danger', seconds: 15));
        await windowManager.setAlwaysOnBottom(true);
      } else if (m.s['desk_confirmed'] != true) {
        _askDeskConfirm();
      }
      return;
    }
    if (embedded) {
      m.storage.releaseFromDesktop();
      embedded = false;
    }
    await windowManager.setAlwaysOnTop(layer == 'top');
    await windowManager.setAlwaysOnBottom(layer == 'bottom');
    await windowManager.setOpacity(((m.s['alpha'] as num?) ?? 1).toDouble().clamp(0.3, 1.0));
  }

  /// Не видно панель под ярлыками — сама вернётся через 15 секунд.
  void _askDeskConfirm() {
    var answered = false;
    m.notice(Notice('Панель видна под ярлыками?', 'Если нет — ничего не нажимайте: через 15 секунд она вернётся сама.',
        seconds: 15,
        actions: [
          ('Да, видна', () {
            answered = true;
            m.setSetting('desk_confirmed', true);
          }),
          ('Нет, вернуть', () {
            answered = true;
            setLayer('bottom');
          }),
        ]));
    Timer(const Duration(milliseconds: 15500), () {
      if (!answered && embedded) {
        setLayer('bottom');
        m.notice(Notice('Вернул панель', 'Под ярлыками её не было видно, поэтому режим выключен. '
            'Пришлите, пожалуйста, журнал ошибок — там сведения о рабочем столе.', kind: 'warn', seconds: 30));
      }
    });
  }

  Future<void> setOpacity(double v) async {
    m.setSetting('alpha', v);
    if (!embedded) await windowManager.setOpacity(v);
  }

  Future<void> setLayer(String layer) async {
    m.setSetting('ui_layer', layer);
    await applyLayer();
  }

  /// Переключение «виджет / окно» меняет рамку окна, поэтому панель перезапускается.
  Future<void> setMode(String mode) async {
    if (m.s['ui_mode'] == mode) return;
    await _saveBounds();
    m.setSetting('ui_mode', mode);
    await restart();
  }

  Future<void> restart() async {
    m.flushSave();
    await m.storage.relaunch();
  }

  Future<void> _saveBounds() async {
    if (_room > 0) return;
    final r = await windowManager.getBounds();
    m.s[_boundsKey] = [r.left.roundToDouble(), r.top.roundToDouble(), r.width.roundToDouble(), r.height.roundToDouble()];
    m.save();
  }

  @override
  void onWindowMoved() => _scheduleBounds();

  @override
  void onWindowResized() => _scheduleBounds();

  void _scheduleBounds() {
    _boundsTimer?.cancel();
    _boundsTimer = Timer(const Duration(milliseconds: 400), _saveBounds);
  }

  /// Крестик окна: при значке в трее панель прячется, выход — из меню трея.
  @override
  void onWindowClose() async {
    if (hasTray) {
      await _saveBounds();
      m.flushSave();
      await hidePanel();
      return;
    }
    await quit();
  }

  void startDrag() {
    if (!embedded) windowManager.startDragging(); // под ярлыками окно дочернее — двигать нельзя
  }

  void startResize(ResizeEdge edge) => windowManager.startResizing(edge);

  Future<void> close() async => hasTray ? hidePanel() : quit();

  Future<void> minimize() => windowManager.minimize();

  /// Виджет узкий: на время большого окна (карточка, неделя) раздвигаем его влево, потом возвращаем.
  Future<T?> withRoom<T>(Size need, Future<T?> Function() open) async {
    if (!widgetMode) return open();
    final scale = ((m.s['ui_scale'] as num?) ?? 1).toDouble();
    final w = need.width * scale + 24, h = need.height * scale + 24;
    final b = await windowManager.getBounds();
    final bottomLayer = m.s['ui_layer'] == 'bottom';
    if (embedded) return open(); // встроенное в рабочий стол окно не раздвигаем
    if (b.width >= w && b.height >= h && !bottomLayer) return open();
    if (_room == 0) _restore = b;
    _room++;
    try {
      if (b.width < w || b.height < h) {
        await windowManager.setBounds(await _roomRect(b, w, h));
      }
      if (bottomLayer) await windowManager.setAlwaysOnBottom(false);
      await windowManager.focus();
      return await open();
    } finally {
      _room--;
      if (_room == 0) {
        final r = _restore;
        if (r != null) await windowManager.setBounds(r);
        await applyLayer();
      }
    }
  }

  /// Куда раздвинуть виджет: в сторону, где есть место, и не дальше краёв экрана.
  Future<Rect> _roomRect(Rect b, double w, double h) async {
    var screen = Rect.fromLTWH(0, 0, 1920, 1040);
    try {
      final displays = await screenRetriever.getAllDisplays();
      for (final d in displays) {
        final pos = d.visiblePosition ?? Offset.zero;
        final size = d.visibleSize ?? d.size;
        final r = pos & size;
        if (r.contains(b.center)) {
          screen = r;
          break;
        }
        if (d == displays.first) screen = r;
      }
    } catch (e) {
      m.storage.logError('Не удалось узнать размер экрана: $e');
    }
    final nw = math.min(math.max(b.width, w), screen.width);
    final nh = math.min(math.max(b.height, h), screen.height);
    // по умолчанию растём влево (виджет обычно справа), но не за левый край экрана
    final left = (b.right - nw).clamp(screen.left, screen.right - nw);
    final top = b.top.clamp(screen.top, screen.bottom - nh);
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), nw, nh);
  }
}
