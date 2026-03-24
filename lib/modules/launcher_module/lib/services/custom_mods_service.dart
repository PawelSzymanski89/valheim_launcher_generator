import 'dart:io';
import 'package:path/path.dart' as p;

/// Result of copying custom_mods into BepInEx
class CustomModsResult {
  final bool performed; // whether custom_mods folder was present and an attempt was made
  final int filesCopied;
  final List<String> errors;
  final String message;

  CustomModsResult({required this.performed, required this.filesCopied, required this.errors, required this.message});
}

class CustomModsService {
  /// Copies the contents of a sibling `custom_mods` folder (sibling to the Valheim folder)
  /// into the game's `BepInEx` folder. Overwrites conflicting files.
  ///
  /// - `gameRoot` is the absolute path to the Valheim folder (where `valheim.exe` resides).
  /// Returns a [CustomModsResult] describing what happened.
  Future<CustomModsResult> copyCustomModsToBepInEx(String gameRoot) async {
    try {
      final valheimDir = Directory(gameRoot);
      if (!await valheimDir.exists()) {
        return CustomModsResult(performed: false, filesCopied: 0, errors: [], message: 'Valheim folder nie istnieje');
      }

      final customDir = Directory(p.join(gameRoot, 'custom_mods'));
      if (!await customDir.exists()) {
        return CustomModsResult(performed: false, filesCopied: 0, errors: [], message: 'Brak folderu custom_mods');
      }

      final bepDir = Directory(p.join(gameRoot, 'BepInEx'));
      if (!await bepDir.exists()) {
        try {
          await bepDir.create(recursive: true);
        } catch (e) {
          return CustomModsResult(performed: true, filesCopied: 0, errors: ['Nie można utworzyć BepInEx: $e'], message: 'Błąd tworzenia BepInEx');
        }
      }

      int copied = 0;
      final errors = <String>[];

      // Iterate recursively through custom_mods
      await for (final entity in customDir.list(recursive: true, followLinks: false)) {
        try {
          var rel = p.relative(entity.path, from: customDir.path);
          // Normalize separators
          rel = rel.replaceAll('\\', '/');
          // If the first path segment is 'BepInEx' (case-insensitive), strip it so contents merge into target BepInEx root
          final parts = p.split(rel);
          if (parts.isNotEmpty && parts[0].toLowerCase() == 'bepinex') {
            final remaining = parts.sublist(1);
            if (remaining.isEmpty) {
              // This is the top-level BepInEx dir in custom_mods; ensure target BepInEx exists and continue
              if (entity is Directory) {
                try { if (!await Directory(p.join(bepDir.path)).exists()) await Directory(p.join(bepDir.path)).create(recursive: true); } catch (e) { errors.add('Failed ensure target BepInEx dir: $e'); }
                continue;
              }
            }
            rel = p.joinAll(remaining);
          }

          final targetPath = p.join(bepDir.path, rel);
          if (entity is File) {
            final targetFile = File(targetPath);
            try {
              await targetFile.parent.create(recursive: true);
            } catch (_) {}
            try {
              // If target exists, overwrite by deleting first (robust on Windows)
              if (await targetFile.exists()) {
                try {
                  await targetFile.delete();
                } catch (_) {}
              }
              await entity.copy(targetFile.path);
              // try to preserve modified time
              try { await targetFile.setLastModified(await entity.lastModified()); } catch (_) {}
              copied++;
            } catch (e) {
              errors.add('Failed to copy file ${entity.path} -> $targetPath : $e');
            }
          } else if (entity is Directory) {
            final d = Directory(targetPath);
            try {
              if (!await d.exists()) await d.create(recursive: true);
            } catch (e) {
              // not fatal, record
              errors.add('Failed to create dir ${d.path}: $e');
            }
          }
        } catch (e) {
          errors.add('Error processing entity ${entity.path}: $e');
        }
      }

      final msg = 'Copied $copied file(s) from custom_mods into BepInEx';
      return CustomModsResult(performed: true, filesCopied: copied, errors: errors, message: msg);
    } catch (e) {
      return CustomModsResult(performed: true, filesCopied: 0, errors: ['Unhandled error: $e'], message: 'Unhandled error during custom_mods copy');
    }
  }
}
