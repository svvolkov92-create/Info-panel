import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  m.load(demo: kIsWeb ? demoData(DateTime.now()) : null);
  DesktopWindow? desk;
  if (isDesktop) {
    desk = DesktopWindow(m);
    await desk.init();
  }
  m.start();
  runApp(PanelApp(m: m, desk: desk));
}
