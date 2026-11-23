// Трей и системные уведомления есть только на ПК; в браузере — заглушка.
export 'system_stub.dart' if (dart.library.io) 'system_io.dart';
