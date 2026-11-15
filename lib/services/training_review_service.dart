import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/muscle_catalog.dart';
import 'planned_load_service.dart';
import 'training_identity_service.dart';
import 'training_imbalance_service.dart';
import 'workout_load_service.dart';
import 'workout_rm_service.dart';

// Cálculo de la revisión planificado vs. realizado (carga muscular, perfil de
// entrenamiento, cumplimiento de series y de kg). Extraído de
// `UnifiedWeeklyReviewScreen` para poder reutilizarlo en rangos arbitrarios
// (ej. el informe de 4 semanas de Planificación) sin duplicar la lógica.

class DayPlannedItem {
  final String key;
  final String name;
  final String blockLabel;
  final double plannedVol;

  /// Movimiento padre (`movementId`/`exerciseId`): permite reconocer que se
  /// hizo OTRA variante del mismo movimiento en lugar de la planificada.
  final String? movementId;

  DayPlannedItem({
    required this.key,
    required this.name,
    required this.blockLabel,
    required this.plannedVol,
    this.movementId,
  });
}

class DayResultItem {
  final DayPlannedItem planned;
  final double achieved;

  /// Nombre del ejercicio realmente hecho cuando fue una variante distinta
  /// de la planificada (sustitución: equipo ocupado, molestia, etc.).
  final String? substitutedBy;
  double get missing =>
      (planned.plannedVol - achieved).clamp(0, double.infinity);

  DayResultItem({
    required this.planned,
    required this.achieved,
    this.substitutedBy,
  });
}

/// Una serie planificada (peso/reps objetivo, sin RPE — el plan nunca
/// define esfuerzo percibido, ver `_buildRpeKpiCard`).
class PlannedSetDetail {
  final double weight;
  final double reps;
  final String? variantLabel;

  PlannedSetDetail({
    required this.weight,
    required this.reps,
    this.variantLabel,
  });
}

/// Una serie realmente ejecutada, con la variante usada (puede diferir de
/// la planificada, ej. cambio de máquina — ver `_complianceKey`) y RPE real.
class AchievedSetDetail {
  final double weight;
  final double reps;
  final double? rpe;
  final String? variantLabel;
  final DateTime? date;

  AchievedSetDetail({
    required this.weight,
    required this.reps,
    this.rpe,
    this.variantLabel,
    this.date,
  });
}

/// Cumplimiento de CARGA (kg) por ejercicio, en paralelo al cumplimiento de
/// SERIES que ya calcula `_calculateDetailedReview`/`DayResultItem`. Son
/// magnitudes distintas: un atleta puede completar todas las series
/// planificadas pero con menos peso del pedido (o al revés). Guarda también
/// el detalle serie a serie para el desglose al tocar el ejercicio.
class ExerciseLoadCompliance {
  final String name;
  final double plannedKg;
  final double achievedKg;
  final List<PlannedSetDetail> plannedSets;
  final List<AchievedSetDetail> achievedSets;

  ExerciseLoadCompliance({
    required this.name,
    required this.plannedKg,
    required this.achievedKg,
    this.plannedSets = const [],
    this.achievedSets = const [],
  });

  double get pct => plannedKg > 0 ? (achievedKg / plannedKg).clamp(0, 2) : 0;
}

/// Resumen de una semana para la tendencia multi-semana: % de cumplimiento
/// en series y en kg, RPE promedio real de esa semana.
class WeeklyComplianceSummary {
  final DateTime weekStart;
  final double seriesPct;
  final double kgPct;
  final double avgRpe;

  WeeklyComplianceSummary({
    required this.weekStart,
    required this.seriesPct,
    required this.kgPct,
    required this.avgRpe,
  });
}

class TrainingReviewCalculator {
  final String athleteId;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  TrainingReviewCalculator({
    required this.athleteId,
    required this.rangeStart,
    required this.rangeEnd,
  });

  // Data for Load Distribution
  Map<DateTime, Map<String, double>> dailyLoads = {};
  Map<String, double> totalLoad = {};
  Map<String, double> exerciseTypeLoad = {};
  Map<DateTime, Map<String, List<Map<String, dynamic>>>> dailyDetails = {};
  List<ImbalanceAlert> imbalanceAlerts = [];
  TrainingIdentityResult? trainingIdentity;
  TrainingIdentityResult? plannedTrainingIdentity;
  TrainingIdentityResult? loggedTrainingIdentity;
  Map<String, double> blockTypeLoad = {};
  Map<TrainingIntentFamily, double> intentFamilyLoad = {};
  Map<String, double> repRangeLoad = {};
  double trackedRmLoad = 0;
  double compoundLoad = 0;
  double isolationLoad = 0;
  double freeLoad = 0;
  double guidedLoad = 0;
  double bodyweightLoad = 0;
  double bilateralLoad = 0;
  double unilateralLoad = 0;
  List<TrainingIdentityExerciseContribution> identityExercises = [];

  // Aggregated Details for Charts
  Map<AnatomicalGroup, List<Map<String, dynamic>>> anatomicalGroupDetails = {};
  Map<String, List<Map<String, dynamic>>> exerciseTypeDetails = {};

  // Data for Detailed Review
  Map<String, List<DayResultItem>> reviewByDay = {};
  Map<String, List<Map<String, dynamic>>> extrasByDay = {};
  List<String> sortedDayKeys = [];
  String? selectedReviewDayKey;

  // Global Compliance Stats
  double weeklyPlannedVol = 0;
  double weeklyAchievedVol = 0;
  double plannedToDateVol = 0;
  double achievedToDateVol = 0;
  int plannedDaysCount = 0;
  int achievedDaysCount = 0;

  // Weight (kg) compliance y RPE real — paralelos al conteo de series de
  // arriba, ver _calculateWeightCompliance.
  List<ExerciseLoadCompliance> exerciseLoadCompliance = [];
  double weeklyPlannedKg = 0;
  double weeklyAchievedKg = 0;
  double weeklyAvgRpe = 0;

  /// Igual que [exerciseLoadCompliance] pero separado por día (clave
  /// `yyyy-MM-dd`, misma que [reviewByDay]); lo usa el informe por período.
  Map<String, List<ExerciseLoadCompliance>> exerciseLoadComplianceByDay = {};

  /// Calcula carga muscular/perfil, cumplimiento de series y de kg para
  /// `[rangeStart, rangeEnd)`.
  Future<void> run() async {
    await Future.wait([
      _calculateMuscularLoad(),
      _calculateDetailedReview(),
      _calculateWeightCompliance(),
    ]);
  }

  /// Perfil de entrenamiento de un subconjunto de contribuciones (ej. solo
  /// lo planificado de un día). Null si no hay ejercicios.
  TrainingIdentityResult? identityFor(
    Iterable<TrainingIdentityExerciseContribution> exercises,
  ) {
    final list = exercises.toList();
    if (list.isEmpty) return null;
    return TrainingIdentityService.analyze(identityInputFor(list));
  }

  Map<TrainingProfile, double> _profileDistributionOverride(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <TrainingProfile, double>{};
    for (final entry in raw.entries) {
      final profile = TrainingProfile.values.where(
        (item) => item.name == entry.key.toString(),
      );
      if (profile.isEmpty || entry.value is! num) continue;
      result[profile.first] = (entry.value as num).toDouble().clamp(0.0, 1.0);
    }
    return result;
  }

  DateTime? _plannedDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _plannedDocsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final snap =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: athleteId)
            .get();
    final docs =
        snap.docs.where((doc) {
          final date = _plannedDate(doc.data()['date']);
          return date != null && !date.isBefore(start) && date.isBefore(end);
        }).toList();
    // Firestore no garantiza el orden de una consulta sin `orderBy`. El
    // perfil debe respetar el flujo real de la planificación: día y luego
    // posición del bloque (`order`).
    docs.sort((a, b) {
      final dateA = _plannedDate(a.data()['date']);
      final dateB = _plannedDate(b.data()['date']);
      final dateCompare = (dateA ?? start).compareTo(dateB ?? start);
      if (dateCompare != 0) return dateCompare;
      final orderA = (a.data()['order'] as num?)?.toInt() ?? 0;
      final orderB = (b.data()['order'] as num?)?.toInt() ?? 0;
      final orderCompare = orderA.compareTo(orderB);
      if (orderCompare != 0) return orderCompare;
      return a.id.compareTo(b.id);
    });
    return docs;
  }

  Map<String, dynamic>? _resolveProfileExerciseData(
    Map<String, Map<String, dynamic>> catalog,
    Map<String, dynamic> exercise,
    String name,
  ) {
    final exerciseId = (exercise['exerciseId'] ?? '').toString();
    final variantId = (exercise['variantId'] ?? '').toString();
    if (exerciseId.isNotEmpty && variantId.isNotEmpty) {
      final variant = catalog['$exerciseId::$variantId'];
      if (variant != null) return variant;
    }
    final byName = catalog[WorkoutRMService.normalizeExerciseName(name)];
    if (byName != null) return byName;
    // Legacy records are retained but visibly identified as an estimate.
    return null;
  }

  Future<void> _calculateMuscularLoad() async {
    dailyLoads.clear();
    totalLoad.clear();
    dailyDetails.clear();
    exerciseTypeLoad.clear();
    anatomicalGroupDetails.clear();
    exerciseTypeDetails.clear();
    imbalanceAlerts = [];
    trainingIdentity = null;
    plannedTrainingIdentity = null;
    loggedTrainingIdentity = null;
    blockTypeLoad = {};
    intentFamilyLoad = {};
    repRangeLoad = {};
    trackedRmLoad = 0;
    compoundLoad = 0;
    isolationLoad = 0;
    freeLoad = 0;
    guidedLoad = 0;
    bodyweightLoad = 0;
    bilateralLoad = 0;
    unilateralLoad = 0;
    identityExercises = [];

    // 1️⃣ Obtener Ponderadores Dinámicos de Firestore
    final dynamicFactors = await WorkoutLoadService.fetchExerciseFolders();

    final exercisesSnapshot =
        await FirebaseFirestore.instance.collection('exercises').get();
    final profileOverridesSnapshot =
        await FirebaseFirestore.instance
            .collection('exercise_profile_overrides')
            .get();
    final profileOverridesByName = <String, Map<String, double>>{};
    final profileOverridesByType = <String, Map<String, double>>{};
    for (final doc in profileOverridesSnapshot.docs) {
      final raw = doc.data()['profiles'];
      if (raw is! Map) continue;
      final profiles = <String, double>{
        for (final entry in raw.entries)
          entry.key.toString(): (entry.value as num).toDouble(),
      };
      final exerciseType = (doc.data()['exerciseType'] ?? '').toString();
      if (exerciseType.isNotEmpty) {
        profileOverridesByType[WorkoutRMService.normalizeExerciseName(
              exerciseType,
            )] =
            profiles;
      } else {
        profileOverridesByName[WorkoutRMService.normalizeExerciseName(doc.id)] =
            profiles;
      }
    }
    final Map<String, Map<String, dynamic>> exerciseMap = {};
    for (final doc in exercisesSnapshot.docs) {
      final data = {...doc.data(), 'id': doc.id};
      final movementName = (data['name'] ?? '').toString().trim();
      if (movementName.isEmpty) continue;
      final baseData = <String, dynamic>{
        'muscleWeights': Map<String, dynamic>.from(data['muscleWeights'] ?? {}),
        'exerciseType': data['exerciseType'] ?? 'Otro',
        'trackRM': data['trackRM'] == true,
        'equipment': List<String>.from(data['equipment'] ?? const []),
        'movementClass': (data['movementClass'] ?? '').toString(),
        'resistanceType': (data['resistanceType'] ?? '').toString(),
        'isUnilateral': data['isUnilateral'] == true,
        'hasIsUnilateralField': data.containsKey('isUnilateral'),
        'movementPlane': (data['movementPlane'] ?? 'sagittal').toString(),
        'trainingDiscipline': (data['trainingDiscipline'] ?? '').toString(),
        'movementIntent': (data['movementIntent'] ?? '').toString(),
        'classificationOrigin': 'base',
      };
      final baseOverride =
          profileOverridesByType[WorkoutRMService.normalizeExerciseName(
            (data['exerciseType'] ?? '').toString(),
          )] ??
          profileOverridesByName[WorkoutRMService.normalizeExerciseName(
            movementName,
          )];
      if (baseOverride != null) {
        baseData['profileDistributionOverride'] = baseOverride;
      }
      exerciseMap[WorkoutRMService.normalizeExerciseName(movementName)] =
          baseData;
      exerciseMap['${doc.id}::original'] = baseData;

      final rawVariants = data['variants'];
      if (rawVariants is! List) continue;
      for (final rawVariant in rawVariants.whereType<Map>()) {
        final variant = Map<String, dynamic>.from(rawVariant);
        final label = (variant['label'] ?? 'Original').toString().trim();
        final displayName =
            label.toLowerCase() == 'original'
                ? movementName
                : '$movementName - $label';
        final overrides = Map<String, dynamic>.from(
          variant['muscleWeightOverrides'] ?? const {},
        );
        exerciseMap[WorkoutRMService.normalizeExerciseName(displayName)] = {
          ...baseData,
          if (overrides.isNotEmpty) 'muscleWeights': overrides,
          'trackRM': variant['trackRM'] == true,
          'exerciseType':
              (variant['exerciseType'] ?? data['exerciseType'] ?? 'Otro')
                  .toString(),
          'equipment': List<String>.from(
            variant['equipment'] ?? data['equipment'] ?? const [],
          ),
          'resistanceType':
              (variant['resistanceType'] ?? data['resistanceType'] ?? '')
                  .toString(),
          'isUnilateral': variant['isUnilateral'] == true,
          'hasIsUnilateralField': variant.containsKey('isUnilateral'),
          'movementPlane':
              (variant['movementPlane'] ?? data['movementPlane'] ?? 'sagittal')
                  .toString(),
          'trainingDiscipline':
              (variant['trainingDiscipline'] ??
                      data['trainingDiscipline'] ??
                      '')
                  .toString(),
          'movementIntent':
              (variant['movementIntent'] ?? data['movementIntent'] ?? '')
                  .toString(),
          'classificationOrigin': 'variant',
        };
        final variantType =
            (variant['exerciseType'] ?? data['exerciseType'] ?? '').toString();
        final variantOverride =
            profileOverridesByType[WorkoutRMService.normalizeExerciseName(
              variantType,
            )] ??
            profileOverridesByName[WorkoutRMService.normalizeExerciseName(
              displayName,
            )];
        if (variantOverride != null) {
          exerciseMap[WorkoutRMService.normalizeExerciseName(
                displayName,
              )]!['profileDistributionOverride'] =
              variantOverride;
        } else if (variantType != (data['exerciseType'] ?? '').toString()) {
          exerciseMap[WorkoutRMService.normalizeExerciseName(displayName)]!
              .remove('profileDistributionOverride');
        }
        exerciseMap['${doc.id}::${variant['id'] ?? ''}'] =
            exerciseMap[WorkoutRMService.normalizeExerciseName(displayName)]!;
      }
    }
    final workoutsSnapshot = await _plannedDocsInRange(rangeStart, rangeEnd);
    final loggedSnapshot =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(rangeEnd))
            .get();
    final allLoggedSnapshot =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .get();
    final historical1RMByExercise = _buildHistorical1RMByExercise(
      allLoggedSnapshot.docs,
    );
    // 3ï¸âƒ£ Obtener todos los IDs de bloque Ãºnicos para el fetch paralelo
    final uniqueBlockIds =
        workoutsSnapshot
            .map((d) => d.data()['blockId'] as String?)
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();

    final blockDocs = await Future.wait(
      uniqueBlockIds.map(
        (id) => FirebaseFirestore.instance.collection('blocks').doc(id).get(),
      ),
    );

    final Map<String, Map<String, dynamic>> blocksCache = {};
    for (int i = 0; i < uniqueBlockIds.length; i++) {
      if (blockDocs[i].exists) {
        blocksCache[uniqueBlockIds[i]] = blockDocs[i].data()!;
      }
    }

    // 4ï¸âƒ£ Calcular carga procesando cada planned_workout individualmente (Evita sobreescritura si se repite bloques)
    for (final doc in workoutsSnapshot) {
      final data = {...doc.data(), 'id': doc.id};
      final blockId = data['blockId'] as String?;
      if (blockId == null) continue;

      final workoutDate = _plannedDate(data['date']);
      if (workoutDate == null) continue;
      final normalizedDate = DateTime(
        workoutDate.year,
        workoutDate.month,
        workoutDate.day,
      );
      // Keep planned work visible even when the athlete logged only part of a
      // day. Planned and completed profiles are compared below.

      final baseBlock = blocksCache[blockId];
      if (baseBlock == null) continue;
      final block = PlannedLoadService.resolveBlock(
        block: baseBlock,
        planned: data,
      );

      // Inicializar día si no existe
      dailyLoads.putIfAbsent(normalizedDate, () => {});
      dailyDetails.putIfAbsent(normalizedDate, () => {});

      final String rawType =
          (block['type'] ?? 'normal').toString().trim().toLowerCase();

      int rounds = 1;
      if (rawType == 'circuito' || rawType == 'tabata' || rawType == 'emom') {
        rounds = (block['rounds'] as num?)?.toInt() ?? 1;
      }

      // Normalizar tipo para el multiplicador de estructura
      String structureType = 'Series';
      if (rawType == 'circuito') structureType = 'Circuito';
      if (rawType == 'tabata') structureType = 'Tabata';
      if (rawType == 'emom') {
        structureType =
            'EMOM'; // EMOM suele comportarse como serie normal o circuito ligero
      }
      if (rawType == 'series descendentes') {
        structureType = 'Series descendentes';
      }
      if (rawType == 'buscar rm') structureType = 'Buscar RM';

      double blockAccumulatedLoad = 0;

      final exercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? [],
      );
      for (final ex in exercises) {
        final String name = _normalizeExerciseName(
          ex['exercise'] ?? ex['name'],
        );
        if (name.isEmpty) continue;

        final exerciseData = _resolveProfileExerciseData(exerciseMap, ex, name);
        if (exerciseData == null) continue;

        final weights = Map<String, dynamic>.from(
          exerciseData['muscleWeights'] ?? {},
        );
        final String exType = exerciseData['exerciseType'] ?? 'Otro';
        final bool trackRm = exerciseData['trackRM'] == true;
        final resistanceType =
            (exerciseData['resistanceType'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
        final movementClass =
            (exerciseData['movementClass'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
        final hasExplicitResistance = resistanceType.isNotEmpty;
        final hasExplicitMovementClass = movementClass.isNotEmpty;
        final hasExplicitUnilateral =
            exerciseData['hasIsUnilateralField'] == true;
        final explicitCatalogUnilateral = exerciseData['isUnilateral'] == true;
        final equipmentDescriptor =
            '$name $exType ${(exerciseData['equipment'] as List? ?? const []).join(' ')}';
        var family = TrainingIdentityService.mapExerciseTypeToIntentFamily(
          exType,
        );
        final inferredBodyweight =
            hasExplicitResistance
                ? (resistanceType == 'bodyweight' ||
                    resistanceType == 'peso corporal')
                : TrainingIdentityService.isBodyweightType(equipmentDescriptor);
        final inferredGuided =
            hasExplicitResistance
                ? (resistanceType == 'guided' || resistanceType == 'guiado')
                : TrainingIdentityService.isGuidedType(equipmentDescriptor);
        final inferredFree =
            hasExplicitResistance
                ? (resistanceType == 'free' || resistanceType == 'libre')
                : !inferredBodyweight &&
                    TrainingIdentityService.isFreeType(equipmentDescriptor);
        final explicitPerSide = ex['perSide'] == true;
        final inferredCatalogUnilateral =
            TrainingIdentityService.isUnilateralExercise(
              name: name,
              type: exType,
            );
        final inferredUnilateral =
            hasExplicitUnilateral
                ? explicitCatalogUnilateral
                : explicitPerSide ||
                    explicitCatalogUnilateral ||
                    inferredCatalogUnilateral;
        final movementPlane =
            (exerciseData['movementPlane'] ?? 'sagittal')
                .toString()
                .toLowerCase()
                .trim();
        final hasExplicitMovementPlane =
            movementPlane.isNotEmpty && movementPlane != 'sagittal';
        final inferredRotational =
            hasExplicitMovementPlane
                ? (movementPlane == 'rotational' ||
                    movementPlane == 'anti-rotational')
                : TrainingIdentityService.isRotationalExercise(
                  name: name,
                  type: exType,
                );
        final inferredCompound =
            hasExplicitMovementClass
                ? (movementClass == 'compound' || movementClass == 'compuesto')
                : TrainingIdentityService.isCompoundExercise(
                  family: family,
                  muscleCount: weights.length,
                  type: exType,
                );
        final inferredIsolation =
            hasExplicitMovementClass
                ? (movementClass == 'isolation' || movementClass == 'aislado')
                : !inferredCompound &&
                    TrainingIdentityService.isIsolationExercise(
                      family: family,
                      muscleCount: weights.length,
                      type: exType,
                    );
        if (inferredIsolation && exType.toLowerCase().contains('hipertrof')) {
          family = TrainingIntentFamily.isolatedHypertrophy;
        }
        final targetReps = _resolveIdentityTargetReps(
          rawType: rawType,
          block: block,
          exercise: ex,
          family: family,
        );
        final repsEquivalent = _resolveIdentityRepsEquivalent(
          rawType: rawType,
          block: block,
          exercise: ex,
          targetReps: targetReps,
          family: family,
        );
        final plannedFactor = dynamicFactors[exType] ?? 1.0;
        final plannedStructFactor = WorkoutLoadService.structureFactor(
          structureType,
        );
        final plannedSets = _buildPlannedIdentitySets(
          rawType: rawType,
          rounds: rounds,
          block: block,
          exercise: ex,
          fallbackTargetReps: targetReps,
          fallbackRepsEquivalent: repsEquivalent,
        );
        final plannedHistorical1RM =
            _shouldUseHistorical1RM(exType)
                ? historical1RMByExercise[WorkoutRMService.normalizeExerciseName(
                  name,
                )]
                : null;

        for (final plannedSet in plannedSets) {
          final setTargetReps =
              (plannedSet['targetReps'] as num?)?.toDouble() ?? targetReps;
          final setRepsEquivalent =
              (plannedSet['repsEquivalent'] as num?)?.toDouble() ??
              repsEquivalent;
          final setPerSide = plannedSet['perSide'] == true;
          final perSideMultiplier = setPerSide ? 2.0 : 1.0;
          final referenceWeight =
              (plannedSet['referenceWeight'] as num?)?.toDouble();
          final percent1RM = _computePercent1RM(
            // RM is stored for the same implement used in the set. "Por lado"
            // doubles volume, not the intensity of each implement.
            referenceWeight: referenceWeight,
            historical1RM: plannedHistorical1RM,
          );
          final normalizedRepFactor =
              (setRepsEquivalent <= 0 ? 1.0 : setRepsEquivalent / 10.0);
          final volumeUnits = normalizedRepFactor * perSideMultiplier;
          final repBucket = TrainingIdentityService.repBucketFor(
            blockType: structureType,
            targetReps: setTargetReps,
            family: family,
          );

          blockAccumulatedLoad += _applyIdentityExerciseLoad(
            normalizedDate: normalizedDate,
            source: 'planned',
            setLabel: (plannedSet['setLabel'] ?? 'Serie').toString(),
            name: name,
            blockTitle:
                (block['title'] ?? block['type'] ?? 'Bloque').toString(),
            exType: exType,
            trainingDiscipline:
                (ex['trainingDisciplineOverride'] ??
                        exerciseData['trainingDiscipline'] ??
                        '')
                    .toString(),
            movementIntent:
                (ex['movementIntentOverride'] ??
                        exerciseData['movementIntent'] ??
                        '')
                    .toString(),
            classificationOrigin:
                ex['movementIntentOverride'] != null ||
                        ex['trainingDisciplineOverride'] != null
                    ? 'block override'
                    : (exerciseData['classificationOrigin'] ?? 'estimated')
                        .toString(),
            durationSeconds:
                (ex['valueType']?.toString() == 'time'
                        ? (ex['value'] ?? ex['seconds'])
                        : null)
                    as num?,
            rounds: rounds.toDouble(),
            structureType: structureType,
            weights: weights,
            baseSets: 1.0,
            targetReps: setTargetReps,
            repsEquivalent: setRepsEquivalent,
            perSideMultiplier: perSideMultiplier,
            factor: plannedFactor,
            structFactor: plannedStructFactor,
            volumeUnits: volumeUnits,
            family: family,
            profileDistributionOverride: _profileDistributionOverride(
              exerciseData['profileDistributionOverride'],
            ),
            repBucket: repBucket,
            referenceWeight: referenceWeight,
            historical1RM: plannedHistorical1RM,
            percent1RM: percent1RM,
            percent1RMBucket: _percent1RMBucket(percent1RM),
            trackRm: trackRm,
            inferredUnilateral: inferredUnilateral,
            inferredFree: inferredFree,
            inferredGuided: inferredGuided,
            inferredBodyweight: inferredBodyweight,
            inferredCompound: inferredCompound,
            inferredIsolation: inferredIsolation,
            inferredRotational: inferredRotational,
            equipmentDescriptor: equipmentDescriptor,
          );
        }
        continue;
      }

      blockTypeLoad[structureType] =
          (blockTypeLoad[structureType] ?? 0) + blockAccumulatedLoad;
    }

    for (final doc in loggedSnapshot.docs) {
      final data = doc.data();
      final workoutDate = (data['date'] as Timestamp?)?.toDate();
      if (workoutDate == null) continue;

      final normalizedDate = DateTime(
        workoutDate.year,
        workoutDate.month,
        workoutDate.day,
      );
      dailyLoads.putIfAbsent(normalizedDate, () => {});
      dailyDetails.putIfAbsent(normalizedDate, () => {});

      final performed = List<Map<String, dynamic>>.from(
        data['performed'] ?? [],
      );
      for (final rawBlock in performed) {
        final block = Map<String, dynamic>.from(rawBlock);
        final structureType = _normalizeLoggedStructureType(
          (block['type'] ?? '').toString(),
        );
        double blockAccumulatedLoad = 0;

        for (final loggedExercise in _extractLoggedExercises(block)) {
          final name = _normalizeExerciseName(loggedExercise['name']);
          if (name.isEmpty) continue;

          final exerciseData = _resolveProfileExerciseData(
            exerciseMap,
            loggedExercise,
            name,
          );
          if (exerciseData == null) continue;

          final weights = Map<String, dynamic>.from(
            exerciseData['muscleWeights'] ?? {},
          );
          final String exType = exerciseData['exerciseType'] ?? 'Otro';
          final bool trackRm = exerciseData['trackRM'] == true;
          final resistanceType =
              (exerciseData['resistanceType'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();
          final movementClass =
              (exerciseData['movementClass'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();
          final hasExplicitResistance = resistanceType.isNotEmpty;
          final hasExplicitMovementClass = movementClass.isNotEmpty;
          final hasExplicitUnilateral =
              exerciseData['hasIsUnilateralField'] == true;
          final explicitCatalogUnilateral =
              exerciseData['isUnilateral'] == true;
          final equipmentDescriptor =
              '$name $exType ${(exerciseData['equipment'] as List? ?? const []).join(' ')}';
          var family = TrainingIdentityService.mapExerciseTypeToIntentFamily(
            exType,
          );
          final inferredBodyweight =
              hasExplicitResistance
                  ? (resistanceType == 'bodyweight' ||
                      resistanceType == 'peso corporal')
                  : TrainingIdentityService.isBodyweightType(
                    equipmentDescriptor,
                  );
          final inferredGuided =
              hasExplicitResistance
                  ? (resistanceType == 'guided' || resistanceType == 'guiado')
                  : TrainingIdentityService.isGuidedType(equipmentDescriptor);
          final inferredFree =
              hasExplicitResistance
                  ? (resistanceType == 'free' || resistanceType == 'libre')
                  : !inferredBodyweight &&
                      TrainingIdentityService.isFreeType(equipmentDescriptor);
          final explicitPerSide = loggedExercise['perSide'] == true;
          final inferredCatalogUnilateral =
              TrainingIdentityService.isUnilateralExercise(
                name: name,
                type: exType,
              );
          final inferredUnilateral =
              hasExplicitUnilateral
                  ? explicitCatalogUnilateral
                  : explicitPerSide ||
                      explicitCatalogUnilateral ||
                      inferredCatalogUnilateral;
          final movementPlane =
              (exerciseData['movementPlane'] ?? 'sagittal')
                  .toString()
                  .toLowerCase()
                  .trim();
          final hasExplicitMovementPlane =
              movementPlane.isNotEmpty && movementPlane != 'sagittal';
          final inferredRotational =
              hasExplicitMovementPlane
                  ? (movementPlane == 'rotational' ||
                      movementPlane == 'anti-rotational')
                  : TrainingIdentityService.isRotationalExercise(
                    name: name,
                    type: exType,
                  );
          final inferredCompound =
              hasExplicitMovementClass
                  ? (movementClass == 'compound' ||
                      movementClass == 'compuesto')
                  : TrainingIdentityService.isCompoundExercise(
                    family: family,
                    muscleCount: weights.length,
                    type: exType,
                  );
          final inferredIsolation =
              hasExplicitMovementClass
                  ? (movementClass == 'isolation' || movementClass == 'aislado')
                  : !inferredCompound &&
                      TrainingIdentityService.isIsolationExercise(
                        family: family,
                        muscleCount: weights.length,
                        type: exType,
                      );
          if (inferredIsolation && exType.toLowerCase().contains('hipertrof')) {
            family = TrainingIntentFamily.isolatedHypertrophy;
          }

          final baseSets =
              (loggedExercise['baseSets'] as num?)?.toDouble() ?? 1.0;
          final targetReps =
              (loggedExercise['targetReps'] as num?)?.toDouble() ?? 0.0;
          // Por tiempo: la equivalencia depende del tipo (cardio vs
          // isometría), que recién se conoce acá con el catálogo.
          final repsEquivalent =
              loggedExercise['valueType']?.toString() == 'time'
                  ? TrainingIdentityService.timeRepsEquivalent(
                    targetReps,
                    family,
                  )
                  : (loggedExercise['repsEquivalent'] as num?)?.toDouble() ??
                      targetReps;
          final perSideMultiplier = explicitPerSide ? 2.0 : 1.0;
          final factor = dynamicFactors[exType] ?? 1.0;
          final structFactor = WorkoutLoadService.structureFactor(
            structureType,
          );
          final referenceWeight =
              (loggedExercise['referenceWeight'] as num?)?.toDouble();
          final historical1RM =
              _shouldUseHistorical1RM(exType)
                  ? historical1RMByExercise[WorkoutRMService.normalizeExerciseName(
                    name,
                  )]
                  : null;
          final percent1RM = _computePercent1RM(
            referenceWeight: referenceWeight,
            historical1RM: historical1RM,
          );
          final normalizedRepFactor =
              (repsEquivalent <= 0 ? 1.0 : repsEquivalent / 10.0);
          final volumeUnits =
              baseSets * normalizedRepFactor * perSideMultiplier;
          final repBucket = TrainingIdentityService.repBucketFor(
            blockType: structureType,
            targetReps: targetReps,
            family: family,
          );

          blockAccumulatedLoad += _applyIdentityExerciseLoad(
            normalizedDate: normalizedDate,
            source: 'logged',
            setLabel: (loggedExercise['setLabel'] ?? 'Serie').toString(),
            name: name,
            blockTitle:
                (block['title'] ?? block['type'] ?? 'Entrenamiento realizado')
                    .toString(),
            exType: exType,
            trainingDiscipline:
                (loggedExercise['trainingDiscipline'] ??
                        exerciseData['trainingDiscipline'] ??
                        '')
                    .toString(),
            movementIntent:
                (loggedExercise['movementIntent'] ??
                        exerciseData['movementIntent'] ??
                        '')
                    .toString(),
            classificationOrigin:
                (loggedExercise['movementIntent'] != null ||
                        loggedExercise['trainingDiscipline'] != null)
                    ? 'logged snapshot'
                    : (exerciseData['classificationOrigin'] ?? 'estimated')
                        .toString(),
            durationSeconds:
                (loggedExercise['valueType']?.toString() == 'time'
                        ? (loggedExercise['value'] ?? loggedExercise['seconds'])
                        : null)
                    as num?,
            rounds: ((loggedExercise['rounds'] as num?)?.toDouble() ?? 1),
            structureType: structureType,
            weights: weights,
            baseSets: baseSets,
            targetReps: targetReps,
            repsEquivalent: repsEquivalent,
            perSideMultiplier: perSideMultiplier,
            factor: factor,
            structFactor: structFactor,
            volumeUnits: volumeUnits,
            family: family,
            profileDistributionOverride: _profileDistributionOverride(
              exerciseData['profileDistributionOverride'],
            ),
            repBucket: repBucket,
            referenceWeight: referenceWeight,
            historical1RM: historical1RM,
            percent1RM: percent1RM,
            percent1RMBucket: _percent1RMBucket(percent1RM),
            reportedRpe: (loggedExercise['reportedRpe'] as num?)?.toDouble(),
            trackRm: trackRm,
            inferredUnilateral: inferredUnilateral,
            inferredFree: inferredFree,
            inferredGuided: inferredGuided,
            inferredBodyweight: inferredBodyweight,
            inferredCompound: inferredCompound,
            inferredIsolation: inferredIsolation,
            inferredRotational: inferredRotational,
            equipmentDescriptor: equipmentDescriptor,
          );
        }

        blockTypeLoad[structureType] =
            (blockTypeLoad[structureType] ?? 0) + blockAccumulatedLoad;
      }
    }

    imbalanceAlerts = TrainingImbalanceService.analyze(totalLoad: totalLoad);
    trainingIdentity = TrainingIdentityService.analyze(
      TrainingIdentityInput(
        totalLoad: totalLoad,
        exerciseTypeLoad: exerciseTypeLoad,
        blockTypeLoad: blockTypeLoad,
        intentFamilyLoad: intentFamilyLoad,
        repRangeLoad: repRangeLoad,
        trackedRmLoad: trackedRmLoad,
        bilateralLoad: bilateralLoad,
        unilateralLoad: unilateralLoad,
        freeLoad: freeLoad,
        guidedLoad: guidedLoad,
        bodyweightLoad: bodyweightLoad,
        compoundLoad: compoundLoad,
        isolationLoad: isolationLoad,
        exercises: identityExercises,
      ),
    );
    plannedTrainingIdentity = TrainingIdentityService.analyze(
      identityInputFor(
        identityExercises.where((item) => item.source == 'planned'),
      ),
    );
    loggedTrainingIdentity = TrainingIdentityService.analyze(
      identityInputFor(
        identityExercises.where((item) => item.source == 'logged'),
      ),
    );
  }

  /// Reconstruye un `TrainingIdentityInput` completo a partir de un
  /// subconjunto de ejercicios ya calculados (ej. solo 'planned', solo
  /// 'logged', o solo los de un día). Recalcula TODOS los agregados
  /// (`intentFamilyLoad`, `repRangeLoad`, balances, etc.) desde ese
  /// subconjunto — nunca reusa los campos agregados de la semana completa,
  /// porque esos mezclarían fuentes/días distintos en las métricas base
  /// aunque `exercises` sí venga filtrado correctamente.
  static TrainingIdentityInput identityInputFor(
    Iterable<TrainingIdentityExerciseContribution> exercises,
  ) {
    final list = exercises.toList();
    final subsetTotalLoad = <String, double>{};
    final subsetExerciseTypeLoad = <String, double>{};
    final subsetBlockTypeLoad = <String, double>{};
    final subsetIntentFamilyLoad = <TrainingIntentFamily, double>{};
    final subsetRepRangeLoad = <String, double>{};
    double subsetTrackedRmLoad = 0;
    double subsetBilateralLoad = 0;
    double subsetUnilateralLoad = 0;
    double subsetFreeLoad = 0;
    double subsetGuidedLoad = 0;
    double subsetBodyweightLoad = 0;
    double subsetCompoundLoad = 0;
    double subsetIsolationLoad = 0;

    for (final exercise in list) {
      exercise.muscleLoads.forEach((muscle, load) {
        subsetTotalLoad[muscle] = (subsetTotalLoad[muscle] ?? 0) + load;
      });
      subsetExerciseTypeLoad[exercise.exerciseType] =
          (subsetExerciseTypeLoad[exercise.exerciseType] ?? 0) + exercise.load;
      subsetBlockTypeLoad[exercise.blockType] =
          (subsetBlockTypeLoad[exercise.blockType] ?? 0) + exercise.load;
      subsetIntentFamilyLoad[exercise.family] =
          (subsetIntentFamilyLoad[exercise.family] ?? 0) + exercise.load;
      subsetRepRangeLoad[exercise.repBucket] =
          (subsetRepRangeLoad[exercise.repBucket] ?? 0) + exercise.load;
      if (exercise.trackRm) subsetTrackedRmLoad += exercise.load;
      if (exercise.compound) subsetCompoundLoad += exercise.load;
      if (exercise.isolation) subsetIsolationLoad += exercise.load;
      if (exercise.freeWeight) subsetFreeLoad += exercise.load;
      if (exercise.guided) subsetGuidedLoad += exercise.load;
      if (exercise.bodyweight) subsetBodyweightLoad += exercise.load;
      if (exercise.unilateral) {
        subsetUnilateralLoad += exercise.load;
      } else {
        subsetBilateralLoad += exercise.load;
      }
    }

    return TrainingIdentityInput(
      totalLoad: subsetTotalLoad,
      exerciseTypeLoad: subsetExerciseTypeLoad,
      blockTypeLoad: subsetBlockTypeLoad,
      intentFamilyLoad: subsetIntentFamilyLoad,
      repRangeLoad: subsetRepRangeLoad,
      trackedRmLoad: subsetTrackedRmLoad,
      bilateralLoad: subsetBilateralLoad,
      unilateralLoad: subsetUnilateralLoad,
      freeLoad: subsetFreeLoad,
      guidedLoad: subsetGuidedLoad,
      bodyweightLoad: subsetBodyweightLoad,
      compoundLoad: subsetCompoundLoad,
      isolationLoad: subsetIsolationLoad,
      exercises: list,
    );
  }

  Future<void> _calculateDetailedReview() async {
    reviewByDay.clear();
    extrasByDay.clear();
    sortedDayKeys.clear();

    final plannedSnap = await _plannedDocsInRange(rangeStart, rangeEnd);

    final Map<String, List<DayPlannedItem>> plannedByDay = {};
    for (final p in plannedSnap) {
      final data = p.data();
      final date = _plannedDate(data['date']);
      if (date == null) continue;
      final day = dayKey(date);
      final blockId = (data['blockId'] ?? '').toString();
      if (blockId.isNotEmpty) {
        final bDoc =
            await FirebaseFirestore.instance
                .collection('blocks')
                .doc(blockId)
                .get();
        final block = (bDoc.data() ?? {});
        plannedByDay
            .putIfAbsent(day, () => [])
            .addAll(_extractPlannedItemsFromBlock(block));
      }
    }

    final workoutsSnap =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(rangeEnd))
            .get();

    final Map<String, Map<String, double>> achievedByDay = {};
    // Nombre y movimiento de cada ejercicio hecho (misma clave que arriba),
    // para reconocer sustituciones por variante.
    final Map<String, Map<String, ({String name, String? movementId})>>
    achievedInfoByDay = {};
    for (final w in workoutsSnap.docs) {
      final data = w.data();
      final workoutDate = _plannedDate(data['date']);
      if (workoutDate == null) continue;
      final day = dayKey(workoutDate);

      // ✅ En workouts_logged la colección de bloques hechos es 'performed'
      final performed =
          (data['performed'] is List) ? List.from(data['performed']) : [];

      for (final pRaw in performed) {
        final p = Map<String, dynamic>.from(pRaw);
        final roundsList = (p['rounds'] is List) ? List.from(p['rounds']) : [];
        final bType = p['type']?.toString().toLowerCase() ?? '';

        // Determinar qué ejercicios procesar
        final List<Map<String, dynamic>> exercisesToProcess = [];

        if (bType == 'circuito' || bType == 'emom') {
          // En circuitos registrados, los ejercicios están DENTRO de cada ronda
          for (final roundRaw in roundsList) {
            final round = Map<String, dynamic>.from(roundRaw);
            final roundExs =
                (round['exercises'] is List)
                    ? List.from(round['exercises'])
                    : [];
            for (final exRaw in roundExs) {
              final ex = Map<String, dynamic>.from(exRaw);
              exercisesToProcess.add(
                ex,
              ); // Agregamos cada instancia (cada serie de la ronda)
            }
          }
        } else if (bType == 'tabata') {
          // Tabata suele tener ejercicios a nivel de bloque
          final exs = (p['exercises'] is List) ? List.from(p['exercises']) : [];
          for (final exRaw in exs) {
            exercisesToProcess.add(Map<String, dynamic>.from(exRaw));
          }
        } else {
          // Series normales
          final exs = (p['exercises'] is List) ? List.from(p['exercises']) : [];
          for (final exRaw in exs) {
            exercisesToProcess.add(Map<String, dynamic>.from(exRaw));
          }
        }

        for (final ex in exercisesToProcess) {
          final name = _normalizeExerciseName(ex['exercise'] ?? ex['name']);
          if (name.isEmpty) continue;

          double volume = 0;
          if (bType == 'series' ||
              bType == 'series descendentes' ||
              bType == 'buscar rm' ||
              bType == 'series plus') {
            final sets = (ex['sets'] is List) ? List.from(ex['sets']) : [];
            volume = sets.length.toDouble();
          } else if (bType == 'tabata') {
            // Tabata se cuenta por el número de rondas del bloque (está a nivel de p)
            final r =
                (p['rounds'] is num) ? (p['rounds'] as num).toDouble() : 1.0;
            volume = r;
          } else {
            // Circuitos / EMOM: cada entrada en exercisesToProcess ya es una "serie" (una ronda)
            volume = 1.0;
          }

          if (volume > 0) {
            achievedByDay.putIfAbsent(day, () => {});
            final key = "name:${_norm(name)}";
            achievedByDay[day]![key] = (achievedByDay[day]![key] ?? 0) + volume;
            achievedInfoByDay.putIfAbsent(day, () => {})[key] = (
              name: name,
              movementId: _movementIdOfExercise(ex),
            );
          }
        }
      }
      final extras =
          (data['extraExercises'] is List)
              ? List.from(data['extraExercises'])
              : [];
      for (final exRaw in extras) {
        final ex = Map<String, dynamic>.from(exRaw);
        extrasByDay.putIfAbsent(day, () => []).add({
          'name': ex['name'] ?? 'Extra',
          'volume': (ex['volume'] as num?)?.toDouble() ?? 0.0,
        });
      }
    }

    // --- Iniciar calculos de estadisticas globales ---
    weeklyPlannedVol = 0;
    weeklyAchievedVol = 0;
    plannedToDateVol = 0;
    achievedToDateVol = 0;
    plannedDaysCount = 0;
    achievedDaysCount = 0;

    final now = DateTime.now();
    final todayNormalized = DateTime(now.year, now.month, now.day);

    sortedDayKeys =
        {
            ...plannedByDay.keys,
            ...achievedByDay.keys,
            ...extrasByDay.keys,
          }.toList()
          ..sort();

    for (final dayKey in sortedDayKeys) {
      final parts = dayKey.split('-');
      final dayDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      final isPast = dayDate.isBefore(todayNormalized);
      final isToday = dayDate.isAtSameMomentAs(todayNormalized);
      final isPastOrToday = isPast || isToday;

      final plannedItems = plannedByDay[dayKey] ?? [];
      final achievedMap = achievedByDay[dayKey] ?? {};
      final dayExtras = extrasByDay[dayKey] ?? [];

      if (plannedItems.isNotEmpty) plannedDaysCount++;
      if (achievedMap.isNotEmpty || dayExtras.isNotEmpty) achievedDaysCount++;

      final results =
          plannedItems.map((p) {
            final totalAchieved = achievedMap[p.key] ?? 0.0;
            final consumed =
                totalAchieved > p.plannedVol ? p.plannedVol : totalAchieved;

            // Acumular globales
            weeklyPlannedVol += p.plannedVol;
            weeklyAchievedVol += consumed;

            // --- LÃ“GICA DE PACE AJUSTADA ---
            if (isPast) {
              plannedToDateVol +=
                  p.plannedVol; // Solo exigimos lo de ayer hacia atrás
            }
            if (isPastOrToday) {
              achievedToDateVol +=
                  consumed; // Pero contamos lo que lleves hoy para estar "adelantado"
            }

            // Restar del mapa para no duplicar en otros bloques si el key fuera igual
            achievedMap[p.key] = (achievedMap[p.key] ?? 0.0) - consumed;
            return DayResultItem(planned: p, achieved: consumed);
          }).toList();

      // Segunda pasada — sustitución por variante: si un ejercicio
      // planificado quedó en 0 y ese día se hizo OTRA variante del mismo
      // movimiento que sobró sin planificar, esa variante lo cumple. Sin
      // esto, cambiar "Remo pecho apoyado" por "Remo con barra" dejaba el
      // planificado como Pendiente aunque el trabajo sí se hizo.
      final achievedInfo = achievedInfoByDay[dayKey] ?? const {};
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        final movementId = r.planned.movementId;
        if (r.achieved > 0 || movementId == null) continue;
        final substituteKey = achievedMap.keys.firstWhere(
          (k) =>
              (achievedMap[k] ?? 0) > 0 &&
              achievedInfo[k]?.movementId == movementId,
          orElse: () => '',
        );
        if (substituteKey.isEmpty) continue;
        final available = achievedMap[substituteKey]!;
        final consumed =
            available > r.planned.plannedVol ? r.planned.plannedVol : available;
        achievedMap[substituteKey] = available - consumed;
        weeklyAchievedVol += consumed;
        if (isPastOrToday) achievedToDateVol += consumed;
        results[i] = DayResultItem(
          planned: r.planned,
          achieved: consumed,
          substitutedBy: achievedInfo[substituteKey]?.name,
        );
      }

      reviewByDay[dayKey] = results;

      // Sumar extras que sobraron al acumulado de volumen logrado
      achievedMap.forEach((_, vol) {
        weeklyAchievedVol += vol;
        if (isPastOrToday) achievedToDateVol += vol;
      });
      for (var extra in dayExtras) {
        final vol = (extra['volume'] as num).toDouble();
        weeklyAchievedVol += vol;
        if (isPastOrToday) achievedToDateVol += vol;
      }
    }

    if (sortedDayKeys.isNotEmpty) {
      selectedReviewDayKey = dayKey(DateTime.now());
      if (!sortedDayKeys.contains(selectedReviewDayKey)) {
        selectedReviewDayKey = sortedDayKeys.first;
      }
    }
  }

  /// Clave de matching planificado↔real para cumplimiento de carga: por
  /// VARIANTE exacta (`movementId::variantId`, o nombre normalizado si
  /// faltan ids). "Sentadilla con salto" y "Sentadilla con barra trasera"
  /// comparten `movementId` pero son ejercicios distintos y deben contarse
  /// por separado — solo se tratan como el mismo ejercicio (sustitución por
  /// equipo ocupado) cuando uno queda sin ejecutar y otro aparece como
  /// extra bajo el mismo `movementId`; eso se reconcilia aparte en
  /// `_reconcileVariantSubstitutions`, no acá.
  String _complianceKey(Map<String, dynamic> ex, String name) {
    final movementId = (ex['movementId'] ?? ex['exerciseId'])?.toString();
    final variantId = ex['variantId']?.toString();
    if (movementId != null && movementId.isNotEmpty) {
      return (variantId != null && variantId.isNotEmpty)
          ? 'mv:$movementId::$variantId'
          : 'mv:$movementId';
    }
    return 'name:${_norm(name)}';
  }

  /// `movementId` "padre" de una compliance key, para detectar sustituciones
  /// entre variantes del mismo movimiento. Devuelve null para claves por
  /// nombre (sin movementId conocido) — ahí no se puede inferir sustitución
  /// con seguridad.
  String? _movementIdOf(String complianceKey) {
    if (!complianceKey.startsWith('mv:')) return null;
    final rest = complianceKey.substring(3);
    final sep = rest.indexOf('::');
    return sep == -1 ? rest : rest.substring(0, sep);
  }

  /// Segunda pasada de reconciliación: si para un mismo `movementId` hay una
  /// variante planificada SIN ejecutar (0 series reales) y otra variante
  /// ejecutada SIN planificar (extra), se asume que la segunda reemplazó a
  /// la primera (ej. equipo ocupado) y se fusionan en una sola entrada — la
  /// planificada define `plannedSets`, la ejecutada define `achievedSets`.
  /// Variantes que SÍ tienen ambos lados (planificado y ejecutado) nunca se
  /// tocan: ya matchean por sí solas y no deben mezclarse con otra variante.
  void _reconcileVariantSubstitutions(
    Map<String, List<PlannedSetDetail>> plannedByKey,
    Map<String, List<AchievedSetDetail>> achievedByKey,
  ) {
    // Solo candidatas: planificado sin ejecución real bajo esa misma key.
    final unmetPlannedKeys =
        plannedByKey.keys
            .where((k) => (achievedByKey[k] ?? const []).isEmpty)
            .toList();
    // Solo candidatas: ejecutado sin nada planificado bajo esa misma key.
    final extraAchievedKeys =
        achievedByKey.keys
            .where((k) => (plannedByKey[k] ?? const []).isEmpty)
            .toList();
    if (unmetPlannedKeys.isEmpty || extraAchievedKeys.isEmpty) return;

    for (final plannedKey in unmetPlannedKeys) {
      final movementId = _movementIdOf(plannedKey);
      if (movementId == null) continue;
      final matchIndex = extraAchievedKeys.indexWhere(
        (k) => _movementIdOf(k) == movementId,
      );
      if (matchIndex == -1) continue;
      final achievedKey = extraAchievedKeys.removeAt(matchIndex);
      // Fusiona el ejecutado dentro de la key planificada y limpia la key
      // "extra" para que no se cuente dos veces como ítem separado.
      plannedByKey[plannedKey] = plannedByKey[plannedKey]!;
      achievedByKey[plannedKey] = achievedByKey.remove(achievedKey) ?? const [];
    }
  }

  /// Series planificadas por ejercicio (agrupadas por `_complianceKey`),
  /// para el cumplimiento de carga y su desglose. Espejo de
  /// `_extractPlannedItemsFromBlock` pero capturando peso/reps por serie en
  /// vez de solo contarlas.
  Map<String, List<PlannedSetDetail>> _extractPlannedSetDetails(
    Map<String, dynamic> block,
  ) {
    final out = <String, List<PlannedSetDetail>>{};
    final type = (block['type'] ?? '').toString().toLowerCase().trim();
    final exs =
        (block['exercises'] is List) ? List.from(block['exercises']) : const [];

    void addSets(
      String key,
      double weight,
      double reps,
      int sets,
      bool perSide,
      String? variantLabel,
    ) {
      if (weight <= 0 || reps <= 0 || sets <= 0) return;
      final effective = perSide ? weight * 2 : weight;
      out.putIfAbsent(key, () => []);
      for (var i = 0; i < sets; i++) {
        out[key]!.add(
          PlannedSetDetail(
            weight: effective,
            reps: reps,
            variantLabel: variantLabel,
          ),
        );
      }
    }

    if (type == 'series' ||
        type == 'series descendentes' ||
        type == 'buscar rm') {
      for (final exRaw in exs) {
        if (exRaw is! Map) continue;
        final ex = Map<String, dynamic>.from(exRaw);
        final name = _normalizeExerciseName(ex['name'] ?? ex['exercise']);
        if (name.isEmpty) continue;
        final sets = (ex['series'] is num) ? (ex['series'] as num).toInt() : 0;
        final reps = (ex['reps'] is num) ? (ex['reps'] as num).toDouble() : 0.0;
        final weight = (ex['weight'] as num?)?.toDouble() ?? 0.0;
        addSets(
          _complianceKey(ex, name),
          weight,
          reps,
          sets,
          ex['perSide'] == true,
          (ex['variantLabel'] ?? ex['techniqueLabel'])?.toString(),
        );
      }
    } else if (type == 'circuito' || type == 'emom') {
      final rounds =
          (block['rounds'] is num) ? (block['rounds'] as num).toInt() : 1;
      for (final exRaw in exs) {
        if (exRaw is! Map) continue;
        final ex = Map<String, dynamic>.from(exRaw);
        final name = _normalizeExerciseName(ex['name'] ?? ex['exercise']);
        if (name.isEmpty) continue;
        final reps = (ex['reps'] is num) ? (ex['reps'] as num).toDouble() : 0.0;
        final weight = (ex['weight'] as num?)?.toDouble() ?? 0.0;
        addSets(
          _complianceKey(ex, name),
          weight,
          reps,
          rounds,
          ex['perSide'] == true,
          (ex['variantLabel'] ?? ex['techniqueLabel'])?.toString(),
        );
      }
    }
    return out;
  }

  /// Series realmente ejecutadas por ejercicio (agrupadas por
  /// `_complianceKey`), leídas de `workouts_logged`. Mismo recorrido por
  /// tipo de bloque que ya usa `_calculateDetailedReview` para el conteo de
  /// series, pero capturando peso/reps/RPE/variante de cada serie.
  Map<String, List<AchievedSetDetail>> _extractAchievedSetDetails(
    Map<String, dynamic> data,
  ) {
    final out = <String, List<AchievedSetDetail>>{};
    final performed =
        (data['performed'] is List) ? List.from(data['performed']) : [];
    final date = _plannedDate(data['date']);

    void addSet(
      String key,
      double weight,
      double reps,
      double? rpe,
      bool perSide,
      String? variantLabel,
    ) {
      if (weight <= 0 || reps <= 0) return;
      final effective = perSide ? weight * 2 : weight;
      out.putIfAbsent(key, () => []);
      out[key]!.add(
        AchievedSetDetail(
          weight: effective,
          reps: reps,
          rpe: rpe,
          variantLabel: variantLabel,
          date: date,
        ),
      );
    }

    for (final pRaw in performed) {
      final p = Map<String, dynamic>.from(pRaw);
      final bType = p['type']?.toString().toLowerCase() ?? '';

      if (bType == 'circuito' || bType == 'emom') {
        final rounds = (p['rounds'] is List) ? List.from(p['rounds']) : [];
        for (final roundRaw in rounds) {
          final round = Map<String, dynamic>.from(roundRaw);
          final exs =
              (round['exercises'] is List) ? List.from(round['exercises']) : [];
          for (final exRaw in exs) {
            final ex = Map<String, dynamic>.from(exRaw);
            final name = _normalizeExerciseName(ex['exercise'] ?? ex['name']);
            if (name.isEmpty) continue;
            final weight = (ex['weight'] as num?)?.toDouble() ?? 0.0;
            final reps = (ex['reps'] as num?)?.toDouble() ?? 0.0;
            addSet(
              _complianceKey(ex, name),
              weight,
              reps,
              (ex['rpe'] as num?)?.toDouble(),
              ex['perSide'] == true,
              (ex['variantLabel'] ?? ex['techniqueLabel'])?.toString(),
            );
          }
        }
      } else if (bType == 'series' ||
          bType == 'series descendentes' ||
          bType == 'buscar rm' ||
          bType == 'series plus') {
        final exs = (p['exercises'] is List) ? List.from(p['exercises']) : [];
        for (final exRaw in exs) {
          final ex = Map<String, dynamic>.from(exRaw);
          final name = _normalizeExerciseName(ex['exercise'] ?? ex['name']);
          if (name.isEmpty) continue;
          final key = _complianceKey(ex, name);
          final variantLabel =
              (ex['variantLabel'] ?? ex['techniqueLabel'])?.toString();
          final exercisePerSide = ex['perSide'] == true;
          final sets = (ex['sets'] is List) ? List.from(ex['sets']) : [];
          for (final sRaw in sets) {
            final s = Map<String, dynamic>.from(sRaw);
            final weight = (s['weight'] as num?)?.toDouble() ?? 0.0;
            final reps = (s['reps'] as num?)?.toDouble() ?? 0.0;
            addSet(
              key,
              weight,
              reps,
              (s['rpe'] as num?)?.toDouble(),
              exercisePerSide || s['perSide'] == true,
              variantLabel,
            );
          }
        }
      }
      // Tabata no tiene peso relevante para esta comparación (bodyweight típico).
    }
    return out;
  }

  double _sumPlannedKg(List<PlannedSetDetail> sets) =>
      sets.fold(0.0, (sum, s) => sum + s.weight * s.reps);

  double _sumAchievedKg(List<AchievedSetDetail> sets) =>
      sets.fold(0.0, (sum, s) => sum + s.weight * s.reps);

  /// Cumplimiento de CARGA (kg) por ejercicio para la semana visible, y RPE
  /// real promedio. Reusa el mismo rango/colecciones que
  /// `_calculateDetailedReview` pero con una magnitud distinta (peso, no
  /// conteo de series) — ver comentario en `ExerciseLoadCompliance`.
  Future<void> _calculateWeightCompliance() async {
    exerciseLoadCompliance = [];
    weeklyPlannedKg = 0;
    weeklyAchievedKg = 0;
    weeklyAvgRpe = 0;
    exerciseLoadComplianceByDay = {};

    final plannedSnap = await _plannedDocsInRange(rangeStart, rangeEnd);
    final Map<String, List<PlannedSetDetail>> plannedByKey = {};
    final Map<String, Map<String, List<PlannedSetDetail>>> plannedByDayKey = {};
    final Map<String, Map<String, List<AchievedSetDetail>>> achievedByDayKey =
        {};
    final Map<String, String> displayNameByKey = {};
    final now = DateTime.now();
    final todayNormalized = DateTime(now.year, now.month, now.day);
    for (final p in plannedSnap) {
      final data = p.data();
      // "Ritmo a la fecha": solo exigimos lo planificado en días que ya
      // pasaron o es hoy. Días futuros de la semana no cuentan todavía como
      // "planificado" para el % — mismo criterio que ya usa el detalle
      // diario (`plannedToDateVol`), que esta card no estaba respetando y
      // por eso mostraba porcentajes bajos artificiales a mitad de semana.
      final plannedDate = _plannedDate(data['date']);
      if (plannedDate != null &&
          DateTime(
            plannedDate.year,
            plannedDate.month,
            plannedDate.day,
          ).isAfter(todayNormalized)) {
        continue;
      }
      final blockId = (data['blockId'] ?? '').toString();
      if (blockId.isEmpty) continue;
      final bDoc =
          await FirebaseFirestore.instance
              .collection('blocks')
              .doc(blockId)
              .get();
      final block = bDoc.data() ?? {};
      final exs =
          (block['exercises'] is List)
              ? List.from(block['exercises'])
              : const [];
      for (final exRaw in exs) {
        if (exRaw is! Map) continue;
        final ex = Map<String, dynamic>.from(exRaw);
        final name = _normalizeExerciseName(ex['name'] ?? ex['exercise']);
        if (name.isNotEmpty) displayNameByKey[_complianceKey(ex, name)] = name;
      }
      final details = _extractPlannedSetDetails(block);
      final plannedDay = plannedDate == null ? null : dayKey(plannedDate);
      details.forEach((key, sets) {
        plannedByKey.putIfAbsent(key, () => []).addAll(sets);
        if (plannedDay != null) {
          plannedByDayKey
              .putIfAbsent(plannedDay, () => {})
              .putIfAbsent(key, () => [])
              .addAll(sets);
        }
      });
    }

    final workoutsSnap =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(rangeEnd))
            .get();

    final Map<String, List<AchievedSetDetail>> achievedByKey = {};
    double rpeSum = 0;
    int rpeCount = 0;
    for (final w in workoutsSnap.docs) {
      final data = w.data();
      final details = _extractAchievedSetDetails(data);
      final workoutDate = _plannedDate(data['date']);
      final workoutDay = workoutDate == null ? null : dayKey(workoutDate);
      details.forEach((key, sets) {
        achievedByKey.putIfAbsent(key, () => []).addAll(sets);
        if (workoutDay != null) {
          achievedByDayKey
              .putIfAbsent(workoutDay, () => {})
              .putIfAbsent(key, () => [])
              .addAll(sets);
        }
        for (final s in sets) {
          if (s.rpe != null && s.rpe! > 0) {
            rpeSum += s.rpe!;
            rpeCount++;
          }
        }
      });
    }

    // Nombres de exhibición para ejercicios ejecutados sin match planificado
    // (extras / variantes nuevas): recorrer una vez más solo para nombres.
    for (final w in workoutsSnap.docs) {
      final performed =
          (w.data()['performed'] is List)
              ? List.from(w.data()['performed'])
              : [];
      for (final pRaw in performed) {
        final p = Map<String, dynamic>.from(pRaw);
        final bType = p['type']?.toString().toLowerCase() ?? '';
        void register(Map<String, dynamic> ex) {
          final name = _normalizeExerciseName(ex['exercise'] ?? ex['name']);
          if (name.isEmpty) return;
          displayNameByKey.putIfAbsent(_complianceKey(ex, name), () => name);
        }

        if (bType == 'circuito' || bType == 'emom') {
          for (final roundRaw
              in (p['rounds'] is List ? p['rounds'] : const [])) {
            final round = Map<String, dynamic>.from(roundRaw);
            for (final exRaw
                in (round['exercises'] is List
                    ? round['exercises']
                    : const [])) {
              register(Map<String, dynamic>.from(exRaw));
            }
          }
        } else {
          for (final exRaw
              in (p['exercises'] is List ? p['exercises'] : const [])) {
            register(Map<String, dynamic>.from(exRaw));
          }
        }
      }
    }

    _reconcileVariantSubstitutions(plannedByKey, achievedByKey);

    final allKeys = {...plannedByKey.keys, ...achievedByKey.keys};
    final list = <ExerciseLoadCompliance>[];
    for (final key in allKeys) {
      final plannedSets = plannedByKey[key] ?? const [];
      final achievedSets = achievedByKey[key] ?? const [];
      final plannedKg = _sumPlannedKg(plannedSets);
      final achievedKg = _sumAchievedKg(achievedSets);
      weeklyPlannedKg += plannedKg;
      weeklyAchievedKg += achievedKg;
      list.add(
        ExerciseLoadCompliance(
          name: displayNameByKey[key] ?? key,
          plannedKg: plannedKg,
          achievedKg: achievedKg,
          plannedSets: plannedSets,
          achievedSets: achievedSets,
        ),
      );
    }
    list.sort((a, b) => b.plannedKg.compareTo(a.plannedKg));
    exerciseLoadCompliance = list;
    weeklyAvgRpe = rpeCount > 0 ? rpeSum / rpeCount : 0;

    // Mismo cálculo, pero reconciliando y agrupando dentro de cada día.
    for (final day in {...plannedByDayKey.keys, ...achievedByDayKey.keys}) {
      final dayPlanned = plannedByDayKey[day] ?? {};
      final dayAchieved = achievedByDayKey[day] ?? {};
      _reconcileVariantSubstitutions(dayPlanned, dayAchieved);
      final dayList = <ExerciseLoadCompliance>[
        for (final key in {...dayPlanned.keys, ...dayAchieved.keys})
          ExerciseLoadCompliance(
            name: displayNameByKey[key] ?? key,
            plannedKg: _sumPlannedKg(dayPlanned[key] ?? const []),
            achievedKg: _sumAchievedKg(dayAchieved[key] ?? const []),
            plannedSets: dayPlanned[key] ?? const [],
            achievedSets: dayAchieved[key] ?? const [],
          ),
      ]..sort((a, b) => b.plannedKg.compareTo(a.plannedKg));
      exerciseLoadComplianceByDay[day] = dayList;
    }
  }

  double _resolveIdentityBaseSets({
    required String rawType,
    required int rounds,
    required Map<String, dynamic> block,
    required Map<String, dynamic> exercise,
  }) {
    if (rawType == 'circuito' || rawType == 'tabata' || rawType == 'emom') {
      return rounds.toDouble();
    }

    if (rawType == 'series descendentes' && block['schema'] is List) {
      return (block['schema'] as List).length.toDouble();
    }

    return (exercise['series'] as num?)?.toDouble() ?? 1.0;
  }

  double _resolveIdentityTargetReps({
    required String rawType,
    required Map<String, dynamic> block,
    required Map<String, dynamic> exercise,
    required TrainingIntentFamily family,
  }) {
    final valueType =
        (exercise['valueType'] ?? '').toString().toLowerCase().trim();
    final reps = (exercise['reps'] as num?)?.toDouble();
    final value = (exercise['value'] as num?)?.toDouble();

    if (rawType == 'series descendentes' && block['schema'] is List) {
      final schemaValues =
          (block['schema'] as List)
              .whereType<num>()
              .map((item) => item.toDouble())
              .where((item) => item > 0)
              .toList();
      if (schemaValues.isNotEmpty) {
        return schemaValues.reduce((a, b) => a + b) / schemaValues.length;
      }
    }

    if (reps != null && reps > 0) return reps;
    if (valueType == 'reps' && value != null && value > 0) return value;
    if (valueType == 'time' && value != null && value > 0) return value;

    final work = (block['work'] as num?)?.toDouble();
    if (rawType == 'tabata' && work != null && work > 0) return work;

    switch (family) {
      case TrainingIntentFamily.athleticPower:
        return 3;
      case TrainingIntentFamily.strength:
        return 5;
      case TrainingIntentFamily.hypertrophy:
      case TrainingIntentFamily.isolatedHypertrophy:
      case TrainingIntentFamily.accessory:
        return 10;
      case TrainingIntentFamily.bodyweight:
        return 8;
      case TrainingIntentFamily.stability:
        return 12;
      case TrainingIntentFamily.conditioning:
        return 20;
      case TrainingIntentFamily.unknown:
        return 8;
    }
  }

  double _resolveIdentityRepsEquivalent({
    required String rawType,
    required Map<String, dynamic> block,
    required Map<String, dynamic> exercise,
    required double targetReps,
    required TrainingIntentFamily family,
  }) {
    final valueType =
        (exercise['valueType'] ?? '').toString().toLowerCase().trim();

    if (valueType == 'time') {
      return TrainingIdentityService.timeRepsEquivalent(targetReps, family);
    }

    if (rawType == 'tabata') {
      final work = (block['work'] as num?)?.toDouble() ?? targetReps;
      return (work / 5).clamp(1.0, 30.0);
    }

    if (targetReps > 0) return targetReps;

    switch (family) {
      case TrainingIntentFamily.athleticPower:
        return 3;
      case TrainingIntentFamily.strength:
        return 5;
      case TrainingIntentFamily.hypertrophy:
      case TrainingIntentFamily.isolatedHypertrophy:
      case TrainingIntentFamily.accessory:
        return 10;
      case TrainingIntentFamily.bodyweight:
        return 8;
      case TrainingIntentFamily.stability:
        return 12;
      case TrainingIntentFamily.conditioning:
        return 20;
      case TrainingIntentFamily.unknown:
        return 8;
    }
  }

  double _applyIdentityExerciseLoad({
    required DateTime normalizedDate,
    required String source,
    required String setLabel,
    required String name,
    required String blockTitle,
    required String exType,
    required String trainingDiscipline,
    required String movementIntent,
    required String classificationOrigin,
    required num? durationSeconds,
    required double rounds,
    required String structureType,
    required Map<String, dynamic> weights,
    required double baseSets,
    required double targetReps,
    required double repsEquivalent,
    required double perSideMultiplier,
    required double factor,
    required double structFactor,
    required double volumeUnits,
    required TrainingIntentFamily family,
    Map<TrainingProfile, double> profileDistributionOverride = const {},
    required String repBucket,
    required double? referenceWeight,
    required double? historical1RM,
    required double? percent1RM,
    required String percent1RMBucket,
    double? reportedRpe,
    required bool trackRm,
    required bool inferredUnilateral,
    required bool inferredFree,
    required bool inferredGuided,
    required bool inferredBodyweight,
    required bool inferredCompound,
    required bool inferredIsolation,
    bool inferredRotational = false,
    String equipmentDescriptor = '',
  }) {
    double exerciseAccumulatedLoad = 0;
    final muscleLoads = <String, double>{};

    weights.forEach((muscle, value) {
      final load =
          volumeUnits * (value as num).toDouble() * factor * structFactor;
      exerciseAccumulatedLoad += load;
      muscleLoads[muscle] = load;

      dailyLoads[normalizedDate]![muscle] =
          (dailyLoads[normalizedDate]![muscle] ?? 0) + load;
      totalLoad[muscle] = (totalLoad[muscle] ?? 0) + load;
      exerciseTypeLoad[exType] = (exerciseTypeLoad[exType] ?? 0) + load;

      final detail = {
        'source': source,
        'setLabel': setLabel,
        'name': name,
        'sets': baseSets,
        'targetReps': targetReps,
        'repsEquivalent': repsEquivalent,
        'perSideMultiplier': perSideMultiplier,
        'volumeUnits': volumeUnits,
        'value': value.toDouble(),
        'factor': factor,
        'structFactor': structFactor,
        'load': load,
        'type': exType,
        'blockTitle': blockTitle,
        'date': normalizedDate,
        'muscle': muscle,
      };

      dailyDetails[normalizedDate]![muscle] ??= [];
      dailyDetails[normalizedDate]![muscle]!.add(detail);
      exerciseTypeDetails[exType] ??= [];
      exerciseTypeDetails[exType]!.add(detail);

      for (final group in AnatomicalGroup.values) {
        final musclesInGroup = anatomicalGroups[group] ?? [];
        if (musclesInGroup.any((m) => m.name == muscle)) {
          anatomicalGroupDetails[group] ??= [];
          anatomicalGroupDetails[group]!.add(detail);
        }
      }
    });

    intentFamilyLoad[family] =
        (intentFamilyLoad[family] ?? 0) + exerciseAccumulatedLoad;
    repRangeLoad[repBucket] =
        (repRangeLoad[repBucket] ?? 0) + exerciseAccumulatedLoad;
    if (trackRm) trackedRmLoad += exerciseAccumulatedLoad;
    if (inferredCompound) compoundLoad += exerciseAccumulatedLoad;
    if (inferredIsolation) isolationLoad += exerciseAccumulatedLoad;
    if (inferredFree) freeLoad += exerciseAccumulatedLoad;
    if (inferredGuided) guidedLoad += exerciseAccumulatedLoad;
    if (inferredBodyweight) bodyweightLoad += exerciseAccumulatedLoad;
    if (inferredUnilateral) {
      unilateralLoad += exerciseAccumulatedLoad;
    } else {
      bilateralLoad += exerciseAccumulatedLoad;
    }

    identityExercises.add(
      TrainingIdentityExerciseContribution(
        source: source,
        setLabel: setLabel,
        date: normalizedDate,
        name: name,
        blockTitle: blockTitle,
        exerciseType: exType,
        blockType: structureType,
        load: exerciseAccumulatedLoad,
        baseSets: baseSets,
        targetReps: targetReps,
        repsEquivalent: repsEquivalent,
        volumeUnits: volumeUnits,
        perSideMultiplier: perSideMultiplier,
        exerciseFactor: factor,
        structureFactor: structFactor,
        referenceWeight: referenceWeight,
        historical1RM: historical1RM,
        percent1RM: percent1RM,
        percent1RMBucket: percent1RMBucket,
        reportedRpe: reportedRpe,
        trackRm: trackRm,
        unilateral: inferredUnilateral,
        freeWeight: inferredFree,
        guided: inferredGuided,
        bodyweight: inferredBodyweight,
        equipmentDescriptor: equipmentDescriptor,
        compound: inferredCompound,
        isolation: inferredIsolation,
        rotational: inferredRotational,
        family: family,
        repBucket: repBucket,
        muscleLoads: muscleLoads,
        profileDistributionOverride: profileDistributionOverride,
        trainingDiscipline: trainingDiscipline,
        movementIntent: movementIntent,
        classificationOrigin: classificationOrigin,
        durationSeconds: durationSeconds?.toDouble(),
        rounds: rounds,
      ),
    );

    return exerciseAccumulatedLoad;
  }

  String _normalizeLoggedStructureType(String rawType) {
    switch (rawType.trim().toLowerCase()) {
      case 'circuito':
        return 'Circuito';
      case 'tabata':
        return 'Tabata';
      case 'emom':
        return 'EMOM';
      case 'series descendentes':
        return 'Series descendentes';
      case 'buscar rm':
        return 'Buscar RM';
      default:
        return 'Series';
    }
  }

  bool _shouldUseHistorical1RM(String exerciseType) {
    final normalized = exerciseType.toLowerCase().trim();
    return normalized.contains('fuerza') ||
        normalized.contains('hipertrofia') ||
        normalized.contains('weightlifting') ||
        normalized.contains('potencia');
  }

  List<Map<String, dynamic>> _buildPlannedIdentitySets({
    required String rawType,
    required int rounds,
    required Map<String, dynamic> block,
    required Map<String, dynamic> exercise,
    required double fallbackTargetReps,
    required double fallbackRepsEquivalent,
  }) {
    final out = <Map<String, dynamic>>[];
    final sets = List<Map<String, dynamic>>.from(exercise['sets'] ?? const []);

    if (sets.isNotEmpty) {
      // En circuito/tabata/EMOM las series resueltas describen UNA ronda: se
      // repiten por cada ronda del bloque (antes un circuito de 3 rondas
      // contaba 1 serie planificada contra 3 realizadas).
      final isRoundBased =
          rawType == 'circuito' || rawType == 'tabata' || rawType == 'emom';
      final count = isRoundBased && rounds > sets.length ? rounds : sets.length;
      // Por tiempo: `reps` son segundos; se usa la equivalencia seg/5 ya
      // calculada en el fallback (igual que lo realizado).
      final isTime = exercise['valueType']?.toString() == 'time';
      for (int i = 0; i < count; i++) {
        final set = sets[i < sets.length ? i : sets.length - 1];
        final reps = (set['reps'] as num?)?.toDouble() ?? fallbackTargetReps;
        final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
        final perSide = set['perSide'] == true || exercise['perSide'] == true;
        out.add({
          'targetReps': reps,
          'repsEquivalent':
              isTime
                  ? fallbackRepsEquivalent
                  : (reps > 0 ? reps : fallbackRepsEquivalent),
          'referenceWeight': weight,
          'perSide': perSide,
          'setLabel': isRoundBased ? 'Ronda ${i + 1}' : 'Serie ${i + 1}',
        });
      }
      return out;
    }

    final totalSets = _resolveIdentityBaseSets(
      rawType: rawType,
      rounds: rounds,
      block: block,
      exercise: exercise,
    ).round().clamp(1, 100);
    final directWeight = _extractPlannedReferenceWeight(exercise) ?? 0.0;
    final perSide = exercise['perSide'] == true;
    String prefix = 'Serie';
    if (rawType == 'tabata') {
      prefix = 'Tabata';
    } else if (rawType == 'circuito' || rawType == 'emom') {
      prefix = 'Ronda';
    }

    for (int i = 0; i < totalSets; i++) {
      out.add({
        'targetReps': fallbackTargetReps,
        'repsEquivalent': fallbackRepsEquivalent,
        'referenceWeight': directWeight,
        'perSide': perSide,
        'setLabel': '$prefix ${i + 1}',
      });
    }

    return out;
  }

  List<Map<String, dynamic>> _extractLoggedExercises(
    Map<String, dynamic> block,
  ) {
    final type = (block['type'] ?? '').toString().trim().toLowerCase();

    if (type == 'series' ||
        type == 'series descendentes' ||
        type == 'buscar rm') {
      final out = <Map<String, dynamic>>[];
      for (final rawExercise in List<Map<String, dynamic>>.from(
        block['exercises'] ?? const [],
      )) {
        final name = rawExercise['exercise'] ?? rawExercise['name'];
        final sets = List<Map<String, dynamic>>.from(rawExercise['sets'] ?? []);
        if (sets.isEmpty) {
          final reps = (rawExercise['reps'] as num?)?.toDouble() ?? 0.0;
          final weight = (rawExercise['weight'] as num?)?.toDouble() ?? 0.0;
          final perSide = rawExercise['perSide'] == true;
          out.add({
            'name': name,
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent': reps,
            'referenceWeight': weight,
            'perSide': perSide,
            'setLabel': 'Serie 1',
            'reportedRpe': (rawExercise['rpe'] as num?)?.toDouble(),
            'exerciseId': rawExercise['exerciseId'],
            'variantId': rawExercise['variantId'],
          });
          continue;
        }

        // Ejercicios por tiempo: `reps` son SEGUNDOS. Se tratan igual que
        // en lo planificado (duración + equivalencia seg/5) para que un trote
        // de 600 s no cuente como 600 repeticiones.
        final isTime = rawExercise['valueType']?.toString() == 'time';
        for (int i = 0; i < sets.length; i++) {
          final set = sets[i];
          final reps = (set['reps'] as num?)?.toDouble() ?? 0.0;
          final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
          final perSide =
              set['perSide'] == true || rawExercise['perSide'] == true;
          out.add({
            'name': name,
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent': isTime ? (reps / 5).clamp(1.0, 30.0) : reps,
            if (isTime) 'valueType': 'time',
            if (isTime) 'value': reps,
            'referenceWeight': weight,
            'perSide': perSide,
            'setLabel': 'Serie ${i + 1}',
            'reportedRpe': (set['rpe'] as num?)?.toDouble(),
            'exerciseId': rawExercise['exerciseId'],
            'variantId': rawExercise['variantId'],
          });
        }
      }
      return out;
    }

    if (type == 'circuito' || type == 'emom') {
      final out = <Map<String, dynamic>>[];
      int roundIndex = 0;
      for (final round in List<Map<String, dynamic>>.from(
        block['rounds'] ?? const [],
      )) {
        roundIndex += 1;
        for (final rawExercise in List<Map<String, dynamic>>.from(
          round['exercises'] ?? const [],
        )) {
          final reps = (rawExercise['reps'] as num?)?.toDouble() ?? 0.0;
          final weight = (rawExercise['weight'] as num?)?.toDouble() ?? 0.0;
          final perSide = rawExercise['perSide'] == true;
          final isTime = rawExercise['valueType']?.toString() == 'time';
          out.add({
            'name': rawExercise['exercise'] ?? rawExercise['name'],
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent':
                isTime
                    ? (reps / 5).clamp(1.0, 30.0)
                    : (reps <= 0 ? 10.0 : reps),
            if (isTime) 'valueType': 'time',
            if (isTime) 'value': reps,
            'referenceWeight': weight,
            'perSide': perSide,
            'setLabel': 'Ronda $roundIndex',
            'exerciseId': rawExercise['exerciseId'],
            'variantId': rawExercise['variantId'],
          });
        }
      }
      return out;
    }

    if (type == 'tabata') {
      final rounds = (block['rounds'] as num?)?.toDouble() ?? 1.0;
      final work = (block['work'] as num?)?.toDouble() ?? 20.0;
      final out = <Map<String, dynamic>>[];
      for (final rawExercise in List<Map<String, dynamic>>.from(
        block['exercises'] ?? const [],
      )) {
        final reps = (rawExercise['reps'] as num?)?.toDouble() ?? 0.0;
        final perSide = rawExercise['perSide'] == true;
        final referenceWeight =
            ((rawExercise['weight'] as num?)?.toDouble() ?? 0.0);
        for (int i = 0; i < rounds.toInt(); i++) {
          out.add({
            'name': rawExercise['exercise'] ?? rawExercise['name'],
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent': reps > 0 ? reps : (work / 5).clamp(1.0, 30.0),
            'referenceWeight': referenceWeight,
            'perSide': perSide,
            'setLabel': 'Tabata ${i + 1}',
            'exerciseId': rawExercise['exerciseId'],
            'variantId': rawExercise['variantId'],
          });
        }
      }
      return out;
    }

    return const [];
  }

  Map<String, double> _buildHistorical1RMByExercise(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final bestByExercise = <String, double>{};

    for (final doc in docs) {
      final performed = List<Map<String, dynamic>>.from(
        doc.data()['performed'] ?? const [],
      );
      final sets = WorkoutRMService.extractAllValidRMSetCandidates(performed);

      for (final set in sets) {
        final rawName = set['exercise']?.toString();
        final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
        final reps = (set['reps'] as num?)?.toInt() ?? 0;
        if (rawName == null ||
            rawName.trim().isEmpty ||
            weight <= 0 ||
            reps <= 0) {
          continue;
        }

        final normalizedName = WorkoutRMService.normalizeExerciseName(rawName);
        final estimated1RM = WorkoutRMService.estimate1RM(
          weight: weight,
          reps: reps,
        );
        final currentBest = bestByExercise[normalizedName] ?? 0.0;
        if (estimated1RM > currentBest) {
          bestByExercise[normalizedName] = estimated1RM;
        }
      }
    }

    return bestByExercise;
  }

  double? _extractPlannedReferenceWeight(Map<String, dynamic> exercise) {
    final directWeight = (exercise['weight'] as num?)?.toDouble();
    if (directWeight != null && directWeight > 0) {
      return directWeight;
    }

    final sets = List<Map<String, dynamic>>.from(exercise['sets'] ?? const []);
    final weights =
        sets
            .map((set) {
              final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
              if (weight <= 0) return 0.0;
              return weight;
            })
            .where((value) => value > 0)
            .toList();

    if (weights.isEmpty) return null;
    return weights.reduce((a, b) => a > b ? a : b);
  }

  double? _computePercent1RM({
    required double? referenceWeight,
    required double? historical1RM,
  }) {
    if (referenceWeight == null ||
        historical1RM == null ||
        referenceWeight <= 0 ||
        historical1RM <= 0) {
      return null;
    }
    return referenceWeight / historical1RM;
  }

  String _percent1RMBucket(double? percent1RM) {
    if (percent1RM == null || percent1RM <= 0) return 'unknown';
    if (percent1RM < 0.55) return '<55%';
    if (percent1RM < 0.60) return '55-60%';
    if (percent1RM < 0.65) return '60-65%';
    if (percent1RM < 0.70) return '65-70%';
    if (percent1RM < 0.75) return '70-75%';
    if (percent1RM < 0.80) return '75-80%';
    if (percent1RM < 0.85) return '80-85%';
    if (percent1RM < 0.90) return '85-90%';
    return '90%+';
  }

  static String dayKey(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  String _norm(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  String _normalizeExerciseName(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is List && raw.isNotEmpty) return raw.first.toString().trim();
    return raw.toString().trim();
  }

  List<DayPlannedItem> _extractPlannedItemsFromBlock(
    Map<String, dynamic> block,
  ) {
    final out = <DayPlannedItem>[];
    final type = (block['type'] ?? '').toString();
    final title = (block['title'] ?? block['name'] ?? '').toString().trim();
    final label = title.isNotEmpty ? "$type • $title" : type;
    final exs =
        (block['exercises'] is List) ? List.from(block['exercises']) : const [];

    final t = type.toLowerCase().trim();
    if (t == 'series' || t == 'series descendentes' || t == 'buscar rm') {
      for (final exRaw in exs) {
        if (exRaw is! Map) continue;
        final ex = Map<String, dynamic>.from(exRaw);
        final name = _normalizeExerciseName(ex['name'] ?? ex['exercise']);
        final sets =
            (ex['series'] is num) ? (ex['series'] as num).toDouble() : 0.0;
        if (name.isEmpty || sets <= 0) continue;
        out.add(
          DayPlannedItem(
            key: "name:${_norm(name)}",
            name: name,
            blockLabel: label,
            plannedVol: sets,
            movementId: _movementIdOfExercise(ex),
          ),
        );
      }
    } else if (t == 'circuito' || t == 'tabata' || t == 'emom') {
      final rounds =
          (block['rounds'] is num) ? (block['rounds'] as num).toDouble() : 1.0;
      for (final exRaw in exs) {
        if (exRaw is! Map) continue;
        final ex = Map<String, dynamic>.from(exRaw);
        final name = _normalizeExerciseName(ex['name'] ?? ex['exercise']);
        if (name.isEmpty) continue;
        out.add(
          DayPlannedItem(
            key: "name:${_norm(name)}",
            name: name,
            blockLabel: label,
            plannedVol: rounds,
            movementId: _movementIdOfExercise(ex),
          ),
        );
      }
    }
    return out;
  }

  String? _movementIdOfExercise(Map ex) {
    final id = (ex['movementId'] ?? ex['exerciseId'])?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Tendencia de cumplimiento (series % y kg %) y RPE real de las últimas
  /// [weeks] semanas (incluida la actual), para el gráfico de línea. Corre
  /// bajo demanda (no en `_loadAllData`) porque agrega varias semanas de
  /// `workouts_logged`/`planned_workouts`, más costoso que la vista semanal
  /// por defecto.
  Future<List<WeeklyComplianceSummary>> loadWeeklyTrend({int weeks = 6}) async {
    final summaries = <WeeklyComplianceSummary>[];
    for (int i = weeks - 1; i >= 0; i--) {
      final weekStart = rangeStart.subtract(Duration(days: 7 * i));
      final weekEnd = weekStart.add(const Duration(days: 7));

      final plannedSnap = await _plannedDocsInRange(weekStart, weekEnd);
      double plannedSeries = 0;
      double plannedKg = 0;
      for (final p in plannedSnap) {
        final blockId = (p.data()['blockId'] ?? '').toString();
        if (blockId.isEmpty) continue;
        final bDoc =
            await FirebaseFirestore.instance
                .collection('blocks')
                .doc(blockId)
                .get();
        final block = bDoc.data() ?? {};
        for (final item in _extractPlannedItemsFromBlock(block)) {
          plannedSeries += item.plannedVol;
        }
        _extractPlannedSetDetails(block).forEach((key, sets) {
          plannedKg += _sumPlannedKg(sets);
        });
      }

      final workoutsSnap =
          await FirebaseFirestore.instance
              .collection('workouts_logged')
              .where('userId', isEqualTo: athleteId)
              .where(
                'date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart),
              )
              .where('date', isLessThan: Timestamp.fromDate(weekEnd))
              .get();

      double achievedSeries = 0;
      double achievedKg = 0;
      double rpeSum = 0;
      int rpeCount = 0;
      for (final w in workoutsSnap.docs) {
        final data = w.data();
        final performed =
            (data['performed'] is List) ? List.from(data['performed']) : [];
        for (final pRaw in performed) {
          final p = Map<String, dynamic>.from(pRaw);
          final bType = p['type']?.toString().toLowerCase() ?? '';
          if (bType == 'series' ||
              bType == 'series descendentes' ||
              bType == 'buscar rm' ||
              bType == 'series plus') {
            for (final exRaw
                in (p['exercises'] is List ? p['exercises'] : const [])) {
              final ex = Map<String, dynamic>.from(exRaw);
              final sets = (ex['sets'] is List) ? List.from(ex['sets']) : [];
              achievedSeries += sets.length;
              for (final sRaw in sets) {
                final s = Map<String, dynamic>.from(sRaw);
                final rpe = (s['rpe'] as num?)?.toDouble();
                if (rpe != null && rpe > 0) {
                  rpeSum += rpe;
                  rpeCount++;
                }
              }
            }
          } else if (bType == 'circuito' || bType == 'emom') {
            for (final roundRaw
                in (p['rounds'] is List ? p['rounds'] : const [])) {
              final round = Map<String, dynamic>.from(roundRaw);
              for (final exRaw
                  in (round['exercises'] is List
                      ? round['exercises']
                      : const [])) {
                achievedSeries += 1;
                final ex = Map<String, dynamic>.from(exRaw);
                final rpe = (ex['rpe'] as num?)?.toDouble();
                if (rpe != null && rpe > 0) {
                  rpeSum += rpe;
                  rpeCount++;
                }
              }
            }
          } else if (bType == 'tabata') {
            final r = (p['rounds'] as num?)?.toDouble() ?? 1.0;
            achievedSeries += r;
          }
        }
        _extractAchievedSetDetails(data).forEach((key, sets) {
          achievedKg += _sumAchievedKg(sets);
        });
      }

      summaries.add(
        WeeklyComplianceSummary(
          weekStart: weekStart,
          seriesPct:
              plannedSeries > 0
                  ? (achievedSeries / plannedSeries).clamp(0, 2)
                  : 0,
          kgPct: plannedKg > 0 ? (achievedKg / plannedKg).clamp(0, 2) : 0,
          avgRpe: rpeCount > 0 ? rpeSum / rpeCount : 0,
        ),
      );
    }
    return summaries;
  }
}
