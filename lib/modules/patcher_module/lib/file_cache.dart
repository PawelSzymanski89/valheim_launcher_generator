class FileCache {
  final String name;
  final String path;
  final int size; // Dla plików rozmiar, dla folderów 0
  final String type; // 'file' lub 'dir'
  final String extension; // Dla plików rozszerzenie, dla folderów pusty string
  final DateTime? modifyTime; // data modyfikacji pliku z serwera
  final String? computedHash; // wygenerowany hash na bazie daty i rozmiaru

  FileCache({
    required this.name,
    required this.path,
    required this.size,
    required this.type,
    required this.extension,
    this.modifyTime,
    this.computedHash,
  });

  // Getter dla pełnej ścieżki
  String get fullPath => path.endsWith('/') ? '$path$name' : '$path/$name';

  // Getter zwracający dostępny hash
  String? get hash => computedHash;
}
