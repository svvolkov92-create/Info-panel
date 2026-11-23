/// В браузере (демо-страница) данные живут только в памяти.
class Storage {
  Storage({String? dirPath});

  static const bool persistent = false;

  String? corrupt;
  String? restored;
  bool blocked = false;

  Map<String, dynamic>? read() => null;

  bool write(Map<String, dynamic> d) => true;

  void logError(String text) {}

  String get logPath => '';
  String get dataDir => '';

  Future<String?> fetchText(String url) async => null;
}
