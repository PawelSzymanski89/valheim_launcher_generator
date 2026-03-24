import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:ftpconnect/ftpconnect.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:typed_data';

class FtpConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String launcherRemote;
  final String launcherVersionRemote;
  final String updaterRemote;
  final String updaterVersionRemote;

  FtpConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.launcherRemote,
    required this.launcherVersionRemote,
    required this.updaterRemote,
    required this.updaterVersionRemote,
  });

  factory FtpConfig.fromJson(Map<String, dynamic> json) => FtpConfig(
        host: json['host'] as String,
        port: (json['port'] as num?)?.toInt() ?? 21,
        username: json['username'] as String? ?? json['user'] as String? ?? '',
        password: json['password'] as String? ?? json['pass'] as String? ?? '',
        launcherRemote: json['launcher_remote'] as String? ?? '/launcher_files/launcher.zip',
        launcherVersionRemote: json['launcher_version_remote'] as String? ?? '/launcher_files/launcher.txt',
        updaterRemote: json['updater_remote'] as String? ?? '/launcher_files/updater.zip',
        updaterVersionRemote: json['updater_version_remote'] as String? ?? '/launcher_files/updater.txt',
      );
}

class FtpDownloader {
  final FtpConfig config;

  // utrzymywany klient FTP, pozwala uniknąć ciągłego łączenia/rozłączania
  FTPConnect? _ftpClient;
  SSHClient? _sshClient;
  SftpClient? _sftpClient;
  bool _isConnected = false;
  bool _isSftp = false;

  FtpDownloader(this.config);

  static Future<FtpConfig> loadFromAsset({String path = 'assets/ftp.json'}) async {
    final raw = await rootBundle.loadString(path);
    final Map<String, dynamic> j = json.decode(raw) as Map<String, dynamic>;
    return FtpConfig.fromJson(j);
  }

  /// Wczytuje konfigurację FTP z pliku na dysku (użyteczne do testów CLI).
  static Future<FtpConfig> loadFromFilePath(String path) async {
    final raw = await File(path).readAsString();
    final Map<String, dynamic> j = json.decode(raw) as Map<String, dynamic>;
    return FtpConfig.fromJson(j);
  }

  /// Otwarcie sesji FTP. Metoda jest idempotentna — nie otworzy wielu połączeń.
  Future<void> connect() async {
    if (_isConnected) return;

    if (config.port == 2022 || config.port == 22) {
      _isSftp = true;
      try {
        final socket = await SSHSocket.connect(config.host, config.port, timeout: const Duration(seconds: 10));
        _sshClient = SSHClient(
          socket,
          username: config.username,
          onPasswordRequest: () => config.password,
        );
        await _sshClient!.authenticated;
        _sftpClient = await _sshClient!.sftp();
        _isConnected = true;
        print('[Downloader] SFTP Connected');
        return;
      } catch (e) {
        print('[Downloader] SFTP Connect failed: $e');
        _isSftp = false; // fallback if needed
      }
    }

    _ftpClient ??= FTPConnect(
      config.host,
      user: config.username,
      pass: config.password,
      port: config.port,
    );

    final connected = await _ftpClient!.connect();
    if (!connected) throw Exception('FTP connect failed');

    // ustaw tryb transferu na binarny i tryb pasywny
    await _ftpClient!.setTransferType(TransferType.binary);
    _ftpClient!.transferMode = TransferMode.passive;

    _isSftp = false;
    _isConnected = true;
    print('[Downloader] FTP Connected');
  }

  /// Zamknięcie sesji FTP (bezpieczne do wywołania wielokrotnie).
  Future<void> disconnect() async {
    try {
      if (_ftpClient != null) await _ftpClient!.disconnect();
      if (_sshClient != null) _sshClient!.close();
    } catch (_) {
    } finally {
      _isConnected = false;
      _ftpClient = null;
      _sshClient = null;
      _sftpClient = null;
    }
  }

  /// Pobiera zdalny plik `remotePath` i zapisuje jako `localPath`.
  Future<void> download(String remotePath, String localPath) async {
    await connect();

    final localFile = File(localPath);
    await localFile.create(recursive: true);

    if (_isSftp && _sftpClient != null) {
      final file = await _sftpClient!.open(remotePath);
      
      // Używamy chunkSize=32768 (maksymalny rozmiar pakietu SFTP serwera).
      // Większy chunkSize powoduje, że serwer odpowiada pierwszym pakietem + EOF
      // i dartssh2 kończy stream przedwcześnie (np. 32KB zamiast całego pliku).
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.read(chunkSize: 32768)) {
        builder.add(chunk);
      }
      await file.close();
      await localFile.writeAsBytes(builder.takeBytes(), flush: true);
      return;
    }

    final success = await _ftpClient!.downloadFile(remotePath, localFile);
    if (!success) throw Exception('Pobieranie nie powiodło się: $remotePath');
  }

  /// Pobiera wiele plików, używając puli klientów FTP.
  /// Domyślnie tworzy 2 sesje (concurrency = 2). Każda sesja pobiera swoje pliki sekwencyjnie.
  ///
  /// Parametry:
  /// - [remotePaths] - lista ścieżek zdalnych do pobrania (ścieżki względne/bezwzględne na serwerze).
  /// - [localDir] - katalog lokalny, do którego będą zapisywane pliki (nazwa pliku jest wyciągana z remotePath).
  /// - [concurrency] - liczba równoczesnych sesji; domyślnie 2.
  /// - [retries] - liczba prób pobrania pojedynczego pliku (domyślnie 3).
  /// - [initialBackoffMillis] - początkowe opóźnienie przy retry w ms (eksponencjalny backoff).
  Future<void> downloadMany(List<String> remotePaths, String localDir,
      {int concurrency = 2, int retries = 3, int initialBackoffMillis = 500}) async {
    if (remotePaths.isEmpty) return;
    if (concurrency < 1) concurrency = 1;

    // dynamiczna kolejka plików (LIFO) — usuwamy z końca bez await, więc operacja jest atomowa
    final queue = List<String>.from(remotePaths.reversed);

    String? getNext() {
      if (queue.isEmpty) return null;
      return queue.removeLast();
    }

    // przygotuj pulę klientów
    final clients = List<FTPConnect>.generate(
      concurrency,
      (_) => FTPConnect(
        config.host,
        user: config.username,
        pass: config.password,
        port: config.port,
      ),
    );

    final List<String> failures = [];

    try {
      // połącz wszystkich klientów
      for (var client in clients) {
        final ok = await client.connect();
        if (!ok) throw Exception('FTP connect failed for pool client');
        await client.setTransferType(TransferType.binary);
        client.transferMode = TransferMode.passive;
      }

      // worker wykonuje zadania pobierania dopóki jest dostępny plik w kolejce
      Future<void> worker(FTPConnect client) async {
        while (true) {
          final remote = getNext();
          if (remote == null) break;

          var attempt = 0;
          var backoff = initialBackoffMillis;
          var success = false;

          while (attempt <= retries && !success) {
            try {
              final name = _basename(remote);
              final localPath = '$localDir\\$name';
              final localFile = File(localPath);
              await localFile.create(recursive: true);

              final ok = await client.downloadFile(remote, localFile);
              if (ok) {
                success = true;
                break;
              } else {
                // traktuj jako błąd i spróbuj ponownie
                attempt++;
                if (attempt <= retries) {
                  final jitter = (backoff * 0.1).toInt();
                  final wait = backoff + (DateTime.now().millisecondsSinceEpoch % (jitter + 1));
                  await Future.delayed(Duration(milliseconds: wait));
                  backoff = backoff * 2;
                }
              }
            } catch (e) {
              attempt++;
              if (attempt <= retries) {
                final jitter = (backoff * 0.1).toInt();
                final wait = backoff + (DateTime.now().millisecondsSinceEpoch % (jitter + 1));
                await Future.delayed(Duration(milliseconds: wait));
                backoff = backoff * 2;
                // spróbuj ponownie
              } else {
                // po wyczerpaniu prób dodaj do failures
                failures.add(remote);
              }
            }
          }

          if (!success && attempt > retries) {
            // jeśli po wszystkich próbach nadal nieudane, zapisz failure
            if (!failures.contains(remote)) failures.add(remote);
          }
        }
      }

      // uruchom workerów równolegle
      final tasks = clients.map((c) => worker(c)).toList();
      await Future.wait(tasks);

      if (failures.isNotEmpty) {
        throw Exception('Nie udało się pobrać niektórych plików: ${failures.join(', ')}');
      }
    } finally {
      // rozłącz wszystkich klientów
      for (var client in clients) {
        try {
          await client.disconnect();
        } catch (_) {}
      }
    }
  }

  String _basename(String path) {
    final parts = path.split(RegExp(r'[\\/]+'));
    return parts.isNotEmpty ? parts.last : path;
  }
}
