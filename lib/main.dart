import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'auth_gate.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

// 🔹 IMPORTANTE PARA DATE PICKER / LOCALIZACIONES
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔹 Inicializa datos de fechas en español
  await initializeDateFormatting('es_ES', null);
  Intl.defaultLocale = 'es_ES';

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // =============================
      // 🌍 LOCALIZACIÓN (CLAVE)
      // =============================
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      supportedLocales: const [
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],

      locale: const Locale('es', 'ES'),

      // =============================
      // 🎨 TEMA DARK ENERGIZER
      // =============================
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,

        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF39FF14),

        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF39FF14),
          secondary: Color(0xFF2ECC71),
          background: Color(0xFF121212),
          surface: Color(0xFF1B1B1B),
          onPrimary: Colors.black,
          onSurface: Color(0xFFEAEAEA),
        ),

        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF5F5F5),
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFD0FFD0),
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFCFCFCF),
          ),
          titleSmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFFB8B8B8),
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: Color(0xFFEAEAEA),
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: Color(0xFFB8B8B8),
          ),
        ),

        cardTheme: CardThemeData(
          color: const Color(0xFF1B1B1B),
          elevation: 6,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF39FF14),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF39FF14),
            side: const BorderSide(
              color: Color(0xFF39FF14),
              width: 1.2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF222222),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFF39FF14),
              width: 1.6,
            ),
          ),
          labelStyle: const TextStyle(color: Color(0xFFB8B8B8)),
          hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
        ),

        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.all(
            const Color(0xFF39FF14),
          ),
          checkColor: MaterialStateProperty.all(Colors.black),
        ),

        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.all(
            const Color(0xFF39FF14),
          ),
          trackColor: MaterialStateProperty.all(
            const Color(0x6639FF14),
          ),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF5F5F5),
          ),
          iconTheme: IconThemeData(color: Color(0xFF39FF14)),
        ),
      ),

      home: const AuthGate(),
    );
  }
}
