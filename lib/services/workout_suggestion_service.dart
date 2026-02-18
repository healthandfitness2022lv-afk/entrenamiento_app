import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutSuggestionService {

  static Future<int?> suggestMaxRepsForWeight({
  required String userId,
  required String exercise,
  required double targetWeight,
  double tolerance = 0.5, // margen por decimales
}) async {
  final snap = await FirebaseFirestore.instance
      .collection('workouts_logged')
      .where('userId', isEqualTo: userId)
      .get();

  int? maxReps;

  for (final doc in snap.docs) {
    final performed = List<Map<String, dynamic>>.from(doc['performed']);

    for (final e in performed) {
      if (e['type'] != 'Series') continue;
      if (e['exercise'] != exercise) continue;

      final sets = List<Map<String, dynamic>>.from(e['sets']);

      for (final s in sets) {
        if (s['done'] != true) continue;

        final weight = (s['weight'] as num?)?.toDouble();
        final reps = (s['reps'] as num?)?.toInt();

        if (weight == null || reps == null) continue;

        // comparación con tolerancia
        if ((weight - targetWeight).abs() <= tolerance) {
          if (maxReps == null || reps > maxReps) {
            maxReps = reps;
          }
        }
      }
    }
  }

  return maxReps;
}


  static Future<double?> suggestWeightForReps({
    required String userId,
    required String exercise,
    required int targetReps,
  }) async {
    if (targetReps <= 0) return null;

    final snap = await FirebaseFirestore.instance
        .collection('workouts_logged')
        .where('userId', isEqualTo: userId)
        .get();

    double? best;

    for (final doc in snap.docs) {
      final data = doc.data();
      final performed = List<Map<String, dynamic>>.from(
        data['performed'] ?? [],
      );

      for (final e in performed) {
        final type = e['type'];

        // ======================================================
        // 🟢 SERIES
        // ======================================================
        if (type == 'Series') {
          if (e['exercise'] != exercise) continue;

          final sets = List<Map<String, dynamic>>.from(e['sets'] ?? []);

          for (final s in sets) {
            final reps = s['reps'];
            final weight = s['weight'];

            if (reps == targetReps && weight != null) {
              final w = (weight as num).toDouble();
              if (best == null || w > best) {
                best = w;
              }
            }
          }
        }

        // ======================================================
        // 🔵 CIRCUITOS
        // ======================================================
        if (type == 'Circuito') {
          final rounds = List<Map<String, dynamic>>.from(
            e['rounds'] ?? [],
          );

          for (final r in rounds) {
            final exercises = List<Map<String, dynamic>>.from(
              r['exercises'] ?? [],
            );

            for (final ex in exercises) {
              if (ex['exercise'] != exercise) continue;

              final reps = ex['reps'];
              final weight = ex['weight'];

              if (reps == targetReps && weight != null) {
                final w = (weight as num).toDouble();
                if (best == null || w > best) {
                  best = w;
                }
              }
            }
          }
        }
      }
    }

    return best; // null si no hay historial
  }
}
