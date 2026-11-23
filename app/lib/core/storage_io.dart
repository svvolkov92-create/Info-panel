import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Файлы данных: data.json, копия прошлого сохранения data.bak.json, журнал ошибок error.log.
/// Логика та же, что в Python-версии, поэтому обе программы читают один и тот же файл.
class Storage {
  Storage({String? dirPath}) {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    dir = Directory(dirPath ?? '$base${Platform.pathSeparator}DesktopPanel');
  }

  static const bool persistent = true;

  late final Directory dir;
  String? corrupt; // куда переложили испорченный data.json
  String? restored; // откуда восстановили данные
  bool blocked = false; // данные не разобрались — не пишем поверх

  File get _data => File(_p('data.json'));
  File get _bak => File(_p('data.bak.json'));
  File get _log => File(_p('error.log'));
  String _p(String name) => '${dir.path}${Platform.pathSeparator}$name';

  Map<String, dynamic> _readJson(File f) {
    final loaded = jsonDecode(f.readAsStringSync());
    if (loaded is! Map<String, dynamic> || (loaded['tasks'] != null && loaded['tasks'] is! List)) {
      throw const FormatException('неожиданная структура файла');
    }
    return loaded;
  }

  /// Данные из data.json, а если он испорчен или пропал — из копии прошлого сохранения.
  Map<String, dynamic>? read() {
    if (_data.existsSync()) {
      try {
        return _readJson(_data);
      } catch (e, st) {
        final n = DateTime.now();
        final stamp = '${n.year}${_2(n.month)}${_2(n.day)}-${_2(n.hour)}${_2(n.minute)}${_2(n.second)}';
        final bad = _p('data.corrupt-$stamp.json');
        try {
          _data.renameSync(bad);
          corrupt = bad;
        } catch (_) {
          corrupt = _data.path;
          blocked = true; // не смогли убрать в сторону — не пишем поверх
        }
        logError('data.json не читается (сохранён как $corrupt):\n$e\n$st');
      }
    }
    if (!_bak.existsSync()) return null;
    try {
      final loaded = _readJson(_bak);
      if (corrupt != null) restored = _bak.path;
      return loaded;
    } catch (e, st) {
      logError('Копия данных тоже не читается:\n$e\n$st');
      return null;
    }
  }

  /// Атомарная запись: сначала во временный файл, прежняя версия остаётся копией.
  bool write(Map<String, dynamic> d) {
    if (blocked) return false;
    try {
      dir.createSync(recursive: true);
      final tmp = File(_p('data.json.tmp'));
      final raf = tmp.openSync(mode: FileMode.write);
      try {
        raf.writeStringSync(const JsonEncoder.withIndent(' ').convert(d));
        raf.flushSync();
      } finally {
        raf.closeSync();
      }
      if (_data.existsSync()) {
        if (_bak.existsSync()) _bak.deleteSync();
        _data.renameSync(_bak.path);
      }
      tmp.renameSync(_data.path);
      return true;
    } catch (e, st) {
      logError('Не удалось сохранить данные:\n$e\n$st');
      return false;
    }
  }

  void logError(String text) {
    try {
      dir.createSync(recursive: true);
      if (_log.existsSync() && _log.lengthSync() > 1024 * 1024) {
        final old = File(_p('error.old.log'));
        if (old.existsSync()) old.deleteSync();
        _log.renameSync(old.path);
      }
      _log.writeAsStringSync('\n[${DateTime.now()}]\n$text\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // журнал — последнее средство; если и он не пишется, сделать уже ничего нельзя
    }
  }

  String get logPath => _log.path;
  String get dataDir => dir.path;

  /// Производственный календарь: строка из 365/366 цифр или null.
  Future<String?> fetchText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'DesktopPanel');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      return (await resp.transform(const AsciiDecoder(allowInvalid: true)).join()).trim();
    } finally {
      client.close(force: true);
    }
  }

  static String _2(int n) => n.toString().padLeft(2, '0');

  /// Открывает ссылку, файл или папку программой по умолчанию (как os.startfile в Python).
  void openExternal(String target) {
    var t = target.trim().replaceAll('"', '');
    while (t.isNotEmpty && '.,;:)'.contains(t[t.length - 1])) {
      t = t.substring(0, t.length - 1);
    }
    if (t.toLowerCase().startsWith('www.')) t = 'https://$t';
    if (Platform.isWindows) {
      Process.start('explorer', [t], runInShell: false);
    } else if (Platform.isMacOS) {
      Process.start('open', [t]);
    } else {
      Process.start('xdg-open', [t]);
    }
  }

  /// Перезапуск программы (после смены режима «виджет / окно»).
  Future<void> relaunch() async {
    await Process.start(Platform.resolvedExecutable, ['--restart'], mode: ProcessStartMode.detached);
    exit(0);
  }

  // ---------- одна копия программы ----------
  // Тот же системный флаг, что у Python-версии: обе версии не могут работать с данными одновременно.
  static const _mutexName = r'Local\DesktopPanelSingleInstance';
  static const windowTitle = 'Информационная панель';

  /// true — эта копия единственная. wait — подождать, пока закроется прежняя (перезапуск).
  bool acquireSingleInstance({bool wait = false}) {
    if (!Platform.isWindows) return true;
    final k32 = DynamicLibrary.open('kernel32.dll');
    final createMutex = k32.lookupFunction<IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');
    final getLastError = k32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
    final closeHandle = k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    final name = _mutexName.toNativeUtf16();
    try {
      for (var i = 0; i < (wait ? 50 : 1); i++) {
        final h = createMutex(nullptr, 0, name);
        if (h != 0 && getLastError() != 183) return true; // 183 — ERROR_ALREADY_EXISTS
        if (h != 0) closeHandle(h);
        if (wait) sleep(const Duration(milliseconds: 100));
      }
      return false;
    } finally {
      calloc.free(name);
    }
  }

  /// Показывает уже открытую панель (новой версии). false — окно не найдено.
  bool activateExisting() {
    if (!Platform.isWindows) return false;
    final u32 = DynamicLibrary.open('user32.dll');
    final findWindow = u32.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
    final showWindow = u32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
    final setForeground = u32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
    final title = windowTitle.toNativeUtf16();
    try {
      final hwnd = findWindow(nullptr, title);
      if (hwnd == 0) return false;
      showWindow(hwnd, 9); // SW_RESTORE
      setForeground(hwnd);
      return true;
    } finally {
      calloc.free(title);
    }
  }
}
