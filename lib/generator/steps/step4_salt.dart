import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config_manager.dart';
import '../../utils/crypto_service.dart';

class Step4Salt extends StatefulWidget {
  const Step4Salt({super.key});
  @override
  State<Step4Salt> createState() => _Step4SaltState();
}

class _Step4SaltState extends State<Step4Salt> {
  late TextEditingController _saltCtrl;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<GeneratorProvider>().config;
    _saltCtrl = TextEditingController(text: cfg.salt);
  }

  @override
  void dispose() {
    _saltCtrl.dispose();
    super.dispose();
  }

  void _generateSalt() {
    final salt = CryptoService.generateSalt(length: 32);
    _saltCtrl.text = salt;
    final prov = context.read<GeneratorProvider>();
    prov.config.salt = salt;
    prov.notify();
    _showWarning();
  }

  void _showWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
          SizedBox(width: 10),
          Text('Ważne — Nie zgub Salt!',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
          'Salt szyfruje dane FTP i hasło serwera w config.json.\n'
          'Zapisywany jest w rejestrze Windows.\n\n'
          '⚠️ UTRATA SALT = launcher/patcher/updater NIE ZALOGUJĄ się.\n'
          'Brak modów, brak aktualizacji.\n'
          'Musisz konfigurować od ZERA.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Rozumiem', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<GeneratorProvider>();
    final cfg = prov.config;
    final saltLen = _saltCtrl.text.length;
    final saltOk = saltLen >= 30;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        '🔐 Salt szyfruje wszystkie hasła w wygenerowanych plikach.\n'
        'Bez salt nikt nie może uruchomić/zaktualizować launchera.',
        style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _saltCtrl,
            onChanged: (v) { cfg.salt = v; prov.notify(); },
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'min. 30 znaków',
              hintStyle: const TextStyle(color: Colors.white38),
              suffixText: '$saltLen znaków',
              suffixStyle: TextStyle(
                color: saltOk ? Colors.greenAccent : Colors.redAccent,
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: saltOk ? Colors.greenAccent.shade700 : Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: saltOk ? Colors.greenAccent.shade700 : Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.blueAccent.shade400),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _generateSalt,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Generuj'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade800,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ]),
      if (!saltOk && _saltCtrl.text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Salt musi mieć min. 30 znaków (${30 - saltLen} brakuje)',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text('Zguba Salt = reset konfiguracji',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Salt jest przechowywany w rejestrze Windows. Jeśli go zgubisz, '
            'launcher, patcher i updater nie będą mogły się połączyć z FTP.',
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Checkbox(
              value: cfg.saveSalt,
              onChanged: (v) {
                cfg.saveSalt = v ?? true;
                prov.notify();
              },
              activeColor: Colors.amber.shade700,
              checkColor: Colors.black,
            ),
            const SizedBox(width: 4),
            const Text('Rozumiem — zapisz salt w rejestrze',
                style: TextStyle(color: Colors.white70)),
          ]),
        ]),
      ),
    ]);
  }
}

