import 'package:flutter/material.dart';
import '../utils/weight_input.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import '../models/muscle_catalog.dart';
import '../services/tabata_timer_service.dart';
import '../services/workout_load_service.dart';
import '../services/load_adjustment_alert_service.dart';
import '../models/achievement.dart';
import '../services/achievement_evaluator_service.dart';
import '../services/fatigue_recalculation_service.dart';
import '../utils/exercise_name_utils.dart';

class _WorkoutBuildResult {
  final List<Map<String, dynamic>> performed;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMinutes;

  _WorkoutBuildResult({
    required this.performed,
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

  /// Nota libre del atleta al terminar (vacía si no escribió nada).
  final String notes;

  final Function(String) onStepChanged;
  final Function(Object, StackTrace) onError;
  final Function(
    List<Achievement>,
    List<Map<String, dynamic>>,
    DocumentReference,
  )
  onSuccess;

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
    this.notes = '',
    required this.onStepChanged,
    required this.onError,
    required this.onSuccess,
  });

  String normalizeExerciseName(dynamic raw) => coerceExerciseName(raw);

  Map<String, dynamic> _identitySnapshot(Map originalExercise) => {
    if (originalExercise['exerciseId'] != null)
      'exerciseId': originalExercise['exerciseId'],
    if (originalExercise['movementId'] != null)
      'movementId': originalExercise['movementId'],
    if (originalExercise['movementName'] != null)
      'movementName': originalExercise['movementName'],
    if (originalExercise['variantId'] != null)
      'variantId': originalExercise['variantId'],
    if (originalExercise['variantLabel'] != null)
      'variantLabel': originalExercise['variantLabel'],
    if (originalExercise['displayName'] != null)
      'displayName': originalExercise['displayName'],
    if (originalExercise['resistanceType'] != null)
      'resistanceType': originalExercise['resistanceType'],
    if (originalExercise['exerciseInstanceId'] != null)
      'exerciseInstanceId': originalExercise['exerciseInstanceId'],
    if (originalExercise['plannedWorkoutId'] != null)
      'plannedWorkoutId': originalExercise['plannedWorkoutId'],
    if (originalExercise['blockId'] != null)
      'blockId': originalExercise['blockId'],
    if (originalExercise['progressionGroupId'] != null)
      'progressionGroupId': originalExercise['progressionGroupId'],
    if (originalExercise['plannedSetsSnapshot'] != null)
      'plannedSetsSnapshot': originalExercise['plannedSetsSnapshot'],
  };

  Future<void> execute() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final data = await _buildWorkoutData();
      final muscleLoad = await _calculateLoad(data);
      final ref = await _persistWorkout(data);

      try {
        final adjustmentAlerts =
            await LoadAdjustmentAlertService.analyzeAndPersist(
              workoutId: ref.id,
              athleteId: uid,
              workoutDate: data.finishedAt,
              routine: routine,
              performed: data.performed,
            );
        if (adjustmentAlerts.isNotEmpty && context.mounted) {
          await _askLoadAdjustmentReasons(adjustmentAlerts);
        }
      } catch (error, stack) {
        debugPrint('No se pudieron generar alertas de carga: $error\n$stack');
      }

      await ref.update({
        'muscleLoad': {for (final e in muscleLoad.entries) e.key.name: e.value},
      });

      List<Achievement> unlocked = [];
      if (isEdit) {
        // En lugar de sumar incrementalmente (lo que duplicaría stats),
        // recalculamos exactamente la fatiga global y los hitos historicos.
        // Importación a FatigueRecalculationService es necesaria si no está (ya lo está).
        await FatigueRecalculationService.recalculateAndPersist(
          uid: uid,
          forceRecalculateLoad: false,
        );
        await AchievementEvaluatorService.syncHistoricalData();
      } else {
        // Camino incremental (O(1) en vez de releer todo el histórico): un
        // workout nuevo siempre es la sesión más reciente, así que alcanza
        // con partir del último estado persistido y sumarle esta carga.
        // Si cambian ponderaciones/factores globales, el botón "Recalcular
        // fatiga" del perfil sigue usando `recalculateAndPersist` para
        // reprocesar todo desde cero.
        await FatigueRecalculationService.applySessionAndPersist(
          uid: uid,
          sessionDate: data.finishedAt,
          load: muscleLoad,
        );

        unlocked = await AchievementEvaluatorService.evaluateSession(
          data.performed,
          data.finishedAt,
        );
      }

      onSuccess(unlocked, data.performed, ref);
    } catch (e, stack) {
      onError(e, stack);
    }
  }

  Future<void> _askLoadAdjustmentReasons(
    List<DocumentReference<Map<String, dynamic>>> references,
  ) async {
    final snapshots = await Future.wait(references.map((ref) => ref.get()));
    if (!context.mounted) return;
    final reasons = <String, String?>{
      for (final snapshot in snapshots) snapshot.id: null,
    };
    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (_, setDialogState) => AlertDialog(
                  title: const Text('Cambios respecto del plan'),
                  content: SizedBox(
                    width: 520,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: snapshots.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        final snapshot = snapshots[index];
                        final data = snapshot.data() ?? const {};
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['exerciseName']?.toString() ?? 'Ejercicio',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              value: reasons[snapshot.id],
                              hint: const Text('Motivo opcional'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'muy_pesado',
                                  child: Text('Estaba muy pesado'),
                                ),
                                DropdownMenuItem(
                                  value: 'muy_liviano',
                                  child: Text('Estaba muy liviano'),
                                ),
                                DropdownMenuItem(
                                  value: 'equipo_distinto',
                                  child: Text('Máquina o discos diferentes'),
                                ),
                                DropdownMenuItem(
                                  value: 'dolor_molestia',
                                  child: Text('Dolor o molestia'),
                                ),
                                DropdownMenuItem(
                                  value: 'otro',
                                  child: Text('Otro motivo'),
                                ),
                              ],
                              onChanged:
                                  (value) => setDialogState(
                                    () => reasons[snapshot.id] = value,
                                  ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Omitir'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Enviar al entrenador'),
                    ),
                  ],
                ),
          ),
    );
    if (save != true) return;
    for (final reference in references) {
      final reason = reasons[reference.id];
      if (reason == null) continue;
      await reference.update({
        'reason': reason,
        if (reason == 'dolor_molestia') ...{
          'priority': 'high',
          'suggestedDeltaRatio': 0,
        },
      });
    }
  }

  Future<_WorkoutBuildResult> _buildWorkoutData() async {
    onStepChanged("Procesando datos…");

    late DateTime startedAt;
    late DateTime finishedAt;
    late int durationMinutes;

    if (isEdit) {
      // Editar nunca cambia cuándo se entrenó: se conservan los tiempos
      // originales y, si faltan (workouts legacy), se derivan de los que sí
      // hay en vez de inventarlos.
      finishedAt = originalFinishedAt ?? originalStartedAt ?? DateTime.now();
      startedAt = originalStartedAt ?? finishedAt;
      durationMinutes =
          originalDurationMinutes ?? finishedAt.difference(startedAt).inMinutes;
    } else {
      finishedAt = DateTime.now();
      startedAt = workoutStartedAt ?? finishedAt;
      durationMinutes = finishedAt.difference(startedAt).inMinutes;
    }

    final List<Map<String, dynamic>> performed = [];

    await _processSeries(performed);
    await _processCircuits(performed);
    await _processTabata(performed);

    // `seriesData`, circuitos y Tabata se recorren desde mapas distintos y
    // pueden agregar bloques en un orden diferente al de la rutina. El orden
    // canónico de ejecución es el índice del bloque planificado.
    performed.sort((a, b) {
      final aIndex = (a['blockIndex'] as num?)?.toInt() ?? 1 << 30;
      final bIndex = (b['blockIndex'] as num?)?.toInt() ?? 1 << 30;
      return aIndex.compareTo(bIndex);
    });

    // Nunca crear un registro que parezca un entrenamiento terminado si no
    // pudimos reconstruir ninguna parte ejecutada. Esto evita documentos con
    // `performed: []` cuando falla una coincidencia secundaria del catálogo.
    if (performed.isEmpty) {
      throw StateError(
        'No se encontraron ejercicios completados para guardar. '
        'Marca las series realizadas o completa un bloque antes de finalizar.',
      );
    }

    return _WorkoutBuildResult(
      performed: performed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMinutes: durationMinutes,
    );
  }

  Future<void> _processSeries(List<Map<String, dynamic>> performed) async {
    onStepChanged("Procesando series…");
    final blocks = routine['blocks'] as List;

    for (final entry in seriesData.entries) {
      final key = entry.key;
      final blockIndex = int.parse(key.split('-').first);
      final block = blocks[blockIndex];
      final blockType = block['type'] ?? 'Series';
      final exerciseName = key.split('-').sublist(1).join('-');

      final originalExercise =
          block['exercises'].firstWhere(
                (ex) => normalizeExerciseName(ex['name']) == exerciseName,
                orElse: () => <String, dynamic>{},
              )
              as Map;
      final List<Map<String, dynamic>> setsToSave = [];

      for (int i = 0; i < entry.value.length; i++) {
        if (entry.value[i]['done'] != true) continue;

        final repsText = seriesRepsCtrl[key]?[i].text ?? '';
        final weightText = seriesWeightCtrl[key]?[i].text ?? '';

        final int reps = int.tryParse(repsText) ?? 0;
        final double? weight = parseWeight(weightText);

        if (reps <= 0) continue;

        setsToSave.add({
          'reps': reps,
          'weight': weight,
          'rpe': entry.value[i]['rpe'],
        });
      }

      if (setsToSave.isNotEmpty) {
        final bool perSide =
            (originalExercise.containsKey('perSide'))
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
            if (block['plannedWorkoutId'] != null)
              'plannedWorkoutId': block['plannedWorkoutId'],
            if (block['blockId'] != null) 'blockId': block['blockId'],
            if (block['progressionGroupId'] != null)
              'progressionGroupId': block['progressionGroupId'],
            'exercises': [],
            if (blockDurationSeconds.containsKey(blockIndex))
              'blockDurationSeconds': blockDurationSeconds[blockIndex],
          });
        }

        final blockMap = performed.firstWhere(
          (b) => b['blockIndex'] == blockIndex,
        );

        // Ejercicios por tiempo: `reps` guarda SEGUNDOS. Sin esta marca la
        // revisión semanal leía un trote de 600 s como 600 repeticiones.
        final isTime =
            entry.value.first['valueType'] == 'time' ||
            originalExercise['valueType'] == 'time';

        blockMap['exercises'].add({
          'exercise': exerciseName,
          ..._identitySnapshot(originalExercise),
          'perSide': perSide,
          if (isTime) 'valueType': 'time',
          'sets': setsToSave,
        });
      }
    }
  }

  Future<void> _processCircuits(List<Map<String, dynamic>> performed) async {
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
          final double? weight = parseWeight(weightText);

          final perSide = circuitoPerSide[blockIndex]?[name] == true;

          exercisesData.add({
            'exercise': name,
            ..._identitySnapshot(ex),
            'reps': reps,
            'rpe': rpe,
            if (weight != null) 'weight': weight,
            'perSide': perSide,
            if (ex['valueType'] == 'time') 'valueType': 'time',
          });
        }

        if (exercisesData.isNotEmpty) {
          roundsData.add({'round': r, 'exercises': exercisesData});
        }
      }

      if (roundsData.isNotEmpty) {
        performed.add({
          'type': 'Circuito',
          'blockIndex': blockIndex,
          'blockTitle': block['title'] ?? block['name'] ?? 'Circuito',
          if (block['plannedWorkoutId'] != null)
            'plannedWorkoutId': block['plannedWorkoutId'],
          if (block['blockId'] != null) 'blockId': block['blockId'],
          if (block['progressionGroupId'] != null)
            'progressionGroupId': block['progressionGroupId'],
          'rounds': roundsData,
          if (blockDurationSeconds.containsKey(blockIndex))
            'blockDurationSeconds': blockDurationSeconds[blockIndex],
        });
      }
    }
  }

  Future<void> _processTabata(List<Map<String, dynamic>> performed) async {
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
          ..._identitySnapshot(ex),
          if (ex['weight'] is num) 'weight': ex['weight'],
          'perSide': ex['perSide'] == true,
          'rpe': rpe,
        });
      }

      if (exercisesData.isNotEmpty) {
        performed.add({
          'type': 'Tabata',
          'blockIndex': blockIndex,
          'blockTitle': block['title'] ?? block['name'] ?? 'Tabata',
          if (block['plannedWorkoutId'] != null)
            'plannedWorkoutId': block['plannedWorkoutId'],
          if (block['blockId'] != null) 'blockId': block['blockId'],
          if (block['progressionGroupId'] != null)
            'progressionGroupId': block['progressionGroupId'],
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
    final routineBlocks = List<Map<String, dynamic>>.from(
      routine['blocks'] ?? const [],
    );
    final plannedWorkoutIds =
        routineBlocks
            .map((block) => block['plannedWorkoutId']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();
    final blockIds =
        routineBlocks
            .map((block) => block['blockId']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();

    if (isEdit) {
      final ref = workoutRef!;
      await ref.update({
        'performed': data.performed,
        'startedAt': Timestamp.fromDate(data.startedAt),
        'finishedAt': Timestamp.fromDate(data.finishedAt),
        'durationMinutes': data.durationMinutes,
        'plannedWorkoutIds': plannedWorkoutIds,
        'plannedBlockIds': blockIds,
        'notes': notes,
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
      'plannedWorkoutIds': plannedWorkoutIds,
      'plannedBlockIds': blockIds,
      if (notes.isNotEmpty) 'notes': notes,
    });
  }

  Future<Map<Muscle, double>> _calculateLoad(_WorkoutBuildResult data) async {
    onStepChanged("Calculando carga muscular…");
    return await WorkoutLoadService.calculateLoadFromWorkout({
      'performed': data.performed,
    });
  }
}
