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

  

  /// Ajuste por RPE (placeholder)
  /// Si ya tienes rpeFactor(rpe), lo conectamos aquí.
  static double estimate1RM({
    required double weight,
    required int reps,
    required double rpe,
    required double Function(double rpe) rpeFactor,
  }) {
    final base = _epley(weight, reps);
    return base * rpeFactor(rpe);
  }

  

 static List<Map<String, dynamic>> extractAllValidRMSetCandidates(
  List<Map<String, dynamic>> performed,
) {
  final List<Map<String, dynamic>> out = [];

  for (final e in performed) {
    final type = e['type'];

    // =========================
    // 🔵 SERIES
    // =========================
    if (type == 'Series') {
      final String? exercise =
          e['exercise'] ??
          (e['exerciseKey'] != null
              ? e['exerciseKey'].toString().split('-').last
              : null);

      if (exercise == null) continue;

      for (final s in e['sets'] ?? []) {
        if (s['done'] != true) continue;

        final reps = s['reps'];
        final weight = s['weight'];
        final rpe = s['rpe'];

        if (reps is num && weight is num && weight > 0 && reps > 0) {
          out.add({
            'exercise': exercise,
            'reps': reps,
            'weight': weight,
            'rpe': (rpe is num && rpe > 0) ? rpe : 8.0,
          });
        }
      }
    }

    // =========================
    // 🔴 CIRCUITO (ESTE FALTABA)
    // =========================
    if (type == 'Circuito') {
      for (final round in e['rounds'] ?? []) {
        for (final ex in round['exercises'] ?? []) {
          final exercise = ex['exercise'];
          final reps = ex['reps'];
          final weight = ex['weight'];
          final rpe = ex['rpe'];

          if (exercise == null) continue;

          if (reps is num && weight is num && weight > 0 && reps > 0) {
            out.add({
              'exercise': exercise,
              'reps': reps,
              'weight': weight,
              'rpe': (rpe is num && rpe > 0) ? rpe : 7.5, // 👈 fallback
            });
          }
        }
      }
    }

    // =========================
    // 🟣 TABATA (NO CUENTA PARA RM)
    // =========================
    // Ignorado intencionalmente
  }

  return out;
}



/// Extrae todos los sets "válidos RM" desde performed (solo Series done)
  static List<Map<String, dynamic>> extractValidSeriesSets(List<Map<String, dynamic>> performed) {
    final out = <Map<String, dynamic>>[];

    for (final e in performed) {
      if (e['type'] != 'Series') continue;

      final String? exercise =
          e['exercise'] ??
          (e['exerciseKey'] != null ? e['exerciseKey'].toString().split('-').last : null);

      if (exercise == null) continue;

      final sets = List<Map<String, dynamic>>.from(e['sets'] ?? []);
      for (final s in sets) {
        if (s['done'] != true) continue;

        final double weight = (s['weight'] as num?)?.toDouble() ?? 0;
        final int reps = (s['reps'] as num?)?.toInt() ?? 0;
        final double rpe = (s['rpe'] as num?)?.toDouble() ?? 0;
        final bool perSide = s['perSide'] == true;

        if (weight <= 0 || reps <= 0 || rpe <= 0) continue;

        final double effectiveWeight = perSide ? weight : weight;

        out.add({
          'exercise': exercise,
          'weight': effectiveWeight,
          'reps': reps,
          'rpe': rpe,
        });
      }
    }

    return out;
  }
}

