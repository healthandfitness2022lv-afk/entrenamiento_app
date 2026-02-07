class WorkoutVolumeService {
  static double calculateWorkoutVolume(
    List<Map<String, dynamic>> performed,
  ) {
    double totalVolume = 0;

    for (final e in performed) {
      // =======================
      // 🔵 SERIES
      // =======================
      if (e['type'] == 'Series') {
        for (final s in e['sets'] ?? []) {
          final double weight =
              (s['weight'] as num?)?.toDouble() ?? 0;
          final int reps =
              (s['reps'] as num?)?.toInt() ?? 0;
          final bool perSide = s['perSide'] == true;

          final double effectiveWeight =
              perSide ? weight * 2 : weight;

          totalVolume += effectiveWeight * reps;
        }
      }

      // =======================
      // 🔴 CIRCUITO
      // =======================
      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final ex in round['exercises'] ?? []) {
            final double weight =
                (ex['weight'] as num?)?.toDouble() ?? 0;
            final int reps =
                (ex['reps'] as num?)?.toInt() ?? 0;
            final bool perSide = ex['perSide'] == true;

            final double effectiveWeight =
                perSide ? weight * 2 : weight;

            totalVolume += effectiveWeight * reps;
          }
        }
      }

      // =======================
      // 🟣 TABATA
      // =======================
      // ❌ intencionalmente no suma volumen
    }

    return totalVolume;
  }
}
