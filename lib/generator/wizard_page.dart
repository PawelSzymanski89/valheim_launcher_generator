import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config_manager.dart';
import 'steps/step1_branding.dart';
import 'steps/step2_server.dart';
import 'steps/step3_ftp.dart';
import 'steps/step4_salt.dart';
import '../utils/shared_salt.dart';

class WizardPage extends StatelessWidget {
  const WizardPage({super.key});

  static const _stepTitles = [
    'BRANDING',
    'SERWER',
    'FTP / SFTP',
    'BEZPIECZEŃSTWO',
  ];

  static const _stepSubtitles = [
    'Nazwa i wygląd launchera',
    'Dane serwera Valheim',
    'Dane do serwera plików',
    'Szyfrowanie konfiguracji',
  ];

  static const _stepIcons = [
    Icons.palette_outlined,
    Icons.dns_outlined,
    Icons.storage_outlined,
    Icons.lock_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<GeneratorProvider>();
    final step = prov.currentStep;

    return Scaffold(
      body: Stack(children: [
        // ── Background texture ──────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A0A0F), Color(0xFF12100A), Color(0xFF0D0A00)],
            ),
          ),
        ),
        // Dekoracyjna siatka
        CustomPaint(painter: _GridPainter(), size: Size.infinite),

        // ── Main layout ──────────────────────────────────────────────
        Row(children: [
          // Left sidebar
          _Sidebar(step: step, stepTitles: _stepTitles, stepIcons: _stepIcons),

          // Content
          Expanded(
            child: Column(children: [
              _TopBar(step: step, subtitle: _stepSubtitles[step]),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: _buildStepContent(step),
                ),
              ),
              _BottomBar(step: step, prov: prov),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _buildStepContent(int step) {
    return switch (step) {
      0 => const Step1Branding(),
      1 => const Step2Server(),
      2 => const Step3Ftp(),
      3 => const Step4Salt(),
      _ => const SizedBox.shrink(),
    };
  }
}

// ── Sidebar ──────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.step, required this.stepTitles, required this.stepIcons});
  final int step;
  final List<String> stepTitles;
  final List<IconData> stepIcons;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF2A2010), width: 1)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D0B05), Color(0xFF100E08)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('VALHEIM',
                  style: TextStyle(
                    fontFamily: 'Norse',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD4A017),
                    letterSpacing: 3,
                  )),
              const Text('LAUNCHER GENERATOR',
                  style: TextStyle(
                    fontFamily: 'Norse',
                    fontSize: 11,
                    color: Color(0xFF8B6914),
                    letterSpacing: 2,
                  )),
              const SizedBox(height: 6),
              Container(height: 1, width: 60, color: const Color(0xFF8B6914)),
            ]),
          ),

          // Steps
          ...List.generate(4, (i) => _StepItem(
            index: i,
            label: stepTitles[i],
            icon: stepIcons[i],
            current: step,
          )),

          const Spacer(),
          // Version
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('v1.0.0',
                style: TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'Norse')),
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.index, required this.label, required this.icon, required this.current});
  final int index, current;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDone = index < current;
    final isActive = index == current;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFD4A017).withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive ? const Color(0xFFD4A017).withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Row(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? const Color(0xFFD4A017) : isActive ? Colors.transparent : Colors.transparent,
            border: Border.all(
              color: isDone || isActive ? const Color(0xFFD4A017) : Colors.white24,
              width: 1.5,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 13, color: Colors.black)
                : Text('${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive ? const Color(0xFFD4A017) : Colors.white38,
                      fontFamily: 'Norse',
                    )),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 15,
            color: isActive ? const Color(0xFFD4A017) : isDone ? Colors.white54 : Colors.white24),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
              fontFamily: 'Norse',
              fontSize: 13,
              letterSpacing: 1,
              color: isActive ? const Color(0xFFD4A017) : isDone ? Colors.white60 : Colors.white30,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
            )),
      ]),
    );
  }
}

// ── Top Bar ─────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({required this.step, required this.subtitle});
  final int step;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A2010))),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('KROK ${step + 1} Z 4',
              style: const TextStyle(
                fontFamily: 'Norse',
                fontSize: 11,
                color: Color(0xFF8B6914),
                letterSpacing: 3,
              )),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(
                fontFamily: 'Norse',
                fontSize: 22,
                color: Colors.white,
                letterSpacing: 1,
              )),
        ]),
        const Spacer(),
        // Progress bar
        SizedBox(
          width: 160,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${((step + 1) / 4 * 100).round()}%',
                style: const TextStyle(
                    color: Color(0xFFD4A017), fontSize: 12, fontFamily: 'Norse')),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (step + 1) / 4,
                backgroundColor: const Color(0xFF2A2010),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFD4A017)),
                minHeight: 3,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Bottom Navigation Bar ────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.step, required this.prov});
  final int step;
  final GeneratorProvider prov;

  bool _canProceed() {
    final cfg = prov.config;
    return switch (step) {
      0 => cfg.isStep1Valid,
      1 => cfg.isStep2Valid,
      2 => cfg.isStep3Valid,
      3 => cfg.isStep4Valid,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isLast = step == 3;
    final canProceed = _canProceed();

    return Container(
      padding: const EdgeInsets.fromLTRB(40, 16, 40, 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2010))),
      ),
      child: Row(children: [
        if (step > 0)
          OutlinedButton.icon(
            onPressed: prov.isGenerating ? null : prov.prevStep,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('WSTECZ'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white54,
              side: const BorderSide(color: Color(0xFF3A2E1A)),
              textStyle: const TextStyle(fontFamily: 'Norse', fontSize: 13, letterSpacing: 1),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        const Spacer(),
        if (prov.lastError != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(prov.lastError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontFamily: 'Norse')),
          ),
        if (prov.outputPath != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 6),
              Text('Gotowe: ${prov.outputPath!.split(r'\').last}',
                  style: const TextStyle(
                      color: Colors.greenAccent, fontSize: 13, fontFamily: 'Norse')),
            ]),
          ),
        ElevatedButton.icon(
          onPressed: (canProceed && !prov.isGenerating)
              ? () => isLast ? _generate(context, prov) : prov.nextStep()
              : null,
          icon: prov.isGenerating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(isLast ? Icons.build_outlined : Icons.arrow_forward, size: 16),
          label: Text(isLast ? 'GENERUJ LAUNCHER' : 'DALEJ'),
          style: ElevatedButton.styleFrom(
            backgroundColor: canProceed ? const Color(0xFF8B6914) : Colors.white12,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontFamily: 'Norse', fontSize: 14, letterSpacing: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ]),
    );
  }

  Future<void> _generate(BuildContext context, GeneratorProvider prov) async {
    prov.setGenerating(true);
    prov.setError(null);
    prov.setOutput(null);
    try {
      final cfg = prov.config;
      // Zapisz salt jeśli zaznaczono
      if (cfg.saveSalt) await SharedSalt.save(cfg.salt);

      // Wygeneruj encrypted config
      final encryptedJson = cfg.toEncryptedJson();
      final outputDir = Directory('output/${cfg.serverName}');
      await outputDir.create(recursive: true);

      // Zapisz encrypted config
      final configFile = File('${outputDir.path}/config_encrypted.json');
      await configFile.writeAsString(jsonEncode({'data': encryptedJson}));

      // Zapisz ftp.json (niezaszyfrowany preview)
      final ftpFile = File('${outputDir.path}/ftp_preview.json');
      await ftpFile.writeAsString(const JsonEncoder.withIndent('  ').convert(cfg.toFtpJson()));

      prov.setOutput(outputDir.path);
    } catch (e) {
      prov.setError('Błąd: $e');
    } finally {
      prov.setGenerating(false);
    }
  }
}

// ── Grid background painter ─────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4A017).withValues(alpha: 0.025)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

