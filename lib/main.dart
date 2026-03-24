import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'generator/config_manager.dart';
import 'generator/wizard_page.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => GeneratorProvider(),
      child: const ValheimGeneratorApp(),
    ),
  );
}

class ValheimGeneratorApp extends StatelessWidget {
  const ValheimGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Valheim Launcher Generator',
      debugShowCheckedModeBanner: false,
      theme: _valheimTheme(),
      home: const WizardPage(),
    );
  }

  ThemeData _valheimTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFFD4A017),
        secondary: const Color(0xFF6B4E11),
        surface: const Color(0xFF0D0D0D),
        error: const Color(0xFFCF6679),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      fontFamily: 'Norse',
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Norse', color: Color(0xFFD4A017), fontWeight: FontWeight.w700, letterSpacing: 2),
        displayMedium: TextStyle(fontFamily: 'Norse', color: Color(0xFFD4A017), fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontFamily: 'Norse', color: Colors.white, fontSize: 20, letterSpacing: 1),
        bodyMedium: TextStyle(fontFamily: 'Norse', color: Colors.white70, fontSize: 15),
        labelLarge: TextStyle(fontFamily: 'Norse', color: Colors.white, fontSize: 14, letterSpacing: 1),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8B6914),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontFamily: 'Norse', fontSize: 15, letterSpacing: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Norse'),
        labelStyle: const TextStyle(color: Color(0xFFD4A017), fontFamily: 'Norse'),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFF3A2E1A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFF3A2E1A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFFD4A017), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

