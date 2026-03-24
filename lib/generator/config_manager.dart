import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/crypto_service.dart';
import '../utils/profile_service.dart';

/// Model pełnej konfiguracji generatora.
class GeneratorConfig {
  // Step 1: Branding
  String serverName;        // "Moja Baza" → "Moja Baza Launcher.exe"
  String backgroundPath;   // Lokalna ścieżka do PNG/MP4

  // Step 2: Serwer
  String serverAddr;        // "192.168.1.100:2456"
  String serverPassword;

  // Step 3: FTP
  String ftpHost;
  int ftpPort;
  String ftpUser;
  String ftpPassword;

  // Step 4: Salt
  String salt;
  bool saveSalt;

  GeneratorConfig({
    this.serverName = '',
    this.backgroundPath = '',
    this.serverAddr = '',
    this.serverPassword = '',
    this.ftpHost = '',
    this.ftpPort = 2022,
    this.ftpUser = '',
    this.ftpPassword = '',
    this.salt = '',
    this.saveSalt = true,
  });

  bool get isStep1Valid => serverName.isNotEmpty;
  bool get isStep2Valid => serverAddr.isNotEmpty;
  bool get isStep3Valid => ftpHost.isNotEmpty && ftpUser.isNotEmpty && ftpPassword.isNotEmpty;
  bool get isStep4Valid => salt.length >= 30 && saveSalt;

  /// Zwraca zaszyfrowany JSON config do wbudowania w launcher/patcher/updater.
  String toEncryptedJson() {
    final plain = jsonEncode({
      'serverName': serverName,
      'serverAddr': serverAddr,
      'serverPassword': serverPassword,
      'ftpHost': ftpHost,
      'ftpPort': ftpPort,
      'ftpUser': ftpUser,
      'ftpPassword': ftpPassword,
    });
    return CryptoService.encrypt(plain, salt);
  }

  /// Zwraca niezaszyfrowany ftp.json (dla zgodności z istniejącym kodem)
  Map<String, dynamic> toFtpJson() => {
    'host': ftpHost,
    'port': ftpPort,
    'user': ftpUser,
    'password': ftpPassword, // zostanie zastąpione przez encrypted przy budowaniu
  };
}

/// Provider stanu wizarda.
class GeneratorProvider extends ChangeNotifier {
  final config = GeneratorConfig();
  int currentStep = 0;
  bool isGenerating = false;
  int profileVersion = 0; // incremented on profile load → forces step widgets to re-init controllers
  String? lastError;
  String? outputPath;

  /// Publiczna metoda do powiadamiania listenerów z widget child.
  void notify() => notifyListeners();

  void nextStep() {
    if (currentStep < 3) {
      currentStep++;
      notifyListeners();
    }
  }

  void prevStep() {
    if (currentStep > 0) {
      currentStep--;
      notifyListeners();
    }
  }

  void setGenerating(bool v) {
    isGenerating = v;
    notifyListeners();
  }

  void setOutput(String? path) {
    outputPath = path;
    notifyListeners();
  }

  void setError(String? e) {
    lastError = e;
    notifyListeners();
  }

  /// Loads non-sensitive fields from a profile into the config.
  /// Passwords and salt are intentionally NOT stored in profiles.
  void loadFromProfile(ServerProfile profile) {
    config.serverName = profile.serverName;
    config.serverAddr = profile.serverAddr;
    config.serverPassword = profile.serverPassword;
    config.ftpHost = profile.ftpHost;
    config.ftpPort = profile.ftpPort;
    config.ftpUser = profile.ftpUser;
    config.ftpPassword = profile.ftpPassword;
    config.backgroundPath = profile.backgroundPath;
    if (profile.salt.isNotEmpty) config.salt = profile.salt;
    profileVersion++;
    currentStep = 0;
    notifyListeners();
  }
}
