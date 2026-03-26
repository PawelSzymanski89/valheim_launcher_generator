import 'dart:ui';
import 'package:flutter/foundation.dart';

class I18n {
  static final I18n instance = I18n._();
  I18n._();

  Locale _locale = const Locale('pl');
  Locale get locale => _locale;

  final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'Patcher',
      'connecting': 'Connecting to server...',
      'scanning': 'Scanning files...',
      'checking_updates': 'Checking for updates...',
      'downloading': 'Downloading...',
      'extracting': 'Extracting...',
      'ready': 'Ready to play',
      'update_available': 'Update available!',
      'start_game': 'START GAME',
      'update': 'UPDATE',
      'settings': 'Settings',
      'language': 'Language',
      'server_info': 'Connected to:',
      'error': 'Error',
      'retry': 'Retry',
      'files': 'Files',
      'size': 'Size',
      'speed': 'Speed',
      'active_threads': 'Active Threads',
      'overall_progress': 'Overall Progress',
      'legal_notice': 'Legal Notice',
      'about_line1': 'Valheim® is a registered trademark of Iron Gate AB.',
      'about_line2': 'This application is an independent, unofficial tool used solely for identification purposes.',
      'created_with': 'Created with Valheim Launcher Generator',
      // New keys for patcher
      'building_cache': 'Building cache...',
      'folder_stats': 'All Folders Statistics',
      'total_files': 'Total files:',
      'total_size': 'Total size:',
      'no_data': 'No data',
      'no_files_in_folder': 'No files in this folder',
      'back': 'Back',
      'refresh': 'Refresh',
      'pool_size': 'Connection pool size',
      'info': 'Info',
      'current_value': 'Current:',
      'cancel': 'Cancel',
      'apply': 'Apply',
      'json_not_ready': 'Error: JSON not ready. Wait for scanning to finish.',
      'json_save_error': 'Error: Could not save JSON to disk',
      'json_saved': '✓ JSON saved:',
      'save_json_first': 'Save JSON first',
      'upload_to_bepinex': 'Upload to BepInEx',
      'uploading': 'Uploading:',
      'all_files_uploaded': '✓ All files uploaded!',
      'close': 'Close',
      'files_per_second': 'f/s',
      'building_cache_structure': 'Building cache structure...',
      'scanning_and_calculating': 'Scanning and calculating sizes...',
      'time': 'Time:',
      'ftp_connections': 'FTP Connections:',
      'last_processed': 'Last processed:',
      'waiting_for_data': 'Waiting for data...',
    },
    'pl': {
      'app_title': 'Patcher',
      'connecting': 'Łączenie z serwerem...',
      'scanning': 'Skanowanie plików...',
      'checking_updates': 'Sprawdzanie aktualizacji...',
      'downloading': 'Pobieranie...',
      'extracting': 'Wypakowywanie...',
      'ready': 'Gotowy do gry',
      'update_available': 'Dostępna aktualizacja!',
      'start_game': 'URUCHOM GRĘ',
      'update': 'AKTUALIZUJ',
      'settings': 'Ustawienia',
      'language': 'Język',
      'server_info': 'Połączono z:',
      'error': 'Błąd',
      'retry': 'Ponów',
      'files': 'Pliki',
      'size': 'Rozmiar',
      'speed': 'Prędkość',
      'active_threads': 'Aktywne wątki',
      'overall_progress': 'Postęp całkowity',
      'legal_notice': 'Informacja prawna',
      'about_line1': 'Valheim® jest zarejestrowanym znakiem towarowym Iron Gate AB.',
      'about_line2': 'Niniejsza aplikacja jest niezależnym narzędziem i używa nazwy Valheim wyłącznie w celu identyfikacji.',
      'created_with': 'Stworzono za pomocą Valheim Launcher Generator',
      // New keys for patcher
      'building_cache': 'Budowanie cache...',
      'folder_stats': 'Statystyki wszystkich folderów',
      'total_files': 'Razem plików:',
      'total_size': 'Razem rozmiar:',
      'no_data': 'Brak danych',
      'no_files_in_folder': 'Brak plików w tym folderze',
      'back': 'Wróć',
      'refresh': 'Odśwież',
      'pool_size': 'Pula połączeń',
      'info': 'Informacje',
      'current_value': 'Aktualnie:',
      'cancel': 'Anuluj',
      'apply': 'Zastosuj',
      'json_not_ready': 'Błąd: JSON nie jest gotowy. Poczekaj na zakończenie skanowania.',
      'json_save_error': 'Błąd: Nie udało się zapisać JSON na dysku',
      'json_saved': '✓ JSON zapisany:',
      'save_json_first': 'Najpierw zapisz JSON',
      'upload_to_bepinex': 'Upload do BepInEx',
      'uploading': 'Uploadowanie:',
      'all_files_uploaded': '✓ Wszystkie pliki przesłane!',
      'close': 'Zamknij',
      'files_per_second': 'pł/s',
      'building_cache_structure': 'Budowanie cache struktury...',
      'scanning_and_calculating': 'Skanowanie i liczenie rozmiarów...',
      'time': 'Czas:',
      'ftp_connections': 'Połączenia FTP:',
      'last_processed': 'Ostatnio przetwarzane:',
      'waiting_for_data': 'Czekam na dane...',
    },
  };

  void setLocale(String langCode) {
    if (_localizedValues.containsKey(langCode)) {
      _locale = Locale(langCode);
    }
  }

  String t(String key) {
    return _localizedValues[_locale.languageCode]?[key] ?? key;
  }
}
