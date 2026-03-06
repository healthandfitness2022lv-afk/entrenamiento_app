import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

import '../models/muscle_catalog.dart';
import '../models/workout_set.dart';
import '../services/fatigue_service.dart';
import '../services/tabata_timer_service.dart';
import '../services/workout_load_service.dart';
import '../models/achievement.dart';
import '../services/achievement_evaluator_service.dart';
import '../services/fatigue_recalculation_service.dart';

class _WorkoutBuildResult {
  final List<Map<String, dynamic>> performed;
  final List<WorkoutSet> workoutSets;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMinutes;

  _WorkoutBuildResult({
    required this.performed,
    required this.workoutSets,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMinutes,
  });
}

class WorkoutSaveService {
  final BuildContext context;
  final bool isEdit;
  final DocumentReference? workoutRef;
  final Map<String, dynamic> routine;
  final DateTime? workoutStartedAt;
  final DateTime? originalStartedAt;
  final DateTime? originalFinishedAt;
  final int? originalDurationMinutes;
  
  final Map<String, List<Map<String, dynamic>>> seriesData;
  final Map<String, List<TextEditingController>> seriesRepsCtrl;
  final Map<String, List<TextEditingController>> seriesWeightCtrl;
  
  final Map<int, int> circuitoRound;
  final Map<int, Map<int, Map<String, TextEditingController>>> circuitoReps;
  final Map<int, Map<int, Map<String, TextEditingController>>> circuitoWeight;
  final Map<int, Map<int, Map<String, int>>> circuitoRpePorRonda;
  final Map<int, Map<String, bool>> circuitoPerSide;
  
  final TabataTimerService tabataTimer;
  final List<Map<String, dynamic>> availableExercisesCatalog;
  final Map<int, int> blockDurationSeconds;
  
  final Function(String) onStepChanged;
  final Function(Object, StackTrace) onError;
  final Function(List<Achievement>, List<Map<String, dynamic>>) onSuccess;

  WorkoutSaveService({
    required this.context,
    required this.isEdit,
    required this.workoutRef,
    required this.routine,
    required this.workoutStartedAt,
    required this.originalStartedAt,
    required this.originalFinishedAt,
    required this.originalDurationMinutes,
    required this.seriesData,
    required this.seriesRepsCtrl,
    required this.seriesWeightCtrl,
    required this.circuitoRound,
    required this.circuitoReps,
    required this.circuitoWeight,
    required this.circuitoRpePorRonda,
    required this.circuitoPerSide,
    required this.tabataTimer,
    required this.availableExercisesCatalog,
    required this.blockDurationSeconds,
    required this.onStepChanged,
    required this.onError,
    required this.onSuccess,
  });

  String normalizeExerciseName(dynamic raw) {
    if (raw is String) return raw;
    if (raw is List && raw.isNotEmpty) return raw.first.toString();
    return 'Ejercicio';
  }

  Map<Muscle, double> resolveMuscleWeights(Map<String, dynamic> exData) {
    final Map<Muscle, double> result = {};
    if (exData.containsKey('muscleWeights')) {
      final raw = Map<String, dynamic>.from(exData['muscleWeights']);
      raw.forEach((k, v) {
        final match = Muscle.values.where((m) => m.name == k);
        if (match.isNotEmpty) {
          result[match.first] = (v as num).toDouble();
        }
      });
    }
    return result;
  }

  Map<String, dynamic>? _getExerciseFromCatalog(String name) {
    try {
      return availableExercisesCatalog.firstWhere(
        (e) => normalizeExerciseName(e['name']) == name,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> execute() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final data = await _buildWorkoutData();
      final muscleLoad = await _calculateLoad(data);
      final ref = await _persistWorkout(data);

      await ref.update({
        'muscleLoad': {
          for (final e in muscleLoad.entries) e.key.name: e.value
        }
      });

      List<Achievement> unlocked = [];
      if (isEdit) {
        // En lugar de sumar incrementalmente (lo que duplicaría stats),
        // recalculamos exactamente la fatiga global y los hitos historicos.
        // Importación a FatigueRecalculationService es necesaria si no está (ya lo está).
        await FatigueRecalculationService.recalculateAndPersist(uid: uid, forceRecalculateLoad: false);
        await AchievementEvaluatorService.syncHistoricalData();
      } else {
        await _updateFatigue(muscleLoad);

        unlocked = await AchievementEvaluatorService.evaluateSession(
          data.performed,
          data.finishedAt,
        );
      }

      onSuccess(unlocked, data.performed);
    } catch (e, stack) {
      onError(e, stack);
    }
  }

  Future<_WorkoutBuildResult> _buildWorkoutData() async {
    onStepChanged("Procesando datos…");

    late DateTime startedAt;
    late DateTime finishedAt;
    late int durationMinutes;

    if (isEdit) {
      if (originalStartedAt != null &&
          originalFinishedAt != null &&
          originalDurationMinutes != null) {
        startedAt = originalStartedAt!;
        finishedAt = originalFinishedAt!;
        durationMinutes = originalDurationMinutes!;
      } else {
        final randomMinutes = 50 + Random().nextInt(21);
        finishedAt = DateTime.now();
        startedAt = finishedAt.subtract(Duration(minutes: randomMinutes));
        durationMinutes = randomMinutes;
      }
    } else {
      finishedAt = DateTime.now();
      startedAt = workoutStartedAt ?? finishedAt;
      durationMinutes = finishedAt.difference(startedAt).inMinutes;
    }

    final List<Map<String, dynamic>> performed = [];
    final List<WorkoutSet> workoutSets = [];

    await _processSeries(performed, workoutSets);
    await _processCircuits(performed, workoutSets);
    await _processTabata(performed, workoutSets);

    return _WorkoutBuildResult(
      performed: performed,
      workoutSets: workoutSets,
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMinutes: durationMinutes,
    );
  }

  Future<void> _processSeries(
    List<Map<String, dynamic>> performed,
    List<WorkoutSet> workoutSets,
  ) async {
    onStepChanged("Procesando series…");
    final blocks = routine['blocks'] as List;

    for (final entry in seriesData.entries) {
      final key = entry.key;
      final blockIndex = int.parse(key.split('-').first);
      final block = blocks[blockIndex];
      final blockType = block['type'] ?? 'Series';
      final exerciseName = key.split('-').sublist(1).join('-');

      final exData = _getExerciseFromCatalog(exerciseName);
      if (exData == null) continue;

      final muscleWeights = resolveMuscleWeights(exData);
      final List<Map<String, dynamic>> setsToSave = [];

      for (int i = 0; i < entry.value.length; i++) {
        if (entry.value[i]['done'] != true) continue;

        final repsText = seriesRepsCtrl[key]?[i].text ?? '';
        final weightText = seriesWeightCtrl[key]?[i].text ?? '';

        final int reps = int.tryParse(repsText) ?? 0;
        final double? weight =
            weightText.isNotEmpty ? double.tryParse(weightText) : null;

        if (reps <= 0) continue;

        setsToSave.add({
          'reps': reps,
          'weight': weight,
          'rpe': entry.value[i]['rpe'],
        });

        workoutSets.add(
          WorkoutSet(
            exercise: exerciseName,
            sets: 1,
            reps: reps,
            rpe: (entry.value[i]['rpe'] as num).toDouble(),
            weight: weight,
            muscleWeights: muscleWeights,
            sourceType: 'Series',
          ),
        );
      }

      if (setsToSave.isNotEmpty) {
        final originalExercise = block['exercises'].firstWhere(
          (ex) => normalizeExerciseName(ex['name']) == exerciseName,
          orElse: () => <String, dynamic>{},
        );

        final bool perSide = (originalExercise is Map &&
                originalExercise.containsKey('perSide'))
            ? originalExercise['perSide'] == true
            : false;

        final existingBlock = performed.firstWhere(
          (b) => b['blockIndex'] == blockIndex,
          orElse: () => <String, dynamic>{},
        );

        if (existingBlock.isEmpty) {
          performed.add({
            'type': blockType,
            'blockIndex': blockIndex,
            'blockTitle': block['title'] ?? block['name'] ?? 'Series',
            'exercises': [],
            if (blockDurationSeconds.containsKey(blockIndex))
              'blockDurationSeconds': blockDurationSeconds[blockIndex],
          });
        }

        final blockMap = performed.firstWhere(
          (b) => b['blockIndex'] == blockIndex,
        );

        blockMap['exercises'].add({
          'exercise': exerciseName,
          'perSide': perSide,
          'sets': setsToSave,
        });
      }
    }
  }

  Future<void> _processCircuits(
    List<Map<String, dynamic>> performed,
    List<WorkoutSet> workoutSets,
  ) async {
    onStepChanged("Procesando circuitos…");
    final blocks = routine['blocks'] as List;

    for (final entry in circuitoRound.entries) {
      final blockIndex = entry.key;
      final block = blocks[blockIndex];

      final visibleRounds = circuitoRound[blockIndex] ?? 1;
      if (visibleRounds == 0) continue;

      final List<Map<String, dynamic>> roundsData = [];

      for (int r = 1; r <= visibleRounds; r++) {
        final List<Map<String, dynamic>> exercisesData = [];

        for (final ex in block['exercises']) {
          final name = normalizeExerciseName(ex['name']);

          final rpe = circuitoRpePorRonda[blockIndex]?[r]?[name];
          if (rpe == null) continue;

          final repsText = circuitoReps[blockIndex]?[r]?[name]?.text ?? '';
          final weightText = circuitoWeight[blockIndex]?[r]?[name]?.text ?? '';

          final int reps = int.tryParse(repsText) ?? 1;
          final double? weight =
              weightText.isNotEmpty ? double.tryParse(weightText) : null;

          final perSide = circuitoPerSide[blockIndex]?[name] == true;

          exercisesData.add({
            'exercise': name,
            'reps': reps,
            'rpe': rpe,
            if (weight != null) 'weight': weight,
            'perSide': perSide,
          });

          final exData = _getExerciseFromCatalog(name);
          if (exData == null) continue;

          final muscleWeights = resolveMuscleWeights(exData);

          workoutSets.add(
            WorkoutSet(
              exercise: name,
              sets: 1,
              reps: reps,
              rpe: rpe.toDouble(),
              weight: weight,
              muscleWeights: muscleWeights,
              sourceType: 'Circuito',
            ),
          );
        }

        if (exercisesData.isNotEmpty) {
          roundsData.add({
            'round': r,
            'exercises': exercisesData,
          });
        }
      }

      if (roundsData.isNotEmpty) {
        performed.add({
          'type': 'Circuito',
          'blockIndex': blockIndex,
          'blockTitle': block['title'] ?? block['name'] ?? 'Circuito',
          'rounds': roundsData,
          if (blockDurationSeconds.containsKey(blockIndex))
            'blockDurationSeconds': blockDurationSeconds[blockIndex],
        });
      }
    }
  }

  Future<void> _processTabata(
    List<Map<String, dynamic>> performed,
    List<WorkoutSet> workoutSets,
  ) async {
    onStepChanged("Procesando tabata…");
    final blocks = routine['blocks'] as List;

    for (final entry in tabataTimer.allResults.entries) {
      final blockIndex = entry.key;
      final rpeByExercise = entry.value;
      final block = blocks[blockIndex];

      final List<Map<String, dynamic>> exercisesData = [];

      for (final ex in block['exercises']) {
        final name = ex['name'];
        final rpe = rpeByExercise[name];

        if (rpe == null) continue;

        exercisesData.add({
          'exercise': name,
          'rpe': rpe,
        });

        final exData = _getExerciseFromCatalog(name);
        if (exData == null) continue;

        final muscleWeights = resolveMuscleWeights(exData);

        workoutSets.add(
          WorkoutSet(
            exercise: name,
            sets: 1,
            reps: 1,
            rpe: rpe.toDouble(),
            muscleWeights: muscleWeights,
            sourceType: 'Tabata',
          ),
        );
      }

      if (exercisesData.isNotEmpty) {
        performed.add({
          'type': 'Tabata',
          'blockIndex': blockIndex,
          'blockTitle': block['title'] ?? block['name'] ?? 'Tabata',
          'work': block['work'],
          'rest': block['rest'],
          'rounds': block['rounds'],
          'exercises': exercisesData,
          if (blockDurationSeconds.containsKey(blockIndex))
            'blockDurationSeconds': blockDurationSeconds[blockIndex],
        });
      }
    }
  }

  Future<DocumentReference> _persistWorkout(_WorkoutBuildResult data) async {
    onStepChanged("Guardando entrenamiento…");
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final now = DateTime.now();

    if (isEdit) {
      final ref = workoutRef!;
      await ref.update({
        'performed': data.performed,
        'startedAt': Timestamp.fromDate(data.startedAt),
        'finishedAt': Timestamp.fromDate(data.finishedAt),
        'durationMinutes': data.durationMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ref;
    }

    return await FirebaseFirestore.instance.collection('workouts_logged').add({
      'userId': uid,
      'sessionName': routine['name'],
      'date': Timestamp.fromDate(now),
      'startedAt': Timestamp.fromDate(data.startedAt),
      'finishedAt': Timestamp.fromDate(data.finishedAt),
      'durationMinutes': data.durationMinutes,
      'performed': data.performed,
    });
  }

  Future<Map<Muscle, double>> _calculateLoad(_WorkoutBuildResult data) async {
    onStepChanged("Calculando carga muscular…");
    return await WorkoutLoadService.calculateLoadFromWorkout({
      'performed': data.performed,
    });
  }

  Future<void> _updateFatigue(Map<Muscle, double> muscleLoad) async {
    onStepChanged("Actualizando fatiga muscular…");
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final now = DateTime.now();
    final muscleStateRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('muscle_state');

    for (final entry in muscleLoad.entries) {
      final muscle = entry.key;
      final sessionMuscleLoad = entry.value;

      final docRef = muscleStateRef.doc(muscle.name);
      final snap = await docRef.get();

      MuscleFatigueState state;
      if (snap.exists) {
        final previousState = MuscleFatigueState(
          fatigue: (snap['fatigue'] ?? 0).toDouble(),
          lastUpdate: (snap['lastUpdated'] as Timestamp).toDate(),
        );

        final recoveredFatigue = FatigueService.recoverToNow(
          muscle: muscle,
          fatigue: previousState.fatigue,
          lastUpdate: previousState.lastUpdate,
          now: now,
        );

        state = MuscleFatigueState(
          fatigue: recoveredFatigue,
          lastUpdate: now,
        );
      } else {
        state = MuscleFatigueState(fatigue: 0, lastUpdate: now);
      }

      final updatedState = FatigueService.updateAfterSession(
        state: state,
        sessionTime: now,
        sessionLoad: sessionMuscleLoad,
      );

      await docRef.set({
        'fatigue': updatedState.fatigue,
        'lastUpdated': Timestamp.fromDate(updatedState.lastUpdate),
      });
    }
  }
}
