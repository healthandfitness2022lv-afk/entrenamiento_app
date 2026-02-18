import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/muscle_catalog.dart';
import '../services/fatigue_service.dart';
import '../services/workout_load_service.dart';

/// ======================================================
/// 📦 RESULTADO FINAL
/// ======================================================
class FatigueRecalculationResult {
  final Map<Muscle, double> finalFatigue;
  final List<FatigueRecalculationStep> steps;

  FatigueRecalculationResult({
    required this.finalFatigue,
    required this.steps,
  });
}

/// ======================================================
/// 🔍 PASO EXPLICATIVO (AUDITORÍA)
/// ======================================================
class FatigueRecalculationStep {
  final DateTime workoutDate;
  final double hoursSinceLastWorkout;

  final Map<Muscle, double> loadApplied;
  final Map<Muscle, double> fatigueBefore;
  final Map<Muscle, double> fatigueAfterRecovery;
  final Map<Muscle, double> fatigueAfter;

  final bool isFirstWorkout;
  final bool isRecoveryOnly;

  FatigueRecalculationStep({
    required this.workoutDate,
    required this.hoursSinceLastWorkout,
    required this.loadApplied,
    required this.fatigueBefore,
    required this.fatigueAfterRecovery,
    required this.fatigueAfter,
    required this.isFirstWorkout,
    required this.isRecoveryOnly,
  });

  // ======================================================
  // 🔄 SERIALIZACIÓN
  // ======================================================
  Map<String, dynamic> toJson() {
    Map<String, double> encode(Map<Muscle, double> m) =>
        {for (final e in m.entries) e.key.name: e.value};

    return {
      'workoutDate': Timestamp.fromDate(workoutDate),
      'hoursSinceLastWorkout': hoursSinceLastWorkout,
      'loadApplied': encode(loadApplied),
      'fatigueBefore': encode(fatigueBefore),
      'fatigueAfterRecovery': encode(fatigueAfterRecovery),
      'fatigueAfter': encode(fatigueAfter),
      'isFirstWorkout': isFirstWorkout,
      'isRecoveryOnly': isRecoveryOnly,
    };
  }

  


  // ======================================================
  // 🔄 DESERIALIZACIÓN
  // ======================================================
  factory FatigueRecalculationStep.fromJson(
    Map<String, dynamic> json,
  ) {
    Map<Muscle, double> decode(Map<String, dynamic>? m) {
  if (m == null) return {};
  return {
    for (final e in m.entries)
      _decodeMuscle(e.key): (e.value as num).toDouble(),
  };
}


    return FatigueRecalculationStep(
      workoutDate: (json['workoutDate'] as Timestamp).toDate(),
      hoursSinceLastWorkout:
          (json['hoursSinceLastWorkout'] as num).toDouble(),
      loadApplied:
          decode(Map<String, dynamic>.from(json['loadApplied'] ?? {})),
      fatigueBefore:
          decode(Map<String, dynamic>.from(json['fatigueBefore'] ?? {})),
      fatigueAfterRecovery: decode(
          Map<String, dynamic>.from(json['fatigueAfterRecovery'] ?? {})),
      fatigueAfter:
          decode(Map<String, dynamic>.from(json['fatigueAfter'] ?? {})),
      isFirstWorkout: json['isFirstWorkout'] ?? false,
      isRecoveryOnly: json['isRecoveryOnly'] ?? false,
    );
  }
}

Muscle _decodeMuscle(String value) {
  switch (value) {

    // 🔥 Compatibilidad hacia atrás
    case "traps":
      return Muscle.trapsUpper;

    // Nuevos
    case "trapsUpper":
      return Muscle.trapsUpper;

    case "lowerTraps":
      return Muscle.lowerTraps;

    default:
      return Muscle.values.firstWhere(
        (m) => m.name == value,
        orElse: () => throw Exception("Músculo desconocido: $value"),
      );
  }
}


/// ======================================================
/// 🧠 SERVICIO DE RECÁLCULO
/// ======================================================
class FatigueRecalculationService {
  /// --------------------------------------------------
  /// 🔁 RECALCULA TODO EL HISTÓRICO
  /// --------------------------------------------------
  static Future<FatigueRecalculationResult> recalculate({
    required String uid,
    bool forceRecalculateLoad = false,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('workouts_logged')
        .where('userId', isEqualTo: uid)
        .orderBy('date')
        .get();

    final Map<Muscle, MuscleFatigueState> state = {};
    final List<FatigueRecalculationStep> steps = [];

    DateTime? lastWorkoutDate;

    for (final doc in snap.docs) {
      final data = doc.data();
      final workoutDate = (data['date'] as Timestamp).toDate();

      final isFirstWorkout = lastWorkoutDate == null;
      final hoursSinceLastWorkout = isFirstWorkout
          ? 0.0
          : workoutDate.difference(lastWorkoutDate).inMinutes / 60.0;

      // =========================
      // 🔹 FATIGA ANTES REAL
      // =========================
      final fatigueBefore = {
        for (final e in state.entries) e.key: e.value.fatigue,
      };

      // =========================
      // 🔹 RECUPERACIÓN
      // =========================
      state.forEach((_, s) {
        s.fatigue = FatigueService.getCurrentFatigue(
          state: s,
          now: workoutDate,
        );
        s.lastUpdate = workoutDate;
      });

      final fatigueAfterRecovery = {
        for (final e in state.entries) e.key: e.value.fatigue,
      };

      // =========================
      // 🏋️ CARGA
      // =========================
      Map<Muscle, double> load;

      final hasStoredLoad = data['muscleLoad'] != null;

      if (hasStoredLoad && !forceRecalculateLoad) {
        final rawLoad = Map<String, dynamic>.from(data['muscleLoad']);
        load = {
  for (final e in rawLoad.entries)
    _decodeMuscle(e.key): (e.value as num).toDouble(),
};

      } else {
        load = await WorkoutLoadService.calculateLoadFromWorkout(data);

        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .doc(doc.id)
            .update({
          'muscleLoad': {
            for (final e in load.entries) e.key.name: e.value,
          }
        });
      }

      // =========================
      // 🔥 APLICAR CARGA
      // =========================
      for (final entry in load.entries) {
        final muscle = entry.key;
        final value = entry.value;

        state.putIfAbsent(
          muscle,
          () => MuscleFatigueState(
            fatigue: 0,
            lastUpdate: workoutDate,
          ),
        );

        state[muscle] = FatigueService.updateAfterSession(
          state: state[muscle]!,
          sessionTime: workoutDate,
          sessionLoad: value,
        );
      }

      final fatigueAfter = {
        for (final e in state.entries) e.key: e.value.fatigue,
      };

      steps.add(
        FatigueRecalculationStep(
          workoutDate: workoutDate,
          hoursSinceLastWorkout: hoursSinceLastWorkout,
          loadApplied: Map.from(load),
          fatigueBefore: Map.from(fatigueBefore),
          fatigueAfterRecovery: Map.from(fatigueAfterRecovery),
          fatigueAfter: Map.from(fatigueAfter),
          isFirstWorkout: isFirstWorkout,
          isRecoveryOnly: false,
        ),
      );

      lastWorkoutDate = workoutDate;
    }

    // =========================
    // 🧠 RECUPERACIÓN HASTA AHORA
    // =========================
    if (lastWorkoutDate != null) {
      final now = DateTime.now();
      final hoursSinceLast =
          now.difference(lastWorkoutDate).inMinutes / 60.0;

      final fatigueBefore = {
        for (final e in state.entries) e.key: e.value.fatigue,
      };

      state.forEach((_, s) {
        s.fatigue = FatigueService.getCurrentFatigue(
          state: s,
          now: now,
        );
        s.lastUpdate = now;
      });

      final fatigueAfter = {
        for (final e in state.entries) e.key: e.value.fatigue,
      };

      steps.add(
        FatigueRecalculationStep(
          workoutDate: now,
          hoursSinceLastWorkout: hoursSinceLast,
          loadApplied: const {},
          fatigueBefore: Map.from(fatigueBefore),
          fatigueAfterRecovery: Map.from(fatigueAfter),
          fatigueAfter: Map.from(fatigueAfter),
          isFirstWorkout: false,
          isRecoveryOnly: true,
        ),
      );
    }

    return FatigueRecalculationResult(
      finalFatigue: {
        for (final e in state.entries) e.key: e.value.fatigue,
      },
      steps: steps,
    );
  }

  /// --------------------------------------------------
  /// 💾 RECALCULA Y PERSISTE
  /// --------------------------------------------------
  static Future<FatigueRecalculationResult> recalculateAndPersist({
  required String uid,
  bool forceRecalculateLoad = false,
}) async {
  final result = await recalculate(
    uid: uid,
    forceRecalculateLoad: forceRecalculateLoad,
  );

  double calculateGlobalFatigue(Map<Muscle, double> fatigue) {
    final values = fatigue.values.where((v) => v >= 5).toList();
    if (values.isEmpty) return 0;

    values.sort((a, b) => b.compareTo(a));
    final top = values.take(5);

    return (top.reduce((a, b) => a + b) / top.length).clamp(0, 100);
  }

  final globalFatigue = calculateGlobalFatigue(result.finalFatigue);

  final userRef =
      FirebaseFirestore.instance.collection('users').doc(uid);

  // 1️⃣ Guardas el estado muscular completo
await userRef
    .collection('fatigue_state')
    .doc('latest')
    .set({
  'generatedAt': Timestamp.now(),
  'fatigue': {
    for (final e in result.finalFatigue.entries)
      e.key.name: e.value,
  },
  'globalFatigue': globalFatigue,
});

// 2️⃣ Guardas el resumen GLOBAL en el usuario (CLAVE)
await userRef.set({
  'globalFatigue': globalFatigue,
  'lastFatigueCalculation': Timestamp.now(),
}, SetOptions(merge: true));

final batch = FirebaseFirestore.instance.batch();
final auditRef = userRef.collection('fatigue_audit');

// 🔥 limpiar audit anterior
final oldAudit = await auditRef.get();
for (final d in oldAudit.docs) {
  batch.delete(d.reference);
}

// 🔥 escribir audit nuevo
for (int i = 0; i < result.steps.length; i++) {
  batch.set(
    auditRef.doc(i.toString().padLeft(4, '0')),
    result.steps[i].toJson(),
  );
}

await batch.commit();




  return result; // 👈 contiene steps SOLO en memoria
}

}
