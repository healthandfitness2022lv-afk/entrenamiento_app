double calculateAverageWorkoutRPE(
  List<Map<String, dynamic>> performed,
) {
  double sum = 0;
  int count = 0;

  for (final block in performed) {

    // =======================
    // 🔵 SERIES
    // =======================
    if (block['type'] == 'Series' || block['type'] == 'Series descendentes' || block['type'] == 'Buscar RM') {

      final exercises =
          List<Map<String, dynamic>>.from(block['exercises'] ?? []);

      for (final ex in exercises) {

        final sets =
            List<Map<String, dynamic>>.from(ex['sets'] ?? []);

        for (final s in sets) {

          final double? rpe =
              (s['rpe'] as num?)?.toDouble();

          if (rpe != null && rpe > 0) {
            sum += rpe;
            count++;
          }
        }
      }
    }

    // =======================
    // 🔴 CIRCUITO
    // =======================
    if (block['type'] == 'Circuito') {

      final rounds =
          List<Map<String, dynamic>>.from(block['rounds'] ?? []);

      for (final round in rounds) {

        final exercises =
            List<Map<String, dynamic>>.from(round['exercises'] ?? []);

        for (final ex in exercises) {

          final double? rpe =
              (ex['rpe'] as num?)?.toDouble();

          if (rpe != null && rpe > 0) {
            sum += rpe;
            count++;
          }
        }
      }
    }

    // =======================
    // 🟣 TABATA
    // =======================
    if (block['type'] == 'Tabata') {

      final exercises =
          List<Map<String, dynamic>>.from(block['exercises'] ?? []);

      for (final ex in exercises) {

        final double? rpe =
            (ex['rpe'] as num?)?.toDouble();

        if (rpe != null && rpe > 0) {
          sum += rpe;
          count++;
        }
      }
    }
  }

  return count == 0 ? 0 : sum / count;
}