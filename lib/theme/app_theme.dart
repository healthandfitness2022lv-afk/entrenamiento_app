import 'package:flutter/material.dart';

/// Paleta única de la app ("Dark Energizer": verde neón sobre negro).
///
/// Todas las pantallas deben tomar colores de acá (o de `Theme.of(context)`)
/// en vez de escribir `Color(0x…)` o `Colors.tealAccent` sueltos: antes había
/// tres estilos distintos (turquesa en inicio, verde neón en detalle, azul
/// en perfil) y cambiar un color implicaba tocar decenas de archivos.
class AppColors {
  AppColors._();

  // ── Marca ─────────────────────────────────────────────
  static const accent = Color(0xFF39FF14); // verde neón (acción principal)
  static const accentSoft = Color(0xFF2ECC71); // verde secundario
  static const accentTint = Color(0xFFD0FFD0); // títulos sobre fondo oscuro

  // ── Superficies (de más profunda a más elevada) ───────
  static const bgDeep = Color(0xFF0A0A0A); // barras laterales
  static const bg = Color(0xFF121212); // fondo de pantalla
  static const surface = Color(0xFF1B1B1B); // tarjetas, diálogos
  static const surface2 = Color(0xFF222222); // campos, tarjetas anidadas
  static const divider = Color(0xFF2A2A2A);

  // ── Texto ─────────────────────────────────────────────
  static const textPrimary = Color(0xFFF5F5F5);
  static const onSurface = Color(0xFFEAEAEA);
  static const textBody = Color(0xFFCFCFCF);
  static const textSecondary = Color(0xFFB8B8B8);
  static const textMuted = Color(0xFF8A8A8A);

  // ── Semánticos ────────────────────────────────────────
  static const info = Color(0xFF3987E5); // datos neutros (volumen, links)
  static const warning = Color(0xFFFFC107); // avisos (recalcular, pendiente)
  static const danger = Color(0xFFE53935); // borrar, errores, salir
  static const success = accentSoft;

  // ── Tipos de bloque (consistentes en toda la app) ─────
  static const series = accent;
  static const circuit = Color(0xFFFF9800);
  static const tabata = Color(0xFFFF5252);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.black,
      secondary: AppColors.accentSoft,
      onSecondary: Colors.black,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainerHighest: AppColors.surface2,
      outline: AppColors.divider,
      outlineVariant: AppColors.divider,
      error: AppColors.danger,
    );

    final roundedMd = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      primaryColor: AppColors.accent,
      dividerColor: AppColors.divider,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.accentTint,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textBody,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.4,
          color: AppColors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: AppColors.textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(50),
          shape: roundedMd,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          minimumSize: const Size(48, 48),
          shape: roundedMd,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.divider),
          shape: roundedMd,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(48, 40),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: AppColors.accent),
        actionsIconTheme: IconThemeData(color: AppColors.accent),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.bgDeep,
        indicatorColor: Color(0x3339FF14),
        selectedIconTheme: IconThemeData(color: AppColors.accent),
        unselectedIconTheme: IconThemeData(color: AppColors.textSecondary),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: AppColors.textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.accent.withOpacity(0.2),
        side: const BorderSide(color: AppColors.divider),
        labelStyle: const TextStyle(color: AppColors.onSurface),
        checkmarkColor: AppColors.accent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.bgDeep,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface2,
        contentTextStyle: TextStyle(color: AppColors.onSurface),
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: AppColors.onSurface),
      ),
    );
  }
}
