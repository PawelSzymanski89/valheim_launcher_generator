class FileInfo {
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modifiedDate;
  final String permission;
  final String? owner;
  final String? group;
  final int? uid;
  final int? gid;
  final String? mode;
  final String? unique;
  final String type;
  FileInfo({
    required this.name,
    required this.isDir,
    required this.size,
    required this.modifiedDate,
    required this.permission,
    this.owner,
    this.group,
    this.uid,
    this.gid,
    this.mode,
    this.unique,
    required this.type,
  });
  String get sizeFormatted {
    if (isDir) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(2)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  String get modifiedFormatted {
    if (modifiedDate == null) return 'Unknown';
    return '${modifiedDate!.year}-${modifiedDate!.month.toString().padLeft(2, '0')}-${modifiedDate!.day.toString().padLeft(2, '0')} ${modifiedDate!.hour.toString().padLeft(2, '0')}:${modifiedDate!.minute.toString().padLeft(2, '0')}';
  }
}
