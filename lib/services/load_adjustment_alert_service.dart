import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'planned_load_service.dart';

class LoadAdjustmentAlertService {
  static const double minimumDifferenceKg = 2.5;
  static const double minimumDifferenceRatio = 0.05;

  static Future<List<DocumentReference<Map<String, dynamic>>>>
  analyzeAndPersist({
    required String workoutId,
    required String athleteId,
    required DateTime workoutDate,
    required Map<String, dynamic> routine,
    required List<Map<String, dynamic>> performed,
  }) async {
    final created = <DocumentReference<Map<String, dynamic>>>[];
    final blocks = List<Map<String, dynamic>>.from(
      routine['blocks'] ?? const [],
    );
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      final plannedWorkoutId = block['plannedWorkoutId']?.toString();
      if (plannedWorkoutId == null || plannedWorkoutId.isEmpty) continue;
      final performedBlock =
          performed.where((entry) {
            return (entry['blockIndex'] as num?)?.toInt() == blockIndex;
          }).firstOrNull;
      if (performedBlock == null) continue;

      final plannedExercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? const [],
      );
      for (final plannedExercise in plannedExercises) {
        final key = plannedExercise['exerciseInstanceId']?.toString();
        if (key == null || key.isEmpty) continue;
        final name =
            (plannedExercise['name'] ?? plannedExercise['exercise'] ?? '')
                .toString();
        final plannedSets = List<Map<String, dynamic>>.from(
          plannedExercise['plannedSetsSnapshot'] ??
              plannedExercise['sets'] ??
              const [],
        );
        final actualSets = _actualSets(performedBlock, name, key);
        final comparisons = <Map<String, dynamic>>[];
        final count = math.min(plannedSets.length, actualSets.length);
        for (var index = 0; index < count; index++) {
          final plannedWeight =
              (plannedSets[index]['weight'] as num?)?.toDouble() ?? 0;
          final actualWeight =
              (actualSets[index]['weight'] as num?)?.toDouble() ?? 0;
          if (plannedWeight <= 0 || actualWeight <= 0) continue;
          final deltaKg = actualWeight - plannedWeight;
          final deltaRatio = deltaKg / plannedWeight;
          if (!isRelevantDifference(plannedWeight, actualWeight)) continue;
          comparisons.add({
            'setIndex': index,
            'plannedWeight': plannedWeight,
            'actualWeight': actualWeight,
            'reps': actualSets[index]['reps'],
            'rpe': actualSets[index]['rpe'],
            'deltaKg': deltaKg,
            'deltaPct': deltaRatio * 100,
          });
        }
        if (comparisons.isEmpty) continue;

        final averageDelta =
            comparisons.fold<double>(
              0,
              (total, item) => total + (item['deltaKg'] as double),
            ) /
            comparisons.length;
        final directions =
            comparisons.map((item) => (item['deltaKg'] as double).sign).toSet();
        final direction =
            directions.length > 1
                ? 'mixed'
                : averageDelta < 0
                ? 'lower'
                : 'higher';
        final deltaRatios =
            comparisons
                .map((item) => (item['deltaPct'] as double) / 100)
                .toList();
        final medianRatio = _median(deltaRatios);
        final trend = await _trendFor(
          workoutId: workoutId,
          athleteId: athleteId,
          exerciseInstanceId: key,
          currentDirection: direction,
          currentRatio: medianRatio,
        );
        final alertId = _safeId('${workoutId}_$key');
        final reference = FirebaseFirestore.instance
            .collection('load_adjustment_alerts')
            .doc(alertId);
        await reference.set({
          'workoutId': workoutId,
          'plannedWorkoutId': plannedWorkoutId,
          'athleteId': athleteId,
          'blockId': block['blockId'],
          'progressionGroupId': block['progressionGroupId'],
          'exerciseInstanceId': key,
          'exerciseId': plannedExercise['exerciseId'],
          'variantId': plannedExercise['variantId'],
          'exerciseName': name,
          'blockTitle': block['title'] ?? block['name'] ?? 'Bloque',
          'workoutDate': Timestamp.fromDate(workoutDate),
          'direction': direction,
          'comparisons': comparisons,
          'medianDeltaRatio': medianRatio,
          'suggestedDeltaRatio': trend.$2,
          'isTrend': trend.$1,
          'status': 'pending',
          'priority': 'normal',
          'reason': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        created.add(reference);
      }
    }
    return created;
  }

  static Future<(bool, double)> _trendFor({
    required String workoutId,
    required String athleteId,
    required String exerciseInstanceId,
    required String currentDirection,
    required double currentRatio,
  }) async {
    if (currentDirection == 'mixed') return (false, currentRatio);
    final snapshot =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .get();
    final observations = <(DateTime, double)>[];
    for (final document in snapshot.docs) {
      if (document.id == workoutId) continue;
      final data = document.data();
      final date = (data['date'] as Timestamp?)?.toDate();
      if (date == null) continue;
      final ratio = _performedDeltaRatio(
        List<Map<String, dynamic>>.from(data['performed'] ?? const []),
        exerciseInstanceId,
      );
      if (ratio != null) observations.add((date, ratio));
    }
    observations.sort((a, b) => b.$1.compareTo(a.$1));
    final lastThree = <double>[
      currentRatio,
      ...observations.take(2).map((entry) => entry.$2),
    ];
    final sameDirection =
        lastThree.where((ratio) {
          return currentDirection == 'lower' ? ratio < 0 : ratio > 0;
        }).toList();
    return (sameDirection.length >= 2, _median(sameDirection));
  }

  static double? _performedDeltaRatio(
    List<Map<String, dynamic>> performed,
    String exerciseInstanceId,
  ) {
    final ratios = <double>[];
    for (final block in performed) {
      for (final raw in (block['exercises'] as List? ?? const [])) {
        if (raw is! Map ||
            raw['exerciseInstanceId']?.toString() != exerciseInstanceId) {
          continue;
        }
        final actual = List<Map<String, dynamic>>.from(raw['sets'] ?? const []);
        final planned = List<Map<String, dynamic>>.from(
          raw['plannedSetsSnapshot'] ?? const [],
        );
        for (
          var index = 0;
          index < math.min(actual.length, planned.length);
          index++
        ) {
          final plannedWeight =
              (planned[index]['weight'] as num?)?.toDouble() ?? 0;
          final actualWeight =
              (actual[index]['weight'] as num?)?.toDouble() ?? 0;
          if (plannedWeight > 0 && actualWeight > 0) {
            ratios.add((actualWeight - plannedWeight) / plannedWeight);
          }
        }
      }
    }
    return ratios.isEmpty ? null : _median(ratios);
  }

  static List<Map<String, dynamic>> _actualSets(
    Map<String, dynamic> block,
    String exerciseName,
    String exerciseInstanceId,
  ) {
    for (final raw in (block['exercises'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final exercise = (raw['exercise'] ?? raw['name'] ?? '').toString();
      if (raw['exerciseInstanceId']?.toString() == exerciseInstanceId ||
          exercise == exerciseName) {
        return List<Map<String, dynamic>>.from(raw['sets'] ?? const []);
      }
    }
    for (final round in (block['rounds'] as List? ?? const [])) {
      if (round is! Map) continue;
      for (final raw in (round['exercises'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final exercise = (raw['exercise'] ?? raw['name'] ?? '').toString();
        if (raw['exerciseInstanceId']?.toString() == exerciseInstanceId ||
            exercise == exerciseName) {
          return [Map<String, dynamic>.from(raw)];
        }
      }
    }
    return const [];
  }

  static Future<int> applyToFuture({
    required DocumentReference<Map<String, dynamic>> alertRef,
    double? customDeltaKg,
    double? customDeltaPercent,
  }) async {
    final alertSnap = await alertRef.get();
    if (!alertSnap.exists) return 0;
    final alert = alertSnap.data()!;
    final athleteId = alert['athleteId']?.toString();
    final blockId = alert['blockId']?.toString();
    final exerciseKey = alert['exerciseInstanceId']?.toString();
    final workoutDate = (alert['workoutDate'] as Timestamp?)?.toDate();
    if (athleteId == null ||
        blockId == null ||
        exerciseKey == null ||
        workoutDate == null) {
      return 0;
    }
    final plans =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: athleteId)
            .get();
    final blockSnapshot =
        await FirebaseFirestore.instance
            .collection('blocks')
            .doc(blockId)
            .get();
    final blockExercises = List<Map<String, dynamic>>.from(
      blockSnapshot.data()?['exercises'] ?? const [],
    );
    Map<String, dynamic>? baseExercise;
    for (
      var exerciseIndex = 0;
      exerciseIndex < blockExercises.length;
      exerciseIndex++
    ) {
      if (PlannedLoadService.exerciseKey(
            blockExercises[exerciseIndex],
            exerciseIndex,
          ) ==
          exerciseKey) {
        baseExercise = blockExercises[exerciseIndex];
        break;
      }
    }
    final future =
        plans.docs.where((doc) {
          final data = doc.data();
          final date = (data['date'] as Timestamp?)?.toDate();
          return data['blockId']?.toString() == blockId &&
              date != null &&
              date.isAfter(workoutDate);
        }).toList();
    var changed = 0;
    for (final plan in future) {
      final data = plan.data();
      final overrides = List<Map<String, dynamic>>.from(
        data['loadOverrides'] ?? const [],
      );
      var index = overrides.indexWhere(
        (item) => item['exerciseInstanceId']?.toString() == exerciseKey,
      );
      if (index < 0 && baseExercise != null) {
        overrides.add({
          'exerciseInstanceId': exerciseKey,
          'sets': [
            for (final set in PlannedLoadService.baseSets(baseExercise))
              {'weight': set['weight'] ?? 0, 'source': 'automatic'},
          ],
        });
        index = overrides.length - 1;
      }
      if (index < 0) continue;
      final entry = Map<String, dynamic>.from(overrides[index]);
      final sets = List<Map<String, dynamic>>.from(entry['sets'] ?? const []);
      final roundingStep =
          baseExercise != null
              ? PlannedLoadService.roundingStepFor(baseExercise)
              : PlannedLoadService.defaultRoundingKg;
      var entryChanged = false;
      for (final set in sets) {
        if (set['source'] == 'manual') continue;
        final current = (set['weight'] as num?)?.toDouble() ?? 0;
        final adjusted =
            customDeltaKg != null
                ? current + customDeltaKg
                : current *
                    (1 +
                        (customDeltaPercent ??
                            ((alert['suggestedDeltaRatio'] as num?)
                                    ?.toDouble() ??
                                0)));
        set['weight'] = PlannedLoadService.roundLoad(
          adjusted,
          step: roundingStep,
        );
        entryChanged = true;
      }
      if (!entryChanged) continue;
      entry['sets'] = sets;
      overrides[index] = entry;
      await plan.reference.update({
        'loadOverrides': overrides,
        'loadAdjustedAt': FieldValue.serverTimestamp(),
      });
      changed++;
    }
    await alertRef.update({
      'status': 'applied',
      'affectedFutureSessions': changed,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    return changed;
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static bool isRelevantDifference(double planned, double actual) {
    if (planned <= 0 || actual <= 0) return false;
    final threshold = math.max(
      minimumDifferenceKg,
      planned * minimumDifferenceRatio,
    );
    return (actual - planned).abs() >= threshold;
  }

  static String _safeId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
