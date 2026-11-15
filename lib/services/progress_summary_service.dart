import 'package:cloud_firestore/cloud_firestore.dart';
import 'progress_alert_service.dart';
import 'workout_rm_service.dart';

/// Mantiene `users/{uid}/stats/progress_summary`: un [ExerciseProgressSummary]
/// por ejercicio, para calcular las alertas de progreso de una sesión nueva
/// leyendo un solo documento en vez de todo `workouts_logged`.
///
/// Si el resumen no existe (primera vez), está desactualizado o se editó un
/// workout, se recalcula desde el historial completo y se reescribe.
class ProgressSummaryService {
  static const int _version = 1;

  static DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('stats')
          .doc('progress_summary');

  /// Alertas de progreso de la sesión recién guardada ([savedWorkoutId]) y
  /// actualización del resumen persistido.
  static Future<List<ProgressAlert>> alertsAfterSave({
    required String uid,
    required List<Map<String, dynamic>> performed,
    required DateTime targetDate,
    required String savedWorkoutId,
    required bool isEdit,
  }) async {
    final current = <String, List<Map<String, dynamic>>>{};
    WorkoutRMService.addSessionToRmHistory(current, performed, targetDate);

    if (!isEdit) {
      final incremental = await _tryIncremental(uid, current, targetDate);
      if (incremental != null) return incremental;
    }
    return _fullRebuild(
      uid: uid,
      current: current,
      targetDate: targetDate,
      savedWorkoutId: savedWorkoutId,
    );
  }

  static Future<List<ProgressAlert>?> _tryIncremental(
    String uid,
    Map<String, List<Map<String, dynamic>>> current,
    DateTime targetDate,
  ) async {
    final snap = await _ref(uid).get();
    final data = snap.data();
    if (data == null || data['version'] != _version) return null;

    final rawExercises = Map<String, dynamic>.from(data['exercises'] ?? {});
    final summaries = <String, ExerciseProgressSummary>{
      for (final name in current.keys)
        if (rawExercises[name] is Map)
          name: ExerciseProgressSummary.fromJson(rawExercises[name] as Map),
    };

    final alerts = ProgressAlertService.analyzeWithSummaries(
      summaries: summaries,
      today: current,
      targetDate: targetDate,
    );
    if (alerts == null) return null;

    final updates = <String, dynamic>{};
    current.forEach((name, points) {
      final summary = summaries[name] ?? ExerciseProgressSummary();
      summary.addDay(targetDate, points);
      updates[name] = summary.toJson();
    });
    await _ref(uid).set({
      'version': _version,
      'exercises': updates,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return alerts;
  }

  static Future<List<ProgressAlert>> _fullRebuild({
    required String uid,
    required Map<String, List<Map<String, dynamic>>> current,
    required DateTime targetDate,
    required String savedWorkoutId,
  }) async {
    final docs =
        (await FirebaseFirestore.instance
                .collection('workouts_logged')
                .where('userId', isEqualTo: uid)
                .get())
            .docs;

    // 1) Alertas: historial previo (sin la sesión guardada) + sesión actual.
    final history = <String, List<Map<String, dynamic>>>{};
    // 2) Resumen: TODOS los workouts, incluida la sesión guardada.
    final everything = <String, List<Map<String, dynamic>>>{};

    for (final doc in docs) {
      final data = doc.data();
      final date = (data['date'] as Timestamp?)?.toDate();
      if (date == null) continue;
      final performed = List<Map<String, dynamic>>.from(
        data['performed'] ?? const [],
      );
      WorkoutRMService.addSessionToRmHistory(everything, performed, date);
      if (doc.id == savedWorkoutId || date.isAfter(targetDate)) continue;
      WorkoutRMService.addSessionToRmHistory(
        history,
        performed,
        date,
        include: current.containsKey,
      );
    }
    current.forEach((exercise, points) {
      history.putIfAbsent(exercise, () => []).addAll(points);
    });

    final alerts = ProgressAlertService.analyzeSessionImpact(
      rmHistory: history,
      targetDate: targetDate,
    );

    await _ref(uid).set({
      'version': _version,
      'exercises': {
        for (final e in everything.entries)
          e.key: ExerciseProgressSummary.fromHistory(e.value).toJson(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return alerts;
  }
}
