import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  Future<void> applyLayer() async {
    final layer = m.s['ui_layer'];
    await windowManager.setAlwaysOnTop(layer == 'top');
    await windowManager.setAlwaysOnBottom(layer == 'bottom' || layer == 'desktop');
    await windowManager.setOpacity(((m.s['alpha'] as num?) ?? 1).toDouble().clamp(0.3, 1.0));
  }

  Future<void> setOpacity(double v) async {
    m.setSetting('alpha', v);
    await windowManager.setOpacity(v);
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

  @override
  void onWindowClose() async {
    _boundsTimer?.cancel();
    await _saveBounds();
    m.flushSave();
    await windowManager.destroy();
  }

  void startDrag() => windowManager.startDragging();

  void startResize(ResizeEdge edge) => windowManager.startResizing(edge);

  Future<void> close() => windowManager.close();

  Future<void> minimize() => windowManager.minimize();

  /// Виджет узкий: на время большого окна (карточка, неделя) раздвигаем его влево, потом возвращаем.
  Future<T?> withRoom<T>(Size need, Future<T?> Function() open) async {
    if (!widgetMode) return open();
    final scale = ((m.s['ui_scale'] as num?) ?? 1).toDouble();
    final w = need.width * scale + 24, h = need.height * scale + 24;
    final b = await windowManager.getBounds();
    final bottomLayer = m.s['ui_layer'] == 'bottom' || m.s['ui_layer'] == 'desktop';
    if (b.width >= w && b.height >= h && !bottomLayer) return open();
    if (_room == 0) _restore = b;
    _room++;
    try {
      if (b.width < w || b.height < h) {
        final nw = math.max(b.width, w), nh = math.max(b.height, h);
        await windowManager.setBounds(Rect.fromLTWH(b.right - nw, b.top, nw, nh));
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
}
