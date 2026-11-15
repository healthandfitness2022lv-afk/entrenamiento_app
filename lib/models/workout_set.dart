import 'muscle_catalog.dart';

class WorkoutSet {
  /// Nombre del ejercicio (solo referencia / debug)
  final String exercise;

  /// Cantidad de sets efectivos
  final int sets;

  /// Reps (informativo, NO entra en la fatiga)
  final int reps;

  /// Intensidad percibida
  final double rpe;

  /// Peso utilizado (solo para Series, opcional)
  final double? weight;

  /// Índice de la serie (1..N) para poder mostrar detalle real
  /// Ej: Serie 1, Serie 2, Serie 3...
  final int? setIndex;

  /// (Opcional) índice de ronda para Circuito (1..N)
  /// Si no lo usas, déjalo null.
  final int? roundIndex;

  /// 🆕 Indica si el ejercicio fue realizado por lado
  /// true = unilateral (por lado)
  /// false = bilateral
  final bool perSide;

  final Map<Muscle, double> muscleWeights;

  /// Tipo de origen (Series / Circuito / Tabata)
  final String sourceType;

  WorkoutSet({
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.rpe,
    this.weight,
    this.setIndex,
    this.roundIndex,
    this.perSide = false, // ✅ default seguro
    required this.muscleWeights,
    required this.sourceType,
  });

  /// 🔥 Carga total del set (fatiga base)
  /// ⚠️ el peso NO entra aquí por diseño
  double get load => sets * rpe;

  /// 🔥 Carga distribuida por músculo
  Map<Muscle, double> get muscleLoad {
    final Map<Muscle, double> result = {};

    for (final entry in muscleWeights.entries) {
      result[entry.key] = load * entry.value;
    }

    return result;
  }
}
