import 'dart:async';
import 'package:flutter/material.dart';
import 'ftp_service.dart';
import 'file_info.dart';
import 'file_stats.dart';
import 'file_cache.dart';
import 'crypto_config.dart';
import 'i18n.dart';

void main() {
  runApp(const MyApp());
}
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Server name loaded from encrypted config at runtime (no recompilation needed)
  String _serverName = 'Server';
  Locale _locale = I18n.instance.locale;

  @override
  void initState() {
    super.initState();
    _loadServerName();
  }

  Future<void> _loadServerName() async {
    final config = await loadDecryptedConfig();
    if (config != null && config.serverName.isNotEmpty && mounted) {
      setState(() => _serverName = config.serverName);
    }
  }

  void _toggleLanguage() {
    setState(() {
      final newLang = _locale.languageCode == 'pl' ? 'en' : 'pl';
      I18n.instance.setLocale(newLang);
      _locale = I18n.instance.locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$_serverName',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0A06),
        fontFamily: 'Norse',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4A017),
          secondary: Color(0xFF8B6914),
          surface: Color(0xFF1A1410),
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onSurface: Colors.white70,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1410),
          foregroundColor: Color(0xFFD4A017),
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Norse',
            fontSize: 20,
            color: Color(0xFFD4A017),
            letterSpacing: 2,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1410),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0xFF2A2010)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4A017),
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontFamily: 'Norse', letterSpacing: 1),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF8B6914),
            textStyle: const TextStyle(fontFamily: 'Norse'),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFD4A017),
          foregroundColor: Colors.black,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF8B6914),
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFFD4A017),
          thumbColor: Color(0xFFD4A017),
          inactiveTrackColor: Color(0xFF2A2010),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFD4A017),
          linearTrackColor: Color(0xFF2A2010),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF1A1410),
          titleTextStyle: TextStyle(fontFamily: 'Norse', fontSize: 20, color: Color(0xFFD4A017)),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1A1410),
          contentTextStyle: TextStyle(fontFamily: 'Norse', color: Colors.white70),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Colors.white70,
          iconColor: Color(0xFF8B6914),
          selectedTileColor: Color(0x20D4A017),
        ),
        dividerColor: const Color(0xFF2A2010),
      ),
      home: FtpFilesPage(
        title: _serverName,
        onLanguageToggle: _toggleLanguage,
      ),
    );
  }
}

class FtpFilesPage extends StatefulWidget {
  const FtpFilesPage({
    super.key,
    required this.title,
    required this.onLanguageToggle,
  });
  final String title;
  final VoidCallback onLanguageToggle;
  @override
  State<FtpFilesPage> createState() => _FtpFilesPageState();
}
class _FtpFilesPageState extends State<FtpFilesPage> {
  late FtpService _ftpService;
  int _poolSize = 4;
  List<FileInfo> _filesList = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _currentPath = '/';
  FileInfo? _selectedFile;
  FileStats? _statistics;
  bool _isLoadingStats = false;
  
  ScanProgress? _lastProgress;

  Stream<ScanProgress>? _progressStream;
  StreamController<ScanProgress>? _proxyController;
  StreamSubscription<ScanProgress>? _originalSubscription;
  DateTime? _startTime;

  // Cache i upload
  List<FileCache>? _cache;
  bool _isUploadingJson = false;
  Map<String, dynamic>? _generatedJson;

  @override
  void initState() {
    super.initState();
    _ftpService = FtpService();
    _poolSize = _ftpService.poolSize;
    _initializeAndLoadFiles();
  }

  @override
  void dispose() {
    _originalSubscription?.cancel();
    try { _proxyController?.close(); } catch (_) {}
    super.dispose();
  }
  Future<void> _initializeAndLoadFiles() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isLoadingStats = true;
        _lastProgress = null;
        _statistics = null;
      });
      await _ftpService.initialize();
      final files = await _ftpService.listFiles(path: _currentPath);
      setState(() {
        _filesList = files;
        _isLoading = false;
      });
      // Rozpocznij indeksowanie i budowanie cache ze statystykami live
      _startIndexing();
    } catch (e) {
      setState(() {
        _errorMessage = '${I18n.instance.t('error')}: $e';
        _isLoading = false;
        _isLoadingStats = false;
      });
    }
  }
  void _startIndexing() {
    _startTime = DateTime.now();
    _lastProgress = null;

    // If there is an existing subscription/controller, cancel/close them to avoid multiple listeners
    _originalSubscription?.cancel();
    try { _proxyController?.close(); } catch (_) {}
    _proxyController = StreamController<ScanProgress>.broadcast();

    // Pobierz oryginalny (single-subscription) stream od serwisu
    final originalStream = _ftpService.getStatisticsForAllFoldersStream();

    // Subskrybuj oryginalny stream tylko RAZ i forwarduj zdarzenia do proxy
    _originalSubscription = originalStream.listen((p) {
      // forward
      if (!(_proxyController?.isClosed ?? true)) _proxyController?.add(p);
      // zapisz ostatni progress i odśwież UI
      if (!mounted) return;
      setState(() {
        _lastProgress = p;
      });
    }, onDone: () {
      // Forward done oraz wykonaj końcowe akcje (ustaw statystyki i cache)
      try { if (!(_proxyController?.isClosed ?? true)) _proxyController?.close(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        if (_lastProgress != null) {
          _statistics = FileStats(
            totalFiles: _lastProgress!.totalFiles,
            totalSize: _lastProgress!.totalSize,
          );
          // Pobierz cache i JSON z serwisu
          _cache = _ftpService.getLastCache();
          _generatedJson = _ftpService.getLastGeneratedJson();
          print('[UI] Cache pobiera z serwisu: ${_cache?.length ?? 0} elementów');
          print('[UI] JSON pobierany z serwisu');
        }
        _isLoadingStats = false;
      });
    }, onError: (error) {
      try { if (!(_proxyController?.isClosed ?? true)) _proxyController?.addError(error); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _isLoadingStats = false;
        print('[UI] Błąd skanowania: $error');
      });
    });

    // Przypisz broadcast proxy do _progressStream używanego przez StreamBuilder
    _progressStream = _proxyController?.stream;
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1410),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF2A2010), width: 1),
        ),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFD4A017)),
            const SizedBox(width: 12),
            Text(I18n.instance.t('legal_notice'),
                style: const TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 20,
                    fontFamily: 'Norse')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              I18n.instance.t('about_line1'),
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              I18n.instance.t('about_line2'),
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const Divider(height: 24, color: Color(0xFF2A2010)),
            Text(
              I18n.instance.t('created_with'),
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11, fontFamily: 'Norse'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style:
                    TextStyle(color: Color(0xFFD4A017), fontFamily: 'Norse')),
          ),
        ],
      ),
    );
  }
  Future<void> _navigateToFolder(String folderName) async {
    final newPath = _currentPath.endsWith('/')
        ? '$_currentPath$folderName/'
        : '$_currentPath/$folderName/';
    setState(() {
      _currentPath = newPath;
      _isLoading = true;
      _errorMessage = null;
      _selectedFile = null;
    });
    try {
      await _ftpService.initialize();
      final files = await _ftpService.listFiles(path: newPath);
      setState(() {
        _filesList = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '${I18n.instance.t('error')}: $e';
        _isLoading = false;
        _currentPath = _ftpService.getParentPath(_currentPath);
      });
    }
  }
  Future<void> _goBack() async {
    final parentPath = _ftpService.getParentPath(_currentPath);
    if (parentPath == _currentPath) return;
    setState(() {
      _currentPath = parentPath;
      _isLoading = true;
      _errorMessage = null;
      _selectedFile = null;
    });
    try {
      await _ftpService.initialize();
      final files = await _ftpService.listFiles(path: parentPath);
      setState(() {
        _filesList = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '${I18n.instance.t('error')}: $e';
        _isLoading = false;
      });
    }
  }
  void _selectFile(FileInfo file) {
    setState(() {
      _selectedFile = file;
    });
  }

  Future<void> _saveJsonCache() async {
    // Sprawdź czy JSON jest wygenerowany
    if (_generatedJson == null) {
      _generatedJson = _ftpService.getLastGeneratedJson();
    }

    if (_generatedJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.instance.t('json_not_ready'))),
      );
      return;
    }

    try {
      setState(() => _isUploadingJson = true);

      // Zapisz JSON na dysk
      final path = await _ftpService.saveLastGeneratedJsonToDisk();

      setState(() => _isUploadingJson = false);

      if (!mounted) return;
      if (path.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.instance.t('json_save_error'))),
        );
        return;
      }

      print('[UI] JSON zapisany: $path');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${I18n.instance.t('json_saved')}\n$path')),
      );
    } catch (e) {
      setState(() => _isUploadingJson = false);
      if (!mounted) return;
      print('[UI] Błąd zapisu JSON: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd zapisu JSON: $e')),
      );
    }
  }

  Future<void> _uploadJsonToBepInEx() async {
    if (_generatedJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.instance.t('save_json_first'))),
      );
      return;
    }

    try {
      setState(() => _isUploadingJson = true);

      // Pokaż dialog z postępem
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _buildUploadDialog(context),
      );
    } catch (e) {
      setState(() => _isUploadingJson = false);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd: $e')),
      );
    }
  }

  Widget _buildUploadDialog(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(I18n.instance.t('upload_to_bepinex')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<Map<String, dynamic>>(
                stream: _ftpService.uploadJsonStream(_generatedJson!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  final data = snapshot.data!;
                  final type = data['type'] as String;

                    if (type == 'file_progress') {
                      final percentage = double.parse(data['percentage'] as String);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${I18n.instance.t('uploading')} ${data['fileName']}'),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: percentage / 100),
                          const SizedBox(height: 8),
                          Text('${data['percentage']}%'),
                        ],
                      );
                  } else if (type == 'file_completed') {
                    return Text('✓ ${data['fileName']} ukończony (${data['completed']}/${data['total']})');
                    } else if (type == 'all_completed') {
                      return Column(
                        children: [
                          Text(I18n.instance.t('all_files_uploaded')),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _isUploadingJson = false);
                            },
                            child: Text(I18n.instance.t('close')),
                          ),
                        ],
                      );
                    } else if (type == 'error') {
                      return Text('❌ ${I18n.instance.t('error')}: ${data['error']}');
                    }

                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.title} ${I18n.instance.t('app_title')}'),
            if (_isLoading == false && _errorMessage == null)
              Text(
                '${I18n.instance.t('server_info')} ${_ftpService.host}',
                style: const TextStyle(fontSize: 10, fontFamily: 'Norse', color: Colors.white38),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: I18n.instance.t('language'),
            onPressed: () {
              widget.onLanguageToggle();
              setState(() {}); // Refresh local UI
            },
          ),
          ElevatedButton.icon(
            onPressed: (_isUploadingJson || _isLoadingStats) ? null : _saveJsonCache,
            icon: const Icon(Icons.save),
            label: Text(I18n.instance.t('files')),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isUploadingJson || _generatedJson == null ? null : _uploadJsonToBepInEx,
            icon: const Icon(Icons.cloud_upload),
            label: Text(I18n.instance.t('update')),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: I18n.instance.t('pool_size'),
            onPressed: () async {
              int newSize = _poolSize;
              await showDialog<void>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text(I18n.instance.t('pool_size')),
                    content: StatefulBuilder(builder: (context, setStateDialog) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${I18n.instance.t('current_value')} $newSize'),
                          Slider(
                            value: newSize.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '$newSize',
                            onChanged: (v) => setStateDialog(() { newSize = v.round(); }),
                          ),
                        ],
                      );
                    }),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(I18n.instance.t('cancel'))),
                      ElevatedButton(onPressed: () {
                        // Zastosuj i restartuj indeksowanie
                        setState(() {
                          _poolSize = newSize;
                          _ftpService.poolSize = _poolSize;
                          _isLoadingStats = true;
                          _startIndexing();
                        });
                        Navigator.of(context).pop();
                      }, child: Text(I18n.instance.t('apply'))),
                    ],
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: I18n.instance.t('info'),
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: Column(
              children: [
                  if (_currentPath != '/')
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton.icon(
                        onPressed: _goBack,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(I18n.instance.t('back')),
                      ),
                    ),
                Expanded(child: _buildLeftPanel()),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: _buildRightPanel(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _initializeAndLoadFiles,
        tooltip: I18n.instance.t('refresh'),
        child: const Icon(Icons.refresh),
      ),
    );
  }
  Widget _buildLeftPanel() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 16),
          ),
        ),
      );
    }
    if (_filesList.isEmpty) {
      return Center(
        child: Text(I18n.instance.t('no_files_in_folder')),
      );
    }

    // Sortuj listę: foldery na górze alfabetycznie, potem pliki alfabetycznie
    final sortedFiles = List<FileInfo>.from(_filesList);
    sortedFiles.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return ListView.builder(
      itemCount: sortedFiles.length,
      itemBuilder: (context, index) {
        final file = sortedFiles[index];
        final isSelected = _selectedFile == file;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          color: isSelected ? const Color(0x30D4A017) : null,
          child: ListTile(
            leading: Icon(
              file.isDir ? Icons.folder : Icons.insert_drive_file,
              color: file.isDir ? const Color(0xFFD4A017) : const Color(0xFF8B6914),
            ),
            title: Text(
              file.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(file.sizeFormatted),
                if (file.unique != null && file.unique!.isNotEmpty)
                  Text(
                    'Unique: ${file.unique}',
                    style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            onTap: () {
              _selectFile(file);
              if (file.isDir) {
                _navigateToFolder(file.name);
              }
            },
            trailing: file.isDir
                ? const Icon(Icons.arrow_forward_ios, size: 16)
                : null,
          ),
        );
      },
    );
  }
  Widget _buildRightPanel() {
    // Jeśli trwa indeksowanie — użyj StreamBuilder, inaczej pokaż finalne statystyki lub brak danych
    if (_isLoadingStats) {
      return Container(
        color: const Color(0xFF0D0A06),
        child: StreamBuilder<ScanProgress>(
          stream: _progressStream,
          builder: (context, snapshot) {
            final progress = snapshot.data ?? _lastProgress;
            // jeśli stream zakończony bez danych — wyświetl komunikat
            if (snapshot.connectionState == ConnectionState.waiting && progress == null) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 8), Text(I18n.instance.t('building_cache'))]));
            }
            return _buildScanProgress(progress);
          },
        ),
      );
    }

    return Container(
      color: const Color(0xFF0D0A06),
      child: _statistics != null
          ? Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            I18n.instance.t('folder_stats'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1410),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF2A2010)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatRow(
                                  I18n.instance.t('total_files'),
                                  _statistics!.totalFiles.toString(),
                                ),
                                _buildStatRow(
                                  I18n.instance.t('total_size'),
                                  _statistics!.totalSizeFormatted,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Text(I18n.instance.t('no_data')),
            ),
    );
  }
  Widget _buildScanProgress(ScanProgress? progress) {
     // Oblicz czas trwania
     String elapsedTime = '0s';
     if (_startTime != null) {
       final elapsed = DateTime.now().difference(_startTime!);
       if (elapsed.inHours > 0) {
         elapsedTime = '${elapsed.inHours}h ${elapsed.inMinutes % 60}m ${elapsed.inSeconds % 60}s';
       } else if (elapsed.inMinutes > 0) {
         elapsedTime = '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s';
       } else {
         elapsedTime = '${elapsed.inSeconds}s';
       }
     }

     // Oblicz szybkość (pliki/sekundę)
     String speed = '0 ${I18n.instance.t('files_per_second')}';
    if (_startTime != null) {
      final elapsed = DateTime.now().difference(_startTime!).inSeconds;
      if (elapsed > 0 && progress != null) {
        final filesPerSecond = progress.totalFiles / elapsed;
        speed = '${filesPerSecond.toStringAsFixed(1)} ${I18n.instance.t('files_per_second')}';
      }
    }

    // Użyj domyślnych wartości jeśli progress jest null
    final totalFiles = progress?.totalFiles ?? 0;
    final totalSizeFormatted = progress?.totalSizeFormatted ?? '0 B';
    final activeConnections = progress?.activeConnections ?? 0;
    // Pobierz ostatnie maksymalnie 100 elementów (lista w streamie ma najnowsze na początku)
    final rawScanned = progress?.scannedItems ?? [];
    final scannedItems = rawScanned.take(100).toList();
    final isBuildingCache = progress == null || progress.totalSize == 0;

    return Container(
      color: const Color(0xFF0D0A06),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1410),
              border: const Border(bottom: BorderSide(color: Color(0xFF2A2010))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBuildingCache ? I18n.instance.t('building_cache_structure') : I18n.instance.t('scanning_and_calculating'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18n.instance.t('files'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$totalFiles',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD4A017),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18n.instance.t('size'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                totalSizeFormatted,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18n.instance.t('time'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                elapsedTime,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18n.instance.t('speed'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                speed,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18n.instance.t('ftp_connections'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$activeConnections',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFD4A017)),
                        strokeWidth: 3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.instance.t('last_processed'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (scannedItems.isEmpty)
                       Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          I18n.instance.t('waiting_for_data'),
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          textAlign: TextAlign.left,
                        ),
                      )
                    else
                      ...scannedItems.map((item) {
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1410),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF2A2010)),
                          ),
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFD4A017),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
