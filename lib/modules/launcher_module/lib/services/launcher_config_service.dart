import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

/// Configuration model for launcher settings
class LauncherConfig {
  final String serverName;
  final String serverAddress;
  final int serverPort;
  final String serverPassword;

  const LauncherConfig({
    required this.serverName,
    required this.serverAddress,
    required this.serverPort,
    required this.serverPassword,
  });

  factory LauncherConfig.fromJson(Map<String, dynamic> json) {
    return LauncherConfig(
      serverName: json['server_name'] as String? ?? 'Aurora Borealis',
      serverAddress: json['server_address'] as String? ?? '65.109.71.176',
      serverPort: json['server_port'] as int? ?? 60400,
      serverPassword: json['server_password'] as String? ?? 'loszki666',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'server_name': serverName,
      'server_address': serverAddress,
      'server_port': serverPort,
      'server_password': serverPassword,
    };
  }

  factory LauncherConfig.defaults() {
    return const LauncherConfig(
      serverName: 'Aurora Borealis',
      serverAddress: '65.109.71.176',
      serverPort: 60400,
      serverPassword: 'loszki666',
    );
  }
}

class LauncherConfigService {
  // Encryption key derived from app-specific data
  static const String _encryptionSalt = 'ValheimLauncher2024';
  
  /// Simple XOR encryption/decryption
  Uint8List _xorCipher(Uint8List data, String key) {
    final keyBytes = utf8.encode(key);
    final result = Uint8List(data.length);
    
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    
    return result;
  }
  
  /// Encrypt config data
  String _encryptConfig(String jsonString) {
    try {
      // Generate encryption key from salt
      final keyHash = sha256.convert(utf8.encode(_encryptionSalt));
      final key = base64.encode(keyHash.bytes);
      
      // Encrypt using XOR
      final dataBytes = utf8.encode(jsonString);
      final encrypted = _xorCipher(Uint8List.fromList(dataBytes), key);
      
      // Encode to base64 for storage
      return base64.encode(encrypted);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LauncherConfigService] Encryption error: $e');
      }
      rethrow;
    }
  }
  
  /// Decrypt config data
  String _decryptConfig(String encryptedData) {
    try {
      // Generate encryption key from salt
      final keyHash = sha256.convert(utf8.encode(_encryptionSalt));
      final key = base64.encode(keyHash.bytes);
      
      // Decode from base64
      final encrypted = base64.decode(encryptedData);
      
      // Decrypt using XOR
      final decrypted = _xorCipher(encrypted, key);
      
      // Convert back to string
      return utf8.decode(decrypted);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LauncherConfigService] Decryption error: $e');
      }
      rethrow;
    }
  }

  /// Loads launcher configuration from launcher_config.json next to the launcher executable.
  /// Creates the file with default values if it doesn't exist.
  /// The file is encrypted to protect sensitive data like passwords.
  Future<LauncherConfig> loadConfig() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final configPath = p.join(exeDir, 'launcher_config.json');
      final configFile = File(configPath);

      if (kDebugMode) {
        debugPrint('[LauncherConfigService] Loading config from: $configPath');
      }

      if (!await configFile.exists()) {
        if (kDebugMode) {
          debugPrint('[LauncherConfigService] Config file not found, creating with defaults');
        }
        // Create file with default values
        final defaultConfig = LauncherConfig.defaults();
        await _saveConfig(configFile, defaultConfig);
        return defaultConfig;
      }

      // Read encrypted file
      final encryptedContent = await configFile.readAsString();
      
      // Try to decrypt
      try {
        final decryptedContent = _decryptConfig(encryptedContent);
        final json = jsonDecode(decryptedContent) as Map<String, dynamic>;
        final config = LauncherConfig.fromJson(json);

        if (kDebugMode) {
          debugPrint('[LauncherConfigService] Loaded encrypted config: ${config.serverName} @ ${config.serverAddress}:${config.serverPort}');
        }

        return config;
      } catch (decryptError) {
        // If decryption fails, try to read as plain JSON (for migration)
        if (kDebugMode) {
          debugPrint('[LauncherConfigService] Decryption failed, trying plain JSON: $decryptError');
        }
        
        try {
          final json = jsonDecode(encryptedContent) as Map<String, dynamic>;
          final config = LauncherConfig.fromJson(json);
          
          // Re-save as encrypted
          if (kDebugMode) {
            debugPrint('[LauncherConfigService] Migrating plain JSON to encrypted format');
          }
          await _saveConfig(configFile, config);
          
          return config;
        } catch (jsonError) {
          if (kDebugMode) {
            debugPrint('[LauncherConfigService] Failed to parse as JSON: $jsonError');
          }
          // If both fail, return defaults
          return LauncherConfig.defaults();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LauncherConfigService] Error loading config: $e, using defaults');
      }
      return LauncherConfig.defaults();
    }
  }

  /// Saves configuration to file (encrypted)
  Future<void> _saveConfig(File configFile, LauncherConfig config) async {
    try {
      final json = config.toJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(json);
      
      // Encrypt the JSON
      final encrypted = _encryptConfig(jsonString);
      
      // Save encrypted data
      await configFile.writeAsString(encrypted);
      
      if (kDebugMode) {
        debugPrint('[LauncherConfigService] Encrypted config saved to: ${configFile.path}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LauncherConfigService] Error saving config: $e');
      }
    }
  }

  /// Validates server address (basic domain/IP check)
  bool isValidAddress(String address) {
    if (address.isEmpty) return false;
    // Allow domain names (letters, numbers, dots, hyphens) or IP addresses
    final domainRegex = RegExp(r'^[a-zA-Z0-9.-]+$');
    return domainRegex.hasMatch(address);
  }

  /// Validates server port (1-65535)
  bool isValidPort(int port) {
    return port >= 1 && port <= 65535;
  }
}

