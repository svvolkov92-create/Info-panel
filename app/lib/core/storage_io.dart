import 'dart:convert';
import 'dart:io';

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
}
