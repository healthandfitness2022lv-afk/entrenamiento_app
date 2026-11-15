import 'package:entrenamiento_app/services/load_adjustment_alert_service.dart';
import 'package:entrenamiento_app/services/planned_load_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final block = <String, dynamic>{
    'type': 'Series',
    'exercises': [
      {
        'instanceId': 'squat-back',
        'name': 'Sentadilla - Barra trasera',
        'series': 3,
        'reps': 5,
        'weight': 100,
      },
    ],
  };

  test('genera progresión fija y redondea a 2,5 kg', () {
    final rules = [
      {
        'exerciseInstanceId': 'squat-back',
        'mode': 'fixedKg',
        'incrementKg': 2.5,
        'roundingKg': 2.5,
      },
    ];
    final result = PlannedLoadService.generateOverrides(
      block: block,
      progressionIndex: 2,
      rules: rules,
    );
    final sets = List<Map<String, dynamic>>.from(result.first['sets']);
    expect(sets.map((set) => set['weight']), everyElement(105.0));
  });

  test('genera carga desde porcentaje de 1RM', () {
    final result = PlannedLoadService.generateOverrides(
      block: block,
      progressionIndex: 1,
      rules: [
        {
          'exerciseInstanceId': 'squat-back',
          'mode': 'percent1rm',
          'reference1RM': 120,
          'startPercent': 70,
          'percentStep': 5,
          'roundingKg': 2.5,
        },
      ],
    );
    final sets = List<Map<String, dynamic>>.from(result.first['sets']);
    expect(sets.first['weight'], 90.0);
  });

  test('la sugerencia de RM funciona sin marca del catálogo', () {
    final result = PlannedLoadService.generateOverrides(
      block: block,
      progressionIndex: 1,
      rules: [
        {
          'exerciseInstanceId': 'squat-back',
          'mode': 'suggested',
          'reference1RM': 120,
          'startPercent': 70,
          'percentStep': 2.5,
          'roundingKg': 2.5,
        },
      ],
    );
    final sets = List<Map<String, dynamic>>.from(result.first['sets']);
    expect(sets.first['weight'], 87.5);
    expect(sets.first['source'], 'automatic');
  });

  test('conserva una serie corregida manualmente al recalcular', () {
    final result = PlannedLoadService.generateOverrides(
      block: block,
      progressionIndex: 1,
      rules: [
        {
          'exerciseInstanceId': 'squat-back',
          'mode': 'fixedKg',
          'incrementKg': 5,
        },
      ],
      existing: [
        {
          'exerciseInstanceId': 'squat-back',
          'sets': [
            {'weight': 97.5, 'source': 'manual'},
            {'weight': 100, 'source': 'automatic'},
          ],
        },
      ],
    );
    final sets = List<Map<String, dynamic>>.from(result.first['sets']);
    expect(sets[0]['weight'], 97.5);
    expect(sets[1]['weight'], 105.0);
    expect(sets[2]['weight'], 105.0);
  });

  test('resuelve cargas particulares sin modificar el bloque base', () {
    final resolved = PlannedLoadService.resolveBlock(
      block: block,
      planned: {
        'id': 'plan-friday',
        'blockId': 'strength-main',
        'loadOverrides': [
          {
            'exerciseInstanceId': 'squat-back',
            'sets': [
              {'weight': 92.5, 'source': 'manual'},
              {'weight': 95, 'source': 'automatic'},
              {'weight': 97.5, 'source': 'automatic'},
            ],
          },
        ],
      },
    );
    final exercise =
        List<Map<String, dynamic>>.from(resolved['exercises']).first;
    final sets = List<Map<String, dynamic>>.from(exercise['sets']);
    expect(sets.map((set) => set['weight']), [92.5, 95, 97.5]);
    expect((block['exercises'] as List).first['weight'], 100);
  });

  test('umbral usa el mayor valor entre 2,5 kg y 5%', () {
    expect(LoadAdjustmentAlertService.isRelevantDifference(100, 96), isFalse);
    expect(LoadAdjustmentAlertService.isRelevantDifference(100, 95), isTrue);
    expect(LoadAdjustmentAlertService.isRelevantDifference(20, 17.6), isFalse);
    expect(LoadAdjustmentAlertService.isRelevantDifference(20, 17.5), isTrue);
  });
}
