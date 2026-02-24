class WorkoutVolumeService {

  static double calculateWorkoutVolume(
    List<Map<String, dynamic>> performed,
  ) {
    double totalVolume = 0;

    for (final block in performed) {

      // =======================
      // 🔵 SERIES 
      // =======================
      if (block['type'] == 'Series') {

        final exercises =
            List<Map<String, dynamic>>.from(block['exercises'] ?? []);

        for (final ex in exercises) {

          final bool exercisePerSide =
              ex['perSide'] == true;

          final sets =
              List<Map<String, dynamic>>.from(ex['sets'] ?? []);

          for (final s in sets) {

            final double weight =
                (s['weight'] as num?)?.toDouble() ?? 0;

            final int reps =
                (s['reps'] as num?)?.toInt() ?? 0;

            if (weight <= 0 || reps <= 0) continue;

            final bool setPerSide =
                s['perSide'] == true;

            final bool perSide =
                exercisePerSide || setPerSide;

            final double effectiveWeight =
                perSide ? weight * 2.0 : weight;

            totalVolume += effectiveWeight * reps;
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

            final double weight =
                (ex['weight'] as num?)?.toDouble() ?? 0;

            final int reps =
                (ex['reps'] as num?)?.toInt() ?? 0;

            if (weight <= 0 || reps <= 0) continue;

            final bool perSide =
                ex['perSide'] == true;

            final double effectiveWeight =
                perSide ? weight * 2.0 : weight;

            totalVolume += effectiveWeight * reps;
          }
        }
      }

      // =======================
      // 🟣 TABATA
      // =======================
      // intencionalmente no suma volumen
    }

    return totalVolume;
  }
}