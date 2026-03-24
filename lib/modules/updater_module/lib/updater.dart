import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'dart:typed_data';

/// Result of comparing a remote file against local copy.
class ChecksumResult {
  final String remotePath;
  final String? remoteHash;
  final String? localHash;
  final bool needsUpdate;

  const ChecksumResult({
    required this.remotePath,
    this.remoteHash,
    this.localHash,
    required this.needsUpdate,
  });

  @override
  String toString() =>
      'ChecksumResult($remotePath, needsUpdate=$needsUpdate, remote=$remoteHash, local=$localHash)';
}

/// UpdaterChecker compares FTP/SFTP remote files against local files
/// using SHA-256 checksums (or size+mtime if server doesn't support checksums).
class UpdaterChecker {
  final String host;
  final int port;
  final String user;
  final String pass;

  UpdaterChecker({
    required this.host,
    required this.port,
    required this.user,
    required this.pass,
  });

  bool get _isSftp => port == 22 || port == 2022;

  /// Compares [remotePaths] against [localBasePath].
  /// Returns list of [ChecksumResult] — one per file.
  Future<List<ChecksumResult>> checkAll({
    required List<String> remotePaths,
    required String localBasePath,
  }) async {
    final results = <ChecksumResult>[];

    if (_isSftp) {
      SSHClient? client;
      SftpClient? sftp;
      try {
        final socket = await SSHSocket.connect(host, port,
            timeout: const Duration(seconds: 15));
        client = SSHClient(socket, username: user, onPasswordRequest: () => pass);
        await client.authenticated;
        sftp = await client.sftp();

        for (final remotePath in remotePaths) {
          final result = await _checkFileSftp(
            sftp: sftp,
            remotePath: remotePath,
            localBasePath: localBasePath,
          );
          results.add(result);
        }
      } finally {
        sftp?.close();
        client?.close();
      }
    } else {
      for (final remotePath in remotePaths) {
        final result = await _checkFileFtp(
          remotePath: remotePath,
          localBasePath: localBasePath,
        );
        results.add(result);
      }
    }
    return results;
  }

  Future<ChecksumResult> _checkFileSftp({
    required SftpClient sftp,
    required String remotePath,
    required String localBasePath,
  }) async {
    try {
      // Get remote file stat (size + mtime as fallback hash)
      final stat = await sftp.stat(remotePath);
      final remoteMeta =
          '${stat.size ?? 0}:${stat.modifyTime ?? 0}';
      final remoteHash = sha256
          .convert(utf8.encode(remoteMeta))
          .toString()
          .substring(0, 16);

      final localPath = _resolveLocal(localBasePath, remotePath);
      final localHash = await _localHash(localPath);

      return ChecksumResult(
        remotePath: remotePath,
        remoteHash: remoteHash,
        localHash: localHash,
        needsUpdate: localHash == null || localHash != remoteHash,
      );
    } catch (e) {
      return ChecksumResult(
        remotePath: remotePath,
        needsUpdate: true,
      );
    }
  }

  Future<ChecksumResult> _checkFileFtp({
    required String remotePath,
    required String localBasePath,
  }) async {
    try {
      final ftp = FTPConnect(host, user: user, pass: pass, port: port, timeout: 10);
      await ftp.connect();
      await ftp.setTransferType(TransferType.binary);
      ftp.transferMode = TransferMode.passive;

      // Get size from LIST
      final parentPath = remotePath.substring(0, remotePath.lastIndexOf('/') + 1);
      final fileName = remotePath.split('/').last;
      await ftp.changeDirectory(parentPath.isEmpty ? '/' : parentPath);
      final entries = await ftp.listDirectoryContent();
      await ftp.disconnect();

      final entry = entries.cast<FTPEntry?>().firstWhere(
            (e) => e?.name?.toLowerCase() == fileName.toLowerCase(),
            orElse: () => null,
          );

      if (entry == null) {
        return ChecksumResult(
            remotePath: remotePath, needsUpdate: true);
      }

      final remoteMeta = '${entry.size ?? 0}:${entry.modifyTime?.millisecondsSinceEpoch ?? 0}';
      final remoteHash = sha256
          .convert(utf8.encode(remoteMeta))
          .toString()
          .substring(0, 16);

      final localPath = _resolveLocal(localBasePath, remotePath);
      final localHash = await _localHash(localPath);

      return ChecksumResult(
        remotePath: remotePath,
        remoteHash: remoteHash,
        localHash: localHash,
        needsUpdate: localHash == null || localHash != remoteHash,
      );
    } catch (e) {
      return ChecksumResult(remotePath: remotePath, needsUpdate: true);
    }
  }

  String _resolveLocal(String base, String remotePath) {
    final relative = remotePath.replaceAll(RegExp(r'^/'), '');
    return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
  }

  /// Computes SHA-256 of local file, or returns null if file doesn't exist.
  Future<String?> _localHash(String localPath) async {
    try {
      final f = File(localPath);
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      return sha256.convert(bytes).toString().substring(0, 16);
    } catch (_) {
      return null;
    }
  }
}
