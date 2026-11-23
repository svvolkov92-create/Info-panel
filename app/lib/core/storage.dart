// Хранилище данных. На ПК — файлы в %APPDATA%\DesktopPanel (те же, что у Python-версии),
// в браузере (демо) — только память.
export 'storage_web.dart' if (dart.library.io) 'storage_io.dart';
