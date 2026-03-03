import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutSuggestionService {

  static Future<int?> suggestMaxRepsForWeight({
  required String userId,
  required String exercise,
  required double targetWeight,
  double tolerance = 0.5,
}) async {
  final snap = await FirebaseFirestore.instance
      .collection('workouts_logged')
      .where('userId', isEqualTo: userId)
      .get();

  int? maxReps;

  for (final doc in snap.docs) {
    final performed = List<Map<String, dynamic>>.from(
      doc['performed'] ?? [],
    );

    for (final block in performed) {
      if (block['type'] != 'Series') continue;

      final exercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? [],
      );

      for (final ex in exercises) {
        final name = ex['exercise']?.toString().trim().toLowerCase();
        if (name != exercise.trim().toLowerCase()) continue;

        final sets = List<Map<String, dynamic>>.from(
          ex['sets'] ?? [],
        );

        for (final s in sets) {
          final weight = (s['weight'] as num?)?.toDouble();
          final reps = (s['reps'] as num?)?.toInt();

          if (weight == null || reps == null) continue;

          if ((weight - targetWeight).abs() <= tolerance) {
            if (maxReps == null || reps > maxReps) {
              maxReps = reps;
            }
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

  final normalizedExercise = exercise.trim().toLowerCase();

  for (final doc in snap.docs) {
    final performed = List<Map<String, dynamic>>.from(
      doc['performed'] ?? [],
    );

    for (final block in performed) {
      final type = block['type'];

      // ================= SERIES =================
      if (type == 'Series') {
        final exercises = List<Map<String, dynamic>>.from(
          block['exercises'] ?? [],
        );

        for (final ex in exercises) {
          final name =
              ex['exercise']?.toString().trim().toLowerCase();

          if (name != normalizedExercise) continue;

          final sets = List<Map<String, dynamic>>.from(
            ex['sets'] ?? [],
          );

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
      }

      // ================= CIRCUITO =================
      if (type == 'Circuito') {
        final rounds = List<Map<String, dynamic>>.from(
          block['rounds'] ?? [],
        );

        for (final r in rounds) {
          final exercises = List<Map<String, dynamic>>.from(
            r['exercises'] ?? [],
          );

          for (final ex in exercises) {
            final name =
                ex['exercise']?.toString().trim().toLowerCase();

            if (name != normalizedExercise) continue;

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

  return best;
}
}
