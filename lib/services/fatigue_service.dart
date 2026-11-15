// lib/services/fatigue_service.dart
import 'dart:math' as math;
import '../models/muscle_catalog.dart';
import '../services/muscle_recovery_service.dart';

const double recoveryStimulus = 0.0;

/// ======================================================
/// 🧠 MODELO DE ESTADO POR MÚSCULO
/// ======================================================
class MuscleFatigueState {
  double fatigue;
  DateTime lastUpdate;

  MuscleFatigueState({required this.fatigue, required this.lastUpdate});
}

/// ======================================================
/// 💪 FATIGUE SERVICE
/// ======================================================
class FatigueService {
  /// --------------------------------------------------
  /// 🕒 Aplica recuperación continua hasta "now"
  /// --------------------------------------------------
  static double recoverToNow({
    required Muscle muscle,
    required double fatigue,
    required DateTime lastUpdate,
    required DateTime now,
  }) {
    if (fatigue <= 0) return 0;

    final hoursElapsed = now.difference(lastUpdate).inMinutes / 60.0;

    if (hoursElapsed <= 0) return fatigue;

    // Calcular factor por hora basado en la recuperación diaria del músculo
    final recoveryFactor = MuscleRecoveryService().getRecoveryFactor(muscle);
    final recoveryFactorPerHour = math.pow(recoveryFactor, 1 / 24).toDouble();

    return (fatigue * math.pow(recoveryFactorPerHour, hoursElapsed)).clamp(
      0.0,
      100.0,
    );
  }

  /// --------------------------------------------------
  /// 🏋️ Actualiza fatiga tras una sesión
  /// ✔ permite múltiples sesiones al día
  /// ✔ sin techo artificial -> AHORA LIMITADO A 100%
  /// --------------------------------------------------
  static MuscleFatigueState updateAfterSession({
    required MuscleFatigueState state,
    required DateTime sessionTime,
    required double sessionLoad,
  }) {
    final netLoad = math.max(0.0, sessionLoad - recoveryStimulus);

    return MuscleFatigueState(
      fatigue: (state.fatigue + netLoad).clamp(0.0, 100.0),
      lastUpdate: sessionTime,
    );
  }

  /// --------------------------------------------------
  /// 👤 Consulta pasiva (ej: abrir "Perfil")
  /// NO guarda nada, solo calcula
  /// --------------------------------------------------
  static double getCurrentFatigue({
    required Muscle muscle,
    required MuscleFatigueState state,
    required DateTime now,
  }) {
    return recoverToNow(
      muscle: muscle,
      fatigue: state.fatigue,
      lastUpdate: state.lastUpdate,
      now: now,
    );
  }
}
