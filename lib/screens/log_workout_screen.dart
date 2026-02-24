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

class _WorkoutBuildResult {
  final List<Map<String, dynamic>> performed;
  final List<WorkoutSet> workoutSets;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMinutes;

  _WorkoutBuildResult({
    required this.performed,
    required this.workoutSets,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMinutes,
  });
}




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

class _LogWorkoutScreenState extends State<LogWorkoutScreen> {
  Map<String, dynamic>? routine;
  bool loading = true;

  final Map<String, double?> _suggestedWeightCache = {};
  final Map<String, List<TextEditingController>> seriesRepsCtrl = {};
final Map<String, List<TextEditingController>> seriesWeightCtrl = {};
final Map<int, Map<int, Map<String, ValueNotifier<bool>>>> circuitoDone = {};
DateTime? workoutStartedAt;
final Map<String, int?> _suggestedRepsCache = {};
  final Map<int, bool> expandedBlocks = {};
  final Map<int, int> circuitoRound = {};
  List<Map<String, dynamic>> availableRoutines = [];
  bool get isEdit => widget.workoutRef != null;
  // 🔥 DATOS ORIGINALES (solo para edición)
DateTime? _originalStartedAt;
DateTime? _originalFinishedAt;
int? _originalDurationMinutes;
final Map<int, Map<String, bool>> circuitoPerSide = {};

  List<Map<String, dynamic>> availableExercisesCatalog = [];


  // blockIndex -> round -> exercise -> reps
final Map<int, Map<int, Map<String, TextEditingController>>> circuitoReps = {};

  late final TabataTimerService tabataTimer;
  // blockIndex -> round -> exercise -> controller
final Map<int, Map<int, Map<String, TextEditingController>>> circuitoWeight = {};


// blockIndex -> round -> exercise -> rpe
final Map<int, Map<int, Map<String, int>>> circuitoRpePorRonda = {};

  final Map<String, String> exerciseInstructionsCache = {};

  bool _saving = false;
  String _savingStep = "";
  // series
  final Map<String, List<Map<String, dynamic>>> seriesData = {};

  @override
void dispose() {
  tabataTimer.stop();
  super.dispose();
}


@override
void initState() {
  super.initState();
  workoutStartedAt = DateTime.now(); // 🔥 inicio automático
  tabataTimer = TabataTimerService();
  _loadExerciseCatalog(); // 👈 NUEVO



  if (isEdit) {
  _loadWorkoutForEdit();
} else {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _askWorkoutMode();
  });
}

}

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
      .limit(1)
      .get();

  if (snap.docs.isEmpty) return null;

  final planned = snap.docs.first;

  final routineDoc = await FirebaseFirestore.instance
      .collection('routines')
      .doc(planned['routineId'])
      .get();

  if (!routineDoc.exists) return null;

  return {
    'id': routineDoc.id,
    ...routineDoc.data()!,
  };
}



void _loadRepsSuggestionIfNeeded(
  String exercise,
  double weight,
) async {
  final key = "$exercise-$weight";

  if (_suggestedRepsCache.containsKey(key)) return;

  final uid = FirebaseAuth.instance.currentUser!.uid;

  final value = await WorkoutSuggestionService.suggestMaxRepsForWeight(
    userId: uid,
    exercise: exercise,
    targetWeight: weight,
  );

  if (!mounted) return;

  setState(() {
    _suggestedRepsCache[key] = value;
  });
}


Widget _suggestedRepsText(String exercise, double weight) {
  final key = "$exercise-$weight";

  if (!_suggestedRepsCache.containsKey(key)) {
    _loadRepsSuggestionIfNeeded(exercise, weight);
    return const SizedBox();
  }

  final value = _suggestedRepsCache[key];

  if (value == null) {
    return const Text(
      "Sin historial para ese peso",
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  return Text(
    "Máx reps con ese peso: $value",
    style: const TextStyle(
      fontSize: 12,
      color: Colors.blue,
      fontStyle: FontStyle.italic,
    ),
  );
}



void _loadSuggestionIfNeeded(
  String exercise,
  int reps,
) async {
  final key = "$exercise-$reps";

  final uid = FirebaseAuth.instance.currentUser!.uid;

  final value = await WorkoutSuggestionService.suggestWeightForReps(
    userId: uid,
    exercise: exercise,
    targetReps: reps,
  );

  if (!mounted) return;

  setState(() {
    _suggestedWeightCache[key] = value;
  });
}

Widget _suggestedWeightText(String exercise, int reps) {
  final key = "$exercise-$reps";

  if (!_suggestedWeightCache.containsKey(key)) {
    _loadSuggestionIfNeeded(exercise, reps);
    return const SizedBox();
  }

  final value = _suggestedWeightCache[key];

  if (value == null) {
    return const Text(
      "Sin sugerencias",
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  return Text(
    "Sugerido para esas reps: ${value.toStringAsFixed(1)} kg",
    style: const TextStyle(
      fontSize: 12,
      color: Colors.green,
      fontStyle: FontStyle.italic,
    ),
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
      (e) => normalizeExerciseName(e['name']) == name,
    );
  } catch (_) {
    return null;
  }
}




void _loadWorkoutForEdit() {
  
  final workout = widget.existingWorkout!;

  // 🔥 Guardar tiempos originales
_originalStartedAt =
    (workout['startedAt'] as Timestamp?)?.toDate();

_originalFinishedAt =
    (workout['finishedAt'] as Timestamp?)?.toDate();

_originalDurationMinutes =
    (workout['durationMinutes'] as num?)?.toInt();

  
  final performed = (workout['performed'] as List<dynamic>? ?? [])
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

  routine = {
    'id': workout['routineId'],
    'name': workout['routineName'],
    'blocks': _rebuildBlocksFromPerformed(performed),
  };

  // 1️⃣ Inicializa estructura BASE (vacía)
  _initializeRoutineState();

  // 2️⃣ AHORA sí hidrata con datos reales
  _hydrateFromPerformed(performed);

  setState(() => loading = false);
}


void _hydrateFromPerformed(List<Map<String, dynamic>> performed) {
  int circuitBlockCursor = 0;

for (final e in performed) {
if (e['type'] == 'Series') {

  final int blockIndex =
      (e['blockIndex'] as num?)?.toInt() ?? 0;

  final List exercises =
      (e['exercises'] as List?) ?? [];

  for (final ex in exercises) {

    final String name =
        normalizeExerciseName(ex['exercise']);

    final sets =
        (ex['sets'] as List<dynamic>? ?? [])
            .map((x) => Map<String, dynamic>.from(x))
            .toList();

    final key = "$blockIndex-$name";
    if (!seriesData.containsKey(key)) continue;

    for (int i = 0;
        i < sets.length &&
        i < seriesData[key]!.length;
        i++) {

      seriesData[key]![i]['reps'] = sets[i]['reps'];
      seriesData[key]![i]['weight'] = sets[i]['weight'];
      seriesData[key]![i]['rpe'] = sets[i]['rpe'];
      seriesData[key]![i]['done'] = true;

      seriesRepsCtrl[key]![i].text =
          sets[i]['reps']?.toString() ?? '';

      seriesWeightCtrl[key]![i].text =
          sets[i]['weight']?.toString() ?? '';
    }
  }
}

    // ================= CIRCUITO (FIX REAL) =================
    if (e['type'] == 'Circuito') {
      // 🔥 buscar el bloque Circuito N° circuitBlockCursor
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

  circuitoReps[blockIndex]![round]![name] =
      TextEditingController(text: ex['reps']?.toString() ?? '1');

  circuitoWeight[blockIndex]![round]![name] =
      TextEditingController(text: ex['weight']?.toString() ?? '');

  circuitoRpePorRonda[blockIndex]![round]![name] =
      ex['rpe'] ?? 5;

  circuitoDone[blockIndex]![round]![name] =
      ValueNotifier(true);

  circuitoPerSide[blockIndex]![name] =
    ex['perSide'] == true;
}
      }
    }

    // ===================== TABATA =====================
    if (e['type'] == 'Tabata') {
      final int blockIndex = e['blockIndex'];
      final List exercises = e['exercises'] ?? [];

      tabataTimer.markBlockHydrated(
  blockIndex,
  {
    for (final ex in exercises)
      normalizeExerciseName(ex['exercise']): ex['rpe'],
  },
);

    }
  }
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

    // ================= SERIES =================
    if (type == 'Series') {

  final List exList =
      (e['exercises'] as List?) ?? const [];

  for (final ex in exList) {
    if (ex is! Map) continue;

    final String name =
        normalizeExerciseName(ex['exercise']);

    final List sets =
        (ex['sets'] as List?) ?? const [];

    if (name.isEmpty || sets.isEmpty) continue;

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
      final name = normalizeExerciseName(ex['exercise']);

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

  Future<void> _loadAvailableRoutines() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final assignSnap = await FirebaseFirestore.instance
        .collection('routine_assignments')
        .where('athleteId', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .get();

    availableRoutines.clear();

    for (final d in assignSnap.docs) {
      final routineSnap = await FirebaseFirestore.instance
          .collection('routines')
          .doc(d['routineId'])
          .get();

      if (routineSnap.exists) {
        availableRoutines.add({'id': routineSnap.id, ...routineSnap.data()!});
      }
    }

    if (availableRoutines.length == 1) {
      routine = availableRoutines.first;
      _initializeRoutineState();
    } else if (availableRoutines.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectRoutine();
      });
    }

    setState(() => loading = false);
  }

  // ================= SELECT ROUTINE =================

  Future<void> _selectRoutine() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text("¿Qué entrenamiento vas a realizar?"),
        children: availableRoutines.map((r) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, r),
            child: Text(r['name']),
          );
        }).toList(),
      ),
    );

    if (selected != null) {
      routine = selected;
      _initializeRoutineState();
      setState(() {});
    }
  }

  // ================= INFO =================

  void _showExerciseInfo(Map<String, dynamic> ex) async {
  final String name = normalizeExerciseName(ex['name']);

  showDialog(
    context: context,
    builder: (_) => const AlertDialog(
      content: SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
  );

  final instructions = await _getExerciseInstructions(name);
  Navigator.pop(context);

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(name),
      content: instructions != null
          ? Text(instructions)
          : const Text("No hay instrucciones disponibles"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cerrar"),
        ),
      ],
    ),
  );
}


  // ================= HEADER BLOQUE =================

  Widget _blockHeader(int index, Map<String, dynamic> block) {
  final bool expanded = expandedBlocks[index] ?? false;
  final theme = Theme.of(context);
  final String blockType = (block['type'] ?? 'Bloque').toString();

  return InkWell(
    onTap: () {
      setState(() {
        expandedBlocks[index] = !expanded;
      });
    },
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expanded
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child:Text(
  blockType,
  style: theme.textTheme.titleLarge,
),

          ),

          // 🗑️ ELIMINAR BLOQUE (TODOS)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: "Eliminar bloque",
            onPressed: () => _confirmDeleteBlock(index),
          ),

          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.expand_more),
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
        initialBlock: routine!['blocks'][blockIndex],
      ),
    ),
  );

  if (block == null) return;

  setState(() {
    // 🔥 reemplaza el bloque completo
    routine!['blocks'][blockIndex] = block;

    // 🔥 inicializa datos internos de CADA ejercicio
    for (final ex in block['exercises']) {
      _initSeriesDataForNewExercise(blockIndex, ex);
    }
  });
}



void _initSeriesDataForNewExercise(
  int blockIndex,
  Map<String, dynamic> ex,
) {
  final name = normalizeExerciseName(ex["name"]);
  final key = "$blockIndex-$name";

  if (seriesData.containsKey(key)) return;

  final int sets = ex["series"] ?? 1;
  final String valueType = ex["valueType"] ?? "reps";
  final int baseValue = ex["value"] ?? ex["reps"] ?? 0;

  seriesData[key] = List.generate(
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

  seriesRepsCtrl[key] = List.generate(
    sets,
    (_) => TextEditingController(text: baseValue.toString()),
  );

  seriesWeightCtrl[key] = List.generate(
  sets,
  (_) => TextEditingController(
    text: ex["weight"]?.toString() ?? "",
  ),
);

if (mounted) {
  setState(() {});
}

}


Future<void> _confirmDeleteExercise(
  int blockIndex,
  String exerciseName,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Eliminar ejercicio"),
      content: Text("¿Eliminar $exerciseName del bloque?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancelar"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Eliminar"),
        ),
      ],
    ),
  );

  if (ok == true) {
    setState(() {
      routine!['blocks'][blockIndex]['exercises']
          .removeWhere((e) => normalizeExerciseName(e['name']) == exerciseName);

      seriesData.remove("$blockIndex-$exerciseName");
      seriesRepsCtrl.remove("$blockIndex-$exerciseName");
      seriesWeightCtrl.remove("$blockIndex-$exerciseName");
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
  // 1️⃣ Detener timer
  tabataTimer.stop();

  // 2️⃣ Identificar bloque activo
  final int blockIndex = routine!['blocks']
      .indexWhere((b) => b['type'] == 'Tabata');

  if (blockIndex == -1) return;

  final block = routine!['blocks'][blockIndex];

  // 3️⃣ Pedir RPE inmediatamente
  await _askTabataRpe(blockIndex, block);
}


  // ================= INIT STATE =================

  void _initializeRoutineState() {
  for (int i = 0; i < routine!['blocks'].length; i++) {
    expandedBlocks[i] = false;
    final block = routine!['blocks'][i];

    // ================= CIRCUITO =================
    // ================= CIRCUITO =================
if (block['type'] == 'Circuito') {
  // ⛔ IMPORTANTE:
  // Si estamos editando, NO inicializamos aquí.
  // Todo el estado real viene desde _hydrateFromPerformed()
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

    circuitoReps[i]![round]![name] =
        TextEditingController(text: (ex['reps'] ?? 1).toString());

    circuitoWeight[i]![round]![name] =
        TextEditingController(text: (ex['weight'] ?? 0).toString());

    circuitoRpePorRonda[i]![round]![name] = 5;
    circuitoDone[i]![round]![name] = ValueNotifier(false);
  }
}


    // ================= SERIES ===========R======
    if (block['type'] == 'Series') {
      for (final ex in block['exercises']) {
        final name = normalizeExerciseName(ex['name']);
final key = "$i-$name";
        final int sets = ex['series'] ?? 1;

        final String valueType = ex['valueType'] ?? 'reps';
        final int baseValue = ex['value'] ?? ex['reps'] ?? 0;

        seriesData[key] = List.generate(
          sets,
          (_) => {
            'valueType': valueType,
            'value': baseValue,
            'reps': valueType == 'reps' ? baseValue : null,
            'weight': ex['weight'],
            'rpe': 5,
            'done': false,
          },
        );

        seriesRepsCtrl[key] = List.generate(
  sets,
  (i) => TextEditingController(
    text: seriesData[key]![i]['reps']?.toString() ?? '',
  ),
);

seriesWeightCtrl[key] = List.generate(
  sets,
  (i) => TextEditingController(
    text: seriesData[key]![i]['weight']?.toString() ?? '',
  ),
);

      }
    }
  }
}


  Future<void> _askTabataRpe(int blockIndex, Map<String, dynamic> block) async {
    final Map<String, int> rpeByExercise = {};

    for (final ex in block['exercises']) {
      final rpe = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          int selected = 7;

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text("RPE — ${ex['name']}"),
                content: DropdownButton<int>(
                  value: selected,
                  items: List.generate(
                    10,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text("RPE ${i + 1}"),
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {
                      selected = v!;
                    });
                  },
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text("Confirmar"),
                  ),
                ],
              );
            },
          );
        },
      );

      if (rpe != null) {
        rpeByExercise[ex['name']] = rpe;
      }
    }

    tabataTimer.completeBlockWithRpe(blockIndex, rpeByExercise);

  }


  void _showAddBlockOptions() {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Agregar bloque",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            _addBlockTile("Series", Icons.repeat),
            _addBlockTile("Circuito", Icons.loop),
            _addBlockTile("Tabata", Icons.timer),
          ],
        ),
      );
    },
  );
}
Map<String, dynamic> _emptyBlockForType(String type) {
  switch (type) {
    case "Series":
      return {
        "type": "Series",
        "exercises": <Map<String, dynamic>>[],
      };

    case "Circuito":
      return {
        "type": "Circuito",
        "rounds": 3,
        "exercises": <Map<String, dynamic>>[],
      };

    case "Tabata":
      return {
        "type": "Tabata",
        "work": 20,
        "rest": 10,
        "rounds": 8,
        "exercises": <Map<String, dynamic>>[],
      };

    default:
      return {
        "type": type,
        "exercises": <Map<String, dynamic>>[],
      };
  }
}


Widget _addBlockTile(String type, IconData icon) {
  return ListTile(
    leading: Icon(icon),
    title: Text(type),
    onTap: () async {
      Navigator.pop(context);

      final block = await Navigator.push<Map<String, dynamic>>(
  context,
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => AddWorkoutScreen(
      initialBlock: _emptyBlockForType(type),
    ),
  ),
);

if (block == null) return;

setState(() {
  routine!['blocks'].add(block);
final index = routine!['blocks'].length - 1;
expandedBlocks[index] = true;

// 🔥 CLAVE
if (block['type'] == 'Series') {
  for (final ex in block['exercises']) {
    _initSeriesDataForNewExercise(index, ex);
  }
}

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
    circuitoRound[index] = 1;
    circuitoReps[index] = {};
    circuitoWeight[index] = {};
    circuitoRpePorRonda[index] = {};
    circuitoDone[index] = {};
  }

  if (block['type'] == 'Tabata') {
    // nada extra por ahora
  }
}


Future<void> _confirmDeleteBlock(int index) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Eliminar bloque"),
      content: const Text("¿Seguro que deseas eliminar este bloque?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancelar"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Eliminar"),
        ),
      ],
    ),
  );

  if (ok != true) return;

  setState(() {
    // 1️⃣ Eliminar bloque visual
    routine!['blocks'].removeAt(index);

    // 2️⃣ Limpiar estado de ese bloque
    expandedBlocks.remove(index);
    circuitoRound.remove(index);
    circuitoReps.remove(index);
    circuitoWeight.remove(index);
    circuitoRpePorRonda.remove(index);
    circuitoDone.remove(index);
    tabataTimer.resetBlock(index);

    // 3️⃣ 🔥 REINDEXAR TODO LO QUE ESTÁ DESPUÉS
    _reindexStateAfterDeletion(index);
  });
}

void _reindexStateAfterDeletion(int deletedIndex) {

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
    } 
    else if (blockIndex > deletedIndex) {
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


  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 🔴 CASO CLAVE FALTANTE
    if (routine == null) {
      return const Scaffold(
        body: Center(child: Text("Selecciona una rutina para comenzar")),
      );
    }

    // 👇 desde aquí routine ES SEGURA

    if (routine == null && availableRoutines.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("No tienes rutinas asignadas")),
      );
    }

    return Scaffold(
      appBar: AppBar(
  title: const Text("Registrar entrenamiento"),
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
    // ================= CONTENIDO NORMAL =================
    ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          routine!['name'],
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),

        for (int i = 0; i < routine!['blocks'].length; i++) ...[
          _blockHeader(i, routine!['blocks'][i]),

          if (routine!['blocks'][i]['type'] == 'Circuito')
  CircuitBlockWidget(
    index: i,
    block: routine!['blocks'][i],
    expanded: expandedBlocks[i] ?? false,
    circuitoRound: circuitoRound,
    circuitoReps: circuitoReps,
    circuitoWeight: circuitoWeight,
    circuitoRpePorRonda: circuitoRpePorRonda,
    circuitoDone: circuitoDone,
    normalizeExerciseName: normalizeExerciseName,
    circuitoPerSide: circuitoPerSide,
onPerSideChanged: (blockIndex, exerciseName, value) {
  circuitoPerSide.putIfAbsent(blockIndex, () => {});
  circuitoPerSide[blockIndex]![exerciseName] = value;

  final exercises =
      routine!['blocks'][blockIndex]['exercises'] as List;

  for (final ex in exercises) {
    if (normalizeExerciseName(ex['name']) ==
        exerciseName) {
      ex['perSide'] = value;
    }
  }

  setState(() {});
},
    onStateChanged: () => setState(() {}),
  ),


          if (routine!['blocks'][i]['type'] == 'Series')
  SeriesBlockWidget(
    index: i,
    block: routine!['blocks'][i],
    expanded: expandedBlocks[i] ?? false,
    seriesData: seriesData,
    seriesRepsCtrl: seriesRepsCtrl,
    seriesWeightCtrl: seriesWeightCtrl,
    normalizeExerciseName: normalizeExerciseName,
    getEquipment: _getEquipment,
    isPerSide: _isPerSide,
    onInfoPressed: _showExerciseInfo,
    onDeleteExercise: _confirmDeleteExercise,
    onAddExercise: _addExerciseToSeries,
    suggestedWeightText: _suggestedWeightText,
    suggestedRepsText: _suggestedRepsText,
    onPerSideChanged: (blockIndex, exerciseName, value) {
  final key = "$blockIndex-$exerciseName";

  if (seriesData.containsKey(key)) {
    for (final s in seriesData[key]!) {
      s['perSide'] = value;
    }
  }
  // también actualizar el block original
  final exercises =
      routine!['blocks'][blockIndex]['exercises'] as List;

  for (final ex in exercises) {
    if (normalizeExerciseName(ex['name']) ==
        exerciseName) {
      ex['perSide'] = value;
    }
  }

  setState(() {});
},
      onStateChanged: () => setState(() {}),

  ),


          if (routine!['blocks'][i]['type'] == 'Tabata')
  TabataBlockWidget(
    index: i,
    block: routine!['blocks'][i],
    expanded: expandedBlocks[i] ?? false,
    tabataTimer: tabataTimer,
    onStartTabata: (blockIndex, block) {
      _startTabata(blockIndex: blockIndex, block: block);
    },
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

    // ================= OVERLAY TABATA =================
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

 
int _countCompletedCircuitRounds(
  int blockIndex,
  Map<String, dynamic> block,
) {
  final visibleRounds = circuitoRound[blockIndex] ?? 1;
  int completed = 0;

  for (int r = 1; r <= visibleRounds; r++) {
    if (_isCircuitRoundCompleted(blockIndex, r, block['exercises'])) {
      completed++;
    }
  }

  return completed;
}


Future<void> _askWorkoutMode() async {
  final plannedRoutine = await _getTodayPlannedRoutine();

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text("¿Cómo quieres entrenar hoy?"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plannedRoutine != null) ...[
            const Text(
              "Tienes un entrenamiento planificado para hoy:",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              plannedRoutine['name'],
              style: const TextStyle(color: Colors.blue),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
      actions: [

        if (plannedRoutine != null)
          ElevatedButton(
            onPressed: () => Navigator.pop(context, "planned"),
            child: const Text("Usar rutina de hoy"),
          ),

        TextButton(
          onPressed: () => Navigator.pop(context, "routine"),
          child: const Text("Elegir otra rutina"),
        ),

        TextButton(
          onPressed: () => Navigator.pop(context, "free"),
          child: const Text("Entrenamiento libre"),
        ),
      ],
    ),
  );

  if (result == "planned" && plannedRoutine != null) {
    setState(() {
      routine = plannedRoutine;
    });
    _initializeRoutineState();
    loading = false;
    return;
  }

  if (result == "free") {
    _startFreeWorkout();
    return;
  }

  await _loadAvailableRoutines();
}


void _startFreeWorkout() {
  setState(() {
    routine = {
      'id': null,
      'name': 'Entrenamiento libre',
      'blocks': <Map<String, dynamic>>[],
    };
  });

  _initializeRoutineState();
  loading = false;
}

bool _isCircuitRoundCompleted(
  int blockIndex,
  int round,
  List exercises,
) {
  for (final ex in exercises) {
    final name = normalizeExerciseName(ex['name']);

    final notifier =
        circuitoDone[blockIndex]?[round]?[name];

    if (notifier == null || notifier.value != true) {
      return false;
    }
  }
  return true;
}

  bool _isWorkoutCompleted() {
  // ================= SERIES =================
  for (final entry in seriesData.entries) {
    for (final set in entry.value) {
      if (set['done'] != true) return false;
    }
  }

  // ================= CIRCUITOS =================
  for (final entry in circuitoRound.entries) {
    final blockIndex = entry.key;
    final block = routine!['blocks'][blockIndex];

    // 🔹 Si no tiene ejercicios, se ignora
    if ((block['exercises'] as List).isEmpty) continue;

    final completedRounds =
        _countCompletedCircuitRounds(blockIndex, block);

    final visibleRounds = circuitoRound[blockIndex] ?? 1;

if (completedRounds < visibleRounds) return false;


  }

  // ================= TABATA =================
  for (int i = 0; i < routine!['blocks'].length; i++) {
  final block = routine!['blocks'][i];
  if (block['type'] != 'Tabata') continue;

  if (tabataTimer.isStarted(i) &&
      !tabataTimer.isCompleted(i)) {
    return false;
  }
}

return true;
  }

  // ================= SAVE =================

  Future<void> _confirmFinish() async {
    if (_saving) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Finalizar entrenamiento"),
        content: const Text("¿Estás seguro?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Finalizar"),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _saveWorkout();
    }
  }

String normalizeExerciseName(dynamic raw) {
  if (raw is String) return raw;
  if (raw is List && raw.isNotEmpty) return raw.first.toString();
  return 'Ejercicio';
}

 // ======================================================
      // 🧠 Resolver muscleWeights (FUENTE ÚNICA)
      // ======================================================
      Map<Muscle, double> resolveMuscleWeights(Map<String, dynamic> exData) {
        final Map<Muscle, double> result = {};

        if (exData.containsKey('muscleWeights')) {
          final raw = Map<String, dynamic>.from(exData['muscleWeights']);
          raw.forEach((k, v) {
            final match = Muscle.values.where((m) => m.name == k);
            if (match.isNotEmpty) {
              result[match.first] = (v as num).toDouble();
            }
          });
        }

        return result;
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
  setState(() {
    _savingStep = step;
  });
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

  debugPrint("❌ ERROR AL GUARDAR:");
  debugPrint(e.toString());
  debugPrint(stack.toString());

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Error al guardar. Revisa consola.")),
  );
}


Future<_WorkoutBuildResult> _buildWorkoutData() async {
  _setSavingStep("Procesando datos…");

  late DateTime startedAt;
  late DateTime finishedAt;
  late int durationMinutes;

  if (isEdit) {

    final workoutDate =
        (widget.existingWorkout?['date'] as Timestamp?)?.toDate()
            ?? DateTime.now();

    if (_originalStartedAt != null &&
        _originalFinishedAt != null &&
        _originalDurationMinutes != null) {

      startedAt = _originalStartedAt!;
      finishedAt = _originalFinishedAt!;
      durationMinutes = _originalDurationMinutes!;
    } else {

      final randomMinutes = 50 + Random().nextInt(21);

      finishedAt = workoutDate;
      startedAt =
          finishedAt.subtract(Duration(minutes: randomMinutes));
      durationMinutes = randomMinutes;
    }

  } else {

    finishedAt = DateTime.now();
    startedAt = workoutStartedAt ?? finishedAt;
    durationMinutes =
        finishedAt.difference(startedAt).inMinutes;
  }

  final List<Map<String, dynamic>> performed = [];
  final List<WorkoutSet> workoutSets = [];

  await _processSeries(performed, workoutSets);
  await _processCircuits(performed, workoutSets);
  await _processTabata(performed, workoutSets);

  return _WorkoutBuildResult(
    performed: performed,
    workoutSets: workoutSets,
    startedAt: startedAt,
    finishedAt: finishedAt,
    durationMinutes: durationMinutes,
  );
}


Future<void> _processSeries(
  List<Map<String, dynamic>> performed,
  List<WorkoutSet> workoutSets,
) async {
  _setSavingStep("Procesando series…");

  for (final entry in seriesData.entries) {
    
    final key = entry.key;
final blockIndex = int.parse(key.split('-').first);
final exerciseName = key.split('-').sublist(1).join('-');


    final exData = _getExerciseFromCatalog(exerciseName);
    if (exData == null) continue;

    final muscleWeights = resolveMuscleWeights(exData);

    final List<Map<String, dynamic>> setsToSave = [];

    for (int i = 0; i < entry.value.length; i++) {
      if (entry.value[i]['done'] != true) continue;

      final repsText = seriesRepsCtrl[key]?[i].text ?? '';
      final weightText = seriesWeightCtrl[key]?[i].text ?? '';


      final int reps = int.tryParse(repsText) ?? 0;
      final double? weight =
          weightText.isNotEmpty ? double.tryParse(weightText) : null;

      


      if (reps <= 0) continue;

      setsToSave.add({
        'reps': reps,
        'weight': weight,
        'rpe': entry.value[i]['rpe'],
      });

      workoutSets.add(
        WorkoutSet(
          exercise: exerciseName,
          sets: 1,
          reps: reps,
          rpe: (entry.value[i]['rpe'] as num).toDouble(),
          weight: weight,
          muscleWeights: muscleWeights,
          sourceType: 'Series',
        ),
      );
    }

    if (setsToSave.isNotEmpty) {
      final block = routine!['blocks'][blockIndex];

    final originalExercise = block['exercises'].firstWhere(
  (ex) => normalizeExerciseName(ex['name']) == exerciseName,
  orElse: () => <String, dynamic>{},
);

final bool perSide =
    (originalExercise is Map && originalExercise.containsKey('perSide'))
        ? originalExercise['perSide'] == true
        : false;

final existingBlock = performed.firstWhere(
  (b) => b['blockIndex'] == blockIndex,
  orElse: () => {},
);

if (existingBlock.isEmpty) {
  performed.add({
    'type': 'Series',
    'blockIndex': blockIndex,
    'blockTitle': block['title'] ?? block['name'] ?? 'Series',
    'exercises': [],
  });
}

final blockMap = performed.firstWhere(
  (b) => b['blockIndex'] == blockIndex,
);

blockMap['exercises'].add({
  'exercise': exerciseName,
  'perSide': perSide,
  'sets': setsToSave,
});



    }
  }
}

Future<void> _processCircuits(
  List<Map<String, dynamic>> performed,
  List<WorkoutSet> workoutSets,
) async {
  _setSavingStep("Procesando circuitos…");

  for (final entry in circuitoRound.entries) {
    final blockIndex = entry.key;
    final block = routine!['blocks'][blockIndex];

    final visibleRounds = circuitoRound[blockIndex] ?? 1;
    if (visibleRounds == 0) continue;

    final List<Map<String, dynamic>> roundsData = [];

    for (int r = 1; r <= visibleRounds; r++) {
      final List<Map<String, dynamic>> exercisesData = [];

      for (final ex in block['exercises']) {
        final name = normalizeExerciseName(ex['name']);

        final rpe = circuitoRpePorRonda[blockIndex]?[r]?[name];
        if (rpe == null) continue;

        final repsText =
            circuitoReps[blockIndex]?[r]?[name]?.text ?? '';
        final weightText =
            circuitoWeight[blockIndex]?[r]?[name]?.text ?? '';

        final int reps = int.tryParse(repsText) ?? 1;
        final double? weight =
            weightText.isNotEmpty ? double.tryParse(weightText) : null;

        final perSide =
    circuitoPerSide[blockIndex]?[name] == true;

exercisesData.add({
  'exercise': name,
  'reps': reps,
  'rpe': rpe,
  if (weight != null) 'weight': weight,
  'perSide': perSide,
});

        final exData = _getExerciseFromCatalog(name);
        if (exData == null) continue;

        final muscleWeights = resolveMuscleWeights(exData);

        workoutSets.add(
          WorkoutSet(
            exercise: name,
            sets: 1,
            reps: reps,
            rpe: rpe.toDouble(),
            weight: weight,
            muscleWeights: muscleWeights,
            sourceType: 'Circuito',
          ),
        );
      }

      if (exercisesData.isNotEmpty) {
        roundsData.add({
          'round': r,
          'exercises': exercisesData,
        });
      }
    }

    if (roundsData.isNotEmpty) {
      performed.add({
  'type': 'Circuito',
  'blockIndex': blockIndex,
  'blockTitle': block['title'] ?? block['name'] ?? 'Circuito',
  'rounds': roundsData,
});
    }
  }
}



Future<DocumentReference> _persistWorkout(
  _WorkoutBuildResult data,
) async {
  _setSavingStep("Guardando entrenamiento…");

  final uid = FirebaseAuth.instance.currentUser!.uid;
  final now = DateTime.now();

  if (isEdit) {
  final ref = widget.workoutRef!;

  await ref.update({
  'performed': data.performed,
  'startedAt': Timestamp.fromDate(data.startedAt),
  'finishedAt': Timestamp.fromDate(data.finishedAt),
  'durationMinutes': data.durationMinutes,
  'updatedAt': FieldValue.serverTimestamp(),
});

  return ref;
}

  return await FirebaseFirestore.instance
      .collection('workouts_logged')
      .add({
    'userId': uid,
    'routineId': routine!['id'],
    'routineName': routine!['name'],
    'date': Timestamp.fromDate(now),
    'startedAt': Timestamp.fromDate(data.startedAt),
    'finishedAt': Timestamp.fromDate(data.finishedAt),
    'durationMinutes': data.durationMinutes,
    'performed': data.performed,
  });
}



Future<void> _processTabata(
  List<Map<String, dynamic>> performed,
  List<WorkoutSet> workoutSets,
) async {
  _setSavingStep("Procesando tabata…");

  for (final entry in tabataTimer.allResults.entries) {
    final blockIndex = entry.key;
    final rpeByExercise = entry.value;
    final block = routine!['blocks'][blockIndex];

    final List<Map<String, dynamic>> exercisesData = [];

    for (final ex in block['exercises']) {
      final name = ex['name'];
      final rpe = rpeByExercise[name];

      if (rpe == null) continue;

      exercisesData.add({
        'exercise': name,
        'rpe': rpe,
      });

      final exData = _getExerciseFromCatalog(name);
      if (exData == null) continue;

      final muscleWeights = resolveMuscleWeights(exData);

      workoutSets.add(
        WorkoutSet(
          exercise: name,
          sets: 1,
          reps: 1,
          rpe: rpe.toDouble(),
          muscleWeights: muscleWeights,
          sourceType: 'Tabata',
        ),
      );
    }

    if (exercisesData.isNotEmpty) {
      performed.add({
  'type': 'Tabata',
  'blockIndex': blockIndex,
  'blockTitle': block['title'] ?? block['name'] ?? 'Tabata',
  'work': block['work'],
  'rest': block['rest'],
  'rounds': block['rounds'],
  'exercises': exercisesData,
});
    }
  }
}



Future<void> _saveWorkout() async {
  if (_saving) return;

  _startSaving();

  try {
    final data = await _buildWorkoutData();
    final muscleLoad = await _calculateLoad(data);
      final workoutRef = await _persistWorkout(data);


    await _updateFatigue(muscleLoad);

    await workoutRef.update({
      'muscleLoad': {
        for (final e in muscleLoad.entries)
          e.key.name: e.value
      }
    });


    _finishSaving();
    Navigator.pop(context);

  } catch (e, stack) {
    _handleSaveError(e, stack);
  }
}




Future<Map<Muscle, double>> _calculateLoad(
  _WorkoutBuildResult data,
) async {
  _setSavingStep("Calculando carga muscular…");

  return await WorkoutLoadService.calculateLoadFromWorkout({
    'performed': data.performed,
  });
}



Future<void> _updateFatigue(
  Map<Muscle, double> muscleLoad,
) async {
  _setSavingStep("Actualizando fatiga muscular…");

  final uid = FirebaseAuth.instance.currentUser!.uid;
  final now = DateTime.now();

  final muscleStateRef = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('muscle_state');

  for (final entry in muscleLoad.entries) {
    final muscle = entry.key;
    final sessionMuscleLoad = entry.value;

    final docRef = muscleStateRef.doc(muscle.name);
    final snap = await docRef.get();

    MuscleFatigueState state;

    if (snap.exists) {
  final previousState = MuscleFatigueState(
    fatigue: (snap['fatigue'] ?? 0).toDouble(),
    lastUpdate: (snap['lastUpdated'] as Timestamp).toDate(),
  );

  final recoveredFatigue = FatigueService.recoverToNow(
    fatigue: previousState.fatigue,
    lastUpdate: previousState.lastUpdate,
    now: now,
  );

  state = MuscleFatigueState(
    fatigue: recoveredFatigue,
    lastUpdate: now,
  );
} else {
  state = MuscleFatigueState(fatigue: 0, lastUpdate: now);
}

    final updatedState = FatigueService.updateAfterSession(
  state: state,
  sessionTime: now,
  sessionLoad: sessionMuscleLoad,
);

    await docRef.set({
      'fatigue': updatedState.fatigue,
      'lastUpdated': Timestamp.fromDate(updatedState.lastUpdate),
    });
  }
}
  }
