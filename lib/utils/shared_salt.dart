import 'package:shared_preferences/shared_preferences.dart';

const _saltKey = 'vlg_salt_v1';

/// Zarządza salt — zapis/odczyt z shared_preferences (rejestr Windows).
class SharedSalt {
  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_saltKey);
  }

  static Future<void> save(String salt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, salt);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saltKey);
  }
}
