import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'generator/config_manager.dart';
import 'utils/shared_salt.dart';
import 'utils/profile_service.dart';

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

  /// On Windows, MSBuild fails when paths exceed 260 chars.
  /// We create a junction from C:\vlg\{l|p|u} → actual module path.
  /// No files are copied — it's a filesystem pointer.
  Future<String> _junctionWorkDir(String modDir, String shortAlias) async {
    if (!Platform.isWindows) return modDir;

    final junctionPath = p.join(r'C:\vlg', shortAlias);

    try {
      await Directory(r'C:\vlg').create(recursive: true);

      // Remove stale junction if exists
      final jDir = Directory(junctionPath);
      if (await jDir.exists()) {
        await Process.run('rmdir', [junctionPath], runInShell: true);
      }

      final result = await Process.run(
        'cmd', ['/c', 'mklink', '/J', junctionPath, modDir],
        runInShell: false,
      );

      if (result.exitCode == 0) {
        onLog('  🔗 Junction: $junctionPath → $modDir');
        return junctionPath;
      }
      onLog('  ⚠️ Nie udało się utworzyć junction (${result.stderr}), używam pełnej ścieżki');
    } catch (e) {
      onLog('  ⚠️ Junction error: $e, używam pełnej ścieżki');
    }
    return modDir; // fallback to original
  }

  Future<void> _removeJunction(String junctionPath) async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('rmdir', [junctionPath], runInShell: true);
    } catch (_) {}
  }

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
        shortAlias: 'l',
        exeName: 'server_launcher',
        outputAs: '${config.serverName} Launcher',
        weight: 0.25,
      ),
      _ModuleSpec(
        name: 'patcher',
        dir: p.join(_modulesRoot, 'patcher_module'),
        shortAlias: 'p',
        exeName: 'server_patcher',
        outputAs: '${config.serverName} Patcher',
        weight: 0.25,
      ),
      _ModuleSpec(
        name: 'updater',
        dir: p.join(_modulesRoot, 'updater_module'),
        shortAlias: 'u',
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
        // Stop immediately on first failure
        onProgress(1.0);
        return results;
      }
    }

    onProgress(1.0);
    return results;
  }

  Future<void> _saveProfile(String encryptedPayload) async {
    try {
      await ProfileService.save(ServerProfile(
        serverName: config.serverName,
        serverAddr: config.serverAddr,
        serverPassword: config.serverPassword,
        ftpHost: config.ftpHost,
        ftpPort: config.ftpPort,
        ftpUser: config.ftpUser,
        ftpPassword: config.ftpPassword,
        backgroundPath: config.backgroundPath,
        salt: config.salt,
        savedAt: DateTime.now(),
      ));
    } catch (e) {
      onLog('  ⚠️ Nie udało się zapisać profilu: $e');
    }
  }

  Future<ModuleBuildResult> _buildModule(
      _ModuleSpec mod, String encryptedPayload) async {
    // Create junction to short path to avoid Windows 260-char path limit
    final workDir = await _junctionWorkDir(mod.dir, mod.shortAlias);
    final junctionCreated = workDir != mod.dir;
    try {
      final modDir = Directory(mod.dir);
      if (!await modDir.exists()) {
        return ModuleBuildResult(
          moduleName: mod.name,
          success: false,
          error: 'Folder modułu nie istnieje: ${mod.dir}',
        );
      }

      // 1. Write config_encrypted.json to module assets (always to real path)
      onLog('  📝 Wstrzykuję config do ${mod.name}/assets/...');
      final assetsDir = Directory(p.join(mod.dir, 'assets'));
      await assetsDir.create(recursive: true);
      await File(p.join(assetsDir.path, 'config_encrypted.json'))
          .writeAsString(encryptedPayload);

      // 2. Write ftp_preview.json
      await File(p.join(assetsDir.path, 'ftp_preview.json'))
          .writeAsString(const JsonEncoder.withIndent('  ')
              .convert(config.toFtpJson()));

      // 3. Run flutter build windows from workDir (short path via junction)
      onLog('  🔨 flutter build windows...');
      final buildResult = await _runFlutterBuild(workDir, mod);
      if (!buildResult.success) {
        return ModuleBuildResult(
          moduleName: mod.name,
          success: false,
          error: buildResult.error,
        );
      }

      // 4. Copy exe to output
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
    } finally {
      if (junctionCreated) await _removeJunction(workDir);
    }
  }

  Future<({bool success, String? error})> _runFlutterBuild(
      String buildDir, _ModuleSpec mod) async {
    // Log file always goes to real (non-junction) path
    final logFile = File(p.join(mod.dir, '..', 'build_${mod.name}.log'));
    final logSink = logFile.openWrite();
    final allLines = <String>[];

    try {
      final process = await Process.start(
        'flutter',
        ['build', 'windows', '--release'],
        workingDirectory: buildDir,   // ← short path via junction
        runInShell: true,
      );

      void handleLine(String line) {
        logSink.write(line);
        allLines.add(line);
        // Stream notable lines to UI in real time
        final t = line.trim();
        if (t.isNotEmpty) onLog('    $t');
      }

      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(handleLine);
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(handleLine);

      final exitCode = await process.exitCode;
      await logSink.flush();
      await logSink.close();

      if (exitCode != 0) {
        // Return last 20 lines so the UI log shows the actual error
        final tail = allLines.reversed.take(20).toList().reversed.join('\n').trim();
        onLog('  ⛔ Pełny log: ${logFile.path}');
        return (
          success: false,
          error: 'flutter build zakończony kodem $exitCode\n$tail',
        );
      }
      return (success: true, error: null);
    } catch (e) {
      await logSink.close();
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
  final String shortAlias; // used for C:\vlg\{alias} junction
  final String exeName;
  final String outputAs;
  final double weight;
  const _ModuleSpec({
    required this.name,
    required this.dir,
    required this.shortAlias,
    required this.exeName,
    required this.outputAs,
    required this.weight,
  });
}
