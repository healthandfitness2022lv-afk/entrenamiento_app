import '../models/muscle_catalog.dart';

enum TrainingProfile {
  powerlifting,
  athlete,
  hypertrophy,
  conditioning,
  bodyweight,
  hybrid,
}

extension TrainingProfileLabel on TrainingProfile {
  String get label {
    switch (this) {
      case TrainingProfile.powerlifting:
        return 'Fuerza máxima';
      case TrainingProfile.athlete:
        return 'Rendimiento';
      case TrainingProfile.hypertrophy:
        return 'Hipertrofia';
      case TrainingProfile.conditioning:
        return 'Acondicionamiento';
      case TrainingProfile.bodyweight:
        return 'Control y coordinación';
      case TrainingProfile.hybrid:
        return 'Híbrido';
    }
  }
}

enum TrainingIntentFamily {
  strength,
  athleticPower,
  hypertrophy,
  isolatedHypertrophy,
  accessory,
  bodyweight,
  stability,
  conditioning,
  unknown,
}

extension TrainingIntentFamilyLabel on TrainingIntentFamily {
  String get label {
    switch (this) {
      case TrainingIntentFamily.strength:
        return 'Fuerza';
      case TrainingIntentFamily.athleticPower:
        return 'Potencia deportiva';
      case TrainingIntentFamily.hypertrophy:
        return 'Hipertrofia';
      case TrainingIntentFamily.isolatedHypertrophy:
        return 'Musculación aislada';
      case TrainingIntentFamily.accessory:
        return 'Accesorios';
      case TrainingIntentFamily.bodyweight:
        return 'Control y coordinación';
      case TrainingIntentFamily.stability:
        return 'Estabilidad';
      case TrainingIntentFamily.conditioning:
        return 'Acondicionamiento';
      case TrainingIntentFamily.unknown:
        return 'Sin clasificar';
    }
  }
}

class TrainingIdentityInput {
  final Map<String, double> totalLoad;
  final Map<String, double> exerciseTypeLoad;
  final Map<String, double> blockTypeLoad;
  final Map<TrainingIntentFamily, double> intentFamilyLoad;
  final Map<String, double> repRangeLoad;
  final double trackedRmLoad;
  final double bilateralLoad;
  final double unilateralLoad;
  final double freeLoad;
  final double guidedLoad;
  final double bodyweightLoad;
  final double compoundLoad;
  final double isolationLoad;
  final List<TrainingIdentityExerciseContribution> exercises;

  const TrainingIdentityInput({
    required this.totalLoad,
    required this.exerciseTypeLoad,
    required this.blockTypeLoad,
    required this.intentFamilyLoad,
    required this.repRangeLoad,
    required this.trackedRmLoad,
    required this.bilateralLoad,
    required this.unilateralLoad,
    required this.freeLoad,
    required this.guidedLoad,
    required this.bodyweightLoad,
    required this.compoundLoad,
    required this.isolationLoad,
    required this.exercises,
  });
}

class TrainingIdentityExerciseContribution {
  final String source;
  final String setLabel;
  final DateTime date;
  final String name;
  final String blockTitle;
  final String exerciseType;
  final String blockType;
  final double load;
  final double baseSets;
  final double targetReps;
  final double repsEquivalent;
  final double volumeUnits;
  final double perSideMultiplier;
  final double exerciseFactor;
  final double structureFactor;
  final double? referenceWeight;
  final double? historical1RM;
  final double? percent1RM;
  final String percent1RMBucket;

  /// RPE reportado por el atleta al ejecutar la serie (1-10). Solo existe
  /// para `source == 'logged'`; el planificado no tiene esfuerzo percibido
  /// real. Cuando está presente, tiene prioridad sobre `percent1RM` (que
  /// depende de un RM histórico a menudo ausente) para estimar `intensity`.
  final double? reportedRpe;
  final bool trackRm;
  final bool unilateral;
  final bool freeWeight;
  final bool guided;
  final bool bodyweight;
  final bool compound;
  final bool isolation;

  /// Texto crudo del/los implemento(s) del catálogo (ej. "Barra",
  /// "Mancuernas", "Kettlebell", "Landmine"). A diferencia de `freeWeight`
  /// (que agrupa todo peso libre en un solo booleano), este campo permite
  /// distinguir un movimiento de halterofilia real con barra libre de la
  /// misma familia de movimiento ejecutada con landmine (potencia) o con
  /// mancuerna/kettlebell (balístico o metabólico según la dosis).
  final String equipmentDescriptor;

  /// El ejercicio genera torque rotacional deliberado (leñador, landmine
  /// snatch, lanzamiento lateral) o exige resistir la rotación del tronco
  /// (Pallof, plancha lateral). Sube el perfil `athlete`: el control
  /// rotacional de tronco es central en deportes de raqueta, lanzamiento y
  /// contacto, y hoy el modelo solo distinguía push/pull/superior/inferior.
  final bool rotational;
  final TrainingIntentFamily family;
  final String repBucket;
  final Map<String, double> muscleLoads;
  final Map<TrainingProfile, double> profileDistributionOverride;
  final Map<TrainingProfile, double> baseProfileDistribution;
  final Map<TrainingProfile, double> equipmentProfileModifiers;
  final Map<TrainingProfile, double> repsProfileModifiers;
  final Map<TrainingProfile, double> percent1RMProfileModifiers;
  final Map<TrainingProfile, double> coherenceProfileModifiers;
  final Map<TrainingProfile, double> blockProfileModifiers;
  final Map<TrainingProfile, double> attributeProfileModifiers;
  final Map<TrainingProfile, double> finalProfileContributions;

  /// Campos que exponen la cadena de cálculo completa de `analyze()` a
  /// nivel de esta serie individual, para que la UI pueda explicar "cómo se
  /// llegó a este número" sin recalcular nada por su cuenta:
  /// `baseValue = dose * technicalDoseMultiplier * intensity *
  /// baseProfileDistribution[perfil]`, y de ahí se multiplica en cadena por
  /// cada mapa de modificadores hasta `finalProfileContributions`.
  final double dose;
  final double technicalDoseMultiplier;
  final double intensity;
  final String doseClassification;

  /// Snapshot from the selected variant or an explicit planning override.
  /// These are deliberately strings so legacy Firestore documents remain readable.
  final String trainingDiscipline;
  final String movementIntent;
  final String classificationOrigin;
  final double? durationSeconds;
  final double rounds;

  const TrainingIdentityExerciseContribution({
    required this.source,
    required this.setLabel,
    required this.date,
    required this.name,
    required this.blockTitle,
    required this.exerciseType,
    required this.blockType,
    required this.load,
    required this.baseSets,
    required this.targetReps,
    required this.repsEquivalent,
    required this.volumeUnits,
    required this.perSideMultiplier,
    required this.exerciseFactor,
    required this.structureFactor,
    this.referenceWeight,
    this.historical1RM,
    this.percent1RM,
    this.percent1RMBucket = 'unknown',
    this.reportedRpe,
    required this.trackRm,
    required this.unilateral,
    required this.freeWeight,
    required this.guided,
    this.bodyweight = false,
    required this.compound,
    required this.isolation,
    this.equipmentDescriptor = '',
    this.rotational = false,
    required this.family,
    required this.repBucket,
    required this.muscleLoads,
    this.profileDistributionOverride = const {},
    this.baseProfileDistribution = const {},
    this.equipmentProfileModifiers = const {},
    this.repsProfileModifiers = const {},
    this.percent1RMProfileModifiers = const {},
    this.coherenceProfileModifiers = const {},
    this.blockProfileModifiers = const {},
    this.attributeProfileModifiers = const {},
    this.finalProfileContributions = const {},
    this.dose = 0,
    this.technicalDoseMultiplier = 1,
    this.intensity = 1,
    this.doseClassification = '',
    this.trainingDiscipline = '',
    this.movementIntent = '',
    this.classificationOrigin = 'estimated',
    this.durationSeconds,
    this.rounds = 1,
  });
}

class TrainingIdentityResult {
  final TrainingProfile primaryProfile;
  final TrainingProfile secondaryProfile;
  final Map<TrainingProfile, double> scores;
  final List<String> biases;
  final List<String> evidence;
  final Map<String, double> debugMetrics;
  final Map<TrainingProfile, Map<String, double>> scoreBreakdown;
  final List<TrainingIdentityExerciseContribution> exercises;

  const TrainingIdentityResult({
    required this.primaryProfile,
    required this.secondaryProfile,
    required this.scores,
    required this.biases,
    required this.evidence,
    required this.debugMetrics,
    required this.scoreBreakdown,
    required this.exercises,
  });
}

class TrainingIdentityService {
  static const List<TrainingProfile> _activeProfiles = [
    TrainingProfile.powerlifting,
    TrainingProfile.athlete,
    TrainingProfile.hypertrophy,
    TrainingProfile.conditioning,
    TrainingProfile.bodyweight,
  ];

  static const Map<String, Map<TrainingProfile, double>> _baseIntentByType = {
    'fuerza': {
      TrainingProfile.powerlifting: 0.58,
      TrainingProfile.athlete: 0.22,
      TrainingProfile.hypertrophy: 0.15,
      TrainingProfile.conditioning: 0.05,
      TrainingProfile.bodyweight: 0.00,
    },
    // Fuerza unilateral con carga libre o corporal: conserva el patrón de
    // fuerza, pero exige control activo de pelvis, rodilla y tronco.
    'fuerza unilateral': {
      TrainingProfile.powerlifting: 0.45,
      TrainingProfile.athlete: 0.20,
      TrainingProfile.hypertrophy: 0.12,
      TrainingProfile.conditioning: 0.03,
      TrainingProfile.bodyweight: 0.20,
    },
    'potencia': {
      TrainingProfile.powerlifting: 0.01,
      TrainingProfile.athlete: 0.68,
      TrainingProfile.hypertrophy: 0.06,
      TrainingProfile.conditioning: 0.25,
      TrainingProfile.bodyweight: 0.00,
    },
    // Los levantamientos olímpicos combinan potencia, recepción y control de
    // trayectorias complejas; no se interpretan como potencia "pura".
    'halterofilia': {
      TrainingProfile.powerlifting: 0.15,
      TrainingProfile.athlete: 0.37,
      TrainingProfile.hypertrophy: 0.02,
      TrainingProfile.conditioning: 0.10,
      TrainingProfile.bodyweight: 0.36,
    },
    // Sólo landmine con intención explosiva/de potencia. Un remo o press de
    // hipertrofia con landmine conserva la clasificación de su variante.
    'landmine potencia': {
      TrainingProfile.powerlifting: 0.03,
      TrainingProfile.athlete: 0.42,
      TrainingProfile.hypertrophy: 0.05,
      TrainingProfile.conditioning: 0.12,
      TrainingProfile.bodyweight: 0.38,
    },
    'pliometria': {
      TrainingProfile.powerlifting: 0.01,
      TrainingProfile.athlete: 0.42,
      TrainingProfile.hypertrophy: 0.03,
      TrainingProfile.conditioning: 0.12,
      // Saltar, aterrizar y desacelerar requieren control motor repetido;
      // por eso una parte sustancial alimenta Control y coordinación.
      TrainingProfile.bodyweight: 0.42,
    },
    'balistico': {
      TrainingProfile.powerlifting: 0.02,
      // La repetición alta aumenta la fatiga, pero no convierte por sí sola
      // un gesto balístico en cardio. Se conserva el predominio deportivo.
      TrainingProfile.athlete: 0.75,
      TrainingProfile.hypertrophy: 0.05,
      TrainingProfile.conditioning: 0.18,
      TrainingProfile.bodyweight: 0.00,
    },
    'hipertrofia': {
      TrainingProfile.powerlifting: 0.04,
      TrainingProfile.athlete: 0.06,
      TrainingProfile.hypertrophy: 0.90,
      TrainingProfile.conditioning: 0.00,
      TrainingProfile.bodyweight: 0.00,
    },
    // Un compuesto de hipertrofia (hack squat, presses, remos, etc.)
    // conserva una demanda relevante de fuerza y transferencia deportiva.
    'hipertrofia compuesta': {
      TrainingProfile.powerlifting: 0.18,
      TrainingProfile.athlete: 0.12,
      TrainingProfile.hypertrophy: 0.68,
      TrainingProfile.conditioning: 0.02,
      TrainingProfile.bodyweight: 0.00,
    },
    // Un aislado de hipertrofia también construye fuerza local, incluso en
    // máquina. No debe leerse como un estímulo puramente estético.
    'hipertrofia aislada': {
      TrainingProfile.powerlifting: 0.24,
      TrainingProfile.athlete: 0.08,
      TrainingProfile.hypertrophy: 0.58,
      TrainingProfile.conditioning: 0.02,
      TrainingProfile.bodyweight: 0.08,
    },
    'accesorio': {
      TrainingProfile.powerlifting: 0.02,
      TrainingProfile.athlete: 0.08,
      TrainingProfile.hypertrophy: 0.90,
      TrainingProfile.conditioning: 0.00,
      TrainingProfile.bodyweight: 0.00,
    },
    'aislamiento': {
      TrainingProfile.powerlifting: 0.24,
      TrainingProfile.athlete: 0.08,
      TrainingProfile.hypertrophy: 0.58,
      TrainingProfile.conditioning: 0.02,
      TrainingProfile.bodyweight: 0.08,
    },
    // Dominadas, fondos y flexiones son patrones básicos de fuerza relativa.
    // Mantienen una señal de control, pero menor que la calistenia técnica.
    'calistenia basica': {
      TrainingProfile.powerlifting: 0.32,
      TrainingProfile.athlete: 0.22,
      TrainingProfile.hypertrophy: 0.18,
      TrainingProfile.conditioning: 0.08,
      TrainingProfile.bodyweight: 0.20,
    },
    'calistenia': {
      TrainingProfile.powerlifting: 0.06,
      TrainingProfile.athlete: 0.30,
      TrainingProfile.hypertrophy: 0.12,
      TrainingProfile.conditioning: 0.10,
      TrainingProfile.bodyweight: 0.42,
    },
    'peso corporal': {
      TrainingProfile.powerlifting: 0.06,
      TrainingProfile.athlete: 0.30,
      TrainingProfile.hypertrophy: 0.12,
      TrainingProfile.conditioning: 0.10,
      TrainingProfile.bodyweight: 0.42,
    },
    'bodyweight': {
      TrainingProfile.powerlifting: 0.06,
      TrainingProfile.athlete: 0.30,
      TrainingProfile.hypertrophy: 0.12,
      TrainingProfile.conditioning: 0.10,
      TrainingProfile.bodyweight: 0.42,
    },
    'core': {
      TrainingProfile.powerlifting: 0.02,
      TrainingProfile.athlete: 0.46,
      TrainingProfile.hypertrophy: 0.12,
      TrainingProfile.conditioning: 0.00,
      TrainingProfile.bodyweight: 0.40,
    },
    'estabilidad': {
      TrainingProfile.powerlifting: 0.02,
      TrainingProfile.athlete: 0.46,
      TrainingProfile.hypertrophy: 0.12,
      TrainingProfile.conditioning: 0.00,
      TrainingProfile.bodyweight: 0.40,
    },
    // Trabajo de control articular, activación y prehabilitación. No es una
    // orientación de hipertrofia aunque a menudo use poleas, bandas o altas
    // repeticiones; su señal principal es de preparación deportiva.
    'correctivo': {
      TrainingProfile.powerlifting: 0.02,
      TrainingProfile.athlete: 0.28,
      TrainingProfile.hypertrophy: 0.02,
      TrainingProfile.conditioning: 0.08,
      TrainingProfile.bodyweight: 0.60,
    },
    'cardio': {
      TrainingProfile.powerlifting: 0.00,
      TrainingProfile.athlete: 0.28,
      TrainingProfile.hypertrophy: 0.02,
      TrainingProfile.conditioning: 0.70,
      TrainingProfile.bodyweight: 0.00,
    },
    'acondicionamiento': {
      TrainingProfile.powerlifting: 0.00,
      TrainingProfile.athlete: 0.26,
      TrainingProfile.hypertrophy: 0.02,
      TrainingProfile.conditioning: 0.72,
      TrainingProfile.bodyweight: 0.00,
    },
    'movilidad': {
      TrainingProfile.powerlifting: 0.00,
      TrainingProfile.athlete: 0.48,
      TrainingProfile.hypertrophy: 0.00,
      TrainingProfile.conditioning: 0.52,
      TrainingProfile.bodyweight: 0.00,
    },
    'metabolico': {
      TrainingProfile.powerlifting: 0.00,
      TrainingProfile.athlete: 0.18,
      TrainingProfile.hypertrophy: 0.08,
      TrainingProfile.conditioning: 0.74,
      TrainingProfile.bodyweight: 0.00,
    },
  };

  static TrainingIdentityResult analyze(TrainingIdentityInput input) {
    final totalIntentLoad = input.exercises.fold<double>(
      0,
      (sum, exercise) => sum + exercise.load,
    );

    double ratio(double value) {
      if (totalIntentLoad <= 0) return 0;
      return (value / totalIntentLoad).clamp(0.0, 1.0);
    }

    final strengthRatio = ratio(
      input.intentFamilyLoad[TrainingIntentFamily.strength] ?? 0,
    );
    final powerRatio = ratio(
      input.intentFamilyLoad[TrainingIntentFamily.athleticPower] ?? 0,
    );
    final hypertrophyRatio = ratio(
      (input.intentFamilyLoad[TrainingIntentFamily.hypertrophy] ?? 0) +
          (input.intentFamilyLoad[TrainingIntentFamily.isolatedHypertrophy] ??
              0),
    );
    final accessoryRatio = ratio(
      input.intentFamilyLoad[TrainingIntentFamily.accessory] ?? 0,
    );
    final bodyweightIntentRatio = ratio(
      input.intentFamilyLoad[TrainingIntentFamily.bodyweight] ?? 0,
    );
    final stabilityRatio = ratio(
      input.intentFamilyLoad[TrainingIntentFamily.stability] ?? 0,
    );
    final conditioningRatio = ratio(
      input.intentFamilyLoad[TrainingIntentFamily.conditioning] ?? 0,
    );

    final reps1to3 = ratio(input.repRangeLoad['1-3'] ?? 0);
    final reps4to6 = ratio(input.repRangeLoad['4-6'] ?? 0);
    final reps7to8 = ratio(input.repRangeLoad['7-8'] ?? 0);
    final reps9to10 = ratio(input.repRangeLoad['9-10'] ?? 0);
    final reps11to12 = ratio(input.repRangeLoad['11-12'] ?? 0);
    final reps13Plus = ratio(input.repRangeLoad['13+'] ?? 0);

    final bilateralRatio = ratio(input.bilateralLoad);
    final unilateralRatio = ratio(input.unilateralLoad);
    final freeRatio = ratio(input.freeLoad);
    final guidedRatio = ratio(input.guidedLoad);
    final bodyweightEquipmentRatio = ratio(input.bodyweightLoad);
    final compoundRatio = ratio(input.compoundLoad);
    final isolationRatio = ratio(input.isolationLoad);
    final trackedRmRatio = ratio(input.trackedRmLoad);

    final pushLoad = _sumMuscles(
      input.totalLoad,
      functionalGroups[FunctionalGroup.upperPush]!,
    );
    final pullLoad = _sumMuscles(
      input.totalLoad,
      functionalGroups[FunctionalGroup.upperPull]!,
    );
    final lowerLoad = _sumMuscles(
      input.totalLoad,
      functionalGroups[FunctionalGroup.lowerBody]!,
    );
    final upperLoad = pushLoad + pullLoad;
    final pushPullBalance = _balanceScore(pushLoad, pullLoad);
    final upperLowerBalance = _balanceScore(upperLoad, lowerLoad);

    final scores = {for (final profile in _activeProfiles) profile: 0.0};
    final scoreBreakdown = {
      for (final profile in _activeProfiles)
        profile: <String, double>{
          'Distribución base por tipo': 0,
          'Ajuste por repeticiones': 0,
          'Ajuste por porcentaje de 1RM': 0,
          'Coherencia entre intención e intensidad': 0,
          'Ajuste por estructura del bloque': 0,
          'Ajuste por implemento': 0,
          'Ajuste por atributos': 0,
          'Bonificación por equilibrio': 0,
        },
    };
    final scoredExercises = <TrainingIdentityExerciseContribution>[];

    for (final exercise in input.exercises) {
      final classification = _classificationFor(exercise);
      final configuredBase =
          exercise.profileDistributionOverride.isNotEmpty
              ? exercise.profileDistributionOverride
              : baseProfileDistributionForType(classification);
      final baseProfileDistribution = _filterActiveProfiles(
        _withRotationalControlBase(
          _withBodyweightBase(
            configuredBase,
            isBodyweight: exercise.bodyweight,
          ),
          isRotational: exercise.rotational,
          isUnilateral: exercise.unilateral,
        ),
      );
      final equipmentProfileModifiers = _filterActiveProfiles(
        equipmentModifiers(
          bodyweight: exercise.bodyweight,
          freeWeight: exercise.freeWeight,
          guided: exercise.guided,
          compound: exercise.compound,
        ),
      );
      final repsProfileModifiers = _filterActiveProfiles(
        repsModifiers(exercise.repBucket),
      );
      // El RPE real reportado (solo existe para 'logged') es más fiel que el
      // %1RM derivado de un RM histórico, que hoy suele no existir. Cuando
      // hay RPE, se deriva un %1RM efectivo a partir de él para no dejar
      // este modificador apagado en 'unknown' por falta de RM guardado.
      final effectivePercent1RM =
          exercise.reportedRpe != null
              ? percent1RMFromRpe(
                rpe: exercise.reportedRpe!,
                reps: exercise.repsEquivalent,
              )
              : exercise.percent1RM;
      final effectivePercent1RMBucket =
          exercise.reportedRpe != null
              ? percent1RMBucketFor(effectivePercent1RM)
              : exercise.percent1RMBucket;
      final percent1RMProfileModifiers = _filterActiveProfiles(
        percent1RMModifiers(effectivePercent1RMBucket),
      );
      final coherenceProfileModifiers = _filterActiveProfiles(
        intentCoherenceModifiers(
          exerciseType: exercise.exerciseType,
          repBucket: exercise.repBucket,
          percent1RMBucket: effectivePercent1RMBucket,
          blockType: exercise.blockType,
          compound: exercise.compound,
        ),
      );
      final blockProfileModifiers = _filterActiveProfiles(
        blockModifiers(exercise.blockType),
      );
      final attributeProfileModifiers = _filterActiveProfiles(
        attributeModifiers(
          trackRm: exercise.trackRm,
          unilateral: exercise.unilateral,
          freeWeight: exercise.freeWeight,
          compound: exercise.compound,
          isolation: exercise.isolation,
          bodyweight: exercise.bodyweight,
          rotational: exercise.rotational,
        ),
      );

      // The profile is driven by declared intent and real dose, never by
      // muscle-weighted load. A side doubles work, not relative intensity.
      // Both sides count fully for muscular volume. For orientation, the
      // second side has diminishing returns so a unilateral hypertrophy
      // accessory does not dominate the weekly profile by itself.
      final isHypertrophyOrientation =
          classification.toLowerCase().contains('hipertrof') ||
          classification.toLowerCase().contains('accesor');
      final profileSideMultiplier =
          exercise.perSideMultiplier >= 2
              ? (exercise.rotational
                  ? 1.15
                  : (isHypertrophyOrientation ? 1.2 : 1.5))
              : exercise.perSideMultiplier;
      final dose =
          exercise.durationSeconds != null && exercise.durationSeconds! > 0
              ? (exercise.durationSeconds! / 60) * exercise.rounds.clamp(1, 99)
              : (exercise.baseSets *
                  (exercise.repsEquivalent > 0 ? exercise.repsEquivalent : 1) *
                  profileSideMultiplier);
      final intensity =
          effectivePercent1RM == null
              ? 1.0
              : (0.75 + (effectivePercent1RM * 0.5)).clamp(0.75, 1.25);

      final finalProfileContributions = <TrainingProfile, double>{};
      for (final profile in _activeProfiles) {
        final baseValue =
            dose *
            _technicalDoseMultiplier(classification) *
            intensity *
            (baseProfileDistribution[profile] ?? 0);
        final afterEquipment =
            baseValue * (equipmentProfileModifiers[profile] ?? 1);
        final afterReps = afterEquipment * (repsProfileModifiers[profile] ?? 1);
        final afterPercent =
            afterReps * (percent1RMProfileModifiers[profile] ?? 1);
        final afterIntent =
            afterPercent * (coherenceProfileModifiers[profile] ?? 1);
        final afterBlock = afterIntent * (blockProfileModifiers[profile] ?? 1);
        final finalValue =
            afterBlock * (attributeProfileModifiers[profile] ?? 1);

        finalProfileContributions[profile] = finalValue;
        scores[profile] = scores[profile]! + finalValue;
        scoreBreakdown[profile]!['Distribución base por tipo'] =
            scoreBreakdown[profile]!['Distribución base por tipo']! + baseValue;
        scoreBreakdown[profile]!['Ajuste por implemento'] =
            scoreBreakdown[profile]!['Ajuste por implemento']! +
            (afterEquipment - baseValue);
        scoreBreakdown[profile]!['Ajuste por repeticiones'] =
            scoreBreakdown[profile]!['Ajuste por repeticiones']! +
            (afterReps - afterEquipment);
        scoreBreakdown[profile]!['Ajuste por porcentaje de 1RM'] =
            scoreBreakdown[profile]!['Ajuste por porcentaje de 1RM']! +
            (afterPercent - afterReps);
        scoreBreakdown[profile]!['Coherencia entre intención e intensidad'] =
            scoreBreakdown[profile]!['Coherencia entre intención e intensidad']! +
            (afterIntent - afterPercent);
        scoreBreakdown[profile]!['Ajuste por estructura del bloque'] =
            scoreBreakdown[profile]!['Ajuste por estructura del bloque']! +
            (afterBlock - afterIntent);
        scoreBreakdown[profile]!['Ajuste por atributos'] =
            scoreBreakdown[profile]!['Ajuste por atributos']! +
            (finalValue - afterBlock);
      }

      _applyCircuitConditioningBonus(
        exercise: exercise,
        contributions: finalProfileContributions,
        scores: scores,
        scoreBreakdown: scoreBreakdown,
      );
      _applyHighRepStrengthTransfer(
        exercise: exercise,
        contributions: finalProfileContributions,
        scores: scores,
        scoreBreakdown: scoreBreakdown,
        referencePowerlifting:
            dose *
            _technicalDoseMultiplier(classification) *
            intensity *
            (baseProfileDistribution[TrainingProfile.powerlifting] ?? 0) *
            (equipmentProfileModifiers[TrainingProfile.powerlifting] ?? 1) *
            (repsModifiers('9-10')[TrainingProfile.powerlifting] ?? 1) *
            (percent1RMProfileModifiers[TrainingProfile.powerlifting] ?? 1) *
            (intentCoherenceModifiers(
                  exerciseType: exercise.exerciseType,
                  repBucket: '9-10',
                  percent1RMBucket: effectivePercent1RMBucket,
                  blockType: exercise.blockType,
                  compound: exercise.compound,
                )[TrainingProfile.powerlifting] ??
                1) *
            (blockProfileModifiers[TrainingProfile.powerlifting] ?? 1) *
            (attributeProfileModifiers[TrainingProfile.powerlifting] ?? 1),
      );

      scoredExercises.add(
        TrainingIdentityExerciseContribution(
          source: exercise.source,
          setLabel: exercise.setLabel,
          date: exercise.date,
          name: exercise.name,
          blockTitle: exercise.blockTitle,
          exerciseType: exercise.exerciseType,
          blockType: exercise.blockType,
          load: exercise.load,
          baseSets: exercise.baseSets,
          targetReps: exercise.targetReps,
          repsEquivalent: exercise.repsEquivalent,
          volumeUnits: exercise.volumeUnits,
          perSideMultiplier: exercise.perSideMultiplier,
          exerciseFactor: exercise.exerciseFactor,
          structureFactor: exercise.structureFactor,
          referenceWeight: exercise.referenceWeight,
          historical1RM: exercise.historical1RM,
          percent1RM: exercise.percent1RM,
          percent1RMBucket: exercise.percent1RMBucket,
          trackRm: exercise.trackRm,
          unilateral: exercise.unilateral,
          freeWeight: exercise.freeWeight,
          guided: exercise.guided,
          bodyweight: exercise.bodyweight,
          compound: exercise.compound,
          isolation: exercise.isolation,
          family: exercise.family,
          repBucket: exercise.repBucket,
          muscleLoads: exercise.muscleLoads,
          profileDistributionOverride: exercise.profileDistributionOverride,
          baseProfileDistribution: baseProfileDistribution,
          equipmentProfileModifiers: equipmentProfileModifiers,
          repsProfileModifiers: repsProfileModifiers,
          percent1RMProfileModifiers: percent1RMProfileModifiers,
          coherenceProfileModifiers: coherenceProfileModifiers,
          blockProfileModifiers: blockProfileModifiers,
          attributeProfileModifiers: attributeProfileModifiers,
          finalProfileContributions: finalProfileContributions,
          dose: dose,
          technicalDoseMultiplier: _technicalDoseMultiplier(classification),
          intensity: intensity,
          doseClassification: classification,
        ),
      );
    }

    // Scale balance adjustments with the analyzed workload so their relative
    // effect is stable in both short and high-volume weeks.
    final balanceScale = totalIntentLoad * 0.04;
    // Reps altas que sí cuentan como acondicionamiento: en fuerza fuera de
    // circuitos solo sobre 15 reps (11-15 reps de fuerza es musculación).
    final highRepConditioningRatio = ratio(
      input.exercises
          .where((e) {
            if (e.targetReps <= 10) return false;
            if (_isStrengthType(e.exerciseType) &&
                !_isMetabolicBlock(e.blockType)) {
              return e.targetReps > 15;
            }
            return true;
          })
          .fold<double>(0, (sum, e) => sum + e.load),
    );
    final balanceBonuses = <TrainingProfile, double>{
      TrainingProfile.powerlifting:
          balanceScale *
          ((bilateralRatio * 0.45) +
              (compoundRatio * 0.40) -
              (conditioningRatio * 0.20)),
      TrainingProfile.athlete:
          balanceScale *
          ((upperLowerBalance * 0.30) +
              (pushPullBalance * 0.30) +
              (unilateralRatio * 0.20) +
              (powerRatio * 0.20)),
      TrainingProfile.hypertrophy:
          balanceScale *
          ((guidedRatio * 0.35) +
              (isolationRatio * 0.25) +
              (hypertrophyRatio * 0.40)),
      TrainingProfile.conditioning:
          balanceScale *
          ((conditioningRatio * 0.45) +
              (highRepConditioningRatio * 0.35) +
              (upperLowerBalance * 0.20)),
      TrainingProfile.bodyweight:
          balanceScale *
          ((bodyweightEquipmentRatio * 0.60) +
              (unilateralRatio * 0.15) +
              (upperLowerBalance * 0.25)),
    };

    for (final profile in _activeProfiles) {
      final bonus = balanceBonuses[profile] ?? 0;
      scoreBreakdown[profile]!['Bonificación por equilibrio'] = bonus;
      scores[profile] = (scores[profile]! + bonus).clamp(0.0, double.infinity);
    }

    // Keep one weekly orientation from becoming disproportionate: a dominant
    // profile is capped at 70% and the excess is redistributed proportionally.
    _rebalanceDominantProfile(scores, scoreBreakdown);

    final ordered =
        scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final biases = <String>[];
    if (pushLoad > 0 && pullLoad > 0) {
      final ratioVal =
          pushLoad > pullLoad ? pushLoad / pullLoad : pullLoad / pushLoad;
      if (ratioVal >= 1.3) {
        biases.add(
          pushLoad > pullLoad
              ? 'Predominio de empuje'
              : 'Predominio de tracción',
        );
      }
    }
    if (upperLoad > 0 && lowerLoad > 0) {
      final ratioVal =
          upperLoad > lowerLoad ? upperLoad / lowerLoad : lowerLoad / upperLoad;
      if (ratioVal >= 1.25) {
        biases.add(
          upperLoad > lowerLoad
              ? 'Predominio de tren superior'
              : 'Predominio de tren inferior',
        );
      }
    }
    if (unilateralRatio >= 0.3) biases.add('Predominio unilateral');
    if (bilateralRatio >= 0.7) biases.add('Predominio bilateral');
    if (guidedRatio >= 0.45) biases.add('Predominio de máquinas y poleas');
    if (freeRatio >= 0.6) biases.add('Predominio de peso libre');
    if (bodyweightEquipmentRatio >= 0.3) {
      biases.add('Predominio de peso corporal');
    }
    if (powerRatio >= 0.2) biases.add('Orientación a la potencia');
    if (stabilityRatio >= 0.2) {
      biases.add('Trabajo correctivo y de estabilidad');
    }
    if (conditioningRatio >= 0.3) {
      biases.add('Orientación al acondicionamiento');
    }
    if (hypertrophyRatio + accessoryRatio >= 0.45) {
      biases.add('Desarrollo muscular localizado');
    }

    final evidence = <String>[
      'Intención por familia: Fuerza ${(strengthRatio * 100).toStringAsFixed(0)}% · Potencia ${(powerRatio * 100).toStringAsFixed(0)}% · Hipertrofia ${(hypertrophyRatio * 100).toStringAsFixed(0)}% · Accesorios ${(accessoryRatio * 100).toStringAsFixed(0)}% · Correctivos ${(stabilityRatio * 100).toStringAsFixed(0)}% · Control y coordinación ${(bodyweightIntentRatio * 100).toStringAsFixed(0)}%',
      'Repeticiones objetivo: 1-3 ${(reps1to3 * 100).toStringAsFixed(0)}% · 4-6 ${(reps4to6 * 100).toStringAsFixed(0)}% · 7-8 ${(reps7to8 * 100).toStringAsFixed(0)}% · 9-10 ${(reps9to10 * 100).toStringAsFixed(0)}% · 11-12 ${(reps11to12 * 100).toStringAsFixed(0)}% · 13+ ${(reps13Plus * 100).toStringAsFixed(0)}%',
      'Implementos: peso libre ${(freeRatio * 100).toStringAsFixed(0)}% · guiado ${(guidedRatio * 100).toStringAsFixed(0)}% · peso corporal ${(bodyweightEquipmentRatio * 100).toStringAsFixed(0)}%',
      'Estructura: bilateral ${(bilateralRatio * 100).toStringAsFixed(0)}% · unilateral ${(unilateralRatio * 100).toStringAsFixed(0)}% · compuesto ${(compoundRatio * 100).toStringAsFixed(0)}% · aislamiento ${(isolationRatio * 100).toStringAsFixed(0)}%',
      'Seguimiento: RM y progresión ${(trackedRmRatio * 100).toStringAsFixed(0)}%',
    ];

    return TrainingIdentityResult(
      primaryProfile: ordered.first.key,
      secondaryProfile: ordered[1].key,
      scores: scores,
      biases: biases,
      evidence: evidence,
      debugMetrics: {
        'strengthRatio': strengthRatio,
        'powerRatio': powerRatio,
        'hypertrophyRatio': hypertrophyRatio,
        'accessoryRatio': accessoryRatio,
        'bodyweightIntentRatio': bodyweightIntentRatio,
        'bodyweightEquipmentRatio': bodyweightEquipmentRatio,
        'stabilityRatio': stabilityRatio,
        'conditioningRatio': conditioningRatio,
        'reps1to3': reps1to3,
        'reps4to6': reps4to6,
        'reps7to8': reps7to8,
        'reps9to10': reps9to10,
        'reps11to12': reps11to12,
        'reps13Plus': reps13Plus,
        'bilateralRatio': bilateralRatio,
        'unilateralRatio': unilateralRatio,
        'freeRatio': freeRatio,
        'guidedRatio': guidedRatio,
        'compoundRatio': compoundRatio,
        'isolationRatio': isolationRatio,
        'trackedRmRatio': trackedRmRatio,
        'pushPullBalance': pushPullBalance,
        'upperLowerBalance': upperLowerBalance,
      },
      scoreBreakdown: scoreBreakdown,
      exercises: scoredExercises,
    );
  }

  /// Repeticiones equivalentes de un ejercicio por tiempo ([seconds]).
  /// - Cardio/acondicionamiento continuo: 1 rep equivalente por minuto
  ///   (10 min de trote ≈ una serie de 10), porque es esfuerzo sostenido de
  ///   baja intensidad. Antes usaba seg/5 y 600 s daba el tope de 30 (tres
  ///   series duras).
  /// - Resto (isometrías, planchas, trabajos cortos): 1 rep cada 5 s.
  static double timeRepsEquivalent(
    double seconds,
    TrainingIntentFamily family,
  ) {
    if (seconds <= 0) return 1.0;
    if (family == TrainingIntentFamily.conditioning) {
      return (seconds / 60).clamp(1.0, 30.0);
    }
    return (seconds / 5).clamp(1.0, 30.0);
  }

  static bool _isStrengthType(String exerciseType) =>
      _normalizeText(exerciseType).contains('fuerza');

  static bool _isMetabolicBlock(String blockType) {
    final b = _normalizeText(blockType);
    return b == 'tabata' || b == 'circuito' || b == 'emom';
  }

  /// Ejercicio de fuerza con más de 10 repeticiones (fuera de circuitos):
  /// sigue siendo fuerza/musculación, no acondicionamiento.
  /// - Lo que pierde de Fuerza máxima respecto de hacerlo a 9-10 reps no
  ///   desaparece: pasa 75% a Hipertrofia y 25% a Control y coordinación.
  /// - Hasta 15 reps no suma a Acondicionamiento (se reparte igual); recién
  ///   sobre 15 conserva su aporte a Acondicionamiento.
  static void _applyHighRepStrengthTransfer({
    required TrainingIdentityExerciseContribution exercise,
    required Map<TrainingProfile, double> contributions,
    required Map<TrainingProfile, double> scores,
    required Map<TrainingProfile, Map<String, double>> scoreBreakdown,
    required double referencePowerlifting,
  }) {
    if (!_isStrengthType(exercise.exerciseType)) return;
    if (_isMetabolicBlock(exercise.blockType)) return;
    final reps = exercise.targetReps;
    if (reps <= 10) return;

    final currentPl = contributions[TrainingProfile.powerlifting] ?? 0;
    var moved = (referencePowerlifting - currentPl).clamp(0.0, double.infinity);
    final conditioning = contributions[TrainingProfile.conditioning] ?? 0;
    if (reps <= 15 && conditioning > 0) {
      moved += conditioning;
      _shiftContribution(
        TrainingProfile.conditioning,
        -conditioning,
        contributions,
        scores,
        scoreBreakdown,
      );
    }
    if (moved <= 0) return;
    _shiftContribution(
      TrainingProfile.hypertrophy,
      moved * 0.75,
      contributions,
      scores,
      scoreBreakdown,
    );
    _shiftContribution(
      TrainingProfile.bodyweight,
      moved * 0.25,
      contributions,
      scores,
      scoreBreakdown,
    );
  }

  static void _shiftContribution(
    TrainingProfile profile,
    double delta,
    Map<TrainingProfile, double> contributions,
    Map<TrainingProfile, double> scores,
    Map<TrainingProfile, Map<String, double>> scoreBreakdown, {
    String breakdownKey = 'Ajuste por repeticiones',
  }) {
    if (!scores.containsKey(profile)) return;
    contributions[profile] = (contributions[profile] ?? 0) + delta;
    scores[profile] = scores[profile]! + delta;
    final breakdown = scoreBreakdown[profile];
    if (breakdown != null) {
      breakdown[breakdownKey] = (breakdown[breakdownKey] ?? 0) + delta;
    }
  }

  /// Proporción del aporte de un ejercicio que un bloque Circuito suma
  /// adicionalmente a Acondicionamiento.
  static const double circuitConditioningBonus = 0.20;

  /// Plus de Acondicionamiento por hacer el ejercicio dentro de un circuito:
  /// todos los ejercicios de la ronda van seguidos y acumulan volumen sin
  /// descanso, sin importar el tipo de ejercicio. Es un plus que se suma
  /// (antes era solo un multiplicador ×1.22 sobre el Acondicionamiento propio
  /// del ejercicio, que en hipertrofia/accesorios/aislados es 0, así que un
  /// circuito de esos no sumaba nada).
  static void _applyCircuitConditioningBonus({
    required TrainingIdentityExerciseContribution exercise,
    required Map<TrainingProfile, double> contributions,
    required Map<TrainingProfile, double> scores,
    required Map<TrainingProfile, Map<String, double>> scoreBreakdown,
  }) {
    if (_normalizeText(exercise.blockType) != 'circuito') return;
    final total = contributions.values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    _shiftContribution(
      TrainingProfile.conditioning,
      total * circuitConditioningBonus,
      contributions,
      scores,
      scoreBreakdown,
      breakdownKey: 'Ajuste por estructura del bloque',
    );
  }

  /// Priority: explicit planning override, variant snapshot, base exercise,
  /// then the legacy type (which is shown as estimated by the caller).
  static String _classificationFor(
    TrainingIdentityExerciseContribution exercise,
  ) {
    final value =
        '${exercise.movementIntent} ${exercise.trainingDiscipline}'
            .toLowerCase();
    final legacyName = _normalizeText(exercise.name);
    final normalizedType = _normalizeText(exercise.exerciseType);
    if (value.contains('acondicion') || value.contains('metabol')) {
      return 'acondicionamiento';
    }
    // La pliometría mantiene su propia distribución: potencia atlética y
    // control de aterrizaje/desaceleración. No debe caer en el cambio
    // genérico Potencia/Balístico definido para variantes balísticas.
    if (value.contains('pliometr') || normalizedType.contains('pliometr')) {
      return 'pliometria';
    }
    // `trainingDiscipline` es el dato explícito de la VARIANTE elegida (ej.
    // la variante "Mancuernas" de Clean & Jerk ya trae
    // trainingDiscipline: 'balistico'), mientras que `exerciseType` es el
    // tipo heredado de la familia de movimiento entera y sigue diciendo
    // "Halterofilia" para todas sus variantes. Cuando la variante ya
    // declaró una disciplina distinta a halterofilia, esa declaración
    // explícita tiene prioridad y no se debe re-derivar del implemento.
    final hasExplicitNonWeightliftingDiscipline =
        exercise.trainingDiscipline.trim().isNotEmpty &&
        !_normalizeText(exercise.trainingDiscipline).contains('halterof');
    final isWeightliftingMovement =
        !hasExplicitNonWeightliftingDiscipline &&
        (value.contains('halterof') ||
            normalizedType.contains('halterof') ||
            normalizedType.contains('weightlifting'));
    if (isWeightliftingMovement) {
      // El mismo gesto de halterofilia (arranque, cargada, envión) cambia
      // de naturaleza según el implemento: solo la barra libre exige la
      // técnica olímpica completa. Con landmine el eje queda fijo al piso
      // (mecánica de potencia/rotación, no halterofilia); con mancuerna o
      // kettlebell no hay recepción bajo barra real, así que se resuelve
      // como balístico o metabólico según la dosis de repeticiones.
      final equipment =
          exercise.equipmentDescriptor.isNotEmpty
              ? exercise.equipmentDescriptor
              : legacyName;
      if (isLandmineType(equipment) || legacyName.contains('landmine')) {
        return 'landmine potencia';
      }
      if (isDumbbellOrKettlebellType(equipment)) {
        final repBasedType = powerTypeForReps(
          declaredType: 'balistico',
          targetReps: exercise.targetReps,
        );
        return repBasedType ?? 'balistico';
      }
      if (isBarbellType(equipment) || equipment.isEmpty) {
        return 'halterofilia';
      }
    }
    final isLandminePower =
        legacyName.contains('landmine') &&
        (value.contains('power') ||
            value.contains('potencia') ||
            value.contains('balistico') ||
            normalizedType.contains('potencia') ||
            normalizedType.contains('balistico') ||
            legacyName.contains('explosivo') ||
            legacyName.contains('snatch') ||
            legacyName.contains('clean') ||
            legacyName.contains('jerk') ||
            legacyName.contains('thruster'));
    if (isLandminePower) return 'landmine potencia';
    final isFreeOrBodyweightUnilateral =
        exercise.unilateral && (exercise.freeWeight || exercise.bodyweight);
    if (isFreeOrBodyweightUnilateral &&
        (value.contains('fuerza') || normalizedType.contains('fuerza'))) {
      return 'fuerza unilateral';
    }
    final repBasedPowerType = powerTypeForReps(
      declaredType: '$value $normalizedType',
      targetReps: exercise.targetReps,
    );
    if (repBasedPowerType != null) {
      return repBasedPowerType;
    }
    if (value.contains('correctiv') ||
        value.contains('estabil') ||
        value.contains('prehab') ||
        value.contains('prevent')) {
      return 'correctivos';
    }
    final isCorrectivePushUp =
        legacyName.contains('plus') ||
        legacyName.contains('serrato') ||
        legacyName.contains('serratus') ||
        legacyName.contains('scapular');
    if (isCorrectivePushUp) return 'correctivos';
    final isBasicCalisthenics =
        !isCorrectivePushUp &&
        (legacyName.contains('dominada') ||
            legacyName.contains('pull up') ||
            legacyName.contains('chin up') ||
            legacyName.contains('fondo') ||
            legacyName.contains('dip') ||
            legacyName.contains('flexion') ||
            legacyName.contains('push up'));
    if (isBasicCalisthenics) return 'calistenia basica';
    if (exercise.compound && normalizedType.contains('hipertrof')) {
      return 'hipertrofia compuesta';
    }
    if (exercise.isolation && normalizedType.contains('hipertrof')) {
      return 'hipertrofia aislada';
    }
    if (value.contains('hipertrof')) {
      return 'hipertrofia';
    }
    if (value.contains('calisten') || value.contains('peso corporal')) {
      return 'peso corporal';
    }
    if (value.contains('fuerza')) {
      return 'fuerza';
    }
    if (legacyName.contains('hang power snatch') ||
        legacyName.contains('power snatch') ||
        legacyName.contains('power clean') ||
        legacyName.contains('snatch') ||
        legacyName.contains('jerk')) {
      return 'potencia';
    }
    return exercise.exerciseType;
  }

  /// Clasifica variantes balísticas/potentes por la dosis programada. Las
  /// repeticiones son por lado: unilateral no duplica este umbral.
  /// Entre 7 y 11 se conserva la intención declarada de la variante.
  static String? powerTypeForReps({
    required String declaredType,
    required double targetReps,
  }) {
    final normalized = _normalizeText(declaredType);
    final isBallistic = normalized.contains('balistico');
    final isPower =
        normalized.contains('potencia') ||
        (normalized.contains('power') && !normalized.contains('powerlifting'));
    if (!isBallistic && !isPower) return null;
    if (targetReps > 0 && targetReps <= 6) return 'potencia';
    if (targetReps >= 12) return 'balistico';
    return isBallistic ? 'balistico' : 'potencia';
  }

  /// Los levantamientos olímpicos tienen pocas repeticiones por serie, pero
  /// cada una exige una secuencia técnica completa y una recepción estable.
  /// Sin esta equivalencia, 3×3 aparece artificialmente menor que accesorios
  /// de altas repeticiones dentro del perfil semanal.
  static double _technicalDoseMultiplier(String classification) {
    final normalized = _normalizeText(classification);
    if (normalized.contains('halterofilia') ||
        normalized.contains('weightlifting')) {
      return 2.0;
    }
    if (normalized.contains('fuerza')) return 1.10;
    // Balístico conserva una orientación deportiva, pero sus repeticiones
    // acumuladas no deben pesar igual que una dosis técnica de fuerza u
    // halterofilia en el perfil semanal.
    if (normalized.contains('balist')) return 0.75;
    return 1.0;
  }

  static void _rebalanceDominantProfile(
    Map<TrainingProfile, double> scores,
    Map<TrainingProfile, Map<String, double>> breakdown,
  ) {
    final total = scores.values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final ordered =
        scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final dominant = ordered.first;
    if (dominant.value / total <= .70) return;
    final target = total * .70;
    final excess = dominant.value - target;
    final remainder = total - dominant.value;
    scores[dominant.key] = target;
    final others = ordered.skip(1).toList();
    for (final entry in others) {
      final share =
          remainder > 0
              ? entry.value / remainder
              : 1 / (others.isEmpty ? 1 : others.length);
      scores[entry.key] = entry.value + excess * share;
    }
    breakdown[dominant.key]!['Límite de dominancia (70%)'] = -excess;
    for (final entry in others) {
      final share =
          remainder > 0
              ? entry.value / remainder
              : 1 / (others.isEmpty ? 1 : others.length);
      breakdown[entry.key]!['Redistribución de equilibrio'] = excess * share;
    }
  }

  static TrainingIntentFamily mapExerciseTypeToIntentFamily(String type) {
    final normalized = _normalizeText(type);

    if (normalized.contains('potencia') ||
        normalized.contains('balist') ||
        normalized.contains('pliometr') ||
        normalized.contains('sprint') ||
        normalized.contains('velocidad')) {
      return TrainingIntentFamily.athleticPower;
    }

    if (normalized.contains('fuerza') ||
        normalized.contains('power') ||
        normalized.contains('basic') ||
        normalized.contains('basi') ||
        normalized.contains('olimp') ||
        normalized.contains('weightlifting') ||
        normalized.contains('halterofilia') ||
        normalized.contains('multiart')) {
      return TrainingIntentFamily.strength;
    }

    if (normalized.contains('hipert') ||
        normalized.contains('bodybuilding') ||
        normalized.contains('pump')) {
      return TrainingIntentFamily.hypertrophy;
    }

    if (normalized.contains('acces') ||
        normalized.contains('aisla') ||
        normalized.contains('brazo')) {
      return TrainingIntentFamily.accessory;
    }

    if (normalized.contains('calistenia') ||
        normalized.contains('peso corporal') ||
        normalized.contains('bodyweight')) {
      return TrainingIntentFamily.bodyweight;
    }

    if (normalized.contains('correctiv') ||
        normalized.contains('core') ||
        normalized.contains('estab') ||
        normalized.contains('movilidad') ||
        normalized.contains('prehab') ||
        normalized.contains('prevent') ||
        normalized.contains('unilateral')) {
      return TrainingIntentFamily.stability;
    }

    if (normalized.contains('condic') ||
        normalized.contains('cardio') ||
        normalized.contains('resistencia') ||
        normalized.contains('metcon') ||
        normalized.contains('metab')) {
      return TrainingIntentFamily.conditioning;
    }

    return TrainingIntentFamily.unknown;
  }

  static Map<TrainingProfile, double> baseProfileDistributionForType(
    String type,
  ) {
    final normalized = _normalizeText(type);

    // "landmine potencia" includes the generic word potencia; resolve this
    // more specific movement family before the generic power distribution.
    if (normalized.contains('landmine') && normalized.contains('potencia')) {
      return Map<TrainingProfile, double>.from(
        _baseIntentByType['landmine potencia']!,
      );
    }
    if (normalized.contains('fuerza unilateral')) {
      return Map<TrainingProfile, double>.from(
        _baseIntentByType['fuerza unilateral']!,
      );
    }
    if (normalized.contains('hipertrofia aislada')) {
      return Map<TrainingProfile, double>.from(
        _baseIntentByType['hipertrofia aislada']!,
      );
    }
    if (normalized.contains('hipertrofia compuesta')) {
      return Map<TrainingProfile, double>.from(
        _baseIntentByType['hipertrofia compuesta']!,
      );
    }
    if (normalized.contains('calistenia basica')) {
      return Map<TrainingProfile, double>.from(
        _baseIntentByType['calistenia basica']!,
      );
    }

    for (final entry in _baseIntentByType.entries) {
      if (normalized.contains(entry.key)) {
        return Map<TrainingProfile, double>.from(entry.value);
      }
    }

    return {
      TrainingProfile.powerlifting: 0.18,
      TrainingProfile.athlete: 0.24,
      TrainingProfile.hypertrophy: 0.33,
      TrainingProfile.conditioning: 0.25,
      TrainingProfile.hybrid: 0.00,
    };
  }

  static Map<TrainingProfile, double> equipmentModifiers({
    required bool bodyweight,
    required bool freeWeight,
    required bool guided,
    bool compound = false,
  }) {
    final modifiers = _neutralModifiers();
    if (bodyweight) {
      // Los patrones corporales compuestos (dominadas, fondos, flexiones)
      // siguen desarrollando fuerza máxima relativa; solo los correctivos o
      // aislados corporales deben quedar sin este componente.
      modifiers[TrainingProfile.powerlifting] = compound ? 0.78 : 0.0;
      modifiers[TrainingProfile.athlete] = 1.06;
      modifiers[TrainingProfile.conditioning] = 1.04;
      modifiers[TrainingProfile.bodyweight] = 1.30;
    } else if (freeWeight) {
      modifiers[TrainingProfile.powerlifting] = 1.10;
      modifiers[TrainingProfile.athlete] = 1.05;
      modifiers[TrainingProfile.hypertrophy] = 0.98;
      modifiers[TrainingProfile.conditioning] = 0.96;
    } else if (guided) {
      modifiers[TrainingProfile.powerlifting] = 0.82;
      modifiers[TrainingProfile.athlete] = 0.94;
      modifiers[TrainingProfile.hypertrophy] = 1.10;
      modifiers[TrainingProfile.conditioning] = 1.02;
    }
    return modifiers;
  }

  static Map<TrainingProfile, double> repsModifiers(String bucket) {
    switch (bucket) {
      case '1-3':
        return {
          TrainingProfile.powerlifting: 1.28,
          TrainingProfile.athlete: 1.08,
          TrainingProfile.hypertrophy: 0.72,
          TrainingProfile.conditioning: 0.50,
          TrainingProfile.bodyweight: 0.92,
          TrainingProfile.hybrid: 1.02,
        };
      case '4-6':
        return {
          TrainingProfile.powerlifting: 1.12,
          TrainingProfile.athlete: 1.00,
          TrainingProfile.hypertrophy: 0.92,
          TrainingProfile.conditioning: 0.70,
          TrainingProfile.bodyweight: 0.96,
          TrainingProfile.hybrid: 1.08,
        };
      case '7-8':
        return {
          TrainingProfile.powerlifting: 1.02,
          TrainingProfile.athlete: 0.98,
          TrainingProfile.hypertrophy: 1.04,
          TrainingProfile.conditioning: 0.78,
          TrainingProfile.bodyweight: 1.02,
          TrainingProfile.hybrid: 1.04,
        };
      case '9-10':
        return {
          TrainingProfile.powerlifting: 0.88,
          TrainingProfile.athlete: 0.94,
          TrainingProfile.hypertrophy: 1.12,
          TrainingProfile.conditioning: 0.82,
          TrainingProfile.bodyweight: 1.08,
          TrainingProfile.hybrid: 1.02,
        };
      case '11-12':
        return {
          TrainingProfile.powerlifting: 0.62,
          TrainingProfile.athlete: 0.90,
          TrainingProfile.hypertrophy: 1.16,
          TrainingProfile.conditioning: 0.92,
          TrainingProfile.bodyweight: 1.10,
          TrainingProfile.hybrid: 0.94,
        };
      case '13+':
        return {
          TrainingProfile.powerlifting: 0.00,
          TrainingProfile.athlete: 0.82,
          TrainingProfile.hypertrophy: 0.78,
          TrainingProfile.conditioning: 1.08,
          TrainingProfile.bodyweight: 1.08,
          TrainingProfile.hybrid: 0.80,
        };
      default:
        return _neutralModifiers();
    }
  }

  static Map<TrainingProfile, double> blockModifiers(String blockType) {
    final normalized = blockType.toLowerCase().trim();
    if (normalized == 'buscar rm') {
      return {
        TrainingProfile.powerlifting: 1.12,
        TrainingProfile.athlete: 1.02,
        TrainingProfile.hypertrophy: 0.95,
        TrainingProfile.conditioning: 0.90,
        TrainingProfile.bodyweight: 1.00,
        TrainingProfile.hybrid: 1.02,
      };
    }
    if (normalized == 'circuito') {
      return {
        TrainingProfile.powerlifting: 0.00,
        TrainingProfile.athlete: 1.03,
        TrainingProfile.hypertrophy: 1.00,
        TrainingProfile.conditioning: 1.22,
        TrainingProfile.bodyweight: 1.02,
        TrainingProfile.hybrid: 1.00,
      };
    }
    if (normalized == 'tabata') {
      return {
        TrainingProfile.powerlifting: 0.90,
        TrainingProfile.athlete: 1.06,
        TrainingProfile.hypertrophy: 0.95,
        TrainingProfile.conditioning: 1.12,
        TrainingProfile.bodyweight: 1.02,
        TrainingProfile.hybrid: 1.00,
      };
    }

    return _neutralModifiers();
  }

  /// Tabla estándar RPE (esfuerzo percibido) + reps → %1RM, basada en la
  /// escala RPE de Tuchscherer/RTS usada en powerlifting. A RPE constante,
  /// más reps implica un %1RM menor (quedaban más repeticiones "en el
  /// tanque" en términos absolutos, pero el mismo esfuerzo relativo).
  /// Filas: RPE 6 a 10. Columnas: 1 a 12 reps. Reps fuera de rango se
  /// clampean al extremo más cercano de la tabla.
  static const Map<int, Map<int, double>> _rpeToPercent1RMTable = {
    10: {
      1: 1.00,
      2: 0.96,
      3: 0.92,
      4: 0.89,
      5: 0.86,
      6: 0.84,
      7: 0.81,
      8: 0.79,
      9: 0.76,
      10: 0.74,
      11: 0.71,
      12: 0.69,
    },
    9: {
      1: 0.96,
      2: 0.92,
      3: 0.89,
      4: 0.86,
      5: 0.84,
      6: 0.81,
      7: 0.79,
      8: 0.76,
      9: 0.74,
      10: 0.71,
      11: 0.69,
      12: 0.66,
    },
    8: {
      1: 0.92,
      2: 0.89,
      3: 0.86,
      4: 0.84,
      5: 0.81,
      6: 0.79,
      7: 0.76,
      8: 0.74,
      9: 0.71,
      10: 0.69,
      11: 0.66,
      12: 0.64,
    },
    7: {
      1: 0.89,
      2: 0.86,
      3: 0.84,
      4: 0.81,
      5: 0.79,
      6: 0.76,
      7: 0.74,
      8: 0.71,
      9: 0.69,
      10: 0.66,
      11: 0.64,
      12: 0.61,
    },
    6: {
      1: 0.86,
      2: 0.84,
      3: 0.81,
      4: 0.79,
      5: 0.76,
      6: 0.74,
      7: 0.71,
      8: 0.69,
      9: 0.66,
      10: 0.64,
      11: 0.61,
      12: 0.59,
    },
  };

  /// Deriva un %1RM efectivo a partir del RPE real reportado y las reps
  /// hechas en la serie, sin depender de un RM histórico guardado. RPE por
  /// debajo de 6 se trata como el propio RPE 6 (series claramente
  /// submáximas; la tabla no discrimina más abajo con precisión útil).
  static double percent1RMFromRpe({required double rpe, required double reps}) {
    final rpeRow = rpe.round().clamp(6, 10);
    final repsCol = reps <= 0 ? 1 : reps.round().clamp(1, 12);
    return _rpeToPercent1RMTable[rpeRow]![repsCol]!;
  }

  static String percent1RMBucketFor(double? percent1RM) {
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

  static Map<TrainingProfile, double> percent1RMModifiers(String bucket) {
    switch (bucket) {
      case '<55%':
        return {
          TrainingProfile.powerlifting: 0.48,
          TrainingProfile.athlete: 1.04,
          TrainingProfile.hypertrophy: 0.92,
          TrainingProfile.conditioning: 1.12,
          TrainingProfile.bodyweight: 0.92,
          TrainingProfile.hybrid: 1.00,
        };
      case '55-60%':
        return {
          TrainingProfile.powerlifting: 0.62,
          TrainingProfile.athlete: 1.02,
          TrainingProfile.hypertrophy: 1.00,
          TrainingProfile.conditioning: 1.02,
          TrainingProfile.bodyweight: 0.96,
          TrainingProfile.hybrid: 1.00,
        };
      case '60-65%':
        return {
          TrainingProfile.powerlifting: 0.74,
          TrainingProfile.athlete: 1.00,
          TrainingProfile.hypertrophy: 1.03,
          TrainingProfile.conditioning: 0.98,
          TrainingProfile.bodyweight: 1.00,
          TrainingProfile.hybrid: 1.00,
        };
      case '65-70%':
        return {
          TrainingProfile.powerlifting: 0.86,
          TrainingProfile.athlete: 1.00,
          TrainingProfile.hypertrophy: 1.04,
          TrainingProfile.conditioning: 0.94,
          TrainingProfile.bodyweight: 1.02,
          TrainingProfile.hybrid: 1.00,
        };
      case '70-75%':
        return {
          TrainingProfile.powerlifting: 0.98,
          TrainingProfile.athlete: 1.00,
          TrainingProfile.hypertrophy: 1.00,
          TrainingProfile.conditioning: 0.92,
          TrainingProfile.bodyweight: 1.04,
          TrainingProfile.hybrid: 1.00,
        };
      case '75-80%':
        return {
          TrainingProfile.powerlifting: 1.08,
          TrainingProfile.athlete: 0.98,
          TrainingProfile.hypertrophy: 0.96,
          TrainingProfile.conditioning: 0.84,
          TrainingProfile.bodyweight: 1.06,
          TrainingProfile.hybrid: 1.00,
        };
      case '80-85%':
        return {
          TrainingProfile.powerlifting: 1.18,
          TrainingProfile.athlete: 0.96,
          TrainingProfile.hypertrophy: 0.90,
          TrainingProfile.conditioning: 0.68,
          TrainingProfile.bodyweight: 1.08,
          TrainingProfile.hybrid: 1.00,
        };
      case '85-90%':
        return {
          TrainingProfile.powerlifting: 1.26,
          TrainingProfile.athlete: 0.92,
          TrainingProfile.hypertrophy: 0.80,
          TrainingProfile.conditioning: 0.56,
          TrainingProfile.bodyweight: 1.10,
          TrainingProfile.hybrid: 1.00,
        };
      case '90%+':
        return {
          TrainingProfile.powerlifting: 1.38,
          TrainingProfile.athlete: 0.86,
          TrainingProfile.hypertrophy: 0.64,
          TrainingProfile.conditioning: 0.45,
          TrainingProfile.bodyweight: 1.12,
          TrainingProfile.hybrid: 1.00,
        };
      default:
        return _neutralModifiers();
    }
  }

  static Map<TrainingProfile, double> intentCoherenceModifiers({
    required String exerciseType,
    required String repBucket,
    required String percent1RMBucket,
    required String blockType,
    bool compound = false,
  }) {
    final normalizedType = _normalizeText(exerciseType);
    final normalizedBlock = _normalizeText(blockType);
    final modifiers = _neutralModifiers();

    if (normalizedType.contains('fuerza')) {
      modifiers[TrainingProfile.conditioning] =
          modifiers[TrainingProfile.conditioning]! * 0.18;

      switch (repBucket) {
        case '1-3':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.22;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.78;
          break;
        case '4-6':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.16;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.92;
          break;
        case '7-8':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.12;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.04;
          modifiers[TrainingProfile.athlete] =
              modifiers[TrainingProfile.athlete]! * 0.95;
          break;
        case '9-10':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.00;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.16;
          modifiers[TrainingProfile.athlete] =
              modifiers[TrainingProfile.athlete]! * 0.92;
          break;
        case '11-12':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 0.72;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.34;
          modifiers[TrainingProfile.athlete] =
              modifiers[TrainingProfile.athlete]! * 0.88;
          break;
        case '13+':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 0.18;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.55;
          modifiers[TrainingProfile.athlete] =
              modifiers[TrainingProfile.athlete]! * 0.85;
          break;
      }

      switch (percent1RMBucket) {
        case '<55%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 0.68;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.18;
          break;
        case '55-60%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 0.76;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.16;
          break;
        case '60-65%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 0.84;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.14;
          break;
        case '65-70%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 0.92;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.10;
          break;
        case '70-75%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.02;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.02;
          break;
        case '75-80%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.10;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.96;
          break;
        case '80-85%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.18;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.88;
          break;
        case '85-90%':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.24;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.80;
          break;
        case '90%+':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.28;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.74;
          break;
      }

      if (normalizedBlock == 'tabata' ||
          normalizedBlock == 'circuito' ||
          normalizedBlock == 'emom') {
        modifiers[TrainingProfile.conditioning] =
            modifiers[TrainingProfile.conditioning]! * 1.8;
      }
    }

    if (normalizedType.contains('balist')) {
      switch (repBucket) {
        case '9-10':
          modifiers[TrainingProfile.athlete] =
              modifiers[TrainingProfile.athlete]! * 0.92;
          modifiers[TrainingProfile.conditioning] =
              modifiers[TrainingProfile.conditioning]! * 1.10;
          break;
        case '11-12':
          modifiers[TrainingProfile.athlete] =
              modifiers[TrainingProfile.athlete]! * 0.82;
          modifiers[TrainingProfile.conditioning] =
              modifiers[TrainingProfile.conditioning]! * 1.22;
          break;
        case '13+':
          modifiers[TrainingProfile.athlete] =
              modifiers[TrainingProfile.athlete]! * 0.84;
          modifiers[TrainingProfile.conditioning] =
              modifiers[TrainingProfile.conditioning]! * 1.18;
          break;
      }
    }

    if (normalizedType.contains('hipertrof')) {
      modifiers[TrainingProfile.conditioning] = 0.0;

      switch (repBucket) {
        case '1-3':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.28;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.92;
          break;
        case '4-6':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.20;
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 0.96;
          break;
        case '7-8':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.10;
          break;
        case '9-10':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 1.04;
          break;
        case '11-12':
          modifiers[TrainingProfile.powerlifting] =
              modifiers[TrainingProfile.powerlifting]! * 0.96;
          break;
        case '13+':
          modifiers[TrainingProfile.powerlifting] = 0.0;
          // En hipertrofia 13-20 reps sigue siendo hipertrofia: se neutraliza
          // el ajuste genérico de 13+ (Hipertrofia ×0.78, Control ×1.08),
          // que empujaba ejercicios aislados hacia Control y coordinación.
          modifiers[TrainingProfile.hypertrophy] =
              modifiers[TrainingProfile.hypertrophy]! * 1.28;
          modifiers[TrainingProfile.bodyweight] =
              modifiers[TrainingProfile.bodyweight]! * 0.92;
          break;
      }
    }

    if (normalizedType.contains('acces') || normalizedType.contains('aisla')) {
      modifiers[TrainingProfile.conditioning] = 0.0;
    }

    if (!compound &&
        (normalizedType.contains('peso corporal') ||
            normalizedType.contains('bodyweight') ||
            normalizedType.contains('calistenia'))) {
      modifiers[TrainingProfile.powerlifting] = 0.0;
    }

    return modifiers;
  }

  static Map<TrainingProfile, double> attributeModifiers({
    required bool trackRm,
    required bool unilateral,
    required bool freeWeight,
    required bool compound,
    required bool isolation,
    required bool bodyweight,
    bool rotational = false,
  }) {
    final modifiers = _neutralModifiers();

    if (bodyweight) {
      modifiers[TrainingProfile.powerlifting] = compound ? 0.78 : 0.0;
    }

    if (rotational) {
      // El control rotacional de tronco (generarlo o resistirlo) es una
      // demanda de transferencia deportiva, no de fuerza máxima ni de
      // hipertrofia local — mismo criterio que ya se aplica a unilateral.
      modifiers[TrainingProfile.powerlifting] =
          modifiers[TrainingProfile.powerlifting]! * 0.90;
      modifiers[TrainingProfile.athlete] =
          modifiers[TrainingProfile.athlete]! * 1.24;
      modifiers[TrainingProfile.hypertrophy] =
          modifiers[TrainingProfile.hypertrophy]! * 0.92;
      modifiers[TrainingProfile.bodyweight] =
          modifiers[TrainingProfile.bodyweight]! * 1.10;
    }

    if (trackRm && compound && !bodyweight) {
      modifiers[TrainingProfile.powerlifting] =
          modifiers[TrainingProfile.powerlifting]! * 1.06;
      modifiers[TrainingProfile.athlete] =
          modifiers[TrainingProfile.athlete]! * 1.02;
    }

    if (unilateral) {
      modifiers[TrainingProfile.powerlifting] =
          modifiers[TrainingProfile.powerlifting]! * 0.94;
      modifiers[TrainingProfile.athlete] =
          modifiers[TrainingProfile.athlete]! * 1.22;
      modifiers[TrainingProfile.hypertrophy] =
          modifiers[TrainingProfile.hypertrophy]! * 0.94;
      modifiers[TrainingProfile.conditioning] =
          modifiers[TrainingProfile.conditioning]! * 1.04;
      // Unilateral work with a free implement or one's own body requires
      // active positional control. Treat that demand as coordination rather
      // than folding it entirely into the athletic-performance profile.
      modifiers[TrainingProfile.bodyweight] =
          modifiers[TrainingProfile.bodyweight]! *
          ((freeWeight || bodyweight) ? 1.22 : 1.06);
    } else {
      modifiers[TrainingProfile.powerlifting] =
          modifiers[TrainingProfile.powerlifting]! * 1.05;
      modifiers[TrainingProfile.athlete] =
          modifiers[TrainingProfile.athlete]! * 0.98;
    }

    if (compound) {
      modifiers[TrainingProfile.powerlifting] =
          modifiers[TrainingProfile.powerlifting]! * 1.06;
      modifiers[TrainingProfile.athlete] =
          modifiers[TrainingProfile.athlete]! * 1.04;
      modifiers[TrainingProfile.hypertrophy] =
          modifiers[TrainingProfile.hypertrophy]! * 0.96;
      modifiers[TrainingProfile.bodyweight] =
          modifiers[TrainingProfile.bodyweight]! * 0.98;
      modifiers[TrainingProfile.hybrid] =
          modifiers[TrainingProfile.hybrid]! * 1.03;
    }

    if (isolation) {
      modifiers[TrainingProfile.powerlifting] =
          modifiers[TrainingProfile.powerlifting]! * 1.20;
      modifiers[TrainingProfile.athlete] =
          modifiers[TrainingProfile.athlete]! * 1.00;
      modifiers[TrainingProfile.hypertrophy] =
          modifiers[TrainingProfile.hypertrophy]! * 1.05;
      modifiers[TrainingProfile.bodyweight] =
          modifiers[TrainingProfile.bodyweight]! * 0.90;
      modifiers[TrainingProfile.hybrid] =
          modifiers[TrainingProfile.hybrid]! * 1.01;

      if (freeWeight) {
        // Un aislamiento libre sigue siendo local, pero requiere estabilizar
        // el implemento y puede progresar como fuerza submáxima.
        modifiers[TrainingProfile.powerlifting] =
            modifiers[TrainingProfile.powerlifting]! * 1.16;
        modifiers[TrainingProfile.bodyweight] =
            modifiers[TrainingProfile.bodyweight]! * 1.04;
      }
    }

    return modifiers;
  }

  static Map<TrainingProfile, double> _neutralModifiers() {
    return {
      TrainingProfile.powerlifting: 1.00,
      TrainingProfile.athlete: 1.00,
      TrainingProfile.hypertrophy: 1.00,
      TrainingProfile.conditioning: 1.00,
      TrainingProfile.bodyweight: 1.00,
      TrainingProfile.hybrid: 1.00,
    };
  }

  static Map<TrainingProfile, double> _filterActiveProfiles(
    Map<TrainingProfile, double> input,
  ) {
    return {
      for (final profile in _activeProfiles) profile: input[profile] ?? 0,
    };
  }

  static Map<TrainingProfile, double> _withBodyweightBase(
    Map<TrainingProfile, double> base, {
    required bool isBodyweight,
  }) {
    final result = Map<TrainingProfile, double>.from(base);
    if (!isBodyweight) return result;

    final current = result[TrainingProfile.bodyweight] ?? 0.0;
    if (current >= 0.18) return result;

    final deficit = 0.18 - current;
    result[TrainingProfile.bodyweight] = 0.18;

    final athlete = (result[TrainingProfile.athlete] ?? 0.0) - (deficit * 0.6);
    final conditioning =
        (result[TrainingProfile.conditioning] ?? 0.0) - (deficit * 0.4);

    result[TrainingProfile.athlete] = athlete < 0 ? 0 : athlete;
    result[TrainingProfile.conditioning] = conditioning < 0 ? 0 : conditioning;
    return result;
  }

  static Map<TrainingProfile, double> _withRotationalControlBase(
    Map<TrainingProfile, double> base, {
    required bool isRotational,
    required bool isUnilateral,
  }) {
    if (!isRotational) return base;

    final result = Map<TrainingProfile, double>.from(base);
    final target = isUnilateral ? 0.16 : 0.12;
    final current = result[TrainingProfile.bodyweight] ?? 0.0;
    if (current >= target) return result;

    var deficit = target - current;
    result[TrainingProfile.bodyweight] = target;

    // Preserve the exercise's primary intent while reserving a modest,
    // explicit share for rotational control and coordination.
    for (final profile in [
      TrainingProfile.athlete,
      TrainingProfile.hypertrophy,
      TrainingProfile.conditioning,
      TrainingProfile.powerlifting,
    ]) {
      if (deficit <= 0) break;
      final available = result[profile] ?? 0.0;
      final transfer = available < deficit ? available : deficit;
      result[profile] = available - transfer;
      deficit -= transfer;
    }
    return result;
  }

  static bool isFreeType(String value) {
    final normalized = _normalizeText(value);
    return normalized.contains('barra') ||
        normalized.contains('mancuer') ||
        normalized.contains('kettlebell') ||
        normalized.contains('barra fija') ||
        normalized.contains('paralela');
  }

  /// Barra libre real (excluye barra fija/paralelas, que son calistenia, y
  /// landmine, que es una variante de barra con extremo fijo al piso y por
  /// eso tiene su propia mecánica).
  static bool isBarbellType(String value) {
    final normalized = _normalizeText(value);
    if (normalized.contains('landmine')) return false;
    return (normalized.contains('barra') &&
            !normalized.contains('barra fija')) ||
        normalized.contains('barra z');
  }

  static bool isLandmineType(String value) {
    return _normalizeText(value).contains('landmine');
  }

  static bool isDumbbellOrKettlebellType(String value) {
    final normalized = _normalizeText(value);
    return normalized.contains('mancuer') || normalized.contains('kettlebell');
  }

  static bool isBodyweightType(String value) {
    final normalized = _normalizeText(value);
    return normalized.contains('peso corporal') ||
        normalized.contains('bodyweight') ||
        normalized.contains('calistenia');
  }

  static bool isGuidedType(String value) {
    final normalized = _normalizeText(value);
    return normalized.contains('polea') ||
        normalized.contains('maquina') ||
        normalized.contains('smith');
  }

  static bool isUnilateralExercise({
    required String name,
    required String type,
  }) {
    final normalizedName = _normalizeText(name);
    final normalizedType = _normalizeText(type);
    return normalizedName.contains('unilateral') ||
        normalizedName.contains('zancada') ||
        normalizedName.contains('split squat') ||
        normalizedName.contains('step up') ||
        normalizedName.contains('a una mano') ||
        normalizedName.contains('a un brazo') ||
        normalizedName.contains('a una pierna') ||
        normalizedType.contains('unilateral');
  }

  /// Fallback por texto para ejercicios legacy sin `movementPlane` explícito
  /// en el catálogo. Cubre tanto patrones rotacionales (leñador, landmine
  /// snatch/twist, lanzamientos laterales) como anti-rotacionales (Pallof,
  /// plancha lateral) — ambos exigen la misma demanda de control de tronco
  /// en el plano transverso.
  static bool isRotationalExercise({
    required String name,
    required String type,
  }) {
    final normalizedName = _normalizeText(name);
    final normalizedType = _normalizeText(type);
    return normalizedName.contains('lenador') ||
        normalizedName.contains('pallof') ||
        normalizedName.contains('windmill') ||
        normalizedName.contains('russian twist') ||
        normalizedName.contains('rotacion') ||
        normalizedName.contains('rotational') ||
        normalizedName.contains('lanzamiento lateral') ||
        normalizedName.contains('giro') ||
        (normalizedName.contains('plancha lateral')) ||
        (normalizedName.contains('landmine') &&
            (normalizedName.contains('snatch') ||
                normalizedName.contains('twist') ||
                normalizedName.contains('rotac'))) ||
        normalizedType.contains('rotacion') ||
        normalizedType.contains('rotational') ||
        normalizedType.contains('anti-rotacion') ||
        normalizedType.contains('antirrotacion');
  }

  static bool isCompoundExercise({
    required TrainingIntentFamily family,
    required int muscleCount,
    required String type,
  }) {
    if (family == TrainingIntentFamily.strength ||
        family == TrainingIntentFamily.athleticPower) {
      return true;
    }

    final normalizedType = _normalizeText(type);
    // Un tipo declarado como aislado manda sobre el conteo de músculos: una
    // elevación lateral pondera 4 músculos (deltoides + trapecio) y se
    // clasificaba como compuesta.
    if (normalizedType.contains('aislad') ||
        normalizedType.contains('aislamiento')) {
      return false;
    }
    return muscleCount >= 3 ||
        normalizedType.contains('multi') ||
        normalizedType.contains('compuesto');
  }

  static bool isIsolationExercise({
    required TrainingIntentFamily family,
    required int muscleCount,
    required String type,
  }) {
    final normalizedType = _normalizeText(type);
    if (normalizedType.contains('aisla') || normalizedType.contains('acces')) {
      return true;
    }
    if (family == TrainingIntentFamily.strength ||
        family == TrainingIntentFamily.athleticPower) {
      return false;
    }
    return muscleCount > 0 && muscleCount <= 2;
  }

  static String repBucketFor({
    required String blockType,
    required double targetReps,
    required TrainingIntentFamily family,
  }) {
    final normalized = _normalizeText(blockType);
    if (targetReps > 0) {
      if (targetReps <= 3) return '1-3';
      if (targetReps <= 6) return '4-6';
      if (targetReps <= 8) return '7-8';
      if (targetReps <= 10) return '9-10';
      if (targetReps <= 12) return '11-12';
      return '13+';
    }

    if (normalized == 'tabata') return '13+';
    if (normalized == 'circuito' || normalized == 'emom') return '9-10';

    switch (family) {
      case TrainingIntentFamily.athleticPower:
        return '4-6';
      case TrainingIntentFamily.strength:
        return '1-3';
      case TrainingIntentFamily.hypertrophy:
        return '9-10';
      case TrainingIntentFamily.isolatedHypertrophy:
        return '11-12';
      case TrainingIntentFamily.accessory:
        return '11-12';
      case TrainingIntentFamily.bodyweight:
        return '9-10';
      case TrainingIntentFamily.stability:
        return '9-10';
      case TrainingIntentFamily.conditioning:
        return '13+';
      case TrainingIntentFamily.unknown:
        return '9-10';
    }
  }

  static double _sumMuscles(Map<String, double> load, List<Muscle> muscles) {
    double total = 0;
    for (final muscle in muscles) {
      total += load[muscle.name] ?? 0;
    }
    return total;
  }

  static double _balanceScore(double a, double b) {
    if (a <= 0 && b <= 0) return 0;
    final max = a > b ? a : b;
    final min = a > b ? b : a;
    if (max == 0) return 0;
    return (min / max).clamp(0.0, 1.0);
  }

  static String _normalizeText(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }
}
