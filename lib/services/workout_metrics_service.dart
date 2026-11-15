import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/workout_rpe_utils.dart';
import 'workout_volume_service.dart';

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
  /// Fuente única de sets/volumen/RPE promedio de un workout.
  /// El volumen se delega en [WorkoutVolumeService] y el RPE en
  /// [calculateAverageWorkoutRPE] para no mantener la fórmula en más de un
  /// lugar. Si [onlyDoneSets] es true, las series de tipo "Series*" que
  /// tengan `done: false` explícito se excluyen del conteo de sets (usado en
  /// pantallas donde el usuario puede marcar series como no completadas).
  static WorkoutMetrics computeFromPerformed(
    List<Map<String, dynamic>> performed, {
    bool onlyDoneSets = false,
  }) {
    int totalSets = 0;

    for (final e in performed) {
      final type = e['type'];

      if (type == 'Series' ||
          type == 'Series descendentes' ||
          type == 'Buscar RM') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        for (final ex in exercises) {
          final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
          for (final s in sets) {
            if (onlyDoneSets && s.containsKey('done') && s['done'] != true) {
              continue;
            }
            totalSets++;
          }
        }
      }

      if (type == 'Circuito') {
        final rounds = List<Map<String, dynamic>>.from(e['rounds'] ?? []);
        for (final round in rounds) {
          final exercises = List<Map<String, dynamic>>.from(
            round['exercises'] ?? [],
          );
          totalSets += exercises.length;
        }
      }

      if (type == 'Tabata') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        totalSets += exercises.length;
      }
    }

    final totalVolume = WorkoutVolumeService.calculateWorkoutVolume(performed);
    final avgRpe = calculateAverageWorkoutRPE(performed);

    return WorkoutMetrics(
      totalSets: totalSets,
      totalVolumeKg: totalVolume.round(),
      avgRpe: avgRpe,
    );
  }

  static List<Map<String, dynamic>> performedFromDoc(DocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>?;

    if (data == null) return [];

    return List<Map<String, dynamic>>.from(data['performed'] ?? []);
  }
}
