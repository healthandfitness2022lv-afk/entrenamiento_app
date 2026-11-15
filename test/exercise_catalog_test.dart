import 'package:flutter_test/flutter_test.dart';
import 'package:entrenamiento_app/models/exercise.dart';
import 'package:entrenamiento_app/services/exercise_catalog_service.dart';
import 'package:entrenamiento_app/utils/exercise_name_utils.dart';
import 'package:entrenamiento_app/utils/exercise_variant_catalog.dart';

void main() {
  group('exercise catalog identity', () {
    test('normalizes accents, separators and whitespace', () {
      expect(
        normalizeExerciseKey('  Extensión / Cuádriceps '),
        'extension cuadriceps',
      );
      expect(normalizeExerciseKey('MÁQUINA---SMITH'), 'maquina smith');
      expect(canonicalExerciseKey('Bulgarian Squat'), 'sentadilla bulgara');
      expect(canonicalExerciseKey('Thrusther'), 'thruster');
    });

    test('identity separates variants of the same movement', () {
      final barbell = exerciseIdentityKey(
        exerciseName: 'Sentadilla',
        exerciseId: 'squat',
        variantId: 'barbell_back',
      );
      final smith = exerciseIdentityKey(
        exerciseName: 'Sentadilla',
        exerciseId: 'squat',
        variantId: 'smith',
      );
      expect(barbell, isNot(smith));
    });

    test('legacy exercise receives a reviewable Original variant', () {
      final exercise = Exercise.fromFirestore({
        'name': 'Ejercicio antiguo',
        'instructions': 'Prueba',
        'exerciseType': 'Otros',
        'equipment': ['Barra'],
        'muscleWeights': {'quads': 1.0},
      }, id: 'legacy');
      expect(exercise.variants, hasLength(1));
      expect(exercise.variants.single.id, 'original');
      expect(exercise.variants.single.needsReview, isTrue);
    });
  });

  test('tabular import accepts pipes and skips its header', () {
    final rows = ExerciseCatalogService.parseTabular(
      'Movimiento | Variante | Grupo | Implementos\n'
      'Sentadilla | Máquina Smith | Máquina | Máquina Smith\n'
      'Sentadilla | Goblet | Peso libre | Kettlebell, Mancuerna',
    );
    expect(rows, hasLength(2));
    expect(rows.last.equipment, ['Kettlebell', 'Mancuerna']);
  });

  test('preloaded movements have stable, unique variant identities', () {
    expect(commonMovementVariants.length, greaterThanOrEqualTo(25));
    for (final entry in commonMovementVariants.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
      final ids = entry.value.map((variant) => variant.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: entry.key);
      expect(ids.every((id) => id.trim().isNotEmpty), isTrue);
    }
    expect(commonMovementVariants['sentadilla'], hasLength(11));
  });
}
