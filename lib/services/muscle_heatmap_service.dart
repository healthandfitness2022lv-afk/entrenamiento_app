import '../models/muscle_catalog.dart';
import '../models/workout_set.dart';

class MuscleHeatmapService {
  /// --------------------------------------------------
  /// 🔥 Calcula carga muscular REAL por músculo
  /// --------------------------------------------------
  static Map<Muscle, double> calculate(List<WorkoutSet> sets) {
    final Map<Muscle, double> heatmap = {};

    for (final set in sets) {
      // ===============================
      // 🧠 CARGA REAL (series × RPE)
      // ===============================
      final double baseLoad = set.sets * set.rpe;

      // ===============================
      // 🔥 DISTRIBUCIÓN MUSCULAR
      // ===============================
      for (final entry in set.muscleWeights.entries) {
        final muscle = entry.key;
        final weight = entry.value;

        heatmap.update(
          muscle,
          (v) => v + baseLoad * weight,
          ifAbsent: () => baseLoad * weight,
        );
      }
    }

    return heatmap;
  }
}