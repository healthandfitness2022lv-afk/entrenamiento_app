// lib/services/workout_load_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_set.dart';
import '../models/muscle_catalog.dart';
import '../utils/exercise_catalogs.dart';
import '../utils/rpe_factor.dart';


class WorkoutLoadService {
  // ======================================================
  // 🔥 API PRINCIPAL
  // ======================================================
  static Future<Map<Muscle, double>> calculateLoadFromWorkout(
    Map<String, dynamic> workoutData,
  ) async {
    final performed = List<Map<String, dynamic>>.from(
      workoutData['performed'] ?? [],
    );

    if (performed.isEmpty) return {};

    final exercisesMap = await _loadExercises(performed);
    final workoutSets = _buildWorkoutSetsForHeatmap(performed, exercisesMap);

    return _calculateMuscleAccumulation(workoutSets, exercisesMap);
  }

  // ======================================================
  // 🔎 CARGAR EJERCICIOS USADOS
  // ======================================================
  static Future<Map<String, Map<String, dynamic>>> _loadExercises(
    List<Map<String, dynamic>> performed,
  ) async {
    final Set<String> names = {};

    for (final e in performed) {
      if (e['type'] == 'Series') {
        if (e['exercise'] != null) {
          names.add(e['exercise']);
        } else if (e['exerciseKey'] != null) {
          names.add(e['exerciseKey'].toString().split('-').last);
        }
      }

      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final ex in round['exercises'] ?? []) {
            names.add(ex['exercise']);
          }
        }
      }

      if (e['type'] == 'Tabata') {
        for (final ex in e['exercises'] ?? []) {
          names.add(ex['exercise']);
        }
      }
    }

    if (names.isEmpty) return {};

    final snap = await FirebaseFirestore.instance
        .collection('exercises')
        .where('name', whereIn: names.toList())
        .get();

    final Map<String, Map<String, dynamic>> exercisesMap = {};

    for (final d in snap.docs) {
      exercisesMap[d['name']] = d.data();
    }

    return exercisesMap;
  }

  // ======================================================
  // 🧱 CONSTRUIR WORKOUT SETS
  // ======================================================
  static List<WorkoutSet> _buildWorkoutSetsForHeatmap(
    List<Map<String, dynamic>> performed,
    Map<String, Map<String, dynamic>> exercisesMap,
  ) {
    final List<WorkoutSet> result = [];

    for (final e in performed) {
      // ======================
      // 🔵 SERIES
      // ======================
      if (e['type'] == 'Series') {
        final String? name =
            e['exercise'] ??
            (e['exerciseKey'] != null
                ? e['exerciseKey'].toString().split('-').last
                : null);

        if (name == null) continue;

        final ex = exercisesMap[name];
        if (ex == null) continue;

        final muscleWeights = _resolveMuscleWeightsFromExercise(ex);

        for (final s in e['sets'] ?? []) {
          if (s['done'] != true) continue;

          result.add(
            WorkoutSet(
              exercise: name,
              sets: 1,
              reps: (s['reps'] as num?)?.toInt() ?? 1,
              rpe: (s['rpe'] as num).toDouble(),
              muscleWeights: muscleWeights,
              sourceType: 'Series',
            ),
          );
        }
      }

      // ======================
      // 🔴 CIRCUITO
      // ======================
      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final exEntry in round['exercises'] ?? []) {
            final String name = exEntry['exercise'];

            final ex = exercisesMap[name];
            if (ex == null) continue;

            final muscleWeights = _resolveMuscleWeightsFromExercise(ex);

            result.add(
              WorkoutSet(
                exercise: name,
                sets: 1,
                reps: 1,
                rpe: (exEntry['rpe'] as num).toDouble(),
                muscleWeights: muscleWeights,
                sourceType: 'Circuito',
              ),
            );
          }
        }
      }

      // ======================
      // 🟣 TABATA
      // ======================
      if (e['type'] == 'Tabata') {
        for (final exEntry in e['exercises'] ?? []) {
          final String name = exEntry['exercise'];

          final ex = exercisesMap[name];
          if (ex == null) continue;

          final muscleWeights = _resolveMuscleWeightsFromExercise(ex);

          result.add(
            WorkoutSet(
              exercise: name,
              sets: 1,
              reps: 1,
              rpe: (exEntry['rpe'] as num).toDouble(),
              muscleWeights: muscleWeights,
              sourceType: 'Tabata',
            ),
          );
        }
      }
    }

    return result;
  }

  // ======================================================
  // 🧠 RESOLVER MÚSCULOS DESDE EJERCICIO
  // ======================================================
  static Map<Muscle, double> _resolveMuscleWeightsFromExercise(
    Map<String, dynamic> ex,
  ) {
    final Map<Muscle, double> result = {};

    final raw = ex['muscleWeights'];

    // 🟢 PONDERACIÓN MODERNA
    if (raw is Map && raw.isNotEmpty) {
      raw.forEach((k, v) {
        final key = k.toString();
        final value = (v as num).toDouble();

        final match = Muscle.values.where((m) => m.name == key);

        if (match.isNotEmpty) {
          result[match.first] = (result[match.first] ?? 0) + value;
        }
      });

      return result;
    }

    // 🔁 FALLBACK (ejercicios antiguos)
    final muscleNames = <String>[
      ex['primaryMuscle'],
      ...?ex['secondaryMuscles'],
    ];

    for (final name in muscleNames) {
      final mapping = normalizedMuscleCatalogMap[normalizeKey(name)];

      if (mapping == null) continue;

      mapping.forEach((muscle, weight) {
        result[muscle] = (result[muscle] ?? 0) + weight;
      });
    }

    return result;
  }

  // ======================================================
  // 🧮 CÁLCULO FINAL DE CARGA MUSCULAR
  // ======================================================
  static Map<Muscle, double> _calculateMuscleAccumulation(
    List<WorkoutSet> sets,
    Map<String, Map<String, dynamic>> exercisesMap,
  ) {
    final Map<Muscle, double> acc = {};

    for (final s in sets) {
      final ex = exercisesMap[s.exercise];
      final String? exerciseType = ex?['exerciseType'];

      final exerciseFactor = exerciseTypeFactorOf(exerciseType);
      final blockFactor = structureFactor(s.sourceType);

      for (final e in s.muscleWeights.entries) {
        final rpeF = rpeFactor(s.rpe);

acc[e.key] =
    (acc[e.key] ?? 0) +
    (s.sets *
     s.rpe *
     rpeF *
     exerciseFactor *
     blockFactor *
     e.value);

      }
    }

    return acc;
  }

  // ======================================================
  // 🧱 FACTOR POR ESTRUCTURA
  // ======================================================
  static double structureFactor(String sourceType) {
    switch (sourceType) {
      case 'Circuito':
        return 1.2;
      case 'Tabata':
        return 2.5;
      default:
        return 1;
    }
  }
}


