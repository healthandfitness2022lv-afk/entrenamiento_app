import 'package:flutter/material.dart';
import '../services/workout_suggestion_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/tabata_timer_service.dart';

class LogWorkoutViewModel extends ChangeNotifier {
  // == Estado Base ==
  Map<String, dynamic>? routine;
  bool loading = true;
  DateTime? workoutStartedAt;
  
  // == Caché ==
  final Map<String, double?> _suggestedWeightCache = {};
  final Map<String, int?> _suggestedRepsCache = {};
  
  // == Series y Controles de Texto ==
  final Map<String, List<Map<String, dynamic>>> seriesData = {};
  final Map<String, List<TextEditingController>> seriesRepsCtrl = {};
  final Map<String, List<TextEditingController>> seriesWeightCtrl = {};
  
  // == Estado de la vista de Bloques ==
  final Map<int, bool> expandedBlocks = {};

  // == Cronómetros por Bloque ==
  /// Timestamp del momento en que se presionó "Comenzar" en cada bloque.
  final Map<int, DateTime> blockStartTimes = {};
  /// Duración final en segundos de cada bloque (null = no iniciado / en curso).
  final Map<int, int> blockDurationSeconds = {};
  
  // == Circuitos ==
  final Map<int, int> circuitoRound = {};
  final Map<int, Map<int, Map<String, TextEditingController>>> circuitoReps = {};
  final Map<int, Map<int, Map<String, TextEditingController>>> circuitoWeight = {};
  final Map<int, Map<int, Map<String, int>>> circuitoRpePorRonda = {};
  final Map<int, Map<int, Map<String, ValueNotifier<bool>>>> circuitoDone = {};
  final Map<int, Map<String, bool>> circuitoPerSide = {};

  // == Edición y Datos Previos ==
  DateTime? originalStartedAt;
  DateTime? originalFinishedAt;
  int? originalDurationMinutes;

  String normalizeExerciseName(dynamic raw) {
    if (raw is String) return raw;
    if (raw is List && raw.isNotEmpty) return raw.first.toString();
    return 'Ejercicio';
  }

  void notify() {
    notifyListeners();
  }

  // ============== Cronómetro por Bloque ==============

  /// Inicia (o reinicia) el cronómetro del bloque [index].
  void startBlockTimer(int index) {
    blockStartTimes[index] = DateTime.now();
    blockDurationSeconds.remove(index); // limpiar duración previa si existía
    notifyListeners();
  }

  /// Detiene el cronómetro del bloque [index] y guarda la duración.
  void stopBlockTimer(int index) {
    final start = blockStartTimes[index];
    if (start == null) return;
    blockDurationSeconds[index] =
        DateTime.now().difference(start).inSeconds;
    notifyListeners();
  }

  /// Retorna el tiempo transcurrido en segundos para un bloque en curso.
  /// Si ya finalizó, retorna la duración guardada.
  int elapsedSecondsForBlock(int index) {
    if (blockDurationSeconds.containsKey(index)) {
      return blockDurationSeconds[index]!;
    }
    final start = blockStartTimes[index];
    if (start == null) return 0;
    return DateTime.now().difference(start).inSeconds;
  }

  bool isBlockTimerRunning(int index) =>
      blockStartTimes.containsKey(index) &&
      !blockDurationSeconds.containsKey(index);

  // ============== Sugerencias de Pesos y Reps ==============
  
  void onRepsSubmitted(String exercise, int reps) {
    final key = "$exercise-$reps";
    // Elimina cache para forzar recálculo
    _suggestedWeightCache.remove(key);
    _loadSuggestionIfNeeded(exercise, reps);
  }

  Future<void> _loadSuggestionIfNeeded(String exercise, int reps) async {
    final key = "$exercise-$reps";
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final value = await WorkoutSuggestionService.suggestWeightForReps(
      userId: uid,
      exercise: exercise,
      targetReps: reps,
    );

    _suggestedWeightCache[key] = value;
    notifyListeners();
  }

  Future<void> loadRepsSuggestionIfNeeded(String exercise, double weight) async {
    final key = "$exercise-$weight";
    if (_suggestedRepsCache.containsKey(key)) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final value = await WorkoutSuggestionService.suggestMaxRepsForWeight(
      userId: uid,
      exercise: exercise,
      targetWeight: weight,
    );

    _suggestedRepsCache[key] = value;
    notifyListeners();
  }

  double? getSuggestedWeight(String exercise, int reps) {
    final key = "$exercise-$reps";
    if (!_suggestedWeightCache.containsKey(key)) {
      _loadSuggestionIfNeeded(exercise, reps); // dispara carga y avisa cuando termine
      return null;
    }
    return _suggestedWeightCache[key];
  }

  int? getSuggestedReps(String exercise, double weight) {
    final key = "$exercise-$weight";
    if (!_suggestedRepsCache.containsKey(key)) {
      loadRepsSuggestionIfNeeded(exercise, weight);
      return null;
    }
    return _suggestedRepsCache[key];
  }

  void reindexStateAfterDeletion(int deletedIndex) {
    Map<String, List<Map<String, dynamic>>> newSeriesData = {};
    Map<String, List<TextEditingController>> newSeriesReps = {};
    Map<String, List<TextEditingController>> newSeriesWeight = {};

    for (final entry in seriesData.entries) {
      final parts = entry.key.split('-');
      int blockIndex = int.parse(parts.first);
      final exercise = parts.sublist(1).join('-');

      if (blockIndex < deletedIndex) {
        newSeriesData[entry.key] = entry.value;
        newSeriesReps[entry.key] = seriesRepsCtrl[entry.key]!;
        newSeriesWeight[entry.key] = seriesWeightCtrl[entry.key]!;
      } else if (blockIndex > deletedIndex) {
        final newIndex = blockIndex - 1;
        final newKey = "$newIndex-$exercise";

        newSeriesData[newKey] = entry.value;
        newSeriesReps[newKey] = seriesRepsCtrl[entry.key]!;
        newSeriesWeight[newKey] = seriesWeightCtrl[entry.key]!;
      }
    }

    seriesData
      ..clear()
      ..addAll(newSeriesData);

    seriesRepsCtrl
      ..clear()
      ..addAll(newSeriesReps);

    seriesWeightCtrl
      ..clear()
      ..addAll(newSeriesWeight);
  }

  void initializeRoutineState({required bool isEdit}) {
    if (routine == null) return;
    for (int i = 0; i < routine!['blocks'].length; i++) {
      expandedBlocks[i] = false;
      final block = routine!['blocks'][i];

      if (block['type'] == 'Circuito') {
        if (isEdit) continue;

        circuitoRound[i] = 1;
        circuitoWeight[i] = {};
        circuitoReps[i] = {};
        circuitoRpePorRonda[i] = {};
        circuitoDone[i] = {};

        final int round = 1;
        circuitoWeight[i]![round] = {};
        circuitoReps[i]![round] = {};
        circuitoRpePorRonda[i]![round] = {};
        circuitoDone[i]![round] = {};
        circuitoPerSide[i] = {};

        for (final ex in block['exercises']) {
          final String name = normalizeExerciseName(ex['name']);
          circuitoPerSide[i]![name] = ex['perSide'] == true;
          circuitoReps[i]![round]![name] = TextEditingController(text: (ex['reps'] ?? 1).toString());
          circuitoWeight[i]![round]![name] = TextEditingController(text: (ex['weight'] ?? 0).toString());
          circuitoRpePorRonda[i]![round]![name] = 5;
          circuitoDone[i]![round]![name] = ValueNotifier(false);
        }
      }

      if (block['type'] == 'Series') {
        for (final ex in block['exercises']) {
          final name = normalizeExerciseName(ex['name']);
          final key = "$i-$name";
          final int sets = ex['series'] ?? 1;
          final String valueType = ex['valueType'] ?? 'reps';
          final int baseValue = ex['value'] ?? ex['reps'] ?? 0;

          seriesData[key] = List.generate(sets, (_) => {
            'valueType': valueType,
            'value': baseValue,
            'reps': valueType == 'reps' ? baseValue : null,
            'weight': ex['weight'],
            'rpe': 5,
            'done': false,
          });

          seriesRepsCtrl[key] = List.generate(sets, (j) => TextEditingController(
            text: seriesData[key]![j]['reps']?.toString() ?? '',
          ));

          seriesWeightCtrl[key] = List.generate(sets, (j) => TextEditingController(
            text: seriesData[key]![j]['weight']?.toString() ?? '',
          ));
        }
      }

      if (block['type'] == 'Series descendentes') {
        final schema = List<int>.from(block['schema'] ?? []);

        for (final ex in block['exercises']) {
          final name = normalizeExerciseName(ex['name']);
          final key = "$i-$name";

          seriesData[key] = schema.map((reps) => {
            'valueType': 'reps',
            'value': reps,
            'reps': reps,
            'weight': ex['weight'],
            'rpe': 5,
            'done': false,
          }).toList();

          seriesRepsCtrl[key] = schema.map((reps) => TextEditingController(text: reps.toString())).toList();
          seriesWeightCtrl[key] = schema.map((_) => TextEditingController(text: ex['weight']?.toString() ?? '')).toList();
        }
      }

      if (block['type'] == 'Buscar RM') {
        final int rmTarget = block['rm'] ?? 5;

        for (final ex in block['exercises']) {
          final name = normalizeExerciseName(ex['name']);
          final key = "$i-$name";
          final int targetReps = ex['reps'] ?? rmTarget;

          seriesData[key] = [{
            'valueType': 'reps',
            'value': targetReps,
            'reps': targetReps,
            'weight': ex['weight'],
            'rpe': 5,
            'done': false,
          }];

          seriesRepsCtrl[key] = [TextEditingController(text: targetReps.toString())];
          seriesWeightCtrl[key] = [TextEditingController(text: ex['weight']?.toString() ?? '')];
        }
      }
    }
  }

  void hydrateFromPerformed(List<Map<String, dynamic>> performed, TabataTimerService tabataTimer) {
    int circuitBlockCursor = 0;

    for (final e in performed) {
      if (e['type'] == 'Series' || e['type'] == 'Series descendentes' || e['type'] == 'Buscar RM') {
        final int blockIndex = (e['blockIndex'] as num?)?.toInt() ?? 0;
        final List exercises = (e['exercises'] as List?) ?? [];

        for (final ex in exercises) {
          final String name = normalizeExerciseName(ex['exercise']);
          final sets = (ex['sets'] as List<dynamic>? ?? []).map((x) => Map<String, dynamic>.from(x)).toList();
          final key = "$blockIndex-$name";

          if (!seriesData.containsKey(key)) continue;

          for (int i = 0; i < sets.length && i < seriesData[key]!.length; i++) {
            seriesData[key]![i]['reps'] = sets[i]['reps'];
            seriesData[key]![i]['weight'] = sets[i]['weight'];
            seriesData[key]![i]['rpe'] = sets[i]['rpe'];
            seriesData[key]![i]['done'] = true;

            seriesRepsCtrl[key]![i].text = sets[i]['reps']?.toString() ?? '';
            seriesWeightCtrl[key]![i].text = sets[i]['weight']?.toString() ?? '';
          }
        }
      }

      if (e['type'] == 'Circuito') {
        final blockIndex = routine!['blocks']
            .asMap()
            .entries
            .where((entry) => entry.value['type'] == 'Circuito')
            .elementAt(circuitBlockCursor)
            .key;

        circuitBlockCursor++;
        final List rounds = e['rounds'] ?? [];

        circuitoRound[blockIndex] = rounds.length;
        circuitoReps[blockIndex] = {};
        circuitoWeight[blockIndex] = {};
        circuitoRpePorRonda[blockIndex] = {};
        circuitoDone[blockIndex] = {};
        circuitoPerSide[blockIndex] = {};

        for (final r in rounds) {
          final int round = r['round'];
          circuitoReps[blockIndex]![round] = {};
          circuitoWeight[blockIndex]![round] = {};
          circuitoRpePorRonda[blockIndex]![round] = {};
          circuitoDone[blockIndex]![round] = {};
          circuitoPerSide.putIfAbsent(blockIndex, () => {});

          for (final ex in r['exercises']) {
            final String name = normalizeExerciseName(ex['exercise']);
            circuitoReps[blockIndex]![round]![name] = TextEditingController(text: ex['reps']?.toString() ?? '1');
            circuitoWeight[blockIndex]![round]![name] = TextEditingController(text: ex['weight']?.toString() ?? '');
            circuitoRpePorRonda[blockIndex]![round]![name] = ex['rpe'] ?? 5;
            circuitoDone[blockIndex]![round]![name] = ValueNotifier(true);
            circuitoPerSide[blockIndex]![name] = ex['perSide'] == true;
          }
        }
      }

      if (e['type'] == 'Tabata') {
        final int blockIndex = e['blockIndex'];
        final List exercises = e['exercises'] ?? [];

        tabataTimer.markBlockHydrated(
          blockIndex,
          {for (final ex in exercises) normalizeExerciseName(ex['exercise']): ex['rpe']},
        );
      }
    }
  }
}
