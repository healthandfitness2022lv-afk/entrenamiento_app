import 'package:entrenamiento_app/services/training_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrainingIdentityService', () {
    test('expone las etiquetas del perfil en español', () {
      expect(TrainingProfile.powerlifting.label, 'Fuerza máxima');
      expect(TrainingProfile.conditioning.label, 'Acondicionamiento');
      expect(TrainingProfile.bodyweight.label, 'Control y coordinación');
      expect(TrainingIntentFamily.athleticPower.label, 'Potencia deportiva');
      expect(TrainingIntentFamily.unknown.label, 'Sin clasificar');
    });

    test('aplica modificadores diferentes según el implemento', () {
      final free = TrainingIdentityService.equipmentModifiers(
        bodyweight: false,
        freeWeight: true,
        guided: false,
      );
      final guided = TrainingIdentityService.equipmentModifiers(
        bodyweight: false,
        freeWeight: false,
        guided: true,
      );
      final bodyweight = TrainingIdentityService.equipmentModifiers(
        bodyweight: true,
        freeWeight: false,
        guided: false,
      );

      expect(free[TrainingProfile.powerlifting], greaterThan(1));
      expect(guided[TrainingProfile.hypertrophy], greaterThan(1));
      expect(bodyweight[TrainingProfile.bodyweight], greaterThan(1));
      expect(bodyweight[TrainingProfile.powerlifting], 0);
    });

    test(
      'un movimiento compuesto no se clasifica también como aislamiento',
      () {
        final compound = TrainingIdentityService.isCompoundExercise(
          family: TrainingIntentFamily.hypertrophy,
          muscleCount: 4,
          type: 'Hipertrofia',
        );
        final isolation = TrainingIdentityService.isIsolationExercise(
          family: TrainingIntentFamily.hypertrophy,
          muscleCount: 4,
          type: 'Hipertrofia',
        );

        expect(compound, isTrue);
        expect(isolation, isFalse);
      },
    );

    test('el seguimiento de RM aumenta el aporte al perfil de fuerza', () {
      final withoutTracking = TrainingIdentityService.analyze(
        _input(trackRm: false),
      );
      final withTracking = TrainingIdentityService.analyze(
        _input(trackRm: true),
      );

      expect(
        withTracking.scores[TrainingProfile.powerlifting]!,
        greaterThan(withoutTracking.scores[TrainingProfile.powerlifting]!),
      );
      expect(withTracking.debugMetrics['trackedRmRatio'], 1);
      expect(withoutTracking.debugMetrics['trackedRmRatio'], 0);
    });

    test('separa la intención del uso real de peso corporal', () {
      final result = TrainingIdentityService.analyze(
        _input(trackRm: false, bodyweight: true),
      );

      expect(result.debugMetrics['bodyweightIntentRatio'], 0);
      expect(result.debugMetrics['bodyweightEquipmentRatio'], 1);
    });

    test('clasifica Correctivos como estabilidad, no como hipertrofia', () {
      expect(
        TrainingIdentityService.mapExerciseTypeToIntentFamily('Correctivos'),
        TrainingIntentFamily.stability,
      );

      final distribution =
          TrainingIdentityService.baseProfileDistributionForType('Correctivos');
      expect(
        distribution[TrainingProfile.athlete],
        greaterThan(distribution[TrainingProfile.hypertrophy]!),
      );
      expect(
        distribution[TrainingProfile.bodyweight],
        greaterThan(distribution[TrainingProfile.athlete]!),
      );
    });

    test('unilateral libre refuerza control y coordinación', () {
      final unilateralLibre = TrainingIdentityService.attributeModifiers(
        trackRm: false,
        unilateral: true,
        freeWeight: true,
        compound: true,
        isolation: false,
        bodyweight: false,
      );
      final unilateralGuiado = TrainingIdentityService.attributeModifiers(
        trackRm: false,
        unilateral: true,
        freeWeight: false,
        compound: true,
        isolation: false,
        bodyweight: false,
      );

      expect(
        unilateralLibre[TrainingProfile.bodyweight],
        greaterThan(unilateralGuiado[TrainingProfile.bodyweight]!),
      );
    });

    test('pliometría aporta de forma relevante a control y coordinación', () {
      final distribution =
          TrainingIdentityService.baseProfileDistributionForType('Pliometría');

      expect(distribution[TrainingProfile.bodyweight], 0.42);
      expect(
        distribution[TrainingProfile.bodyweight],
        closeTo(distribution[TrainingProfile.athlete]!, 0.01),
      );
    });

    test('halterofilia y landmine de potencia aportan a control', () {
      final olympic = TrainingIdentityService.baseProfileDistributionForType(
        'Halterofilia',
      );
      final landmine = TrainingIdentityService.baseProfileDistributionForType(
        'Landmine potencia',
      );

      expect(olympic[TrainingProfile.bodyweight], greaterThan(0.30));
      expect(landmine[TrainingProfile.bodyweight], greaterThan(0.30));
    });

    test('calistenia básica prioriza fuerza relativa sobre control', () {
      final distribution =
          TrainingIdentityService.baseProfileDistributionForType(
            'Calistenia básica',
          );

      expect(distribution[TrainingProfile.powerlifting], 0.32);
      expect(
        distribution[TrainingProfile.powerlifting],
        greaterThan(distribution[TrainingProfile.bodyweight]!),
      );
    });

    test('fuerza unilateral libre incorpora control y coordinación', () {
      final distribution =
          TrainingIdentityService.baseProfileDistributionForType(
            'Fuerza unilateral',
          );

      expect(distribution[TrainingProfile.powerlifting], 0.45);
      expect(distribution[TrainingProfile.bodyweight], 0.20);
    });

    test('aislamiento conserva un componente de fuerza máxima', () {
      final distribution =
          TrainingIdentityService.baseProfileDistributionForType('Aislamiento');

      expect(distribution[TrainingProfile.powerlifting], 0.24);
      expect(distribution[TrainingProfile.hypertrophy], 0.58);
    });

    test('hipertrofia aislada incorpora fuerza local significativa', () {
      final distribution =
          TrainingIdentityService.baseProfileDistributionForType(
            'Hipertrofia aislada',
          );

      expect(distribution[TrainingProfile.powerlifting], 0.24);
      expect(distribution[TrainingProfile.powerlifting], greaterThan(0.20));
    });

    test('variantes de potencia cambian según repeticiones por lado', () {
      expect(
        TrainingIdentityService.powerTypeForReps(
          declaredType: 'Balístico',
          targetReps: 6,
        ),
        'potencia',
      );
      expect(
        TrainingIdentityService.powerTypeForReps(
          declaredType: 'Potencia',
          targetReps: 12,
        ),
        'balistico',
      );
      expect(
        TrainingIdentityService.powerTypeForReps(
          declaredType: 'Balístico',
          targetReps: 8,
        ),
        'balistico',
      );
    });
    test('prioriza la intención de variante sobre el tipo legacy', () {
      final result = TrainingIdentityService.analyze(
        _input(
          trackRm: false,
          intent: 'conditioning',
          discipline: 'metabolico',
        ),
      );
      expect(
        result.scores[TrainingProfile.conditioning]!,
        greaterThan(result.scores[TrainingProfile.powerlifting]!),
      );
    });

    test('por lado conserva volumen muscular y atenúa orientación', () {
      final single = TrainingIdentityService.analyze(
        _input(
          trackRm: false,
          intent: 'hypertrophy',
          discipline: 'hipertrofia',
        ),
      );
      final perSide = TrainingIdentityService.analyze(
        _input(
          trackRm: false,
          multiplier: 2,
          intent: 'hypertrophy',
          discipline: 'hipertrofia',
        ),
      );
      expect(
        perSide.exercises.single.finalProfileContributions[TrainingProfile
            .powerlifting]!,
        closeTo(
          single.exercises.single.finalProfileContributions[TrainingProfile
                  .powerlifting]! *
              1.2,
          .001,
        ),
      );
    });

    test('fuerza sobre 10 reps no suma a acondicionamiento hasta pasar 15', () {
      double contribution(double reps, TrainingProfile profile) =>
          TrainingIdentityService.analyze(
            _input(trackRm: false, reps: reps),
          ).exercises.first.finalProfileContributions[profile] ??
          0;

      expect(contribution(12, TrainingProfile.conditioning), closeTo(0, 1e-9));
      expect(contribution(15, TrainingProfile.conditioning), closeTo(0, 1e-9));
      expect(contribution(18, TrainingProfile.conditioning), greaterThan(0));
      // Lo que pierde Fuerza máxima pasa a Hipertrofia y a Control.
      expect(
        contribution(12, TrainingProfile.hypertrophy),
        greaterThan(contribution(10, TrainingProfile.hypertrophy)),
      );
      expect(
        contribution(12, TrainingProfile.bodyweight),
        greaterThan(contribution(10, TrainingProfile.bodyweight)),
      );
    });

    test(
      'un circuito suma un plus a acondicionamiento a cualquier ejercicio',
      () {
        double conditioning(String blockType) =>
            TrainingIdentityService.analyze(
              _input(
                trackRm: false,
                reps: 12,
                exerciseType: 'Hipertrofia aislada',
                blockType: blockType,
              ),
            ).exercises.first.finalProfileContributions[TrainingProfile
                .conditioning] ??
            0;

        // Aislado fuera de circuito: 0. Dentro de circuito: recibe el plus.
        expect(conditioning('normal'), closeTo(0, 1e-9));
        expect(conditioning('Circuito'), greaterThan(0));
      },
    );

    test('un ejercicio declarado aislado no se infiere compuesto', () {
      expect(
        TrainingIdentityService.isCompoundExercise(
          family: TrainingIntentFamily.isolatedHypertrophy,
          muscleCount: 4,
          type: 'Hipertrofia aislada',
        ),
        isFalse,
      );
    });

    test('hipertrofia a 15 reps no se desplaza hacia control', () {
      Map<TrainingProfile, double> shares(double reps) {
        final contributions =
            TrainingIdentityService.analyze(
              _input(
                trackRm: false,
                reps: reps,
                exerciseType: 'Hipertrofia aislada',
              ),
            ).exercises.first.finalProfileContributions;
        final total = contributions.values.fold<double>(0, (a, b) => a + b);
        return contributions.map((k, v) => MapEntry(k, v / total));
      }

      final at10 = shares(10);
      final at15 = shares(15);
      expect(
        at15[TrainingProfile.bodyweight]!,
        lessThanOrEqualTo(at10[TrainingProfile.bodyweight]! + 0.03),
      );
      expect(at15[TrainingProfile.hypertrophy]!, greaterThan(0.7));
    });
  });
}

TrainingIdentityInput _input({
  required bool trackRm,
  bool bodyweight = false,
  String intent = '',
  String discipline = '',
  double multiplier = 1,
  double reps = 5,
  String blockType = 'normal',
  String exerciseType = 'Fuerza',
}) {
  const load = 10.0;
  return TrainingIdentityInput(
    totalLoad: const {'quads': load},
    exerciseTypeLoad: const {'Fuerza': load},
    blockTypeLoad: const {'normal': load},
    intentFamilyLoad: const {TrainingIntentFamily.strength: load},
    repRangeLoad: const {'4-6': load},
    trackedRmLoad: trackRm ? load : 0,
    bilateralLoad: load,
    unilateralLoad: 0,
    freeLoad: bodyweight ? 0 : load,
    guidedLoad: 0,
    bodyweightLoad: bodyweight ? load : 0,
    compoundLoad: load,
    isolationLoad: 0,
    exercises: [
      _exercise(
        trackRm: trackRm,
        bodyweight: bodyweight,
        intent: intent,
        discipline: discipline,
        multiplier: multiplier,
        reps: reps,
        blockType: blockType,
        exerciseType: exerciseType,
      ),
    ],
  );
}

TrainingIdentityExerciseContribution _exercise({
  required bool trackRm,
  bool bodyweight = false,
  String intent = '',
  String discipline = '',
  double multiplier = 1,
  double reps = 5,
  String blockType = 'normal',
  String exerciseType = 'Fuerza',
}) {
  return TrainingIdentityExerciseContribution(
    source: 'planned',
    setLabel: 'Serie 1',
    date: DateTime(2026, 9, 17),
    name: 'Sentadilla - Barra trasera',
    blockTitle: 'Fuerza principal',
    exerciseType: exerciseType,
    blockType: blockType,
    load: 10,
    baseSets: 1,
    targetReps: reps,
    repsEquivalent: reps,
    volumeUnits: 0.5,
    perSideMultiplier: multiplier,
    exerciseFactor: 1,
    structureFactor: 1,
    referenceWeight: 100,
    historical1RM: 125,
    percent1RM: 0.8,
    percent1RMBucket: '80-89',
    trackRm: trackRm,
    unilateral: false,
    freeWeight: !bodyweight,
    guided: false,
    bodyweight: bodyweight,
    compound: true,
    isolation: false,
    family: TrainingIntentFamily.strength,
    repBucket: TrainingIdentityService.repBucketFor(
      blockType: blockType,
      targetReps: reps,
      family: TrainingIntentFamily.strength,
    ),
    muscleLoads: const {'quads': 10},
    movementIntent: intent,
    trainingDiscipline: discipline,
  );
}
