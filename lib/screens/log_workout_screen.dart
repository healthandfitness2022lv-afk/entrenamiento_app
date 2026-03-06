import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/fatigue_service.dart';
import '../models/muscle_catalog.dart';
import '../models/workout_set.dart';
import '../services/tabata_timer_service.dart';
import '../services/workout_load_service.dart';
import 'add_workout_screen.dart';
import '../services/workout_suggestion_service.dart';
import '/widgets/series_block_widget.dart';
import '../widgets/circuit_block_widget.dart';
import '../widgets/tabata_block_widget.dart';
import 'dart:math';
import '../widgets/descending_series_block_widget.dart';
import '../widgets/buscar_rm_block_widget.dart';
import '../services/workout_save_service.dart';
import '../widgets/log_workout_dialogs.dart';
import '../widgets/achievement_dialog.dart';
import '../screens/workout_summary_screen.dart';
import '../services/workout_rm_service.dart';
import '../services/progress_alert_service.dart';
import '../services/workout_volume_service.dart';


import '../view_models/log_workout_view_model.dart';

class LogWorkoutScreen extends StatefulWidget {
  final Map<String, dynamic>? existingWorkout;
  final DocumentReference? workoutRef;

  const LogWorkoutScreen({
    super.key,
    this.existingWorkout,
    this.workoutRef,
  });


  @override
  State<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends State<LogWorkoutScreen>
    with TickerProviderStateMixin {
  late final LogWorkoutViewModel viewModel;

  List<Map<String, dynamic>> availableRoutines = [];
  bool get isEdit => widget.workoutRef != null;
  List<Map<String, dynamic>> availableExercisesCatalog = [];
  late final TabataTimerService tabataTimer;
  final Map<String, String> exerciseInstructionsCache = {};
  bool _saving = false;
  String _savingStep = "";
  Timer? _blockTickerTimer;

  @override
  void dispose() {
    _blockTickerTimer?.cancel();
    tabataTimer.stop();
    viewModel.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    viewModel = LogWorkoutViewModel();
    viewModel.addListener(_onViewModelChanged);
    viewModel.workoutStartedAt = DateTime.now(); // 🔥 inicio automático
    tabataTimer = TabataTimerService();
    _loadExerciseCatalog(); // 👈 NUEVO

    if (isEdit) {
      _loadWorkoutForEdit();
    } else {
      _loadInitialWorkout();
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    // Arrancar / detener el ticker según haya bloques corriendo
    final anyRunning = viewModel.blockStartTimes.keys
        .any((i) => !viewModel.blockDurationSeconds.containsKey(i));
    if (anyRunning && _blockTickerTimer == null) {
      _blockTickerTimer =
          Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!anyRunning) {
      _blockTickerTimer?.cancel();
      _blockTickerTimer = null;
    }
    setState(() {});
  }



/// Carga TODOS los bloques planificados para hoy y los une en una sola
/// estructura de "rutina" con múltiples bloques, compatible con el ViewModel.
Future<Map<String, dynamic>?> _getTodayPlannedRoutine() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;

  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final end = start.add(const Duration(days: 1));

  final snap = await FirebaseFirestore.instance
      .collection('planned_workouts')
      .where('athleteId', isEqualTo: uid)
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('date', isLessThan: Timestamp.fromDate(end))
      .get();

  if (snap.docs.isEmpty) return null;

  // Recolectar todos los bloques del día
  final List<Map<String, dynamic>> allBlocks = [];
  final List<String> blockTitles = [];

  for (final planned in snap.docs) {
    final data = planned.data();

    // Nuevo formato: blockId
    if (data.containsKey('blockId') && data['blockId'] != null) {
      final blockDoc = await FirebaseFirestore.instance
          .collection('blocks')
          .doc(data['blockId'] as String)
          .get();

      if (blockDoc.exists) {
        allBlocks.add({...blockDoc.data()!});
        blockTitles.add(data['blockTitle'] ?? blockDoc.data()?['title'] ?? 'Bloque');
      }
    }
  }

  if (allBlocks.isEmpty) return null;

  return {
    'id': null,
    'name': blockTitles.length == 1
        ? blockTitles.first
        : 'Sesión del día (${allBlocks.length} bloques)',
    'blocks': allBlocks,
  };
}



  void _onRepsSubmitted(String exercise, int reps) {
    viewModel.onRepsSubmitted(exercise, reps);
  }

  Widget _suggestedRepsText(String exercise, double weight) {
    final value = viewModel.getSuggestedReps(exercise, weight);

    if (value == null) {
      return const Text(
        "Sin historial para ese peso",
        style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }

    return Text(
      "Máx reps: $value",
      style: const TextStyle(fontSize: 12, color: Colors.blue, fontStyle: FontStyle.italic),
    );
  }

  Widget _suggestedWeightText(String exercise, int reps) {
    final value = viewModel.getSuggestedWeight(exercise, reps);

    if (value == null) {
      return const Text(
        "Sin sugerencias",
        style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }

    return Text(
      "Sugerido: ${value.toStringAsFixed(1)} kg",
      style: const TextStyle(fontSize: 12, color: Colors.green, fontStyle: FontStyle.italic),
    );
  }



Future<void> _loadExerciseCatalog() async {
  final snap = await FirebaseFirestore.instance
      .collection('exercises')
      .orderBy('name')
      .get();

  availableExercisesCatalog = snap.docs.map((d) {
    return {
      'id': d.id,
      ...d.data(),
    };
  }).toList();
}

Map<String, dynamic>? _getExerciseFromCatalog(String name) {
  try {
    return availableExercisesCatalog.firstWhere(
      (e) => viewModel.normalizeExerciseName(e['name']) == name,
    );
  } catch (_) {
    return null;
  }
}




  void _loadWorkoutForEdit() {
    final workout = widget.existingWorkout!;

    viewModel.originalStartedAt = (workout['startedAt'] as Timestamp?)?.toDate();
    viewModel.originalFinishedAt = (workout['finishedAt'] as Timestamp?)?.toDate();
    viewModel.originalDurationMinutes = (workout['durationMinutes'] as num?)?.toInt();

    final performed = (workout['performed'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    viewModel.routine = {
      'id': workout['blockId'],
      'name': workout['blockTitle'] ?? workout['routineName'] ?? 'Entrenamiento',
      'blocks': _rebuildBlocksFromPerformed(performed),
    };

    viewModel.initializeRoutineState(isEdit: isEdit);
    viewModel.hydrateFromPerformed(performed, tabataTimer);

    if (mounted) setState(() => viewModel.loading = false);
  }





List<Map<String, dynamic>> _rebuildBlocksFromPerformed(
  List<Map<String, dynamic>> performed,
) {
  final Map<int, Map<String, dynamic>> blocksMap = {};

  for (final e in performed) {
    final String type = (e['type'] ?? '').toString();
    final int blockIndex = (e['blockIndex'] as num?)?.toInt() ?? 0;

    blocksMap.putIfAbsent(blockIndex, () {
      return {
        'type': type,
        'title': e['blockTitle'],
        'exercises': <Map<String, dynamic>>[],
      };
    });

    // ================= SERIES Y DESCENDENTES =================
    if (type == 'Series' || type == 'Series descendentes' || type == 'Buscar RM') {

  final List exList =
      (e['exercises'] as List?) ?? const [];

  for (final ex in exList) {
    if (ex is! Map) continue;

    final String name =
        viewModel.normalizeExerciseName(ex['exercise']);

    final List sets =
        (ex['sets'] as List?) ?? const [];

    if (name.isEmpty || sets.isEmpty) continue;

    if (type == 'Series descendentes') {
      blocksMap[blockIndex]!['schema'] = sets.map((s) => s['reps'] as int).toList();
    }
    if (type == 'Buscar RM') {
      blocksMap[blockIndex]!['rm'] = sets.isNotEmpty ? sets.last['reps'] as int : 5;
    }

    blocksMap[blockIndex]!['exercises'].add({
      'name': name,
      'series': sets.length,
      'reps': (sets.first as Map)['reps'],
      'valueType': 'reps',
      'weight': (sets.first as Map)['weight'],
      'perSide': ex['perSide'] == true,
    });
  }
}

    // ================= CIRCUITO =================
    if (type == 'Circuito') {
      blocksMap[blockIndex] = {
        'type': 'Circuito',
        'title': e['blockTitle'],
        'rounds': (e['rounds'] as List?)?.length ?? 1,
        'exercises': _extractCircuitExercises(e),
      };
    }

    // ================= TABATA =================
    if (type == 'Tabata') {
      blocksMap[blockIndex] = {
        'type': 'Tabata',
        'title': e['blockTitle'],
        'work': e['work'],
        'rest': e['rest'],
        'rounds': e['rounds'],
        'exercises': (e['exercises'] as List?)
                ?.map((x) => {'name': (x as Map)['exercise']})
                .toList() ??
            [],
      };
    }
  }

  final sortedKeys = blocksMap.keys.toList()..sort();
  return sortedKeys.map((k) => blocksMap[k]!).toList();
}

List<Map<String, dynamic>> _extractCircuitExercises(
  Map<String, dynamic> e,
) {
  final List<Map<String, dynamic>> exercises = [];

  final roundsRaw = (e['rounds'] as List?) ?? const [];

  for (final r in roundsRaw) {
    final exs = (r['exercises'] as List?) ?? const [];

    for (final ex in exs) {
      final name = viewModel.normalizeExerciseName(ex['exercise']);

      if (!exercises.any((x) => x['name'] == name)) {
        exercises.add({
          'name': name,
          'reps': ex['reps'] ?? 1,
        });
      }
    }
  }

  return exercises;
}


  // ================= HELPERS =================

  bool _isPerSide(Map<String, dynamic> ex) {
    return ex['perSide'] == true;
  }

  String? _getEquipment(Map<String, dynamic> ex) {
    return ex['equipment'];
  }

  Future<String?> _getExerciseInstructions(String exerciseName) async {
  final snap = await FirebaseFirestore.instance
      .collection('exercises')
      .where('name', isEqualTo: exerciseName)
      .limit(1)
      .get();

  if (snap.docs.isEmpty) return null;

  final instructions = snap.docs.first.data()['instructions'];
  return instructions is String ? instructions : null;
}


  // ================= LOAD =================

  /// Carga todos los bloques disponibles en segundo plano para el selector.
  Future<void> _loadAvailableRoutinesBackground() async {
    final blocksSnap = await FirebaseFirestore.instance
        .collection('blocks')
        .orderBy('createdAt', descending: true)
        .get();

    availableRoutines.clear();

    for (final d in blocksSnap.docs) {
      final data = d.data();
      final title = (data['title'] ?? '').toString().trim();
      final type = (data['type'] ?? 'Bloque').toString();
      // Envolvemos el bloque individual en el formato que espera el ViewModel
      availableRoutines.add({
        'id': d.id,
        'name': title.isNotEmpty ? title : type,
        'blocks': [data],
      });
    }
  }

  Future<void> _loadInitialWorkout() async {
    final plannedRoutine = await _getTodayPlannedRoutine();
    
    // Cargar las demás en segundo plano para el selector desplegable
    await _loadAvailableRoutinesBackground();

    if (plannedRoutine != null) {
      _changeRoutine({
        'id': plannedRoutine['id'],
        ...plannedRoutine,
      });
    } else {
      _startFreeWorkout();
    }
  }
  
  void _changeRoutine(Map<String, dynamic>? newRoutine) {
    viewModel.seriesData.clear();
    viewModel.seriesRepsCtrl.clear();
    viewModel.seriesWeightCtrl.clear();
    viewModel.expandedBlocks.clear();
    viewModel.circuitoRound.clear();
    viewModel.circuitoReps.clear();
    viewModel.circuitoWeight.clear();
    viewModel.circuitoRpePorRonda.clear();
    viewModel.circuitoDone.clear();
    viewModel.circuitoPerSide.clear();
    tabataTimer.stop();

    if (newRoutine == null) {
      viewModel.routine = {
        'id': null,
        'name': 'Entrenamiento libre',
        'blocks': <Map<String, dynamic>>[],
      };
    } else {
      viewModel.routine = newRoutine;
    }

    viewModel.initializeRoutineState(isEdit: isEdit);
    if (mounted) setState(() => viewModel.loading = false);
  }

  // ================= INFO =================

  void _showExerciseInfo(Map<String, dynamic> ex) async {
    final String name = viewModel.normalizeExerciseName(ex['name']);
    await LogWorkoutDialogs.showExerciseInfo(
      context: context,
      name: name,
      fetchInstructions: _getExerciseInstructions,
    );
  }


  // ================= HEADER BLOQUE =================

  Widget _blockHeader(int index, Map<String, dynamic> block) {
  final bool expanded = viewModel.expandedBlocks[index] ?? false;
  final theme = Theme.of(context);
  final String blockType = (block['type'] ?? 'Bloque').toString();
  final bool timerRunning = viewModel.isBlockTimerRunning(index);
  final bool timerStarted = viewModel.blockStartTimes.containsKey(index);
  final int elapsed = viewModel.elapsedSecondsForBlock(index);
  final bool timerFinished =
      timerStarted && !timerRunning;

  // Formato mm:ss
  String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  return InkWell(
    onTap: () {
      setState(() {
        viewModel.expandedBlocks[index] = !expanded;
      });
    },
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: timerRunning
              ? theme.colorScheme.primary
              : expanded
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withOpacity(0.25),
          width: timerRunning ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  blockType,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              // Cronometro en vivo
              if (timerStarted)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: timerRunning
                        ? theme.colorScheme.primary.withOpacity(0.15)
                        : Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        timerRunning ? Icons.timer : Icons.timer_off,
                        size: 16,
                        color: timerRunning
                            ? theme.colorScheme.primary
                            : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(elapsed),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: timerRunning
                              ? theme.colorScheme.primary
                              : Colors.green,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 4),
              // 🗑️ Eliminar bloque
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: "Eliminar bloque",
                onPressed: () => _confirmDeleteBlock(index),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more),
              ),
            ],
          ),
          // Boton Comenzar / Detener bloque
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: timerFinished
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Reiniciar cronómetro'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      side:
                          BorderSide(color: theme.colorScheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => viewModel.startBlockTimer(index),
                  )
                : timerRunning
                    ? FilledButton.icon(
                        icon: const Icon(Icons.stop_circle_outlined,
                            size: 18),
                        label: const Text('Detener bloque'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orangeAccent.shade700,
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => viewModel.stopBlockTimer(index),
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded,
                            size: 18),
                        label: const Text('Comenzar bloque'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => viewModel.startBlockTimer(index),
                      ),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _addExerciseToSeries(int blockIndex) async {
    final block = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddWorkoutScreen(
          initialBlock: viewModel.routine!['blocks'][blockIndex],
        ),
      ),
    );

    if (block == null) return;

    setState(() {
      viewModel.routine!['blocks'][blockIndex] = block;

      for (final ex in block['exercises']) {
        _initSeriesDataForNewExercise(blockIndex, ex);
      }
    });
  }

  void _initSeriesDataForNewExercise(int blockIndex, Map<String, dynamic> ex) {
    final name = viewModel.normalizeExerciseName(ex["name"]);
    final key = "$blockIndex-$name";

    if (viewModel.seriesData.containsKey(key)) return;

    final int sets = ex["series"] ?? 1;
    final String valueType = ex["valueType"] ?? "reps";
    final int baseValue = ex["value"] ?? ex["reps"] ?? 0;

    viewModel.seriesData[key] = List.generate(
      sets,
      (_) => {
        'valueType': valueType,
        'value': baseValue,
        'reps': valueType == "reps" ? baseValue : null,
        'weight': ex["weight"],
        'rpe': 5,
        'done': false,
      },
    );

    viewModel.seriesRepsCtrl[key] = List.generate(
      sets,
      (_) => TextEditingController(text: baseValue.toString()),
    );

    viewModel.seriesWeightCtrl[key] = List.generate(
      sets,
      (_) => TextEditingController(text: ex["weight"]?.toString() ?? ""),
    );

    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteExercise(int blockIndex, String exerciseName) async {
    final ok = await LogWorkoutDialogs.confirmDeleteExercise(
      context: context,
      exerciseName: exerciseName,
    );

    if (ok) {
      setState(() {
        viewModel.routine!['blocks'][blockIndex]['exercises']
            .removeWhere((e) => viewModel.normalizeExerciseName(e['name']) == exerciseName);

        viewModel.seriesData.remove("$blockIndex-$exerciseName");
        viewModel.seriesRepsCtrl.remove("$blockIndex-$exerciseName");
        viewModel.seriesWeightCtrl.remove("$blockIndex-$exerciseName");
      });
    }
  }




  void _startTabata({
    required int blockIndex,
    required Map<String, dynamic> block,
  }) {
    tabataTimer.startBlock(
      blockIndex: blockIndex,
      workSeconds: block['work'],
      restSeconds: block['rest'],
      rounds: block['rounds'],
      exercises: List<Map<String, dynamic>>.from(block['exercises']),
    );
  }

  void _skipTabata() async {
    tabataTimer.stop();
    final int blockIndex = viewModel.routine!['blocks'].indexWhere((b) => b['type'] == 'Tabata');
    if (blockIndex == -1) return;
    final block = viewModel.routine!['blocks'][blockIndex];
    await _askTabataRpe(blockIndex, block);
  }

  Future<void> _askTabataRpe(int blockIndex, Map<String, dynamic> block) async {
    final Map<String, int> rpeByExercise = {};
    for (final ex in block['exercises']) {
      final rpe = await LogWorkoutDialogs.askTabataRpe(
        context: context,
        exerciseName: ex['name'],
      );
      if (rpe != null) rpeByExercise[ex['name']] = rpe;
    }
    tabataTimer.completeBlockWithRpe(blockIndex, rpeByExercise);
  }

  void _showAddBlockOptions() {
    LogWorkoutDialogs.showAddBlockOptions(
      context: context,
      onBlockAdded: (block) {
        setState(() {
          viewModel.routine!['blocks'].add(block);
          final index = viewModel.routine!['blocks'].length - 1;
          viewModel.expandedBlocks[index] = true;
          _initializeBlockState(index, block);
        });
      },
    );
  }

  void _initializeBlockState(int index, Map<String, dynamic> block) {
    if (block['type'] == 'Series') {
      for (final ex in block['exercises']) {
        _initSeriesDataForNewExercise(index, ex);
      }
    }

    if (block['type'] == 'Circuito') {
      viewModel.circuitoRound[index] = 1;
      viewModel.circuitoReps[index] = {};
      viewModel.circuitoWeight[index] = {};
      viewModel.circuitoRpePorRonda[index] = {};
      viewModel.circuitoDone[index] = {};
    }

    if (block['type'] == 'Series descendentes') {
      final schema = List<int>.from(block['schema'] ?? []);
      for (final ex in block['exercises']) {
        final name = viewModel.normalizeExerciseName(ex['name']);
        final key = "$index-$name";

        viewModel.seriesData[key] = schema.map((reps) => {
          'valueType': 'reps',
          'value': reps,
          'reps': reps,
          'weight': ex['weight'],
          'rpe': 5,
          'done': false,
        }).toList();

        viewModel.seriesRepsCtrl[key] = schema.map((reps) => TextEditingController(text: reps.toString())).toList();
        viewModel.seriesWeightCtrl[key] = schema.map((_) => TextEditingController(text: ex['weight']?.toString() ?? '')).toList();
      }
    }

    if (block['type'] == 'Buscar RM') {
      final int rmTarget = block['rm'] ?? 5;
      for (final ex in block['exercises']) {
        final name = viewModel.normalizeExerciseName(ex['name']);
        final key = "$index-$name";
        final int targetReps = ex['reps'] ?? rmTarget;

        viewModel.seriesData[key] = [{
          'valueType': 'reps',
          'value': targetReps,
          'reps': targetReps,
          'weight': ex['weight'],
          'rpe': 5,
          'done': false,
        }];

        viewModel.seriesRepsCtrl[key] = [TextEditingController(text: targetReps.toString())];
        viewModel.seriesWeightCtrl[key] = [TextEditingController(text: ex['weight']?.toString() ?? '')];
      }
    }
  }

  Future<void> _confirmDeleteBlock(int index) async {
    final ok = await LogWorkoutDialogs.confirmDeleteBlock(context);
    if (!ok) return;

    setState(() {
      viewModel.routine!['blocks'].removeAt(index);
      viewModel.expandedBlocks.remove(index);
      viewModel.circuitoRound.remove(index);
      viewModel.circuitoReps.remove(index);
      viewModel.circuitoWeight.remove(index);
      viewModel.circuitoRpePorRonda.remove(index);
      viewModel.circuitoDone.remove(index);
      // Limpiar cronómetros del bloque eliminado
      viewModel.blockStartTimes.remove(index);
      viewModel.blockDurationSeconds.remove(index);
      tabataTimer.resetBlock(index);
      viewModel.reindexStateAfterDeletion(index);
    });
  }




  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    if (viewModel.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (viewModel.routine == null) {
      return const Scaffold(
        body: Center(child: Text("Selecciona una rutina para comenzar")),
      );
    }

    if (viewModel.routine == null && availableRoutines.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("No tienes rutinas asignadas")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showRoutineSelectorSheet,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  viewModel.routine?['name'] ?? 'Entrenamiento libre',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, size: 28),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: "Agregar bloque",
            onPressed: _saving ? null : _showAddBlockOptions,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.2,
              child: Image.asset(
                'assets/images/people_training_1.png',
                fit: BoxFit.cover,
                colorBlendMode: BlendMode.darken,
                color: Colors.black54,
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                viewModel.routine!['name'],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              for (int i = 0; i < viewModel.routine!['blocks'].length; i++) ...[
                _blockHeader(i, viewModel.routine!['blocks'][i]),
                if (viewModel.routine!['blocks'][i]['type'] == 'Circuito')
                  CircuitBlockWidget(
                    index: i,
                    block: viewModel.routine!['blocks'][i],
                    expanded: viewModel.expandedBlocks[i] ?? false,
                    circuitoRound: viewModel.circuitoRound,
                    circuitoReps: viewModel.circuitoReps,
                    circuitoWeight: viewModel.circuitoWeight,
                    circuitoRpePorRonda: viewModel.circuitoRpePorRonda,
                    circuitoDone: viewModel.circuitoDone,
                    normalizeExerciseName: viewModel.normalizeExerciseName,
                    circuitoPerSide: viewModel.circuitoPerSide,
                    onPerSideChanged: (blockIndex, exerciseName, value) {
                      viewModel.circuitoPerSide.putIfAbsent(blockIndex, () => {});
                      viewModel.circuitoPerSide[blockIndex]![exerciseName] = value;
                      final exercises = viewModel.routine!['blocks'][blockIndex]['exercises'] as List;
                      for (final ex in exercises) {
                        if (viewModel.normalizeExerciseName(ex['name']) == exerciseName) {
                          ex['perSide'] = value;
                        }
                      }
                      setState(() {});
                    },
                    onStateChanged: () => setState(() {}),
                  ),
                if (viewModel.routine!['blocks'][i]['type'] == 'Series')
                  SeriesBlockWidget(
                    index: i,
                    block: viewModel.routine!['blocks'][i],
                    expanded: viewModel.expandedBlocks[i] ?? false,
                    seriesData: viewModel.seriesData,
                    seriesRepsCtrl: viewModel.seriesRepsCtrl,
                    seriesWeightCtrl: viewModel.seriesWeightCtrl,
                    normalizeExerciseName: viewModel.normalizeExerciseName,
                    getEquipment: _getEquipment,
                    isPerSide: _isPerSide,
                    onInfoPressed: _showExerciseInfo,
                    onDeleteExercise: _confirmDeleteExercise,
                    onAddExercise: _addExerciseToSeries,
                    onRepsSubmitted: _onRepsSubmitted,
                    suggestedWeightText: _suggestedWeightText,
                    suggestedRepsText: _suggestedRepsText,
                    onPerSideChanged: (blockIndex, exerciseName, value) {
                      final key = "$blockIndex-$exerciseName";
                      if (viewModel.seriesData.containsKey(key)) {
                        for (final s in viewModel.seriesData[key]!) {
                          s['perSide'] = value;
                        }
                      }
                      final exercises = viewModel.routine!['blocks'][blockIndex]['exercises'] as List;
                      for (final ex in exercises) {
                        if (viewModel.normalizeExerciseName(ex['name']) == exerciseName) {
                          ex['perSide'] = value;
                        }
                      }
                      setState(() {});
                    },
                    onStateChanged: () => setState(() {}),
                  ),
                if (viewModel.routine!['blocks'][i]['type'] == 'Series descendentes')
                  DescendingSeriesBlockWidget(
                    index: i,
                    block: viewModel.routine!['blocks'][i],
                    expanded: viewModel.expandedBlocks[i] ?? false,
                    seriesData: viewModel.seriesData,
                    seriesRepsCtrl: viewModel.seriesRepsCtrl,
                    seriesWeightCtrl: viewModel.seriesWeightCtrl,
                    normalizeExerciseName: viewModel.normalizeExerciseName,
                    isPerSide: _isPerSide,
                    onInfoPressed: _showExerciseInfo,
                    onStateChanged: () => setState(() {}),
                  ),
                if (viewModel.routine!['blocks'][i]['type'] == 'Buscar RM')
                  BuscarRmBlockWidget(
                    index: i,
                    block: viewModel.routine!['blocks'][i],
                    expanded: viewModel.expandedBlocks[i] ?? false,
                    seriesData: viewModel.seriesData,
                    seriesRepsCtrl: viewModel.seriesRepsCtrl,
                    seriesWeightCtrl: viewModel.seriesWeightCtrl,
                    normalizeExerciseName: viewModel.normalizeExerciseName,
                    isPerSide: _isPerSide,
                    onInfoPressed: _showExerciseInfo,
                    onStateChanged: () => setState(() {}),
                  ),
                if (viewModel.routine!['blocks'][i]['type'] == 'Tabata')
                  TabataBlockWidget(
                    index: i,
                    block: viewModel.routine!['blocks'][i],
                    expanded: viewModel.expandedBlocks[i] ?? false,
                    tabataTimer: tabataTimer,
                    onStartTabata: (blockIdx, blk) => _startTabata(blockIndex: blockIdx, block: blk),
                    onSkipTabata: _skipTabata,
                  ),
                const SizedBox(height: 24),
              ],
              if (_isWorkoutCompleted())
                ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle),
                  label: Text(_saving ? _savingStep : "Finalizar entrenamiento"),
                  onPressed: _saving ? null : _confirmFinish,
                ),
            ],
          ),
          AnimatedBuilder(
            animation: tabataTimer,
            builder: (_, __) {
              if (!tabataTimer.isRunning) return const SizedBox();
              return TabataOverlayWidget(
                tabataTimer: tabataTimer,
                onSkip: _skipTabata,
              );
            },
          ),
        ],
      ),
    );
  }

  int _countCompletedCircuitRounds(int blockIndex, Map<String, dynamic> block) {
    final visibleRounds = viewModel.circuitoRound[blockIndex] ?? 1;
    int completed = 0;
    for (int r = 1; r <= visibleRounds; r++) {
      if (_isCircuitRoundCompleted(blockIndex, r, block['exercises'])) {
        completed++;
      }
    }
    return completed;
  }

  void _startFreeWorkout() {
    _changeRoutine(null);
  }

  void _showRoutineSelectorSheet() async {
    if (availableRoutines.isEmpty) {
      await _loadAvailableRoutinesBackground();
    }
    if (!mounted) return;
    LogWorkoutDialogs.showRoutineSelectorSheet(
      context: context,
      availableRoutines: availableRoutines,
      currentRoutine: viewModel.routine,
      onConfirmChange: _confirmChangeRoutine,
      onFreeWorkoutSelected: _startFreeWorkout,
      onRoutineSelected: _changeRoutine,
    );
  }

  Future<bool> _confirmChangeRoutine() async {
    bool hasProgress = viewModel.routine != null && (viewModel.routine!['blocks'] as List).isNotEmpty;
    if (!hasProgress) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cambiar rutina"),
        content: const Text("Si cambias de rutina, perderás el progreso de la sesión actual no guardada. ¿Continuar?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Cambiar"),
          ),
        ],
      ),
    );
    return ok == true;
  }

  bool _isCircuitRoundCompleted(int blockIndex, int round, List exercises) {
    for (final ex in exercises) {
      final name = viewModel.normalizeExerciseName(ex['name']);
      final notifier = viewModel.circuitoDone[blockIndex]?[round]?[name];
      if (notifier == null || notifier.value != true) return false;
    }
    return true;
  }

  bool _isWorkoutCompleted() {
    for (final entry in viewModel.seriesData.entries) {
      for (final set in entry.value) {
        if (set['done'] != true) return false;
      }
    }
    for (final entry in viewModel.circuitoRound.entries) {
      final blockIndex = entry.key;
      final block = viewModel.routine!['blocks'][blockIndex];
      if ((block['exercises'] as List).isEmpty) continue;
      final completedRounds = _countCompletedCircuitRounds(blockIndex, block);
      final visibleRounds = viewModel.circuitoRound[blockIndex] ?? 1;
      if (completedRounds < visibleRounds) return false;
    }
    for (int i = 0; i < viewModel.routine!['blocks'].length; i++) {
      final block = viewModel.routine!['blocks'][i];
      if (block['type'] != 'Tabata') continue;
      if (tabataTimer.isStarted(i) && !tabataTimer.isCompleted(i)) return false;
    }
    return true;
  }

  // ================= SAVE =================

  Future<void> _confirmFinish() async {
    if (_saving) return;
    final ok = await LogWorkoutDialogs.confirmFinish(context);
    if (ok) await _saveWorkout();
  }

  void _startSaving() {
    if (!mounted) return;
    setState(() {
      _saving = true;
      _savingStep = "Preparando datos…";
    });
  }

  void _setSavingStep(String step) {
    if (!mounted) return;
    setState(() => _savingStep = step);
  }

  void _finishSaving() {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savingStep = "";
    });
  }

  void _handleSaveError(Object e, StackTrace stack) {
    _finishSaving();
    debugPrint("❌ ERROR AL GUARDAR: $e\n$stack");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Error al guardar. Revisa consola.")),
    );
  }

  Future<void> _saveWorkout() async {
    if (_saving) return;
    _startSaving();
    // Auto-detener cronómetros de bloques que sigan corriendo al guardar
    for (final idx in viewModel.blockStartTimes.keys.toList()) {
      if (viewModel.isBlockTimerRunning(idx)) {
        viewModel.stopBlockTimer(idx);
      }
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final oldStatsSnap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('stats').doc('global').get();
    final Map<String, dynamic> oldStats = oldStatsSnap.exists ? oldStatsSnap.data()! : {};

    final service = WorkoutSaveService(
      context: context,
      isEdit: isEdit,
      workoutRef: widget.workoutRef,
      routine: viewModel.routine ?? {},
      workoutStartedAt: viewModel.workoutStartedAt,
      originalStartedAt: viewModel.originalStartedAt,
      originalFinishedAt: viewModel.originalFinishedAt,
      originalDurationMinutes: viewModel.originalDurationMinutes,
      seriesData: viewModel.seriesData,
      seriesRepsCtrl: viewModel.seriesRepsCtrl,
      seriesWeightCtrl: viewModel.seriesWeightCtrl,
      circuitoRound: viewModel.circuitoRound,
      circuitoReps: viewModel.circuitoReps,
      circuitoWeight: viewModel.circuitoWeight,
      circuitoRpePorRonda: viewModel.circuitoRpePorRonda,
      circuitoPerSide: viewModel.circuitoPerSide,
      tabataTimer: tabataTimer,
      availableExercisesCatalog: availableExercisesCatalog,
      blockDurationSeconds: viewModel.blockDurationSeconds,
      onStepChanged: _setSavingStep,
      onError: _handleSaveError,
      onSuccess: (achievements, performed) async {
        
        final newStatsSnap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('stats').doc('global').get();
        final Map<String, dynamic> newStats = newStatsSnap.exists ? newStatsSnap.data()! : {};

        Map<String, dynamic> computedOldStats = Map.from(oldStats);
        if (isEdit) {
           // Para stats globales, al editar no hemos sumado un nuevo entrenamiento ni días a la racha
           // a menos que cambiaramos la fecha a un día clave. Por ende, no forzamos que racha o 
           // maxWeeklySessions suban simulando restas. Solo simulamos la suma de volumen porque el 
           // edit reemplaza el volumen viejo por el nuevo.
           final sessionVolume = WorkoutVolumeService.calculateWorkoutVolume(performed);
           computedOldStats['totalVolume'] = (newStats['totalVolume'] ?? 0.0) - sessionVolume;
           // Max session volume respetamos el viejo
           computedOldStats['maxVolumeSession'] = oldStats['maxVolumeSession'] ?? 0.0;
        }

        final allDocsSnap = await FirebaseFirestore.instance.collection('workouts_logged').where('userId', isEqualTo: uid).get();
        final rmHistory = <String, List<Map<String, dynamic>>>{};
        final targetDate = viewModel.workoutStartedAt ?? DateTime.now();
        
        // Agregar los sets de TODOS los workouts guardados MENOS el que estamos guardando/editando.
        for (final ad in allDocsSnap.docs) {
          if (ad.id == widget.workoutRef?.id) continue;
          final data = ad.data();
          final adDate = (data['date'] as Timestamp?)?.toDate() ?? targetDate;
          if (adDate.isAfter(targetDate)) continue;
          final perf = List<Map<String,dynamic>>.from(data['performed'] ?? []);
          final sets = WorkoutRMService.extractAllValidRMSetCandidates(perf);
          for (final s in sets) {
            final weight = (s['weight'] as num).toDouble();
            final reps = (s['reps'] as num).toInt();
            rmHistory.putIfAbsent(s['exercise'], () => []).add({
              'date': adDate, 
              'rm': weight * (1 + reps / 30), 
              'weight': weight, 
              'reps': reps,
              'rpe': s['rpe']
            });
          }
        }

        // Agregar los sets DEL ENTRENAMIENTO ACTUAL
        final currentSets = WorkoutRMService.extractAllValidRMSetCandidates(performed);
        for (final s in currentSets) {
          final weight = (s['weight'] as num).toDouble();
          final reps = (s['reps'] as num).toInt();
          rmHistory.putIfAbsent(s['exercise'], () => []).add({
            'date': targetDate, 
            'rm': weight * (1 + reps / 30), 
            'weight': weight, 
            'reps': reps,
            'rpe': s['rpe']
          });
        }
        
        final alerts = ProgressAlertService.analyzeSessionImpact(
          rmHistory: rmHistory,
          targetDate: targetDate,
        );

        _finishSaving();

        if (!mounted) return;
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WorkoutSummaryScreen(
              unlockedAchievements: achievements,
              progressAlerts: alerts,
              oldStats: computedOldStats,
              newStats: newStats,
              sessionName: viewModel.routine?['name'] ?? 'Entrenamiento libre',
              durationMinutes: viewModel.originalDurationMinutes ?? 
                 (DateTime.now().difference(viewModel.workoutStartedAt ?? DateTime.now()).inMinutes),
            ),
          ),
        );
      },
    );
    await service.execute();
  }
}
