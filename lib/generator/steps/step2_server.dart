import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config_manager.dart';
import '../../utils/lang_provider.dart';

class Step2Server extends StatefulWidget {
  const Step2Server({super.key});
  @override
  State<Step2Server> createState() => _Step2ServerState();
}

class _Step2ServerState extends State<Step2Server> {
  late TextEditingController _addrCtrl;
  late TextEditingController _passCtrl;
  bool _obscurePass = true;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<GeneratorProvider>().config;
    _addrCtrl = TextEditingController(text: cfg.serverAddr);
    _passCtrl = TextEditingController(text: cfg.serverPassword);
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<GeneratorProvider>();
    final lang = context.watch<LangProvider>();
    final cfg = prov.config;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(lang.t('server_addr')),
        const SizedBox(height: 8),
        _field(
          controller: _addrCtrl,
          hint: lang.t('server_addr_hint'),
          onChanged: (v) { cfg.serverAddr = v; prov.notify(); },
        ),
        const SizedBox(height: 20),
        _label(lang.t('server_pass')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              onChanged: (v) { cfg.serverPassword = v; prov.notify(); },
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco(
                hint: lang.t('optional'),
                suffix: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white38, size: 20),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _copied
                ? const Icon(Icons.check_circle, color: Colors.greenAccent, key: ValueKey('ok'))
                : OutlinedButton.icon(
                    key: const ValueKey('copy'),
                    onPressed: _passCtrl.text.isNotEmpty ? () async {
                      await Clipboard.setData(ClipboardData(text: _passCtrl.text));
                      setState(() => _copied = true);
                      await Future.delayed(const Duration(seconds: 2));
                      if (mounted) setState(() => _copied = false);
                    } : null,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(lang.t('copy')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
          ),
        ]),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600));

  InputDecoration _inputDeco({required String hint, Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blueAccent.shade400)),
  );

  Widget _field({required TextEditingController controller, required String hint, required void Function(String) onChanged}) =>
      TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDeco(hint: hint),
      );
}
