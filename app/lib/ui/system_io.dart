import 'dart:io';

import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/core.dart';
import '../core/model.dart';
import 'desktop.dart';

/// Значок в трее и уведомления Windows.
class SystemIntegration with TrayListener {
  SystemIntegration(this.m, this.desk);
  final PanelModel m;
  final DesktopWindow? desk;
  void Function(String id)? onOpenTask;
  void Function()? onSettings;
  bool _tray = false;
  bool _notifier = false;

  Future<void> init() async {
    if (desk == null || !Platform.isWindows) return;
    try {
      await trayManager.setIcon('assets/tray.ico');
      await trayManager.setToolTip('Информационная панель');
      await _menu();
      trayManager.addListener(this);
      _tray = true;
      desk!.hasTray = true;
    } catch (e) {
      m.storage.logError('Трей не запустился: $e');
    }
    try {
      await localNotifier.setup(appName: 'Информационная панель', shortcutPolicy: ShortcutPolicy.requireCreate);
      _notifier = true;
    } catch (e) {
      m.storage.logError('Уведомления Windows недоступны: $e');
    }
  }

  Future<void> _menu() => trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Показать панель'),
        MenuItem(key: 'hide', label: 'Скрыть панель'),
        MenuItem.separator(),
        MenuItem(key: 'settings', label: 'Настройки…'),
        MenuItem(key: 'clickthrough', label: m.s['click_through'] == true ? 'Выключить сквозные клики' : 'Включить сквозные клики'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Выход'),
      ]));

  @override
  void onTrayIconMouseDown() => desk?.toggleVisible();

  @override
  void onTrayIconRightMouseDown() async {
    await _menu();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'show':
        await desk?.showPanel();
      case 'hide':
        await desk?.hidePanel();
      case 'settings':
        await desk?.showPanel();
        onSettings?.call();
      case 'clickthrough':
        await desk?.setClickThrough(m.s['click_through'] != true);
      case 'quit':
        await desk?.quit();
    }
  }

  /// Уведомление Windows — когда панель не на виду (свёрнута, под окнами или неактивна).
  Future<void> notify(Notice n) async {
    final sound = n.sound != null ? ((m.s['sounds'] as Map?)?[n.sound] as Map?)?['file'] as String? ?? 'default' : 'default';
    m.storage.playSound(sound);
    if (!_notifier) return;
    try {
      final focused = await windowManager.isFocused() && await windowManager.isVisible();
      if (focused) return;
    } catch (_) {
      // не узнали состояние окна — уведомление лишним не будет
    }
    final id = n.taskId;
    final note = LocalNotification(
      title: n.title,
      body: short(n.text, 120),
      silent: true,
      actions: id == null
          ? null
          : [
              LocalNotificationAction(text: 'Через 10 мин'),
              LocalNotificationAction(text: 'Через час'),
              LocalNotificationAction(text: 'Открыть'),
            ],
    );
    note.onClick = () async {
      await desk?.showPanel();
      if (id != null) onOpenTask?.call(id);
    };
    note.onClickAction = (i) async {
      if (id == null) return;
      if (i == 0) m.snooze(id, 10);
      if (i == 1) m.snooze(id, 60);
      if (i == 2) {
        await desk?.showPanel();
        onOpenTask?.call(id);
      }
    };
    await note.show();
  }

  void dispose() {
    if (_tray) {
      trayManager.removeListener(this);
      trayManager.destroy();
    }
  }
}
