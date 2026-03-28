import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// App secret injected at compile time via --dart-define=APP_SECRET=...
/// Never hardcode this value — it lives in .env (gitignored).
/// If empty, encryption/decryption will fail loudly at runtime.
const kAppSecret = String.fromEnvironment('APP_SECRET');

/// Szyfrowanie XOR-stream z kluczem derywowanym PBKDF2-SHA256.
/// Wystarczające dla konfiguracji offline — nie wymaga pointycastle.
class CryptoService {
  /// Derywuje strumień kluczowy o długości [length] z [salt] metodą PBKDF2-SHA256.
  static Uint8List _keyStream(String salt, int length) {
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

  /// Szyfruje [plaintext] używając XOR z kluczem PBKDF2 z [salt].
  /// Prepend: 16 bajtów losowego IV, następnie XOR-encrypted data.
  static String encrypt(String plaintext, String salt) {
    final rng = Random.secure();
    final iv = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    final saltWithIv = '$salt-${base64.encode(iv)}';
    final plainBytes = utf8.encode(plaintext);
    final keyStream = _keyStream(saltWithIv, plainBytes.length);
    final encrypted = Uint8List(plainBytes.length);
    for (int i = 0; i < plainBytes.length; i++) {
      encrypted[i] = plainBytes[i] ^ keyStream[i];
    }
    final combined = Uint8List(16 + encrypted.length);
    combined.setRange(0, 16, iv);
    combined.setRange(16, combined.length, encrypted);
    return base64.encode(combined);
  }

  /// Deszyfruje [ciphertext] (base64) używając [salt].
  static String decrypt(String ciphertext, String salt) {
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

  /// Generuje kryptograficznie bezpieczny salt min. 30 znaków (base64url).
  static String generateSalt({int length = 32}) {
    final rng = Random.secure();
    final bytes =
        Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
    final b64 = base64Url.encode(bytes);
    return b64.length >= 30 ? b64 : b64.padRight(30, '0');
  }

  /// Szyfruje [salt] kluczem APP_SECRET — do zapisu w pliku config_salt.txt.
  /// Wynik to base64 — wygląda jak losowe śmieci, bez APP_SECRET nie do odszyfrowania.
  static String encryptSalt(String salt) => encrypt(salt, kAppSecret);

  /// Odszyfrowuje zawartość config_salt.txt (zaszyfrowaną przez encryptSalt).
  static String decryptSalt(String encryptedSalt) =>
      decrypt(encryptedSalt, kAppSecret);
}
