import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'generator/config_manager.dart';
import 'utils/shared_salt.dart';

/// Result of a single module build.
class ModuleBuildResult {
  final String moduleName;
  final bool success;
  final String? exePath;
  final String? error;
  const ModuleBuildResult({
    required this.moduleName,
    required this.success,
    this.exePath,
    this.error,
  });
}

/// Orchestrates the full build pipeline:
///   1. Writes config_encrypted.json into each module's assets/
///   2. Runs `flutter build windows` for each module
///   3. Copies output exe to output/{serverName}/
///   4. Saves profile to profiles/{serverName}.json
class BuildService {
  final GeneratorConfig config;
  final void Function(String message) onLog;
  final void Function(double progress) onProgress;

  BuildService({
    required this.config,
    required this.onLog,
    required this.onProgress,
  });

  // Paths relative to generator project root
  static String get _generatorRoot {
    // When running as compiled exe: exe is in build/windows/runner/Release/
    // Project root is 4 levels up. In debug: Directory.current is the project root.
    final exe = Platform.resolvedExecutable;
    final exeDir = File(exe).parent;
    // Heuristic: go up until we find pubspec.yaml for the generator
    Directory dir = exeDir;
    for (int i = 0; i < 6; i++) {
      final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final content = pubspec.readAsStringSync();
        if (content.contains('valheim_launcher_generator')) return dir.path;
      }
      dir = dir.parent;
    }
    return Directory.current.path;
  }

  String get _modulesRoot => p.join(_generatorRoot, 'lib', 'modules');
  String get _outputRoot => p.join(_generatorRoot, 'output');
  String get _profilesRoot => p.join(_generatorRoot, 'profiles');

  /// Main entry point — runs the full build pipeline.
  /// Returns list of results for each module.
  Future<List<ModuleBuildResult>> run() async {
    final results = <ModuleBuildResult>[];
    double prog = 0.0;

    onLog('🔐 Generowanie zaszyfrowanego configa...');
    final encryptedJson = config.toEncryptedJson();
    final encryptedPayload = jsonEncode({'data': encryptedJson});
    onProgress(prog += 0.05);

    // Save profile
    onLog('💾 Zapisywanie profilu...');
    await _saveProfile(encryptedPayload);
    onProgress(prog += 0.05);

    // Save salt if requested
    if (config.saveSalt) {
      await SharedSalt.save(config.salt);
      onLog('🔑 Salt zapisany w rejestrze.');
    }

    final modules = [
      _ModuleSpec(
        name: 'launcher',
        dir: p.join(_modulesRoot, 'launcher_module'),
        exeName: 'server_launcher',
        outputAs: '${config.serverName} Launcher',
        weight: 0.25,
      ),
      _ModuleSpec(
        name: 'patcher',
        dir: p.join(_modulesRoot, 'patcher_module'),
        exeName: 'server_patcher',
        outputAs: '${config.serverName} Patcher',
        weight: 0.25,
      ),
      _ModuleSpec(
        name: 'updater',
        dir: p.join(_modulesRoot, 'updater_module'),
        exeName: 'server_updater',
        outputAs: '${config.serverName} Updater',
        weight: 0.25,
      ),
    ];

    for (final mod in modules) {
      onLog('\n📦 Budowanie ${mod.outputAs}.exe...');
      final result = await _buildModule(mod, encryptedPayload);
      results.add(result);
      prog += mod.weight;
      onProgress(prog.clamp(0.0, 0.95));
      if (result.success) {
        onLog('  ✅ ${mod.outputAs}.exe → ${result.exePath}');
      } else {
        onLog('  ❌ Błąd ${mod.name}: ${result.error}');
      }
    }

    onProgress(1.0);
    return results;
  }

  Future<void> _saveProfile(String encryptedPayload) async {
    try {
      final profileDir = Directory(_profilesRoot);
      await profileDir.create(recursive: true);
      final safeName = config.serverName.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final profileFile = File(p.join(_profilesRoot, '$safeName.json'));
      final profileData = jsonEncode({
        'serverName': config.serverName,
        'serverAddr': config.serverAddr,
        'ftpHost': config.ftpHost,
        'ftpPort': config.ftpPort,
        'ftpUser': config.ftpUser,
        'createdAt': DateTime.now().toIso8601String(),
        // NOTE: sensitive fields (ftpPassword, serverPassword, salt) are NOT stored in profile
        'encryptedConfig': encryptedPayload,
      });
      await profileFile.writeAsString(profileData);
    } catch (e) {
      onLog('  ⚠️ Nie udało się zapisać profilu: $e');
    }
  }

  Future<ModuleBuildResult> _buildModule(
      _ModuleSpec mod, String encryptedPayload) async {
    try {
      final modDir = Directory(mod.dir);
      if (!await modDir.exists()) {
        return ModuleBuildResult(
          moduleName: mod.name,
          success: false,
          error: 'Folder modułu nie istnieje: ${mod.dir}',
        );
      }

      // 1. Write config_encrypted.json to module assets
      onLog('  📝 Wstrzykuję config do ${mod.name}/assets/...');
      final assetsDir = Directory(p.join(mod.dir, 'assets'));
      await assetsDir.create(recursive: true);
      await File(p.join(assetsDir.path, 'config_encrypted.json'))
          .writeAsString(encryptedPayload);

      // 2. Write ftp_preview.json (plain preview, not used at runtime)
      await File(p.join(assetsDir.path, 'ftp_preview.json'))
          .writeAsString(const JsonEncoder.withIndent('  ')
              .convert(config.toFtpJson()));

      // 3. Ensure assets entry in pubspec (silent — rely on existing pubspec)

      // 4. Run flutter build windows
      onLog('  🔨 flutter build windows...');
      final buildResult = await _runFlutterBuild(mod);
      if (!buildResult.success) {
        return ModuleBuildResult(
          moduleName: mod.name,
          success: false,
          error: buildResult.error,
        );
      }

      // 5. Copy exe to output
      final exePath = await _copyOutput(mod);
      return ModuleBuildResult(
        moduleName: mod.name,
        success: true,
        exePath: exePath,
      );
    } catch (e) {
      return ModuleBuildResult(
        moduleName: mod.name,
        success: false,
        error: '$e',
      );
    }
  }

  Future<({bool success, String? error})> _runFlutterBuild(
      _ModuleSpec mod) async {
    try {
      final process = await Process.start(
        'flutter',
        [
          'build',
          'windows',
          '--release',
        ],
        workingDirectory: mod.dir,
        runInShell: true,
      );

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();

      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((line) {
        stdoutBuf.write(line);
        if (kDebugMode) debugPrint('[${mod.name}] $line');
      });
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((line) {
        stderrBuf.write(line);
      });

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        final err = stderrBuf.toString().trim();
        return (
          success: false,
          error: 'flutter build zakończony kodem $exitCode\n$err'
        );
      }
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Błąd uruchamiania flutter: $e');
    }
  }

  Future<String> _copyOutput(_ModuleSpec mod) async {
    // Built exe is at <modDir>/build/windows/x64/runner/Release/<exeName>.exe
    final releaseDir = Directory(p.join(
      mod.dir,
      'build',
      'windows',
      'x64',
      'runner',
      'Release',
    ));

    final builtExe = File(p.join(releaseDir.path, '${mod.exeName}.exe'));
    if (!await builtExe.exists()) {
      throw 'Nie znaleziono zbudowanego exe: ${builtExe.path}';
    }

    // Each module gets its OWN subfolder to avoid data/ DLL conflicts:
    //   output/{serverName}/{ModuleName}/
    //     ├── {ServerName} Launcher.exe   ← renamed
    //     ├── flutter_windows.dll
    //     └── data/                       ← flutter assets
    final outDir = Directory(p.join(_outputRoot, config.serverName, mod.outputAs));
    await outDir.create(recursive: true);

    // Copy entire Release folder first (DLLs + data/)
    await _copyDirContents(releaseDir, outDir, skipFiles: ['${mod.exeName}.exe']);

    // Then copy renamed exe
    final destExe = File(p.join(outDir.path, '${mod.outputAs}.exe'));
    await builtExe.copy(destExe.path);

    return destExe.path;
  }

  Future<void> _copyDirContents(
    Directory src,
    Directory dest, {
    List<String> skipFiles = const [],
  }) async {
    await for (final entity in src.list(recursive: false)) {
      final name = p.basename(entity.path);
      if (entity is File) {
        if (skipFiles.contains(name)) continue; // already copied as renamed
        final destFile = File(p.join(dest.path, name));
        await entity.copy(destFile.path);
      } else if (entity is Directory) {
        final subDest = Directory(p.join(dest.path, name));
        await subDest.create(recursive: true);
        await _copyDirContents(entity, subDest);
      }
    }
  }
}

class _ModuleSpec {
  final String name;
  final String dir;
  final String exeName;
  final String outputAs;
  final double weight;
  const _ModuleSpec({
    required this.name,
    required this.dir,
    required this.exeName,
    required this.outputAs,
    required this.weight,
  });
}
