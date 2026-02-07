// lib/services/fatigue_service.dart
import 'dart:math' as math;
/// 0.70 = recupera 30% diario
const double dailyRecoveryFactor = 0.7;


const double recoveryStimulus = 0.0;


/// ======================================================
/// 🧠 MODELO DE ESTADO POR MÚSCULO
/// ======================================================
class MuscleFatigueState {
  double fatigue;
  DateTime lastUpdate;

  MuscleFatigueState({
    required this.fatigue,
    required this.lastUpdate,
  });
}


/// ======================================================
/// 💪 FATIGUE SERVICE
/// ======================================================
class FatigueService {

  /// --------------------------------------------------
  /// 🔢 Factor de recuperación por hora
  /// Garantiza que 24h == dailyRecoveryFactor
  /// --------------------------------------------------
  static final double _recoveryFactorPerHour =
      math.pow(dailyRecoveryFactor, 1 / 24).toDouble();


  /// --------------------------------------------------
  /// 🕒 Aplica recuperación continua hasta "now"
  /// --------------------------------------------------
  static double recoverToNow({
  required double fatigue,
  required DateTime lastUpdate,
  required DateTime now,
}) {
  if (fatigue <= 0) return 0;

  final hoursElapsed =
      now.difference(lastUpdate).inMinutes / 60.0;

  if (hoursElapsed <= 0) return fatigue;

  return fatigue *
      math.pow(_recoveryFactorPerHour, hoursElapsed);
}



  /// --------------------------------------------------
  /// 🏋️ Actualiza fatiga tras una sesión
  /// ✔ permite múltiples sesiones al día
  /// ✔ sin techo artificial
  /// --------------------------------------------------
  static MuscleFatigueState updateAfterSession({
  required MuscleFatigueState state,
  required DateTime sessionTime,
  required double sessionLoad,
}) {
  final netLoad =
      math.max(0, sessionLoad - recoveryStimulus);

  return MuscleFatigueState(
    fatigue: state.fatigue + netLoad,
    lastUpdate: sessionTime,
  );
}


  /// --------------------------------------------------
  /// 👤 Consulta pasiva (ej: abrir "Perfil")
  /// NO guarda nada, solo calcula
  /// --------------------------------------------------
  static double getCurrentFatigue({
    required MuscleFatigueState state,
    required DateTime now,
  }) {
    return recoverToNow(
      fatigue: state.fatigue,
      lastUpdate: state.lastUpdate,
      now: now,
    );
  }
}
