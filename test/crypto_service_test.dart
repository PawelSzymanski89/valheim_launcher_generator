import 'dart:convert';
import 'package:test/test.dart';
import '../lib/utils/crypto_service.dart';

void main() {
  group('CryptoService', () {
    const salt = 'test-salt-value-1234';
    const shortSalt = 'abc';

    test('encrypt then decrypt returns original string', () {
      const original = 'Hello, Valheim Generator!';
      final encrypted = CryptoService.encrypt(original, salt);
      final decrypted = CryptoService.decrypt(encrypted, salt);
      expect(decrypted, equals(original));
    });

    test('encrypt produces valid base64 different from original', () {
      const original = 'FTP password: supersecret@123';
      final encrypted = CryptoService.encrypt(original, salt);
      expect(encrypted, isNot(equals(original)));
      expect(() => base64.decode(encrypted), returnsNormally);
    });

    test('decrypt with wrong salt produces garbage or throws (not original)', () {
      const original = 'secret data';
      final encrypted = CryptoService.encrypt(original, salt);
      try {
        final wrongDecrypt = CryptoService.decrypt(encrypted, 'wrong-salt');
        // If it didn't throw, it must not equal the original
        expect(wrongDecrypt, isNot(equals(original)));
      } on FormatException {
        // Expected: garbled XOR bytes can produce invalid UTF-8
      }
    });

    test('encrypt empty string roundtrips', () {
      const original = '';
      final encrypted = CryptoService.encrypt(original, salt);
      final decrypted = CryptoService.decrypt(encrypted, salt);
      expect(decrypted, equals(original));
    });

    test('encrypt unicode/Polish characters', () {
      const original = 'Żółty pień ćmąś zażółcić gęślą jaźń €';
      final encrypted = CryptoService.encrypt(original, salt);
      final decrypted = CryptoService.decrypt(encrypted, salt);
      expect(decrypted, equals(original));
    });

    test('encrypt large data (50k chars)', () {
      final original = 'x' * 50000;
      final encrypted = CryptoService.encrypt(original, salt);
      final decrypted = CryptoService.decrypt(encrypted, salt);
      expect(decrypted, equals(original));
    });

    test('different calls produce different ciphertexts (random IV)', () {
      const original = 'test payload';
      final enc1 = CryptoService.encrypt(original, salt);
      final enc2 = CryptoService.encrypt(original, salt);
      // Random IV ensures different outputs
      expect(enc1, isNot(equals(enc2)));
      // But both decrypt correctly
      expect(CryptoService.decrypt(enc1, salt), equals(original));
      expect(CryptoService.decrypt(enc2, salt), equals(original));
    });

    test('encrypt with short salt', () {
      const original = 'data with short salt';
      final encrypted = CryptoService.encrypt(original, shortSalt);
      final decrypted = CryptoService.decrypt(encrypted, shortSalt);
      expect(decrypted, equals(original));
    });

    test('JSON roundtrip encryption', () {
      const jsonPayload =
          '{"serverName":"Aurora Borealis","serverAddr":"65.109.71.176","serverPort":2456,'
          '"serverPassword":"s3cr3t","ftpHost":"ftp.example.com","ftpPort":21,'
          '"ftpUser":"admin","ftpPassword":"ftpPass123"}';
      final encrypted = CryptoService.encrypt(jsonPayload, salt);
      final decrypted = CryptoService.decrypt(encrypted, salt);
      expect(decrypted, equals(jsonPayload));
    });

    test('generateSalt produces unique salts of adequate length', () {
      final s1 = CryptoService.generateSalt();
      final s2 = CryptoService.generateSalt();
      expect(s1, isNot(equals(s2)));
      expect(s1.length, greaterThanOrEqualTo(30));
    });
  });
}
