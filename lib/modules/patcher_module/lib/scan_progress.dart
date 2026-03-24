class ScanProgress {
  final int totalFiles;
  final int totalSize;
  final String currentPath;
  final List<String> scannedItems;
  final int activeConnections;
  ScanProgress({
    required this.totalFiles,
    required this.totalSize,
    required this.currentPath,
    required this.scannedItems,
    required this.activeConnections,
  });
  String get totalSizeFormatted {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(2)} KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
