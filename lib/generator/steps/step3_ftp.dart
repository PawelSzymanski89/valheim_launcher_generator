import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:dartssh2/dartssh2.dart';
import '../config_manager.dart';
import '../../utils/lang_provider.dart';

class Step3Ftp extends StatefulWidget {
  const Step3Ftp({super.key});
  @override
  State<Step3Ftp> createState() => _Step3FtpState();
}

class _Step3FtpState extends State<Step3Ftp> {
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  bool _obscurePass = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<GeneratorProvider>().config;
    _hostCtrl = TextEditingController(text: cfg.ftpHost);
    _portCtrl = TextEditingController(text: cfg.ftpPort.toString());
    _userCtrl = TextEditingController(text: cfg.ftpUser);
    _passCtrl = TextEditingController(text: cfg.ftpPassword);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final cfg = context.read<GeneratorProvider>().config;
    setState(() { _testing = true; _testResult = null; });
    try {
      final port = int.tryParse(_portCtrl.text) ?? 2022;
      final isSftp = port == 22 || port == 2022;

      if (isSftp) {
        final socket = await SSHSocket.connect(cfg.ftpHost, port,
            timeout: const Duration(seconds: 10));
        final client = SSHClient(socket,
            username: cfg.ftpUser,
            onPasswordRequest: () => cfg.ftpPassword);
        await client.authenticated;
        client.close();
        setState(() { _testOk = true; _testResult = '✓ SFTP OK (port $port)'; });
      } else {
        final ftp = FTPConnect(cfg.ftpHost,
            port: port, user: cfg.ftpUser, pass: cfg.ftpPassword,
            timeout: 10);
        await ftp.connect();
        await ftp.disconnect();
        setState(() { _testOk = true; _testResult = '✓ FTP OK (port $port)'; });
      }
    } catch (e) {
      setState(() { _testOk = false; _testResult = '✗ $e'; });
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<GeneratorProvider>();
    final lang = context.watch<LangProvider>();
    final cfg = prov.config;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(lang.t('ftp_host')),
          const SizedBox(height: 8),
          _field(_hostCtrl, lang.t('ftp_host_hint'), (v) { cfg.ftpHost = v; prov.notify(); }),
        ])),
        const SizedBox(width: 16),
        SizedBox(width: 100, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(lang.t('ftp_port')),
          const SizedBox(height: 8),
          _field(_portCtrl, '2022', (v) {
            cfg.ftpPort = int.tryParse(v) ?? 2022;
            prov.notify();
          }, keyboardType: TextInputType.number),
        ])),
      ]),
      const SizedBox(height: 16),
      _label(lang.t('ftp_user')),
      const SizedBox(height: 8),
      _field(_userCtrl, lang.t('ftp_user_hint'), (v) { cfg.ftpUser = v; prov.notify(); }),
      const SizedBox(height: 16),
      _label(lang.t('ftp_pass')),
      const SizedBox(height: 8),
      TextField(
        controller: _passCtrl,
        obscureText: _obscurePass,
        onChanged: (v) { cfg.ftpPassword = v; prov.notify(); },
        style: const TextStyle(color: Colors.white),
        decoration: _deco(lang.t('ftp_pass_hint')).copyWith(
          suffixIcon: IconButton(
            icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off,
                color: Colors.white38, size: 20),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(children: [
        ElevatedButton.icon(
          onPressed: _testing ? null : _testConnection,
          icon: _testing
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.wifi_tethering, size: 18),
          label: Text(_testing ? lang.t('testing') : lang.t('test_conn')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        if (_testResult != null) ...[
          const SizedBox(width: 14),
          Text(_testResult!,
              style: TextStyle(
                color: _testOk ? Colors.greenAccent.shade400 : Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )),
        ],
      ]),
    ]);
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600));

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.blueAccent.shade400)),
  );

  Widget _field(TextEditingController ctrl, String hint, void Function(String) onChange,
      {TextInputType? keyboardType}) =>
    TextField(
      controller: ctrl,
      onChanged: onChange,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _deco(hint),
    );
}
