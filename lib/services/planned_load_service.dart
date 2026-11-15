import 'dart:math' as math;

/// Un grupo de series consecutivas que comparten peso y reps (ej. "2 series
/// de 3 reps a 85kg"). Es cómo se debe MOSTRAR un ejercicio con series
/// mixtas, a diferencia de la lista plana de sets individuales que usa
/// internamente `PlannedLoadService`.
class SetGroup {
  final double weight;
  final int reps;
  final int count;
  final bool perSide;

  const SetGroup({
    required this.weight,
    required this.reps,
    required this.count,
    this.perSide = false,
  });

  /// Formato compacto: "2x3 @ 85kg" (o "2x3 @ 85kg · por lado").
  String get label {
    final weightLabel =
        weight == weight.roundToDouble()
            ? weight.toInt().toString()
            : weight.toString();
    final repsLabel = reps > 0 ? '${count}x$reps' : '$count series';
    return '$repsLabel @ ${weightLabel}kg${perSide ? ' · por lado' : ''}';
  }
}

class PlannedLoadService {
  static const double defaultRoundingKg = 2.5;

  /// Agrupa una lista plana de `sets` (`{weight, reps, perSide}` por serie)
  /// en grupos de series consecutivas con el mismo peso y reps — es la
  /// forma correcta de MOSTRAR un ejercicio cuando sus series tienen
  /// valores distintos entre sí (ej. 2 series a 85kg y 1 serie a 90kg),
  /// en vez de colapsar todo a un solo número o listar cada serie suelta.
  static List<SetGroup> groupSets(List<Map<String, dynamic>> sets) {
    if (sets.isEmpty) return const [];
    final groups = <SetGroup>[];
    for (final rawSet in sets) {
      final weight = (rawSet['weight'] as num?)?.toDouble() ?? 0;
      final reps = (rawSet['reps'] as num?)?.toInt() ?? 0;
      final perSide = rawSet['perSide'] == true;
      if (groups.isNotEmpty &&
          groups.last.weight == weight &&
          groups.last.reps == reps &&
          groups.last.perSide == perSide) {
        final last = groups.removeLast();
        groups.add(
          SetGroup(
            weight: weight,
            reps: reps,
            count: last.count + 1,
            perSide: perSide,
          ),
        );
      } else {
        groups.add(
          SetGroup(weight: weight, reps: reps, count: 1, perSide: perSide),
        );
      }
    }
    return groups;
  }

  /// Texto de una línea con todos los grupos de un ejercicio, separados por
  /// " / " — ej. "2x3 @ 85kg / 1x3 @ 90kg".
  static String formatSetGroups(List<Map<String, dynamic>> sets) {
    final groups = groupSets(sets);
    if (groups.isEmpty) return '';
    return groups.map((g) => g.label).join(' / ');
  }

  static String exerciseKey(Map exercise, int index) {
    final explicit = exercise['instanceId']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final exerciseId = exercise['exerciseId']?.toString() ?? 'legacy';
    final variantId = exercise['variantId']?.toString() ?? 'original';
    return '${exerciseId}_${variantId}_$index';
  }

  static List<Map<String, dynamic>> baseSets(Map exercise) {
    if (exercise['sets'] is List && (exercise['sets'] as List).isNotEmpty) {
      return List<Map<String, dynamic>>.from(
        exercise['sets'] as List,
      ).map((set) => Map<String, dynamic>.from(set)).toList();
    }
    final count = math.max(1, (exercise['series'] as num?)?.toInt() ?? 1);
    final reps =
        exercise['reps'] ?? exercise['value'] ?? exercise['targetReps'] ?? 0;
    final rawWeight = exercise['weight'] ?? exercise['referenceWeight'] ?? 0;
    final weight = rawWeight is num ? rawWeight.toDouble() : 0.0;
    return List.generate(
      count,
      (_) => {
        'reps': reps,
        'weight': weight,
        'perSide': exercise['perSide'] == true,
      },
    );
  }

  static Map<String, dynamic> resolveBlock({
    required Map<String, dynamic> block,
    required Map<String, dynamic> planned,
  }) {
    final resolved = Map<String, dynamic>.from(block);
    final overrides = <String, Map<String, dynamic>>{
      for (final raw in (planned['loadOverrides'] as List? ?? const []))
        if (raw is Map && raw['exerciseInstanceId'] != null)
          raw['exerciseInstanceId'].toString(): Map<String, dynamic>.from(raw),
    };
    final exercises = List<Map<String, dynamic>>.from(
      block['exercises'] ?? const [],
    );
    resolved['plannedWorkoutId'] = planned['id'];
    resolved['blockId'] = planned['blockId'];
    resolved['progressionGroupId'] = planned['progressionGroupId'];
    resolved['progressionIndex'] = planned['progressionIndex'];
    resolved['exercises'] = <Map<String, dynamic>>[
      for (var index = 0; index < exercises.length; index++)
        _resolveExercise(
          exercises[index],
          exerciseKey(exercises[index], index),
          overrides[exerciseKey(exercises[index], index)],
          planned,
        ),
    ];
    return resolved;
  }

  static Map<String, dynamic> _resolveExercise(
    Map<String, dynamic> exercise,
    String key,
    Map<String, dynamic>? override,
    Map<String, dynamic> planned,
  ) {
    final result = Map<String, dynamic>.from(exercise);
    final originalSets = baseSets(exercise);
    final overrideSets = List<Map<String, dynamic>>.from(
      override?['sets'] ?? const [],
    );
    final resolvedSets = <Map<String, dynamic>>[];
    // Las correcciones manuales pueden agregar series nuevas, no solo cambiar
    // el peso de las existentes — por eso el máximo con `originalSets`.
    // Cuando el override declara `totalSets` explícito (por ejemplo, un
    // editor que permite REDUCIR la cantidad de series, no solo agregar),
    // se respeta esa cantidad exacta en vez de inferirla como un máximo.
    final explicitTotalSets = (override?['totalSets'] as num?)?.toInt();
    final totalSets =
        explicitTotalSets ?? math.max(originalSets.length, overrideSets.length);
    for (var i = 0; i < totalSets; i++) {
      final overrideSet = i < overrideSets.length ? overrideSets[i] : const {};
      final base =
          i < originalSets.length
              ? Map<String, dynamic>.from(originalSets[i])
              : <String, dynamic>{
                'reps': exercise['reps'] ?? exercise['value'] ?? 0,
                'weight': 0,
                'perSide': exercise['perSide'] == true,
              };
      if (overrideSet['weight'] != null) {
        base['weight'] = overrideSet['weight'];
        base['loadSource'] = overrideSet['source'] ?? 'manual';
      } else {
        base['loadSource'] = 'base';
      }
      if (overrideSet['reps'] != null) base['reps'] = overrideSet['reps'];
      if (overrideSet['perSide'] != null) {
        base['perSide'] = overrideSet['perSide'] == true;
      }
      resolvedSets.add(base);
    }
    result['instanceId'] = key;
    result['exerciseInstanceId'] = key;
    result['plannedWorkoutId'] = planned['id'];
    result['blockId'] = planned['blockId'];
    result['progressionGroupId'] = planned['progressionGroupId'];
    result['sets'] = resolvedSets;
    result['series'] = resolvedSets.length;
    if (resolvedSets.isNotEmpty) {
      result['weight'] =
          resolvedSets
              .map((set) => (set['weight'] as num?)?.toDouble() ?? 0)
              .fold<double>(0, (total, value) => total + value) /
          resolvedSets.length;
    }
    result['plannedSetsSnapshot'] = [
      for (final set in resolvedSets)
        {
          'reps': set['reps'],
          'weight': set['weight'],
          'perSide': set['perSide'] == true,
        },
    ];
    return result;
  }

  static double roundLoad(double value, {double step = defaultRoundingKg}) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }

  /// Paso de redondeo real del equipo: las máquinas de polea/cable
  /// (pin-loaded) incrementan de 5 en 5 kg, a diferencia de una barra con
  /// discos pequeños que permite 2.5 kg.
  static double roundingStepFor(Map exercise) {
    final group = (exercise['group'] ?? '').toString().toLowerCase();
    final equipment = List<String>.from(exercise['equipment'] ?? const []);
    final isPulley =
        group.contains('polea') ||
        equipment.any((e) => e.toLowerCase().contains('polea'));
    return isPulley ? 5.0 : defaultRoundingKg;
  }

  static List<Map<String, dynamic>> generateOverrides({
    required Map<String, dynamic> block,
    required int progressionIndex,
    required List<Map<String, dynamic>> rules,
    List<Map<String, dynamic>> existing = const [],
  }) {
    final existingByKey = {
      for (final raw in existing)
        if (raw['exerciseInstanceId'] != null)
          raw['exerciseInstanceId'].toString(): raw,
    };
    final rulesByKey = {
      for (final rule in rules)
        if (rule['exerciseInstanceId'] != null)
          rule['exerciseInstanceId'].toString(): rule,
    };
    final exercises = List<Map<String, dynamic>>.from(
      block['exercises'] ?? const [],
    );
    final output = <Map<String, dynamic>>[];
    for (var index = 0; index < exercises.length; index++) {
      final exercise = exercises[index];
      final key = exerciseKey(exercise, index);
      final rule = rulesByKey[key];
      final previous = existingByKey[key];
      if (rule == null && previous == null) continue;
      final bases = baseSets(exercise);
      final previousSets = List<Map<String, dynamic>>.from(
        previous?['sets'] ?? const [],
      );
      final sets = <Map<String, dynamic>>[];
      for (var setIndex = 0; setIndex < bases.length; setIndex++) {
        if (setIndex < previousSets.length &&
            previousSets[setIndex]['source'] == 'manual') {
          sets.add(Map<String, dynamic>.from(previousSets[setIndex]));
          continue;
        }
        final baseWeight = (bases[setIndex]['weight'] as num?)?.toDouble() ?? 0;
        final mode = rule?['mode']?.toString() ?? 'manual';
        final referenceRm = (rule?['reference1RM'] as num?)?.toDouble() ?? 0;
        final effectiveMode =
            mode == 'suggested'
                ? (referenceRm > 0 ? 'percent1rm' : 'fixedKg')
                : mode;
        double weight = baseWeight;
        if (effectiveMode == 'fixedKg') {
          weight +=
              ((rule?['incrementKg'] as num?)?.toDouble() ?? 0) *
              progressionIndex;
        } else if (effectiveMode == 'percent1rm') {
          final rm = referenceRm;
          final percent =
              ((rule?['startPercent'] as num?)?.toDouble() ?? 0) +
              ((rule?['percentStep'] as num?)?.toDouble() ?? 0) *
                  progressionIndex;
          if (rm > 0) weight = rm * percent / 100;
        }
        sets.add({
          'weight': roundLoad(
            weight,
            step:
                (rule?['roundingKg'] as num?)?.toDouble() ??
                roundingStepFor(exercise),
          ),
          'source': effectiveMode == 'manual' ? 'manual' : 'automatic',
        });
      }
      output.add({'exerciseInstanceId': key, 'sets': sets});
    }
    return output;
  }
}
