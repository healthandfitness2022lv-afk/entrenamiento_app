import 'package:cloud_firestore/cloud_firestore.dart';
import 'muscle_recovery_service.dart';
import '../models/muscle_catalog.dart';
import '../services/fatigue_service.dart';
import '../services/workout_load_service.dart';

/// ======================================================
/// 📦 RESULTADO FINAL
/// ======================================================
class FatigueRecalculationResult {
  final Map<Muscle, double> finalFatigue;
  final List<FatigueRecalculationStep> steps;

  /// Fatiga y último `lastUpdate` por músculo SIN aplicar recuperación hasta
  /// "ahora" — es el estado justo tras el último workout real. Es lo que se
  /// persiste para poder recuperar de forma incremental (aplicando
  /// `FatigueService.recoverToNow` en el momento de la lectura, en vez de
  /// recalcular todo el histórico cada vez).
  final Map<Muscle, MuscleFatigueState> stateAfterLastWorkout;

  FatigueRecalculationResult({
    required this.finalFatigue,
    required this.steps,
    required this.stateAfterLastWorkout,
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
    Map<String, double> encode(Map<Muscle, double> m) => {
      for (final e in m.entries) e.key.name: e.value,
    };

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
  factory FatigueRecalculationStep.fromJson(Map<String, dynamic> json) {
    Map<Muscle, double> decode(Map<String, dynamic>? m) {
      if (m == null) return {};
      return {
        for (final e in m.entries)
          _decodeMuscle(e.key): (e.value as num).toDouble(),
      };
    }

    return FatigueRecalculationStep(
      workoutDate: (json['workoutDate'] as Timestamp).toDate(),
      hoursSinceLastWorkout: (json['hoursSinceLastWorkout'] as num).toDouble(),
      loadApplied: decode(Map<String, dynamic>.from(json['loadApplied'] ?? {})),
      fatigueBefore: decode(
        Map<String, dynamic>.from(json['fatigueBefore'] ?? {}),
      ),
      fatigueAfterRecovery: decode(
        Map<String, dynamic>.from(json['fatigueAfterRecovery'] ?? {}),
      ),
      fatigueAfter: decode(
        Map<String, dynamic>.from(json['fatigueAfter'] ?? {}),
      ),
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
    await MuscleRecoveryService().ensureLoaded();
    final snap =
        await FirebaseFirestore.instance
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
      final hoursSinceLastWorkout =
          isFirstWorkout
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
      state.forEach((muscle, s) {
        s.fatigue = FatigueService.getCurrentFatigue(
          muscle: muscle,
          state: s,
          now: workoutDate,
        );
        s.lastUpdate = workoutDate;
      });

      final fatigueAfterRecovery = {
        for (final e in state.entries) e.key: e.value.fatigue,
      };

      // =========================
      // 🏋️ CARGA (robusta)
      // =========================
      Map<Muscle, double> load = {};

      // 1) Si ya existe muscleLoad en el workout y NO quieres recalcular, úsalo
      final raw = data['muscleLoad'];

      Map<Muscle, double> decodeLoad(dynamic rawMap) {
        if (rawMap is! Map) return {};
        final m = Map<String, dynamic>.from(rawMap);
        final out = <Muscle, double>{};

        for (final e in m.entries) {
          final key = e.key;
          try {
            final muscle = _decodeMuscle(key);
            out[muscle] = (e.value as num).toDouble();
          } catch (_) {
            // Ignorar músculos desconocidos
          }
        }
        return out;
      }

      if (!forceRecalculateLoad && raw != null) {
        load = decodeLoad(raw);
      } else {
        // 2) Si falta muscleLoad, intenta calcularlo; si falla, queda vacío
        try {
          load = await WorkoutLoadService.calculateLoadFromWorkout(data);
        } catch (_) {
          load = {}; // 👈 CLAVE: igual habrá step y aparecerá en audit
        }
      }

      // =========================
      // 🔥 APLICAR CARGA
      // =========================
      for (final entry in load.entries) {
        final muscle = entry.key;
        final value = entry.value;

        state.putIfAbsent(
          muscle,
          () => MuscleFatigueState(fatigue: 0, lastUpdate: workoutDate),
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

    // Estado justo tras el último workout real, antes de aplicar
    // recuperación hasta "ahora" — es lo que se persiste para el camino
    // incremental.
    final stateAfterLastWorkout = {
      for (final e in state.entries)
        e.key: MuscleFatigueState(
          fatigue: e.value.fatigue,
          lastUpdate: e.value.lastUpdate,
        ),
    };

    // =========================
    // 🧠 RECUPERACIÓN HASTA AHORA
    // =========================
    if (lastWorkoutDate != null) {
      final now = DateTime.now();
      final hoursSinceLast = now.difference(lastWorkoutDate).inMinutes / 60.0;

      final fatigueBefore = {
        for (final e in state.entries) e.key: e.value.fatigue,
      };

      state.forEach((muscle, s) {
        s.fatigue = FatigueService.getCurrentFatigue(
          muscle: muscle,
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
      finalFatigue: {for (final e in state.entries) e.key: e.value.fatigue},
      steps: steps,
      stateAfterLastWorkout: stateAfterLastWorkout,
    );
  }

  /// --------------------------------------------------
  /// 🎚️ PONDERACIÓN DE VARIANTE CAMBIADA
  /// --------------------------------------------------
  /// Tras editar la ponderación de una variante, el `muscleLoad` guardado en
  /// cada workout que la usa queda desactualizado (se calculó al guardar).
  /// Recalcula solo esos workouts del usuario, persiste su `muscleLoad` y
  /// rehace la fatiga desde los valores ya actualizados.
  /// Devuelve cuántos workouts se actualizaron.
  static Future<int> refreshLoadForVariantChange({
    required String uid,
    required String exerciseId,
    required Set<String> variantIds,
  }) async {
    final snap =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: uid)
            .get();

    bool usesVariant(Map ex) =>
        ex['exerciseId']?.toString() == exerciseId &&
        variantIds.contains((ex['variantId'] ?? 'original').toString());

    bool workoutUsesVariant(Map<String, dynamic> data) {
      for (final raw in (data['performed'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final exercises = <dynamic>[
          ...(raw['exercises'] as List? ?? const []),
          for (final round in (raw['rounds'] as List? ?? const []))
            if (round is Map) ...(round['exercises'] as List? ?? const []),
        ];
        if (exercises.whereType<Map>().any(usesVariant)) return true;
      }
      return false;
    }

    final affected =
        snap.docs.where((d) => workoutUsesVariant(d.data())).toList();
    if (affected.isEmpty) return 0;

    var batch = FirebaseFirestore.instance.batch();
    var pending = 0;
    for (final doc in affected) {
      final load = await WorkoutLoadService.calculateLoadFromWorkout(
        doc.data(),
      );
      batch.update(doc.reference, {
        'muscleLoad': {for (final e in load.entries) e.key.name: e.value},
      });
      if (++pending == 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();

    await recalculateAndPersist(uid: uid);
    return affected.length;
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

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    // 1️⃣ Guardas el estado muscular tal como quedó tras el último workout
    // real (sin aplicar recuperación hasta "ahora" — eso se calcula al leer,
    // ver `readCurrentFatigue`).
    await _persistState(userRef, result.stateAfterLastWorkout);

    // 2️⃣ Guardas el resumen GLOBAL en el usuario, ya con recuperación
    // aplicada hasta el momento del cálculo (para lecturas que solo miran
    // `globalFatigue` sin recalcular nada, ej. listados de atletas).
    final globalFatigue = calculateGlobalFatigue(result.finalFatigue);
    await userRef.set({
      'globalFatigue': globalFatigue,
      'lastFatigueCalculation': Timestamp.now(),
    }, SetOptions(merge: true));

    // 3️⃣ Reescribe el audit completo (solo steps con carga real: el
    // consumidor de este historial ignora los de recuperación pura).
    final batch = FirebaseFirestore.instance.batch();
    final auditRef = userRef.collection('fatigue_audit');

    final oldAudit = await auditRef.get();
    for (final d in oldAudit.docs) {
      batch.delete(d.reference);
    }

    final realSteps = result.steps.where((s) => !s.isRecoveryOnly).toList();
    for (int i = 0; i < realSteps.length; i++) {
      batch.set(
        auditRef.doc(i.toString().padLeft(4, '0')),
        realSteps[i].toJson(),
      );
    }

    await batch.commit();

    return result;
  }

  /// --------------------------------------------------
  /// ⚡ APLICA UNA SESIÓN NUEVA DE FORMA INCREMENTAL
  /// --------------------------------------------------
  /// A diferencia de [recalculateAndPersist] (que relee TODO el histórico de
  /// `workouts_logged`), parte del estado ya persistido en
  /// `fatigue_state/latest`, le aplica recuperación hasta la fecha de la
  /// sesión nueva y le suma su carga — O(1) en vez de O(historial). Se debe
  /// usar en el camino normal de guardar un workout; `recalculateAndPersist`
  /// queda para cuando cambian ponderaciones/factores y hay que reprocesar
  /// todo desde cero.
  static Future<void> applySessionAndPersist({
    required String uid,
    required DateTime sessionDate,
    required Map<Muscle, double> load,
  }) async {
    await MuscleRecoveryService().ensureLoaded();
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final stateDoc =
        await userRef.collection('fatigue_state').doc('latest').get();

    final Map<Muscle, MuscleFatigueState> state = {};
    if (stateDoc.exists) {
      final data = stateDoc.data()!;
      final rawFatigue = Map<String, dynamic>.from(data['fatigue'] ?? {});
      final rawLastUpdate = Map<String, dynamic>.from(
        data['lastUpdateByMuscle'] ?? {},
      );
      for (final entry in rawFatigue.entries) {
        try {
          final muscle = _decodeMuscle(entry.key);
          final lastUpdateRaw = rawLastUpdate[entry.key];
          final lastUpdate =
              lastUpdateRaw is Timestamp ? lastUpdateRaw.toDate() : sessionDate;
          state[muscle] = MuscleFatigueState(
            fatigue: (entry.value as num).toDouble(),
            lastUpdate: lastUpdate,
          );
        } catch (_) {
          // Ignorar músculos desconocidos (aliases legacy ya migrados, etc.)
        }
      }
    }

    final fatigueBefore = {
      for (final e in state.entries) e.key: e.value.fatigue,
    };

    // La sesión anterior más reciente entre todos los músculos, para
    // reportar `hoursSinceLastWorkout` en el audit (informativo).
    final previousLastUpdate =
        state.values.isEmpty
            ? sessionDate
            : state.values
                .map((s) => s.lastUpdate)
                .reduce((a, b) => a.isAfter(b) ? a : b);
    final hoursSinceLastWorkout =
        state.isEmpty
            ? 0.0
            : sessionDate.difference(previousLastUpdate).inMinutes / 60.0;

    // Recuperación hasta el momento de la sesión nueva.
    state.forEach((muscle, s) {
      s.fatigue = FatigueService.getCurrentFatigue(
        muscle: muscle,
        state: s,
        now: sessionDate,
      );
      s.lastUpdate = sessionDate;
    });

    final fatigueAfterRecovery = {
      for (final e in state.entries) e.key: e.value.fatigue,
    };

    // Aplicar la carga de la sesión nueva.
    for (final entry in load.entries) {
      state.putIfAbsent(
        entry.key,
        () => MuscleFatigueState(fatigue: 0, lastUpdate: sessionDate),
      );
      state[entry.key] = FatigueService.updateAfterSession(
        state: state[entry.key]!,
        sessionTime: sessionDate,
        sessionLoad: entry.value,
      );
    }

    await _persistState(userRef, state);

    final globalFatigue = calculateGlobalFatigue({
      for (final e in state.entries) e.key: e.value.fatigue,
    });
    await userRef.set({
      'globalFatigue': globalFatigue,
      'lastFatigueCalculation': Timestamp.now(),
    }, SetOptions(merge: true));

    // Agrega UN paso al audit existente en vez de reescribirlo entero.
    // Los IDs son correlativos (0000, 0001, ...), así que el siguiente índice
    // es la cantidad de pasos. count() no requiere índice compuesto, a
    // diferencia de ordenar por documentId con limitToLast.
    final auditRef = userRef.collection('fatigue_audit');
    final countSnap = await auditRef.count().get();
    final nextIndex = countSnap.count ?? 0;

    await auditRef
        .doc(nextIndex.toString().padLeft(4, '0'))
        .set(
          FatigueRecalculationStep(
            workoutDate: sessionDate,
            hoursSinceLastWorkout: hoursSinceLastWorkout,
            loadApplied: Map.from(load),
            fatigueBefore: fatigueBefore,
            fatigueAfterRecovery: fatigueAfterRecovery,
            fatigueAfter: {
              for (final e in state.entries) e.key: e.value.fatigue,
            },
            isFirstWorkout: fatigueBefore.isEmpty,
            isRecoveryOnly: false,
          ).toJson(),
        );
  }

  /// Fuente única de "fatiga global": promedia los músculos con fatiga
  /// relevante (>=5). Con [topK] nulo (default, usado para persistir
  /// `globalFatigue` del usuario) promedia TODOS los relevantes, sin forzar
  /// una cantidad fija, así una fatiga muy concentrada en pocos grupos (ej.
  /// 3 músculos al 90% tras un día de piernas) no se diluye con ceros de
  /// músculos que ni se entrenaron. Con [topK] fijo se usa para vistas que
  /// necesitan acotar a los N músculos más fatigados (ej. resumen de
  /// perfil, timeline de auditoría), pero siempre con la misma fórmula.
  static double calculateGlobalFatigue(
    Map<Muscle, double> fatigue, {
    int? topK,
  }) {
    final values = fatigue.values.where((v) => v >= 5).toList();
    if (values.isEmpty) return 0;

    values.sort((a, b) => b.compareTo(a));
    final selected = topK == null ? values : values.take(topK).toList();

    return (selected.reduce((a, b) => a + b) / selected.length).clamp(0, 100);
  }

  static Future<void> _persistState(
    DocumentReference<Map<String, dynamic>> userRef,
    Map<Muscle, MuscleFatigueState> state,
  ) async {
    await userRef.collection('fatigue_state').doc('latest').set({
      'generatedAt': Timestamp.now(),
      'fatigue': {for (final e in state.entries) e.key.name: e.value.fatigue},
      'lastUpdateByMuscle': {
        for (final e in state.entries)
          e.key.name: Timestamp.fromDate(e.value.lastUpdate),
      },
    });
  }

  /// --------------------------------------------------
  /// 👁 LECTURA EN TIEMPO REAL (sin escribir nada)
  /// --------------------------------------------------
  /// Lee `fatigue_state/latest` y aplica recuperación hasta [now] al vuelo.
  /// Es lo que deben usar Home/Perfil para mostrar el % actual sin disparar
  /// un recálculo completo del histórico.
  static Future<Map<Muscle, double>> readCurrentFatigue({
    required String uid,
    DateTime? now,
  }) async {
    await MuscleRecoveryService().ensureLoaded();
    final effectiveNow = now ?? DateTime.now();
    final stateDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fatigue_state')
            .doc('latest')
            .get();

    if (!stateDoc.exists) return {};

    final data = stateDoc.data()!;
    final rawFatigue = Map<String, dynamic>.from(data['fatigue'] ?? {});
    final rawLastUpdate = Map<String, dynamic>.from(
      data['lastUpdateByMuscle'] ?? {},
    );

    final Map<Muscle, double> result = {};
    for (final entry in rawFatigue.entries) {
      try {
        final muscle = _decodeMuscle(entry.key);
        final lastUpdateRaw = rawLastUpdate[entry.key];
        final lastUpdate =
            lastUpdateRaw is Timestamp ? lastUpdateRaw.toDate() : effectiveNow;
        result[muscle] = FatigueService.recoverToNow(
          muscle: muscle,
          fatigue: (entry.value as num).toDouble(),
          lastUpdate: lastUpdate,
          now: effectiveNow,
        );
      } catch (_) {
        // Ignorar músculos desconocidos
      }
    }
    return result;
  }
}
