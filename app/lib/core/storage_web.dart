/// В браузере (демо-страница) данные живут только в памяти.
class Storage {
  Storage({String? dirPath});

  static const bool persistent = false;

  String? corrupt;
  String? restored;
  bool blocked = false;

  Map<String, dynamic>? read() => null;

  bool write(Map<String, dynamic> d) => true;

  final _archive = <dynamic>[];
  List<dynamic> readArchive() => _archive;
  bool appendArchive(List<dynamic> items) {
    _archive.addAll(items);
    return true;
  }

  void logError(String text) {}

  String get logPath => '';
  String get dataDir => '';

  Future<String?> fetchText(String url) async => null;

  void openExternal(String target) {}

  Future<void> relaunch() async {}

  static const windowTitle = 'Информационная панель';
  bool acquireSingleInstance({bool wait = false}) => true;
  bool activateExisting() => false;

  List<String> systemSounds() => [];
  void playSound(String file) {}
  bool ctrlPressed() => false;
  bool autostartEnabled() => false;
  void setAutostart(bool on) {}

  bool embedInDesktop() => false;
  void releaseFromDesktop() {}

  Object pack(String s) => s;
  String unpack(Object o) => o as String;
}
