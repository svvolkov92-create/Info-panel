import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/model.dart';
import 'ui/app.dart';
import 'ui/desktop.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final m = PanelModel();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    m.storage.logError('${details.exceptionAsString()}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    m.storage.logError('$error\n$stack');
    return true;
  };
  if (!m.storage.acquireSingleInstance(wait: args.contains('--restart'))) {
    // панель уже работает: показываем её и выходим; если это прежняя версия — объясняем
    if (!m.storage.activateExisting()) runApp(const AlreadyRunningApp());
    return;
  }
  m.load(demo: kIsWeb ? demoData(DateTime.now()) : null);
  DesktopWindow? desk;
  if (isDesktop) {
    desk = DesktopWindow(m);
    await desk.init();
  }
  m.start();
  runApp(PanelApp(m: m, desk: desk));
}

/// Запущена прежняя (Python) версия панели — работать с одними данными вдвоём нельзя.
class AlreadyRunningApp extends StatelessWidget {
  const AlreadyRunningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1F24),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Панель уже запущена',
                  style: TextStyle(color: Color(0xFFE8E8EC), fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const Text(
                'Скорее всего, работает прежняя версия панели. Закройте её: правый щелчок по значку в трее, «Выход». '
                'Затем запустите панель снова.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8B8D98), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: () => SystemNavigator.pop(), child: const Text('Понятно')),
            ]),
          ),
        ),
      ),
    );
  }
}
