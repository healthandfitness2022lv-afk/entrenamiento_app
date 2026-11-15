import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_set.dart';
import '../models/muscle_catalog.dart';
import '../utils/rpe_factor.dart';
import 'rpe_factor_service.dart';
import '../utils/muscle_utils.dart';
import '../utils/variant_resolver.dart';

class WorkoutLoadService {
  // ======================================================
  // 🔥 API PRINCIPAL
  // ======================================================
  static Future<Map<Muscle, double>> calculateLoadFromWorkout(
    Map<String, dynamic> workoutData,
  ) async {
    final performed = List<Map<String, dynamic>>.from(
      workoutData['performed'] ?? [],
    );

    if (performed.isEmpty) return {};

    await RpeFactorService().ensureLoaded();
    final exercisesMap = await _loadExercises(performed);
    final factors = await _fetchExerciseFolders();
    final workoutSets = _buildWorkoutSetsForHeatmap(performed, exercisesMap);

    return _calculateMuscleAccumulation(workoutSets, exercisesMap, factors);
  }

  // ======================================================
  // 🗓️ CARGA MUSCULAR DE UNA SESIÓN PLANIFICADA (RPE fijo)
  // ======================================================
  /// Igual que [calculateLoadFromWorkout] pero para bloques planificados
  /// (formato resuelto por `PlannedRoutineLoaderService`/`PlannedLoadService`,
  /// donde cada bloque tiene `exercises: [{name, sets: [{reps, weight}]}]`
  /// sin importar el tipo). Como todavía no hay un RPE real ejecutado, se usa
  /// un RPE fijo para estimar la carga muscular esperada de la sesión.
  static Future<Map<Muscle, double>> calculateLoadFromPlannedBlocks(
    List<Map<String, dynamic>> plannedBlocks, {
    double assumedRpe = 7.0,
  }) async {
    if (plannedBlocks.isEmpty) return {};
    await RpeFactorService().ensureLoaded();

    final exercisesById = await _loadExercisesFromPlannedBlocks(plannedBlocks);
    final factors = await _fetchExerciseFolders();
    // `_calculateMuscleAccumulation` busca por `WorkoutSet.exercise` (el
    // nombre planificado, no el id), así que le pasamos un mapa indexado
    // por ese mismo nombre para que pueda resolver `exerciseType`.
    final Map<String, Map<String, dynamic>> exercisesByName = {};
    for (final block in plannedBlocks) {
      for (final rawEx in (block['exercises'] as List? ?? const [])) {
        final ex = Map<String, dynamic>.from(rawEx as Map);
        final name = ex['name']?.toString();
        if (name == null) continue;
        final matched = _matchPlannedExercise(ex, exercisesById);
        if (matched != null) exercisesByName[name] = matched;
      }
    }
    final workoutSets = _buildWorkoutSetsFromPlannedBlocks(
      plannedBlocks,
      exercisesById,
      assumedRpe,
    );

    return _calculateMuscleAccumulation(workoutSets, exercisesByName, factors);
  }

  /// Ejercicios planificados que traen `exerciseId` (caso normal, ejercicios
  /// creados desde el catálogo de movimientos) se resuelven por ID directo.
  /// El nombre guardado en el bloque suele ser el compuesto
  /// "nombre base - variante" (ej. "Sentadilla - Salto vertical"), que
  /// NO existe como `name` en `exercises` (el doc base es solo "Sentadilla"
  /// con la variante dentro de `variants[]`), así que buscar por nombre
  /// exacto falla salvo que no haya `exerciseId` (planes legacy).
  static Future<Map<String, Map<String, dynamic>>>
  _loadExercisesFromPlannedBlocks(List<Map<String, dynamic>> blocks) async {
    final Set<String> ids = {};
    final Set<String> namesWithoutId = {};

    for (final block in blocks) {
      for (final rawEx in (block['exercises'] as List? ?? const [])) {
        final ex = rawEx as Map;
        final id = ex['exerciseId']?.toString();
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        } else if (ex['name'] != null) {
          namesWithoutId.add(ex['name'].toString());
        }
      }
    }

    final Map<String, Map<String, dynamic>> exercisesById = {};

    if (ids.isNotEmpty) {
      final docs = await Future.wait(
        ids.map(
          (id) =>
              FirebaseFirestore.instance.collection('exercises').doc(id).get(),
        ),
      );
      for (final doc in docs) {
        if (doc.exists) exercisesById[doc.id] = doc.data()!;
      }
    }

    if (namesWithoutId.isNotEmpty) {
      final snap =
          await FirebaseFirestore.instance
              .collection('exercises')
              .where('name', whereIn: namesWithoutId.toList())
              .get();
      for (final d in snap.docs) {
        exercisesById[d.id] = d.data();
      }
    }

    return exercisesById;
  }

  /// Resuelve el ejercicio planificado contra el catálogo cargado, igual
  /// criterio que `WorkoutSaveService._getExerciseFromCatalog`: primero por
  /// `exerciseId`, y si no está disponible, por nombre exacto o por el
  /// nombre compuesto "base - variante" de alguna de sus variantes.
  static Map<String, dynamic>? _matchPlannedExercise(
    Map<String, dynamic> ex,
    Map<String, Map<String, dynamic>> exercisesById,
  ) {
    final id = ex['exerciseId']?.toString();
    if (id != null && exercisesById.containsKey(id)) {
      return exercisesById[id];
    }

    final name = ex['name']?.toString();
    if (name == null) return null;

    for (final catalogEx in exercisesById.values) {
      if (catalogEx['name']?.toString() == name) return catalogEx;
      final variants = catalogEx['variants'];
      if (variants is! List) continue;
      final match = variants.whereType<Map>().any((raw) {
        final label = (raw['label'] ?? '').toString();
        return '${catalogEx['name']} - $label' == name;
      });
      if (match) return catalogEx;
    }
    return null;
  }

  static List<WorkoutSet> _buildWorkoutSetsFromPlannedBlocks(
    List<Map<String, dynamic>> blocks,
    Map<String, Map<String, dynamic>> exercisesById,
    double assumedRpe,
  ) {
    final List<WorkoutSet> result = [];

    for (final block in blocks) {
      final String sourceType = (block['type'] ?? 'Series').toString();
      // En un bloque Circuito, `exercises` representa UNA ronda; hay que
      // contar la carga de todas las rondas planificadas.
      final int rounds =
          sourceType == 'Circuito'
              ? math.max(1, (block['rounds'] as num?)?.toInt() ?? 1)
              : 1;

      for (final rawEx in (block['exercises'] as List? ?? const [])) {
        final ex = rawEx as Map<String, dynamic>;
        final String? name = ex['name']?.toString();
        if (name == null) continue;

        final catalogExercise = _matchPlannedExercise(ex, exercisesById);
        if (catalogExercise == null) continue;

        // Igual criterio que `_resolveExecutionMuscleWeights`: los
        // overrides de músculo guardados en el propio ejercicio planificado
        // (por variante) tienen prioridad sobre el catálogo genérico.
        final overrides = ex['muscleWeightOverrides'];
        final muscleWeights =
            (overrides is Map && overrides.isNotEmpty)
                ? decodeMuscleWeights({
                  'muscleWeights': Map<String, dynamic>.from(overrides),
                })
                : _resolveMuscleWeightsFromExercise(catalogExercise);
        final sets = (ex['sets'] as List? ?? const []);

        for (final rawSet in sets) {
          final set = rawSet as Map<String, dynamic>;
          for (var round = 0; round < rounds; round++) {
            result.add(
              WorkoutSet(
                exercise: name,
                sets: 1,
                reps: (set['reps'] as num?)?.toInt() ?? 1,
                rpe: assumedRpe,
                weight: (set['weight'] as num?)?.toDouble() ?? 0.0,
                perSide: (ex['perSide'] == true) || (set['perSide'] == true),
                muscleWeights: muscleWeights,
                sourceType: sourceType,
              ),
            );
          }
        }
      }
    }

    return result;
  }

  // 📂 OBTENER CARPETAS Y PONDERADORES
  /// Multiplicador por tipo de ejercicio (`exercise_folders`).
  static Future<Map<String, double>> fetchExerciseFolders() =>
      _fetchExerciseFolders();

  static Future<Map<String, double>> _fetchExerciseFolders() async {
    final snap =
        await FirebaseFirestore.instance.collection('exercise_folders').get();
    final Map<String, double> factors = {};
    for (var doc in snap.docs) {
      final name = doc.data()['name'] as String?;
      final multiplier = (doc.data()['multiplier'] ?? 1.0).toDouble();
      if (name != null) factors[name] = multiplier;
    }
    return factors;
  }

  // ======================================================
  // 🔎 CARGAR EJERCICIOS USADOS
  // ======================================================
  /// Catálogo de los ejercicios usados en `performed`, indexado por el
  /// nombre guardado (por `exerciseId`, con fallback por nombre/variante).
  static Future<Map<String, Map<String, dynamic>>> loadExercisesForPerformed(
    List<Map<String, dynamic>> performed,
  ) => _loadExercises(performed);

  static Future<Map<String, Map<String, dynamic>>> _loadExercises(
    List<Map<String, dynamic>> performed,
  ) async {
    // Por cada nombre de ejercicio guardado en `performed`, recordamos el
    // `exerciseId` que haya venido junto (si vino) para poder resolver por
    // ID, igual criterio que `_matchPlannedExercise`.
    final Map<String, String?> idByName = {};

    void collect(Map ex) {
      final name = ex['exercise'];
      if (name == null) return;
      final id = ex['exerciseId']?.toString();
      if (id != null && id.isNotEmpty) {
        idByName[name] = id;
      } else {
        idByName.putIfAbsent(name, () => null);
      }
    }

    for (final e in performed) {
      // 🔵 SERIES
      if (e['type'] == 'Series' ||
          e['type'] == 'Series descendentes' ||
          e['type'] == 'Buscar RM') {
        for (final ex in e['exercises'] ?? []) {
          collect(ex as Map);
        }
      }

      // 🔴 CIRCUITO
      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final ex in round['exercises'] ?? []) {
            collect(ex as Map);
          }
        }
      }

      // 🟣 TABATA
      if (e['type'] == 'Tabata') {
        for (final ex in e['exercises'] ?? []) {
          collect(ex as Map);
        }
      }
    }

    if (idByName.isEmpty) return {};

    // 1) Resolver por `exerciseId` (método principal, robusto: apunta
    // directo al doc canónico sin depender del texto del nombre).
    final ids = idByName.values.whereType<String>().toSet();
    final Map<String, Map<String, dynamic>> byId = {};
    if (ids.isNotEmpty) {
      final docs = await Future.wait(
        ids.map(
          (id) =>
              FirebaseFirestore.instance.collection('exercises').doc(id).get(),
        ),
      );
      for (final doc in docs) {
        if (doc.exists) byId[doc.id] = doc.data()!;
      }
    }

    final Map<String, Map<String, dynamic>> exercisesMap = {};
    final Set<String> namesNeedingNameLookup = {};

    idByName.forEach((name, id) {
      final byIdMatch = id != null ? byId[id] : null;
      if (byIdMatch != null) {
        exercisesMap[name] = byIdMatch;
      } else {
        namesNeedingNameLookup.add(name);
      }
    });

    if (namesNeedingNameLookup.isEmpty) return exercisesMap;

    // 2) Fallback por nombre (workouts legacy sin `exerciseId`, o `id`
    // apuntando a un doc que ya no existe). El nombre guardado puede ser el
    // compuesto "nombre base - variante" (ver `_matchPlannedExercise`), que
    // no existe como `name` de ningún doc en `exercises` (el doc base solo
    // tiene el nombre sin variante, con la variante dentro de `variants[]`).
    // Por eso buscamos tanto por el nombre completo como por su posible
    // nombre base.
    final Set<String> lookupNames = {};
    for (final name in namesNeedingNameLookup) {
      lookupNames.add(name);
      final idx = name.indexOf(' - ');
      if (idx > 0) lookupNames.add(name.substring(0, idx));
    }

    final Map<String, Map<String, dynamic>> byCatalogName = {};
    for (final batch in _chunk(lookupNames.toList(), 10)) {
      final snap =
          await FirebaseFirestore.instance
              .collection('exercises')
              .where('name', whereIn: batch)
              .get();
      for (final d in snap.docs) {
        byCatalogName[d['name']] = d.data();
      }
    }

    for (final name in namesNeedingNameLookup) {
      // 2a) Match exacto (ejercicios sin variante)
      final exact = byCatalogName[name];
      if (exact != null) {
        exercisesMap[name] = exact;
        continue;
      }

      // 2b) Match por nombre compuesto "base - variante"
      for (final catalogEx in byCatalogName.values) {
        final variants = catalogEx['variants'];
        if (variants is! List) continue;
        final match = variants.whereType<Map>().any((raw) {
          final label = (raw['label'] ?? '').toString();
          return '${catalogEx['name']} - $label' == name;
        });
        if (match) {
          exercisesMap[name] = catalogEx;
          break;
        }
      }
    }

    return exercisesMap;
  }

  static Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, math.min(i + size, items.length));
    }
  }

  // ======================================================
  // 🧱 CONSTRUIR WORKOUT SETS
  // ======================================================
  static List<WorkoutSet> _buildWorkoutSetsForHeatmap(
    List<Map<String, dynamic>> performed,
    Map<String, Map<String, dynamic>> exercisesMap,
  ) {
    final List<WorkoutSet> result = [];

    for (final e in performed) {
      // ======================
      // 🔵 SERIES
      // ======================
      if (e['type'] == 'Series' ||
          e['type'] == 'Series descendentes' ||
          e['type'] == 'Buscar RM') {
        for (final exEntry in e['exercises'] ?? []) {
          final String? name = exEntry['exercise'];
          if (name == null) continue;

          final ex = exercisesMap[name];
          if (ex == null) continue;

          final muscleWeights = _resolveMuscleWeightsFromExercise(
            ex,
            variantId: exEntry['variantId']?.toString(),
            variantLabel: exEntry['variantLabel']?.toString(),
          );

          for (final s in exEntry['sets'] ?? []) {
            result.add(
              WorkoutSet(
                exercise: name,
                sets: 1,
                reps: (s['reps'] as num?)?.toInt() ?? 1,
                rpe: (s['rpe'] as num?)?.toDouble() ?? defaultSeriesRpe,
                weight: (s['weight'] as num?)?.toDouble() ?? 0.0,
                perSide: (exEntry['perSide'] == true) || (s['perSide'] == true),
                muscleWeights: muscleWeights,
                sourceType: 'Series',
              ),
            );
          }
        }
      }
      // ======================
      // 🔴 CIRCUITO
      // ======================
      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final exEntry in round['exercises'] ?? []) {
            final String? name = exEntry['exercise'];
            if (name == null) continue;

            final ex = exercisesMap[name];
            if (ex == null) continue;

            final muscleWeights = _resolveMuscleWeightsFromExercise(
              ex,
              variantId: exEntry['variantId']?.toString(),
              variantLabel: exEntry['variantLabel']?.toString(),
            );

            result.add(
              WorkoutSet(
                exercise: name,
                sets: 1,
                reps: (exEntry['reps'] as num?)?.toInt() ?? 1,
                rpe: (exEntry['rpe'] as num?)?.toDouble() ?? 5.0,
                weight: (exEntry['weight'] as num?)?.toDouble() ?? 0.0,
                perSide: exEntry['perSide'] == true,
                muscleWeights: muscleWeights,
                sourceType: 'Circuito',
              ),
            );
          }
        }
      }

      // ======================
      // 🟣 TABATA
      // ======================
      if (e['type'] == 'Tabata') {
        for (final exEntry in e['exercises'] ?? []) {
          final String? name = exEntry['exercise'];
          if (name == null) continue;

          final ex = exercisesMap[name];
          if (ex == null) continue;

          final muscleWeights = _resolveMuscleWeightsFromExercise(
            ex,
            variantId: exEntry['variantId']?.toString(),
            variantLabel: exEntry['variantLabel']?.toString(),
          );

          result.add(
            WorkoutSet(
              exercise: name,
              sets: 1,
              reps: 1,
              rpe: (exEntry['rpe'] as num?)?.toDouble() ?? 5.0,
              weight: (exEntry['weight'] as num?)?.toDouble() ?? 0.0,
              perSide: exEntry['perSide'] == true,
              muscleWeights: muscleWeights,
              sourceType: 'Tabata',
            ),
          );
        }
      }
    }

    return result;
  }

  // ======================================================
  // 🧠 RESOLVER MÚSCULOS DESDE EJERCICIO
  // ======================================================
  /// Fuente única para decodificar un mapa `{muscleName: weight}` crudo de
  /// Firestore a `Map<Muscle, double>`, incluyendo el alias legacy
  /// `traps` → `trapsUpper`. Pública para que otras pantallas (ej. detalle
  /// de workout) no mantengan su propia copia divergente.
  static Map<Muscle, double> decodeMuscleWeightsMap(Map raw) =>
      _decodeMuscleWeightsMap(raw);

  static Map<Muscle, double> _decodeMuscleWeightsMap(Map raw) {
    final Map<Muscle, double> result = {};
    raw.forEach((k, v) {
      if (v is! num) return;
      final key = k.toString();
      final value = v.toDouble();

      String normalizedKey = key;
      if (key == 'traps') normalizedKey = 'trapsUpper';

      final match = Muscle.values.where((m) => m.name == normalizedKey);

      if (match.isNotEmpty) {
        result[match.first] = (result[match.first] ?? 0) + value;
      }
    });
    return result;
  }

  /// Fuente única para resolver los `Muscle`→peso de un ejercicio ejecutado,
  /// incluyendo overrides de variante y el fallback legacy por
  /// `primaryMuscle`/`secondaryMuscles`. Pública por el mismo motivo que
  /// [decodeMuscleWeightsMap].
  static Map<Muscle, double> resolveMuscleWeightsFromExercise(
    Map<String, dynamic> ex, {
    String? variantId,
    String? variantLabel,
  }) => _resolveMuscleWeightsFromExercise(
    ex,
    variantId: variantId,
    variantLabel: variantLabel,
  );

  static Map<Muscle, double> _resolveMuscleWeightsFromExercise(
    Map<String, dynamic> ex, {
    String? variantId,
    String? variantLabel,
  }) {
    // La variante puede tener su propia ponderación (override), que tiene
    // prioridad sobre la ponderación base del ejercicio padre. Se resuelve
    // también por alias/label, por si el id guardado quedó obsoleto.
    if ((variantId != null && variantId.isNotEmpty) ||
        (variantLabel != null && variantLabel.isNotEmpty)) {
      final variant = resolveCatalogVariant(
        ex,
        variantId: variantId,
        variantLabel: variantLabel,
      );
      final overrides = variant?['muscleWeightOverrides'];
      if (overrides is Map && overrides.isNotEmpty) {
        return _decodeMuscleWeightsMap(overrides);
      }
    }

    final raw = ex['muscleWeights'];

    // 🟢 PONDERACIÓN MODERNA (del padre)
    if (raw is Map && raw.isNotEmpty) {
      return _decodeMuscleWeightsMap(raw);
    }

    // 🔁 FALLBACK (ejercicios antiguos)
    final Map<Muscle, double> result = {};
    // Ejercicios sin ponderación ni primaryMuscle (ej. recién creados o
    // incompletos) no deben romper el guardado: se ignoran valores nulos.
    final muscleNames = <String>[
      if (ex['primaryMuscle'] != null) ex['primaryMuscle'].toString(),
      for (final m in (ex['secondaryMuscles'] as List?) ?? const [])
        if (m != null) m.toString(),
    ];

    for (final name in muscleNames) {
      final mapping = normalizedMuscleCatalogMap[normalizeKey(name)];

      if (mapping == null) continue;

      mapping.forEach((muscle, weight) {
        result[muscle] = (result[muscle] ?? 0) + weight;
      });
    }

    return result;
  }

  // ======================================================
  // 🧮 CÁLCULO FINAL DE CARGA MUSCULAR
  // ======================================================
  static Map<Muscle, double> _calculateMuscleAccumulation(
    List<WorkoutSet> sets,
    Map<String, Map<String, dynamic>> exercisesMap,
    Map<String, double> factors,
  ) {
    final Map<Muscle, double> acc = {};

    for (final s in sets) {
      final ex = exercisesMap[s.exercise];
      final String? exerciseType = ex?['exerciseType'];

      final exerciseFactor = effectiveExerciseFactor(
        factors,
        exerciseType,
        s.weight ?? 0,
      );

      final blockFactor = structureFactor(s.sourceType);
      final double perSideFactor =
          1.0; // ✅ Mantenemos factor 1.0 (el usuario prefiere no duplicar por lado)

      for (final e in s.muscleWeights.entries) {
        final rpeF = rpeFactor(s.rpe);

        acc[e.key] =
            (acc[e.key] ?? 0) +
            (s.sets *
                s.rpe *
                rpeF *
                exerciseFactor *
                blockFactor *
                perSideFactor *
                e.value);
      }
    }

    return {for (final e in acc.entries) e.key: saturate(e.value)};
  }

  /// Curva de saturación de la carga cruda de una sesión: se acerca al 100%
  /// progresivamente sin pasarse.
  static double saturate(double rawLoad) =>
      100 * (1 - math.exp(-rawLoad / 45.0));

  /// Factor del tipo de ejercicio. Solo se escala a 1.0 si es un tipo de muy
  /// baja fatiga (Movilidad/Cardio < 0.8) usado con peso significativo
  /// (>7 kg); Accesorio (0.9), Core (0.85) o Isométrico (0.8) mantienen su
  /// factor aunque tengan peso.
  static double effectiveExerciseFactor(
    Map<String, double> factors,
    String? exerciseType,
    double weight,
  ) {
    final factor = factors[exerciseType ?? ''] ?? 1.0;
    if (weight > 7 && factor < 0.8) return 1.0;
    return factor;
  }

  /// RPE asumido cuando una serie no lo trae (datos legacy).
  static const double defaultSeriesRpe = 6;

  // ======================================================
  // 🧱 FACTOR POR ESTRUCTURA
  // ======================================================
  static double structureFactor(String sourceType) {
    switch (sourceType) {
      case 'Circuito':
        return 1.1; // Subido de 1.2
      case 'Tabata':
        return 2.5;
      default:
        return 1;
    }
  }
}
