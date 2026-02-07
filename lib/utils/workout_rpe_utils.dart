// lib/utils/workout_rpe_utils.dart
double calculateAverageWorkoutRPE(
  List<Map<String, dynamic>> performed,
) {
  double sum = 0;
  int count = 0;

  for (final e in performed) {
    // SERIES
    if (e['type'] == 'Series') {
      for (final s in e['sets'] ?? []) {
        if (s['done'] != true) continue;
        final rpe = (s['rpe'] as num?)?.toDouble();
        if (rpe != null) {
          sum += rpe;
          count++;
        }
      }
    }

    // CIRCUITO
    if (e['type'] == 'Circuito') {
      for (final round in e['rounds'] ?? []) {
        for (final ex in round['exercises'] ?? []) {
          final rpe = (ex['rpe'] as num?)?.toDouble();
          if (rpe != null) {
            sum += rpe;
            count++;
          }
        }
      }
    }

    // TABATA
    if (e['type'] == 'Tabata') {
      for (final ex in e['exercises'] ?? []) {
        final rpe = (ex['rpe'] as num?)?.toDouble();
        if (rpe != null) {
          sum += rpe;
          count++;
        }
      }
    }
  }

  return count == 0 ? 0 : sum / count;
}
