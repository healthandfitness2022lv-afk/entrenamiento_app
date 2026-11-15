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

  static double estimate1RM({required double weight, required int reps}) {
    return _epley(weight, reps);
  }

  /// Inversa de Epley: dado un 1RM (real o estimado), el peso esperado para
  /// completar [targetReps] repeticiones.
  static double estimateWeightForReps({
    required double oneRepMax,
    required int targetReps,
  }) {
    return oneRepMax / (1 + targetReps / 30.0);
  }

  /// Agrega al historial de RM (`{ejercicio: [{date, rm, weight, reps, rpe}]}`)
  /// los sets válidos de una sesión. Fuente única del formato que consume
  /// `ProgressAlertService.analyzeSessionImpact` y las gráficas de progreso.
  static void addSessionToRmHistory(
    Map<String, List<Map<String, dynamic>>> history,
    List<Map<String, dynamic>> performed,
    DateTime date, {
    bool Function(String exercise)? include,
  }) {
    for (final s in extractAllValidRMSetCandidates(performed)) {
      final exercise = s['exercise'] as String;
      if (include != null && !include(exercise)) continue;
      final weight = (s['weight'] as num).toDouble();
      final reps = (s['reps'] as num).toInt();
      history.putIfAbsent(exercise, () => []).add({
        'date': date,
        'rm': _epley(weight, reps),
        'weight': weight,
        'reps': reps,
        'rpe': s['rpe'],
      });
    }
  }

  /// Copia del historial con solo los puntos hasta [date] inclusive.
  static Map<String, List<Map<String, dynamic>>> rmHistoryUpTo(
    Map<String, List<Map<String, dynamic>>> history,
    DateTime date,
  ) {
    final out = <String, List<Map<String, dynamic>>>{};
    history.forEach((exercise, points) {
      final kept =
          points.where((p) => !(p['date'] as DateTime).isAfter(date)).toList();
      if (kept.isNotEmpty) out[exercise] = kept;
    });
    return out;
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
      if (block['type'] == 'Series' ||
          block['type'] == 'Series descendentes' ||
          block['type'] == 'Buscar RM') {
        final exercises = List<Map<String, dynamic>>.from(
          block['exercises'] ?? [],
        );

        for (final ex in exercises) {
          final String? exercise = ex['name'] ?? ex['exercise'];
          if (exercise == null) continue;

          final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);

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
            final double effectiveWeight = weight;

            out.add({
              'exercise': exercise,
              'reps': reps,
              'weight': effectiveWeight,
              'rpe': (rpeRaw is num && rpeRaw > 0) ? rpeRaw.toDouble() : 8.0,
            });
          }
        }
      }

      // =========================
      // 🔴 CIRCUITO
      // =========================
      if (block['type'] == 'Circuito') {
        final rounds = List<Map<String, dynamic>>.from(block['rounds'] ?? []);

        for (final round in rounds) {
          final exercises = List<Map<String, dynamic>>.from(
            round['exercises'] ?? [],
          );

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
            final double effectiveWeight = weight;

            out.add({
              'exercise': exercise,
              'reps': reps,
              'weight': effectiveWeight,
              'rpe': (rpeRaw is num && rpeRaw > 0) ? rpeRaw.toDouble() : 7.5,
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
      if (block['type'] != 'Series' &&
          block['type'] != 'Series descendentes' &&
          block['type'] != 'Buscar RM')
        continue;

      final exercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? [],
      );

      for (final ex in exercises) {
        final String? exercise = ex['name'] ?? ex['exercise'];
        if (exercise == null) continue;

        final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);

        for (final s in sets) {
          final double weight = (s['weight'] as num?)?.toDouble() ?? 0;

          final int reps = (s['reps'] as num?)?.toInt() ?? 0;

          final double rpe = (s['rpe'] as num?)?.toDouble() ?? 0;

          if (weight <= 0 || reps <= 0 || rpe <= 0) continue;

          final double effectiveWeight = weight;

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

  // ==========================================================
  // 🧹 Utilidades de Normalización
  // ==========================================================
  static String normalizeExerciseName(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
