import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/muscle_catalog.dart';
import '../utils/muscle_utils.dart';
import 'fatigue_recalculation_service.dart';
import 'workout_metrics_service.dart';
import 'workout_rm_service.dart';

class FatiguePerformancePoint {
  final DateTime date;
  final double preSessionFatigue;
  final double estimatedRM;
  final double totalLoad;
  final double avgRpe;
  final int totalSets;
  final List<FatiguePerformanceSetEvidence> sets;

  const FatiguePerformancePoint({
    required this.date,
    required this.preSessionFatigue,
    required this.estimatedRM,
    required this.totalLoad,
    required this.avgRpe,
    required this.totalSets,
    required this.sets,
  });

  double get efficiencyScore {
    if (avgRpe <= 0) return estimatedRM;
    return estimatedRM / avgRpe;
  }
}

class FatiguePerformanceSetEvidence {
  final double weight;
  final int reps;
  final double rpe;
  final double estimatedRM;

  const FatiguePerformanceSetEvidence({
    required this.weight,
    required this.reps,
    required this.rpe,
    required this.estimatedRM,
  });
}

class FatiguePerformanceCorrelationResult {
  final List<FatiguePerformancePoint> points;
  final List<Muscle> primaryMuscles;
  final double rmCorrelation;
  final double volumeCorrelation;
  final double efficiencyCorrelation;

  const FatiguePerformanceCorrelationResult({
    required this.points,
    required this.primaryMuscles,
    required this.rmCorrelation,
    required this.volumeCorrelation,
    required this.efficiencyCorrelation,
  });

  bool get hasEnoughData => points.length >= 3;
}

class FatiguePerformanceCorrelationService {
  static Future<FatiguePerformanceCorrelationResult> analyzeExercise({
    required String uid,
    required String exercise,
    required List<QueryDocumentSnapshot> docs,
  }) async {
    final exerciseSnap =
        await FirebaseFirestore.instance
            .collection('exercises')
            .where('name', isEqualTo: exercise)
            .limit(1)
            .get();

    final exerciseData =
        exerciseSnap.docs.isNotEmpty ? exerciseSnap.docs.first.data() : null;

    final muscleWeights = _decodeMuscleWeights(exerciseData);
    final primaryMuscles = _sortedPrimaryMuscles(muscleWeights);

    if (primaryMuscles.isEmpty) {
      return const FatiguePerformanceCorrelationResult(
        points: [],
        primaryMuscles: [],
        rmCorrelation: 0,
        volumeCorrelation: 0,
        efficiencyCorrelation: 0,
      );
    }

    final auditSnap =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fatigue_audit')
            .orderBy('workoutDate')
            .get();

    final steps =
        auditSnap.docs
            .map((d) => FatigueRecalculationStep.fromJson(d.data()))
            .where((s) => !s.isRecoveryOnly)
            .toList();

    final Map<String, FatigueRecalculationStep> stepByDay = {
      for (final step in steps) _dayKey(step.workoutDate): step,
    };

    final List<FatiguePerformancePoint> points = [];
    final targetNorm = WorkoutRMService.normalizeExerciseName(exercise);

    for (final d in docs) {
      final date = (d['date'] as Timestamp).toDate();
      final performed = WorkoutMetricsService.performedFromDoc(d);
      final sets =
          WorkoutRMService.extractAllValidRMSetCandidates(performed).where((s) {
            final raw = s['exercise']?.toString() ?? '';
            return WorkoutRMService.normalizeExerciseName(raw) == targetNorm;
          }).toList();

      if (sets.isEmpty) continue;

      final step = stepByDay[_dayKey(date)];
      if (step == null) continue;

      double bestEstimatedRm = 0;
      double totalLoad = 0;
      double weightedRpeSum = 0;
      int totalReps = 0;
      final evidenceSets = <FatiguePerformanceSetEvidence>[];

      for (final set in sets) {
        final reps = (set['reps'] as num?)?.toInt() ?? 0;
        final weight = (set['weight'] as num?)?.toDouble() ?? 0;
        final rpe = (set['rpe'] as num?)?.toDouble() ?? 0;

        if (reps <= 0 || weight <= 0) continue;

        final estimatedRm = WorkoutRMService.estimate1RM(
          weight: weight,
          reps: reps,
        );
        evidenceSets.add(
          FatiguePerformanceSetEvidence(
            weight: weight,
            reps: reps,
            rpe: rpe,
            estimatedRM: estimatedRm,
          ),
        );
        if (estimatedRm > bestEstimatedRm) {
          bestEstimatedRm = estimatedRm;
        }

        totalLoad += weight * reps;
        if (rpe > 0) {
          weightedRpeSum += rpe * reps;
          totalReps += reps;
        }
      }

      if (bestEstimatedRm <= 0 || totalLoad <= 0) continue;

      evidenceSets.sort((a, b) => b.estimatedRM.compareTo(a.estimatedRM));

      final avgRpe = totalReps > 0 ? weightedRpeSum / totalReps : 0.0;
      final preSessionFatigue = _weightedFatigue(
        fatigue: step.fatigueAfterRecovery,
        weights: muscleWeights,
      );

      points.add(
        FatiguePerformancePoint(
          date: date,
          preSessionFatigue: preSessionFatigue,
          estimatedRM: bestEstimatedRm,
          totalLoad: totalLoad,
          avgRpe: avgRpe,
          totalSets: sets.length,
          sets: evidenceSets,
        ),
      );
    }

    points.sort((a, b) => a.date.compareTo(b.date));

    return FatiguePerformanceCorrelationResult(
      points: points,
      primaryMuscles: primaryMuscles,
      rmCorrelation: _pearson(
        points.map((p) => p.preSessionFatigue).toList(),
        points.map((p) => p.estimatedRM).toList(),
      ),
      volumeCorrelation: _pearson(
        points.map((p) => p.preSessionFatigue).toList(),
        points.map((p) => p.totalLoad).toList(),
      ),
      efficiencyCorrelation: _pearson(
        points.map((p) => p.preSessionFatigue).toList(),
        points.map((p) => p.efficiencyScore).toList(),
      ),
    );
  }

  static Map<Muscle, double> _decodeMuscleWeights(
    Map<String, dynamic>? exerciseData,
  ) => decodeMuscleWeights(exerciseData);

  static List<Muscle> _sortedPrimaryMuscles(Map<Muscle, double> weights) {
    final entries =
        weights.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).map((e) => e.key).toList();
  }

  static double _weightedFatigue({
    required Map<Muscle, double> fatigue,
    required Map<Muscle, double> weights,
  }) {
    if (weights.isEmpty) return 0;

    double weightedSum = 0;
    double totalWeight = 0;

    for (final entry in weights.entries) {
      weightedSum += (fatigue[entry.key] ?? 0) * entry.value;
      totalWeight += entry.value;
    }

    if (totalWeight <= 0) return 0;
    return weightedSum / totalWeight;
  }

  static double _pearson(List<double> xs, List<double> ys) {
    if (xs.length != ys.length || xs.length < 3) return 0;

    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;

    double numerator = 0;
    double sumSqX = 0;
    double sumSqY = 0;

    for (int i = 0; i < xs.length; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      numerator += dx * dy;
      sumSqX += dx * dx;
      sumSqY += dy * dy;
    }

    final denominator = math.sqrt(sumSqX * sumSqY);
    if (denominator == 0) return 0;
    return numerator / denominator;
  }

  static String _dayKey(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }
}
