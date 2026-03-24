import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config_manager.dart';

class Step1Branding extends StatefulWidget {
  const Step1Branding({super.key});
  @override
  State<Step1Branding> createState() => _Step1BrandingState();
}

class _Step1BrandingState extends State<Step1Branding> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<GeneratorProvider>().config;
    _nameCtrl = TextEditingController(text: cfg.serverName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<GeneratorProvider>();
    final cfg = prov.config;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Nazwa serwera'),
        const SizedBox(height: 8),
        _field(
          controller: _nameCtrl,
          hint: 'np. Moja Baza',
          onChanged: (v) { cfg.serverName = v; prov.notify(); },
        ),
        const SizedBox(height: 4),
        Text(
          _nameCtrl.text.isNotEmpty
              ? 'Plik wyjściowy: "${_nameCtrl.text} Launcher.exe"'
              : 'Wprowadź nazwę serwera',
          style: TextStyle(
            color: _nameCtrl.text.isNotEmpty
                ? Colors.greenAccent.shade400
                : Colors.white38,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 28),
        _label('Tło launchera (PNG / MP4)'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                cfg.backgroundPath.isEmpty ? 'Nie wybrano pliku' : cfg.backgroundPath.split(r'\').last,
                style: TextStyle(
                  color: cfg.backgroundPath.isEmpty ? Colors.white38 : Colors.white70,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['png', 'jpg', 'mp4'],
              );
              if (result != null && result.files.single.path != null) {
                cfg.backgroundPath = result.files.single.path!;
                prov.notify();
              }
            },
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Przeglądaj'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600));

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required void Function(String) onChanged,
    bool obscure = false,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.blueAccent.shade400),
          ),
        ),
      );
}

