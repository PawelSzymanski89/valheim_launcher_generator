import 'dart:async';
import 'package:flutter/material.dart';
import 'ftp_service.dart';
import 'file_info.dart';
import 'file_stats.dart';
import 'file_cache.dart';
void main() {
  runApp(const MyApp());
}
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // This value is replaced by the build script
  static const String buildServerName = 'AURORA BOREALIS'; 
  String _serverName = 'Patch Builder';

  @override
  void initState() {
    super.initState();
    _serverName = '$buildServerName Patch Builder';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$_serverName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: FtpFilesPage(title: '$_serverName'),
    );
  }
}

class FtpFilesPage extends StatefulWidget {
  const FtpFilesPage({super.key, required this.title});
  final String title;
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
        _errorMessage = 'Blad: $e';
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
        _errorMessage = 'Blad: $e';
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
        _errorMessage = 'Blad: $e';
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
        const SnackBar(content: Text('Błąd: JSON nie jest gotowy. Poczekaj na zakończenie skanowania.')),
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
          const SnackBar(content: Text('Błąd: Nie udało się zapisać JSON na dysku')),
        );
        return;
      }

      print('[UI] JSON zapisany: $path');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ JSON zapisany:\n$path')),
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
        const SnackBar(content: Text('Najpierw zapisz JSON')),
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
        title: const Text('Upload do BepInEx'),
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
                        Text('Uploadowanie: ${data['fileName']}'),
                        SizedBox(height: 8),
                        LinearProgressIndicator(value: percentage / 100),
                        SizedBox(height: 8),
                        Text('${data['percentage']}%'),
                      ],
                    );
                  } else if (type == 'file_completed') {
                    return Text('✓ ${data['fileName']} ukończony (${data['completed']}/${data['total']})');
                  } else if (type == 'all_completed') {
                    return Column(
                      children: [
                        const Text('✓ Wszystkie pliki przesłane!'),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() => _isUploadingJson = false);
                          },
                          child: const Text('Zamknij'),
                        ),
                      ],
                    );
                  } else if (type == 'error') {
                    return Text('❌ Błąd: ${data['error']}');
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
          children: [
            Text(widget.title),
            Text(
              _currentPath,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: (_isUploadingJson || _isLoadingStats) ? null : _saveJsonCache,
            icon: const Icon(Icons.save),
            label: const Text('Zapisz JSON'),
          ),
          SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isUploadingJson || _generatedJson == null ? null : _uploadJsonToBepInEx,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Upload'),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Pool size',
            onPressed: () async {
              int newSize = _poolSize;
              await showDialog<void>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Rozmiar puli połączeń'),
                    content: StatefulBuilder(builder: (context, setStateDialog) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Aktualnie: $newSize'),
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
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Anuluj')),
                      ElevatedButton(onPressed: () {
                        // Zastosuj i restartuj indeksowanie
                        setState(() {
                          _poolSize = newSize;
                          _ftpService.poolSize = _poolSize;
                          _isLoadingStats = true;
                          _startIndexing();
                        });
                        Navigator.of(context).pop();
                      }, child: const Text('Zastosuj')),
                    ],
                  );
                },
              );
            },
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
                      label: const Text('Wróć'),
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
        tooltip: 'Odswiez',
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
      return const Center(
        child: Text('Brak plikow w tym folderze'),
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
          color: isSelected ? Colors.deepPurple.shade100 : null,
          child: ListTile(
            leading: Icon(
              file.isDir ? Icons.folder : Icons.insert_drive_file,
              color: file.isDir ? Colors.blue : Colors.grey,
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
        color: Colors.grey.shade100,
        child: StreamBuilder<ScanProgress>(
          stream: _progressStream,
          builder: (context, snapshot) {
            final progress = snapshot.data ?? _lastProgress;
            // jeśli stream zakończony bez danych — wyświetl komunikat
            if (snapshot.connectionState == ConnectionState.waiting && progress == null) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [CircularProgressIndicator(), SizedBox(height: 8), Text('Budowanie cache...')]));
            }
            return _buildScanProgress(progress);
          },
        ),
      );
    }

    return Container(
      color: Colors.grey.shade100,
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
                          const Text(
                            'Statystyki wszystkich folderow',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.deepPurple.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatRow(
                                  'Razem plikow:',
                                  _statistics!.totalFiles.toString(),
                                ),
                                _buildStatRow(
                                  'Razem rozmiar:',
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
          : const Center(
              child: Text('Brak danych'),
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
     String speed = '0 pł/s';
    if (_startTime != null) {
      final elapsed = DateTime.now().difference(_startTime!).inSeconds;
      if (elapsed > 0 && progress != null) {
        final filesPerSecond = progress.totalFiles / elapsed;
        speed = '${filesPerSecond.toStringAsFixed(1)} pł/s';
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
      color: Colors.grey.shade100,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              border: Border(bottom: BorderSide(color: Colors.deepPurple.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBuildingCache ? 'Budowanie cache struktury...' : 'Skanowanie i liczenie rozmiarów...',
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
                              const Text(
                                'Pliki:',
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
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Rozmiar:',
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
                              const Text(
                                'Czas:',
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
                              const Text(
                                'Szybkość:',
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
                              const Text(
                                'Połączenia FTP:',
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
                        valueColor: AlwaysStoppedAnimation(Colors.deepPurple.shade400),
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
                    const Text(
                      'Ostatnio przetwarzane:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (scannedItems.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Czekam na dane...',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
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
              color: Colors.deepPurple,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
