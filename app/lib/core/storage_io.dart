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

  // ---------- звуки ----------
  /// Звуки Windows из C:\Windows\Media.
  List<String> systemSounds() {
    if (!Platform.isWindows) return [];
    final dir = Directory('${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Media');
    if (!dir.existsSync()) return [];
    final list = dir.listSync().whereType<File>().map((f) => f.path).where((p) => p.toLowerCase().endsWith('.wav')).toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// file: 'default' — системный звук, 'none' — тишина, иначе путь к .wav.
  void playSound(String file) {
    if (!Platform.isWindows || file == 'none') return;
    try {
      if (file == 'default' || !File(file).existsSync()) {
        final u32 = DynamicLibrary.open('user32.dll');
        u32.lookupFunction<Int32 Function(Uint32), int Function(int)>('MessageBeep')(0x40); // MB_ICONINFORMATION
        return;
      }
      final winmm = DynamicLibrary.open('winmm.dll');
      final play = winmm.lookupFunction<Int32 Function(Pointer<Utf16>, IntPtr, Uint32), int Function(Pointer<Utf16>, int, int)>('PlaySoundW');
      final path = file.toNativeUtf16();
      // SND_FILENAME | SND_ASYNC | SND_NODEFAULT; строку не освобождаем сразу — звук играет асинхронно
      play(path, 0, 0x20000 | 0x1 | 0x2);
      Future<void>.delayed(const Duration(seconds: 30), () => calloc.free(path));
    } catch (e) {
      logError('Звук не проигрался: $file\n$e');
    }
  }

  // ---------- клавиши ----------
  bool ctrlPressed() {
    if (!Platform.isWindows) return false;
    final u32 = DynamicLibrary.open('user32.dll');
    final state = u32.lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState')(0x11);
    return (state & 0x8000) != 0;
  }

  // ---------- автозапуск ----------
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  bool autostartEnabled() {
    if (!Platform.isWindows) return false;
    final r = Process.runSync('reg', ['query', _runKey, '/v', 'DesktopPanel']);
    return r.exitCode == 0 && '${r.stdout}'.toLowerCase().contains(Platform.resolvedExecutable.toLowerCase());
  }

  void setAutostart(bool on) {
    if (!Platform.isWindows) return;
    if (on) {
      Process.runSync('reg', ['add', _runKey, '/v', 'DesktopPanel', '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}"', '/f']);
    } else {
      Process.runSync('reg', ['delete', _runKey, '/v', 'DesktopPanel', '/f']);
    }
  }

  // ---------- под ярлыками рабочего стола ----------
  // Как в Python-версии: Progman по сообщению 0x052C создаёт слой WorkerW позади значков,
  // туда же встраиваются «живые обои». Окно становится его дочерним окном.
  static final List<int> _found = [];

  static int _enumProc(int hwnd, int lParam) {
    final u = DynamicLibrary.open('user32.dll');
    final findEx = u.lookupFunction<IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
    final shell = 'SHELLDLL_DefView'.toNativeUtf16();
    final worker = 'WorkerW'.toNativeUtf16();
    try {
      if (findEx(hwnd, 0, shell, nullptr) != 0) {
        final w = findEx(0, hwnd, worker, nullptr);
        if (w != 0) _found.add(w);
      }
    } finally {
      calloc.free(shell);
      calloc.free(worker);
    }
    return 1;
  }

  DynamicLibrary get _u => DynamicLibrary.open('user32.dll');

  int _selfHwnd() {
    final find = _u.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>), int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
    final title = windowTitle.toNativeUtf16();
    try {
      return find(nullptr, title);
    } finally {
      calloc.free(title);
    }
  }

  int _desktopLayer() {
    final find = _u.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>), int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
    final findEx = _u.lookupFunction<IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
    final send = _u.lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr, Uint32, Uint32, Pointer<IntPtr>),
        int Function(int, int, int, int, int, int, Pointer<IntPtr>)>('SendMessageTimeoutW');
    final enumWindows = _u.lookupFunction<Int32 Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, IntPtr),
        int Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, int)>('EnumWindows');
    final cls = 'Progman'.toNativeUtf16();
    final worker = 'WorkerW'.toNativeUtf16();
    final res = calloc<IntPtr>();
    try {
      final progman = find(cls, nullptr);
      if (progman == 0) return 0;
      send(progman, 0x052C, 0xD, 0x1, 0, 1000, res);
      send(progman, 0x052C, 0, 0, 0, 1000, res);
      _found.clear();
      enumWindows(Pointer.fromFunction<Int32 Function(IntPtr, IntPtr)>(_enumProc, 1), 0);
      final w = _found.isNotEmpty ? _found.first : findEx(progman, 0, worker, nullptr);
      logError('Слой рабочего стола: Windows ${Platform.operatingSystemVersion}; Progman=$progman; WorkerW=$w; '
          'способ=${_found.isNotEmpty ? 'отдельное окно' : w != 0 ? 'внутри Progman' : 'не найден'}');
      return w;
    } finally {
      calloc.free(cls);
      calloc.free(worker);
      calloc.free(res);
    }
  }

  (int, int, int, int) _rect(int hwnd) {
    final get = _u.lookupFunction<Int32 Function(IntPtr, Pointer<Int32>), int Function(int, Pointer<Int32>)>('GetWindowRect');
    final r = calloc<Int32>(4);
    try {
      get(hwnd, r);
      return (r[0], r[1], r[2], r[3]);
    } finally {
      calloc.free(r);
    }
  }

  void _setStyles(int hwnd, {required bool child}) {
    final getL = _u.lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>('GetWindowLongPtrW');
    final setL = _u.lookupFunction<IntPtr Function(IntPtr, Int32, IntPtr), int Function(int, int, int)>('SetWindowLongPtrW');
    const gwlStyle = -16, gwlExStyle = -20, wsChild = 0x40000000, wsPopup = 0x80000000;
    const wsExLayered = 0x80000, wsExTransparent = 0x20;
    if (child) {
      // дочернее окно не может быть «слоистым» — Windows его просто не рисует
      setL(hwnd, gwlExStyle, getL(hwnd, gwlExStyle) & ~(wsExLayered | wsExTransparent));
      setL(hwnd, gwlStyle, (getL(hwnd, gwlStyle) & ~wsPopup) | wsChild);
    } else {
      setL(hwnd, gwlStyle, (getL(hwnd, gwlStyle) & ~wsChild) | wsPopup);
    }
  }

  /// Встраивает панель под ярлыки. false — слой не найден или окно не нашлось.
  bool embedInDesktop() {
    if (!Platform.isWindows) return false;
    try {
      final self = _selfHwnd();
      final parent = _desktopLayer();
      if (self == 0 || parent == 0) return false;
      final (l, t, r, b) = _rect(self);
      final (pl, pt, _, _) = _rect(parent);
      _setStyles(self, child: true);
      _u.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('SetParent')(self, parent);
      _setPos(self, l - pl, t - pt, r - l, b - t);
      return true;
    } catch (e, st) {
      logError('Не удалось встроить панель в рабочий стол:\n$e\n$st');
      return false;
    }
  }

  /// Возвращает панель обычным окном на прежнее место экрана.
  void releaseFromDesktop() {
    if (!Platform.isWindows) return;
    try {
      final self = _selfHwnd();
      if (self == 0) return;
      final (l, t, r, b) = _rect(self); // уже в экранных координатах
      _u.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('SetParent')(self, 0);
      _setStyles(self, child: false);
      _setPos(self, l, t, r - l, b - t);
    } catch (e, st) {
      logError('Не удалось вернуть панель из рабочего стола:\n$e\n$st');
    }
  }

  void _setPos(int hwnd, int x, int y, int w, int h) {
    final setPos = _u.lookupFunction<Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
        int Function(int, int, int, int, int, int, int)>('SetWindowPos');
    const noZ = 0x4, noAct = 0x10, show = 0x40, frame = 0x20;
    setPos(hwnd, 0, x, y, w, h, noZ | noAct | show | frame);
  }

  /// Сжатие снимков истории отмены.
  Object pack(String s) => zlib.encode(utf8.encode(s));
  String unpack(Object o) => o is String ? o : utf8.decode(zlib.decode(o as List<int>));
}
