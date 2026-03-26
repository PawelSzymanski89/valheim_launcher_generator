import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:server_launcher/services/ftp_downloader.dart' show FtpConfig;

// ─── APP SECRET ──────────────────────────────────────────────────────────────
// Ten sam stały sekret co w generatorze (crypto_service.dart → kAppSecret).
// Skompilowany w binarce — do odszyfrowania manifest.sig potrzeba tej binarki.
// Zmiana → trzeba regenerować wszystkie launchery.
const _kAppSecret = r'Vl4h31m@Schr0n#2024!Xd9zQmPwK';
// ─────────────────────────────────────────────────────────────────────────────

Uint8List _keyStream(String salt, int length) {
  final saltBytes = utf8.encode(salt);
  final result = <int>[];
  int block = 1;
  while (result.length < length) {
    final blockBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, block, Endian.big);
    var u = Uint8List.fromList(
        Hmac(sha256, saltBytes).convert([...saltBytes, ...blockBytes]).bytes);
    final xored = Uint8List.fromList(u);
    for (int i = 1; i < 1; i++) {
      u = Uint8List.fromList(Hmac(sha256, saltBytes).convert(u).bytes);
      for (int j = 0; j < xored.length; j++) {
        xored[j] ^= u[j];
      }
    }
    result.addAll(xored);
    block++;
  }
  return Uint8List.fromList(result.sublist(0, length));
}

String _xorDecrypt(String ciphertext, String salt) {
  final combined = base64.decode(ciphertext);
  final iv = combined.sublist(0, 16);
  final encrypted = combined.sublist(16);
  final saltWithIv = '$salt-${base64.encode(iv)}';
  final keyStream = _keyStream(saltWithIv, encrypted.length);
  final decrypted = Uint8List(encrypted.length);
  for (int i = 0; i < encrypted.length; i++) {
    decrypted[i] = encrypted[i] ^ keyStream[i];
  }
  return utf8.decode(decrypted);
}

/// Czyta manifest.sig z assets, odszyfrowuje go APP_SECRET i zwraca sól.
/// Sól w pliku to zaszyfrowany base64 — nie jest czytelna bez binarki.
Future<String?> loadSalt() async {
  try {
    final encryptedSalt = await rootBundle.loadString('assets/manifest.sig');
    final trimmed = encryptedSalt.trim();
    if (trimmed.isEmpty || trimmed == 'PLACEHOLDER') return null;
    return _xorDecrypt(trimmed, _kAppSecret);
  } catch (_) {
    return null;
  }
}

String cryptoDecrypt(String ciphertext, String salt) =>
    _xorDecrypt(ciphertext, salt);

/// Decrypted configuration from config_encrypted.json
class DecryptedConfig {
  final String serverName;
  final String serverAddr;
  final int serverPort;
  final String serverPassword;
  final String ftpHost;
  final int ftpPort;
  final String ftpUser;
  final String ftpPassword;

  const DecryptedConfig({
    required this.serverName,
    required this.serverAddr,
    required this.serverPort,
    required this.serverPassword,
    required this.ftpHost,
    required this.ftpPort,
    required this.ftpUser,
    required this.ftpPassword,
  });

  factory DecryptedConfig.fromJson(Map<String, dynamic> j) => DecryptedConfig(
        serverName: j['serverName'] as String? ?? '',
        serverAddr: j['serverAddr'] as String? ?? '',
        serverPort: (j['serverPort'] as num?)?.toInt() ?? 2456,
        serverPassword: j['serverPassword'] as String? ?? '',
        ftpHost: j['ftpHost'] as String? ?? '',
        ftpPort: (j['ftpPort'] as num?)?.toInt() ?? 21,
        ftpUser: j['ftpUser'] as String? ?? '',
        ftpPassword: j['ftpPassword'] as String? ?? '',
      );

  FtpConfig toFtpConfig() => FtpConfig(
        host: ftpHost,
        port: ftpPort,
        username: ftpUser,
        password: ftpPassword,
        launcherRemote: '/launcher_files/launcher.zip',
        launcherVersionRemote: '/launcher_files/launcher.txt',
        updaterRemote: '/launcher_files/updater.zip',
        updaterVersionRemote: '/launcher_files/updater.txt',
      );
}

/// Loads and decrypts the config bundled in assets.
/// 1) Reads manifest.sig  → decrypts with APP_SECRET → real salt
/// 2) Reads config_encrypted.json → decrypts with real salt → plain config
Future<DecryptedConfig?> loadDecryptedConfig() async {
  try {
    final salt = await loadSalt();
    if (salt == null || salt.isEmpty) return null;

    final raw = await rootBundle.loadString('assets/config_encrypted.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    final data = map['data'] as String;
    if (data == 'PLACEHOLDER_REPLACE_BY_GENERATOR') return null;

    final plainJson = cryptoDecrypt(data, salt);
    final decoded = json.decode(plainJson) as Map<String, dynamic>;
    return DecryptedConfig.fromJson(decoded);
  } catch (_) {
    return null;
  }
}
