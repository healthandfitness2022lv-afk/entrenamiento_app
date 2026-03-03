class RMEntry {
  final String exercise;
  final DateTime date;
  final double estimated1RM;
  final double weight;
  final int reps;
  final double rpe;

  const RMEntry({
    required this.exercise,
    required this.date,
    required this.estimated1RM,
    required this.weight,
    required this.reps,
    required this.rpe,
  });
}

class WorkoutRMService {

  /// Epley: 1RM = w * (1 + reps/30)
  static double _epley(double weight, int reps) {
    return weight * (1 + reps / 30.0);
  }

  static double estimate1RM({
    required double weight,
    required int reps,
    required double rpe,
    required double Function(double rpe) rpeFactor,
  }) {
    final base = _epley(weight, reps);
    return base * rpeFactor(rpe);
  }

  // ==========================================================
  // 🔥 Extrae TODOS los sets válidos (Series + Circuito)
  // ==========================================================
  static List<Map<String, dynamic>> extractAllValidRMSetCandidates(
    List<Map<String, dynamic>> performed,
  ) {
    final out = <Map<String, dynamic>>[];

    for (final block in performed) {

      // =========================
      // 🔵 SERIES
      // =========================
      if (block['type'] == 'Series') {

        final exercises =
            List<Map<String, dynamic>>.from(block['exercises'] ?? []);

        for (final ex in exercises) {

          final String? exercise = ex['name'] ?? ex['exercise'];
          if (exercise == null) continue;

          final sets =
              List<Map<String, dynamic>>.from(ex['sets'] ?? []);

          for (final s in sets) {

            final repsRaw = s['reps'];
            final weightRaw = s['weight'];
            final rpeRaw = s['rpe'];

            if (repsRaw is! num ||
                weightRaw is! num ||
                repsRaw <= 0 ||
                weightRaw <= 0) {
              continue;
            }

            final int reps = repsRaw.toInt();
            final double weight = weightRaw.toDouble();
            final bool perSide = s['perSide'] == true;

            final double effectiveWeight =
                perSide ? weight * 2.0 : weight;

            out.add({
              'exercise': exercise,
              'reps': reps,
              'weight': effectiveWeight,
              'rpe': (rpeRaw is num && rpeRaw > 0)
                  ? rpeRaw.toDouble()
                  : 8.0,
            });
          }
        }
      }

      // =========================
      // 🔴 CIRCUITO
      // =========================
      if (block['type'] == 'Circuito') {

        final rounds =
            List<Map<String, dynamic>>.from(block['rounds'] ?? []);

        for (final round in rounds) {

          final exercises =
              List<Map<String, dynamic>>.from(round['exercises'] ?? []);

          for (final ex in exercises) {

            final String? exercise = ex['exercise'];
            if (exercise == null) continue;

            final repsRaw = ex['reps'];
            final weightRaw = ex['weight'];
            final rpeRaw = ex['rpe'];

            if (repsRaw is! num ||
                weightRaw is! num ||
                repsRaw <= 0 ||
                weightRaw <= 0) {
              continue;
            }

            final int reps = repsRaw.toInt();
            final double weight = weightRaw.toDouble();
            final bool perSide = ex['perSide'] == true;

            final double effectiveWeight =
                perSide ? weight * 2.0 : weight;

            out.add({
              'exercise': exercise,
              'reps': reps,
              'weight': effectiveWeight,
              'rpe': (rpeRaw is num && rpeRaw > 0)
                  ? rpeRaw.toDouble()
                  : 7.5,
            });
          }
        }
      }
    }

    return out;
  }

  // ==========================================================
  // 🎯 Solo Series 
  // ==========================================================
  static List<Map<String, dynamic>> extractValidSeriesSets(
    List<Map<String, dynamic>> performed,
  ) {
    final out = <Map<String, dynamic>>[];

    for (final block in performed) {

      if (block['type'] != 'Series') continue;

      final exercises =
          List<Map<String, dynamic>>.from(block['exercises'] ?? []);

      for (final ex in exercises) {

        final String? exercise = ex['name'] ?? ex['exercise'];
        if (exercise == null) continue;

        final sets =
            List<Map<String, dynamic>>.from(ex['sets'] ?? []);

        for (final s in sets) {

          final double weight =
              (s['weight'] as num?)?.toDouble() ?? 0;

          final int reps =
              (s['reps'] as num?)?.toInt() ?? 0;

          final double rpe =
              (s['rpe'] as num?)?.toDouble() ?? 0;

          if (weight <= 0 || reps <= 0 || rpe <= 0) continue;

          final bool perSide = s['perSide'] == true;
          final double effectiveWeight =
              perSide ? weight * 2.0 : weight;

          out.add({
            'exercise': exercise,
            'weight': effectiveWeight,
            'reps': reps,
            'rpe': rpe,
          });
        }
      }
    }

    return out;
  }
}