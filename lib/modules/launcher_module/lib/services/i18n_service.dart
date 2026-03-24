import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Represents a language with its code, translations and flag path
class Language {
  final String code; // e.g. 'en', 'pl', 'ua'
  final Map<String, String> translations;
  final String? flagPath; // path to flag.png (null for embedded)
  final bool isEmbedded;

  Language({
    required this.code,
    required this.translations,
    this.flagPath,
    this.isEmbedded = false,
  });

  String get displayName {
    final names = {
      'bg': 'Български',      // Bulgarian
      'hr': 'Hrvatski',       // Croatian
      'cs': 'Čeština',        // Czech
      'da': 'Dansk',          // Danish
      'nl': 'Nederlands',     // Dutch
      'en': 'English',        // English
      'et': 'Eesti',          // Estonian
      'fi': 'Suomi',          // Finnish
      'fr': 'Français',       // French
      'de': 'Deutsch',        // German
      'el': 'Ελληνικά',       // Greek
      'hu': 'Magyar',         // Hungarian
      'ga': 'Gaeilge',        // Irish
      'it': 'Italiano',       // Italian
      'lv': 'Latviešu',       // Latvian
      'lt': 'Lietuvių',       // Lithuanian
      'mt': 'Malti',          // Maltese
      'pl': 'Polski',         // Polish
      'pt': 'Português',      // Portuguese
      'ro': 'Română',         // Romanian
      'sk': 'Slovenčina',     // Slovak
      'sl': 'Slovenščina',    // Slovenian
      'es': 'Español',        // Spanish
      'sv': 'Svenska',        // Swedish
      'ua': 'Українська',     // Ukrainian
    };
    return names[code] ?? code.toUpperCase();
  }
}

/// I18n service for runtime-loaded translations from lang/ folders
class I18nService {
  static final I18nService _instance = I18nService._internal();
  static I18nService get instance => _instance;

  I18nService._internal();

  String? _appRootPath;
  String _currentLanguageCode = 'en';
  final Map<String, Language> _languages = {};
  final List<VoidCallback> _listeners = [];

  /// Current active language
  Language? get currentLanguage => _languages[_currentLanguageCode];
  String get currentLanguageCode => _currentLanguageCode;

  /// All available languages (from appRoot/lang/ and embedded assets)
  List<Language> get availableLanguages => _languages.values.toList();

  /// Initialize i18n: scan lang/ folders in appRoot and load embedded fallbacks
  Future<void> init({String? appRootPath, String? defaultLanguage}) async {
    _appRootPath = appRootPath;
    _currentLanguageCode = defaultLanguage ?? _detectSystemLanguage();

    if (kDebugMode) {
      debugPrint('[I18n] Initializing with appRoot=$appRootPath, defaultLang=$_currentLanguageCode');
    }

    // 1. Load embedded languages from assets as fallback
    await _loadEmbeddedLanguages();

    // 2. Load external languages from appRoot/lang/ (overrides embedded)
    if (appRootPath != null) {
      await _loadExternalLanguages(appRootPath);
    }

    // 3. Ensure current language exists, fallback to 'en' if not
    if (!_languages.containsKey(_currentLanguageCode)) {
      if (kDebugMode) {
        debugPrint('[I18n] Language $_currentLanguageCode not found, falling back to en');
      }
      _currentLanguageCode = 'en';
    }

    if (!_languages.containsKey(_currentLanguageCode)) {
      if (kDebugMode) {
        debugPrint('[I18n] CRITICAL: No languages loaded, using empty fallback');
      }
      _languages[_currentLanguageCode] = Language(
        code: _currentLanguageCode,
        translations: {},
        isEmbedded: true,
      );
    }

    if (kDebugMode) {
      debugPrint('[I18n] Initialized with ${_languages.length} languages: ${_languages.keys.join(', ')}');
      debugPrint('[I18n] Current language: $_currentLanguageCode');
    }
  }

  /// Reload translations from external files (useful for hot-reload without restart)
  Future<void> reload() async {
    if (_appRootPath == null) {
      if (kDebugMode) debugPrint('[I18n] Cannot reload: appRootPath not set');
      return;
    }

    if (kDebugMode) debugPrint('[I18n] Reloading translations...');

    // Reload embedded first (in case user deleted external files)
    await _loadEmbeddedLanguages();

    // Then reload external (overrides embedded)
    await _loadExternalLanguages(_appRootPath!);

    // Notify listeners
    _notifyListeners();

    if (kDebugMode) {
      debugPrint('[I18n] Reload complete. Languages: ${_languages.keys.join(', ')}');
    }
  }

  /// Set active language
  Future<void> setLanguage(String code) async {
    if (!_languages.containsKey(code)) {
      if (kDebugMode) debugPrint('[I18n] Language $code not available');
      return;
    }

    _currentLanguageCode = code;
    _notifyListeners();

    if (kDebugMode) debugPrint('[I18n] Language changed to: $code');
  }

  /// Get translated text by key, with optional parameter substitution
  /// Example: t('error_message', {'error': 'File not found'})
  String t(String key, [Map<String, String>? params]) {
    final lang = currentLanguage;
    if (lang == null) {
      if (kDebugMode) debugPrint('[I18n] No current language set');
      return key;
    }

    String? text = lang.translations[key];
    // Fallback do en jeśli klucz nie istnieje w aktualnym języku
    if (text == null && _languages.containsKey('en')) {
      text = _languages['en']!.translations[key];
    }

    if (text == null) {
      if (kDebugMode) debugPrint('[I18n] Missing key: $key in ${lang.code} (and en)');
      return key; // Fallback to key itself
    }

    // Replace parameters {name} with values
    if (params != null) {
      params.forEach((k, v) {
        text = text!.replaceAll('{$k}', v);
      });
    }

    return text!;
  }

  /// Add listener for language changes
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Load embedded languages from assets/lang/{code}/translations.json
  Future<void> _loadEmbeddedLanguages() async {
    // Oficjalne języki UE + obecne dodatkowe (ua)
    final codes = [
      'bg','hr','cs','da','nl','en','et','fi','fr','de','el','hu','ga','it','lv','lt','mt','pl','pt','ro','sk','sl','es','sv','ua'
    ];

    final Map<String, Map<String, String>> loaded = {};

    for (final code in codes) {
      try {
        final jsonString = await rootBundle.loadString('assets/lang/$code/translations.json');
        final Map<String, dynamic> json = jsonDecode(jsonString);
        final translations = json.map((k, v) => MapEntry(k, v.toString()));
        loaded[code] = translations;
        if (kDebugMode) {
          debugPrint('[I18n] Loaded embedded language: $code (${translations.length} keys)');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[I18n] Failed to load embedded language $code: $e');
        }
      }
    }

    // Zapewnij obecność en jako baza
    final en = loaded['en'] ?? {};

    // Dodaj do mapy języków każdy kod; jeśli nie ma własnych tłumaczeń -> użyj en jako fallback
    for (final code in codes) {
      final map = loaded[code] ?? en;
      _languages[code] = Language(code: code, translations: Map<String, String>.from(map), isEmbedded: true);
    }
  }

  /// Load external languages from appRoot/lang/{code}/translations.json
  Future<void> _loadExternalLanguages(String appRootPath) async {
    try {
      final langDir = Directory('$appRootPath${Platform.pathSeparator}lang');
      if (!await langDir.exists()) {
        if (kDebugMode) debugPrint('[I18n] External lang directory not found: ${langDir.path}');
        return;
      }

      // Scan for language folders
      await for (final entity in langDir.list()) {
        if (entity is Directory) {
          final code = entity.path.split(Platform.pathSeparator).last;
          await _loadExternalLanguage(code, entity.path);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[I18n] Error loading external languages: $e');
    }
  }

  /// Load a single external language from folder
  Future<void> _loadExternalLanguage(String code, String folderPath) async {
    try {
      final translationsFile = File('$folderPath${Platform.pathSeparator}translations.json');
      final flagFile = File('$folderPath${Platform.pathSeparator}flag.png');

      if (!await translationsFile.exists()) {
        if (kDebugMode) {
          debugPrint('[I18n] Translations file not found for $code: ${translationsFile.path}');
        }
        return;
      }

      final jsonString = await translationsFile.readAsString();
      final Map<String, dynamic> json = jsonDecode(jsonString);
      final translations = json.map((k, v) => MapEntry(k, v.toString()));

      _languages[code] = Language(
        code: code,
        translations: translations,
        flagPath: await flagFile.exists() ? flagFile.path : null,
        isEmbedded: false,
      );

      if (kDebugMode) {
        debugPrint('[I18n] Loaded external language: $code (${translations.length} keys)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[I18n] Error loading external language $code: $e');
      }
    }
  }

  /// Detect system language (simple heuristic based on platform locale)
  String _detectSystemLanguage() {
    try {
      final locale = Platform.localeName; // e.g. 'en_US', 'pl_PL'
      final code = locale.split('_').first.toLowerCase();
      if (kDebugMode) debugPrint('[I18n] Detected system language: $code (from $locale)');
      return code;
    } catch (e) {
      if (kDebugMode) debugPrint('[I18n] Failed to detect system language: $e');
      return 'en';
    }
  }
}

/// Convenience alias
typedef I18n = I18nService;

