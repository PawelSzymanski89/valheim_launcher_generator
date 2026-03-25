import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:dartssh2/dartssh2.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'generator/config_manager.dart';
import 'utils/crypto_service.dart';
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

    // ── Flutter pre-check ─────────────────────────────────────────
    onLog('🔍 Sprawdzam Flutter SDK...');
    final flutterCheck = await Process.run(
      'flutter', ['--version', '--machine'],
      runInShell: true,
    );
    if (flutterCheck.exitCode != 0) {
      onLog('');
      onLog('❌ Flutter SDK nie znaleziony w PATH!');
      onLog('');
      onLog('  Generator wymaga zainstalowanego Flutter SDK:');
      onLog('  1. Pobierz: https://docs.flutter.dev/get-started/install/windows');
      onLog('  2. Rozpakuj i dodaj flutter\\bin do zmiennej PATH');
      onLog('  3. Uruchom: flutter doctor -v');
      onLog('  4. Wymagane: Visual Studio 2022 z C++ desktop');
      onLog('');
      results.add(ModuleBuildResult(
        moduleName: 'flutter_check',
        success: false,
        error: 'Flutter SDK nie znaleziony w PATH. Zainstaluj Flutter i spróbuj ponownie.',
      ));
      return results;
    }
    // Extract version from JSON output
    try {
      final versionInfo = jsonDecode(flutterCheck.stdout as String) as Map;
      onLog('  ✅ Flutter ${versionInfo['frameworkVersion']} (Dart ${versionInfo['dartSdkVersion']})');
    } catch (_) {
      onLog('  ✅ Flutter SDK znaleziony');
    }
    onProgress(prog += 0.02);

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

  /// Increments the build number (+N) in the module's pubspec.yaml.
  /// e.g. version: 1.0.0+5 → 1.0.0+6
  Future<void> _bumpBuildNumber(String modDir) async {
    try {
      final pubspecFile = File(p.join(modDir, 'pubspec.yaml'));
      if (!await pubspecFile.exists()) return;
      var content = await pubspecFile.readAsString();
      final versionRegex = RegExp(r'^(version:\s*\S+?\+)(\d+)', multiLine: true);
      final match = versionRegex.firstMatch(content);
      if (match == null) return;
      final prefix = match.group(1)!;
      final current = int.parse(match.group(2)!);
      final next = current + 1;
      content = content.replaceFirst(versionRegex, '$prefix$next');
      await pubspecFile.writeAsString(content);
      onLog('  🔢 Build number: $current → $next');
    } catch (e) {
      onLog('  ⚠️ Nie udało się podbić build number: $e');
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

      // 1b. Write manifest.sig — salt encrypted with APP_SECRET (not plaintext!)
      final encryptedSalt = CryptoService.encryptSalt(config.salt);
      await File(p.join(assetsDir.path, 'manifest.sig'))
          .writeAsString(encryptedSalt);
      onLog('  🔐 manifest.sig wstrzyknięty do ${mod.name}/assets/');

      // 2. Write ftp.json (plaintext — used by valheim_files_service for FTP operations)
      await File(p.join(assetsDir.path, 'ftp.json'))
          .writeAsString(const JsonEncoder.withIndent('  ')
              .convert(config.toFtpJson()));

      // 3. Bump build number in pubspec.yaml (+N → +N+1)
      await _bumpBuildNumber(mod.dir);
      onLog('  📦 flutter pub get...');
      final pubResult = await Process.run(
        'flutter', ['pub', 'get'],
        workingDirectory: mod.dir,
        runInShell: true,
      );
      if (pubResult.exitCode != 0) {
        onLog('  ⚠️ pub get warning: ${pubResult.stderr}'.trim());
      }

      // 4. If CMakeCache has stale junction paths → flutter clean (one-time cost)
      final cmakeCache = File(p.join(mod.dir, 'build', 'windows', 'x64', 'CMakeCache.txt'));
      if (await cmakeCache.exists()) {
        final cacheContent = await cmakeCache.readAsString();
        if (cacheContent.contains(r'C:/vlg/') || cacheContent.contains(r'C:\vlg\')) {
          onLog('  🧹 Wykryto stale ścieżki junction — flutter clean...');
          await Process.run('flutter', ['clean'], workingDirectory: mod.dir, runInShell: true);
        }
      }

      // 5. Run flutter build windows from workDir (short path via junction)
      onLog('  🔨 flutter build windows...');
      final buildResult = await _runFlutterBuild(workDir, mod);
      if (!buildResult.success) {
        return ModuleBuildResult(
          moduleName: mod.name,
          success: false,
          error: buildResult.error,
        );
      }

      // 6. Copy exe to output
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
    final meaningfulLines = <String>[];
    final startTime = DateTime.now();

    // Lines that are noise — suppress from UI but keep in log
    bool _isNoise(String t) =>
        t.startsWith('CMake Warning') ||
        t.startsWith('Policy CMP') ||
        t.startsWith('Run "cmake') ||
        t.startsWith('This warning is for') ||
        t.startsWith('  Policy') ||
        t.startsWith('  Run ') ||
        t.startsWith('  Assuming') ||
        t.startsWith('  POST_BUILD') ||
        t.startsWith('  PRE_') ||
        t.startsWith('Use -Wno-dev');

    try {
      final process = await Process.start(
        'flutter',
        ['build', 'windows', '--release'],
        workingDirectory: buildDir,
        runInShell: true,
      );

      void handleChunk(String chunk) {
        // Log EVERYTHING to file
        logSink.write(chunk);
        // Split on \n and \r, skip empty and spinner-only lines
        for (final raw in chunk.split(RegExp(r'[\r\n]+'))) {
          final t = raw.trim();
          if (t.isEmpty || t == r'\' || t == '|' || t == '-' || t == '/') continue;
          meaningfulLines.add(t);
          // Show non-noise lines in UI
          if (!_isNoise(t)) {
            onLog('    $t');
          }
        }
      }

      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(handleChunk);
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(handleChunk);

      final exitCode = await process.exitCode;
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      await logSink.flush();
      await logSink.close();

      onLog('    ⏱️ czas buildu: ${elapsed}s');

      if (exitCode != 0) {
        final tail = meaningfulLines.reversed.take(20).toList().reversed.join('\n').trim();
        onLog('  ⛔ Pełny log: ${logFile.path}');
        return (
          success: false,
          error: 'flutter build kod $exitCode (${elapsed}s)\n$tail',
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

    // Each module gets its OWN versioned subfolder:
    //   output/{serverName}/v{version}/{ModuleName}/
    //     ├── {ServerName} Launcher.exe
    //     ├── flutter_windows.dll
    //     └── data/
    final version = _readVersion(mod.dir); // reads bumped version from pubspec
    final outDir = Directory(p.join(_outputRoot, config.serverName, 'v$version', mod.outputAs));
    await outDir.create(recursive: true);

    // Copy entire Release folder first (DLLs + data/)
    await _copyDirContents(releaseDir, outDir, skipFiles: ['${mod.exeName}.exe']);

    // Then copy renamed exe
    final destExe = File(p.join(outDir.path, '${mod.outputAs}.exe'));
    await builtExe.copy(destExe.path);

    onLog('  📁 Output: ${outDir.path}');
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
        if (skipFiles.contains(name)) continue;
        final destFile = File(p.join(dest.path, name));
        await entity.copy(destFile.path);
      } else if (entity is Directory) {
        final subDest = Directory(p.join(dest.path, name));
        await subDest.create(recursive: true);
        await _copyDirContents(entity, subDest);
      }
    }
  }

  // ── Upload to server ─────────────────────────────────────────────────────

  /// Uploads [serverName] Launcher.exe + Updater.exe + version manifests
  /// to `launcher_files/` on the configured FTP/SFTP server.
  Future<({bool success, String? error})> uploadToServer() async {
    const remoteDir = 'launcher_files';
    final isSftp = config.ftpPort == 22 || config.ftpPort == 2022;

    // Discover files to upload
    final List<({File file, String remoteName})> uploads = [];

    for (final alias in [
      (label: '${config.serverName} Launcher', isLauncher: true),
      (label: '${config.serverName} Updater',  isLauncher: false),
    ]) {
      final exeFile = File(p.join(_outputRoot, config.serverName, alias.label, '${alias.label}.exe'));
      if (!await exeFile.exists()) {
        onLog('⚠️  Pominięto (brak pliku): ${exeFile.path}');
        continue;
      }
      uploads.add((file: exeFile, remoteName: '${alias.label}.exe'));

      // Version manifest
      final modDir = alias.isLauncher
          ? p.join(_modulesRoot, 'launcher_module')
          : p.join(_modulesRoot, 'updater_module');
      final version = _readVersion(modDir);
      final vName = alias.isLauncher ? 'launcher_version.txt' : 'updater_version.txt';
      final tmpFile = File(p.join(Directory.systemTemp.path, vName));
      await tmpFile.writeAsString(version, flush: true);
      uploads.add((file: tmpFile, remoteName: vName));
      onLog('  📄 $vName → $version');
    }

    if (uploads.isEmpty) {
      return (success: false, error: 'Brak plików do wysłania. Czy build zakończył się sukcesem?');
    }

    onLog('');
    onLog('🚀 Łączę z ${config.ftpHost}:${config.ftpPort} (${isSftp ? "SFTP" : "FTP"})...');

    try {
      if (isSftp) {
        return await _uploadSftp(remoteDir, uploads);
      } else {
        return await _uploadFtp(remoteDir, uploads);
      }
    } catch (e) {
      return (success: false, error: '$e');
    }
  }

  String _readVersion(String modDir) {
    try {
      final content = File(p.join(modDir, 'pubspec.yaml')).readAsStringSync();
      final m = RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(content);
      return m?.group(1)?.trim() ?? '1.0.0+0';
    } catch (_) {
      return '1.0.0+0';
    }
  }

  Future<({bool success, String? error})> _uploadSftp(
      String remoteDir, List<({File file, String remoteName})> uploads) async {
    final socket = await SSHSocket.connect(config.ftpHost, config.ftpPort,
        timeout: const Duration(seconds: 15));
    final client = SSHClient(socket,
        username: config.ftpUser, onPasswordRequest: () => config.ftpPassword);
    await client.authenticated;
    final sftp = await client.sftp();

    try {
      await sftp.mkdir(remoteDir).catchError((_) {});
      for (final u in uploads) {
        onLog('  ⬆️  ${u.remoteName}...');
        final remote = await sftp.open(
          '$remoteDir/${u.remoteName}',
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        await remote.write(u.file.openRead().cast());
        await remote.close();
        onLog('     ✅ ${u.remoteName} (${_fmtSize(await u.file.length())})');
      }
    } finally {
      sftp.close();
      client.close();
    }
    return (success: true, error: null);
  }

  Future<({bool success, String? error})> _uploadFtp(
      String remoteDir, List<({File file, String remoteName})> uploads) async {
    final ftp = FTPConnect(
      config.ftpHost,
      user: config.ftpUser,
      pass: config.ftpPassword,
      port: config.ftpPort,
      timeout: 20,
    );
    await ftp.connect();
    try {
      await ftp.makeDirectory(remoteDir).catchError((_) => false);
      await ftp.changeDirectory(remoteDir);
      for (final u in uploads) {
        onLog('  ⬆️  ${u.remoteName}...');
        final ok = await ftp.uploadFile(u.file, sRemoteName: u.remoteName);
        if (ok) {
          onLog('     ✅ ${u.remoteName} (${_fmtSize(await u.file.length())})');
        } else {
          onLog('     ❌ Błąd wysyłania ${u.remoteName}');
        }
      }
    } finally {
      await ftp.disconnect();
    }
    return (success: true, error: null);
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
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
