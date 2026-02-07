import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutMetrics {
  final int totalSets;
  final int totalVolumeKg;
  final double avgRpe;

  const WorkoutMetrics({
    required this.totalSets,
    required this.totalVolumeKg,
    required this.avgRpe,
  });
}

class WorkoutMetricsService {
  /// Calcula métricas igual que MyWorkoutDetailsScreen:
  /// - totalSets (Series done + Circuito + Tabata)
  /// - totalVolumeKg (solo cuando hay reps y weight)
  /// - avgRpe (promedio de rpe encontrados)
  static WorkoutMetrics computeFromPerformed(List<Map<String, dynamic>> performed) {
    int totalSets = 0;
    int totalVolume = 0;

    double rpeSum = 0;
    int rpeCount = 0;

    for (final e in performed) {
      final type = e['type'];

      // =========================
      // 🔵 SERIES
      // =========================
      if (type == 'Series') {
        final sets = List<Map<String, dynamic>>.from(e['sets'] ?? []);
        for (final s in sets) {
          if (s['done'] != true) continue;

          totalSets++;

          final rpe = (s['rpe'] as num?)?.toDouble();
          if (rpe != null) {
            rpeSum += rpe;
            rpeCount++;
          }

          final double weight = (s['weight'] as num?)?.toDouble() ?? 0;
          final int reps = (s['reps'] as num?)?.toInt() ?? 0;
          final bool perSide = s['perSide'] == true;

          final double effectiveWeight = perSide ? weight * 2 : weight;

          if (reps > 0 && effectiveWeight > 0) {
            totalVolume += (effectiveWeight * reps).round();
          }
        }
      }

      // =========================
      // 🔴 CIRCUITO
      // =========================
      if (type == 'Circuito') {
        final rounds = List<Map<String, dynamic>>.from(e['rounds'] ?? []);
        for (final round in rounds) {
          final exercises = List<Map<String, dynamic>>.from(round['exercises'] ?? []);
          for (final ex in exercises) {
            totalSets++;

            final rpe = (ex['rpe'] as num?)?.toDouble();
            if (rpe != null) {
              rpeSum += rpe;
              rpeCount++;
            }

            final double weight = (ex['weight'] as num?)?.toDouble() ?? 0;
            final int reps = (ex['reps'] as num?)?.toInt() ?? 0;
            final bool perSide = ex['perSide'] == true;
            final double effectiveWeight = perSide ? weight * 2 : weight;

            if (reps > 0 && effectiveWeight > 0) {
              totalVolume += (effectiveWeight * reps).round();
            }
          }
        }
      }

      // =========================
      // 🟣 TABATA
      // =========================
      if (type == 'Tabata') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        for (final ex in exercises) {
          totalSets++;

          final rpe = (ex['rpe'] as num?)?.toDouble();
          if (rpe != null) {
            rpeSum += rpe;
            rpeCount++;
          }

          // Tabata normalmente no suma volumen (a menos que tú guardes reps/weight)
          final double weight = (ex['weight'] as num?)?.toDouble() ?? 0;
          final int reps = (ex['reps'] as num?)?.toInt() ?? 0;
          final bool perSide = ex['perSide'] == true;
          final double effectiveWeight = perSide ? weight * 2 : weight;

          if (reps > 0 && effectiveWeight > 0) {
            totalVolume += (effectiveWeight * reps).round();
          }
        }
      }
    }

    final avgRpe = rpeCount > 0 ? (rpeSum / rpeCount) : 0.0;

    return WorkoutMetrics(
      totalSets: totalSets,
      totalVolumeKg: totalVolume,
      avgRpe: avgRpe,
    );
  }

  /// Helper para convertir DocumentSnapshot -> performed
  static List<Map<String, dynamic>> performedFromDoc(DocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['performed'] ?? []);
  }
}
