import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config_manager.dart';
import '../../utils/crypto_service.dart';
import '../../utils/lang_provider.dart';

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
    final lang = context.read<LangProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
          const SizedBox(width: 10),
          Text(lang.t('salt_warn_title'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          lang.t('salt_box_body'),
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(lang.t('salt_checkbox'),
                style: const TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<GeneratorProvider>();
    final lang = context.watch<LangProvider>();
    final cfg = prov.config;
    final saltLen = _saltCtrl.text.length;
    final saltOk = saltLen >= 30;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        lang.t('salt_intro'),
        style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _saltCtrl,
            onChanged: (v) { cfg.salt = v; prov.notify(); },
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: lang.t('salt_hint'),
              hintStyle: const TextStyle(color: Colors.white38),
              suffixText: lang.t('salt_chars').replaceAll('{n}', '$saltLen'),
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
          label: Text(lang.t('generate_salt')),
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
          child: Text(
            lang.t('salt_min_warn').replaceAll('{n}', '${30 - saltLen}'),
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
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
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text(lang.t('salt_box_title'),
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text(
            lang.t('salt_box_body'),
            style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
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
            Text(lang.t('salt_checkbox'),
                style: const TextStyle(color: Colors.white70)),
          ]),
        ]),
      ),
    ]);
  }
}
