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
  int tabataElapsed = 0;
  int tabataTotal = 0;
  final Map<String, double?> _suggestedWeightCache = {};
  final Map<String, List<TextEditingController>> seriesRepsCtrl = {};
final Map<String, List<TextEditingController>> seriesWeightCtrl = {};
final Map<int, Map<int, Map<String, ValueNotifier<bool>>>> circuitoDone = {};
final Set<int> startedTabataBlocks = {};





  

  // estado por bloque
  final Map<int, bool> expandedBlocks = {};
  final Map<int, int> circuitoRound = {};
  List<Map<String, dynamic>> availableRoutines = [];
  bool get isEdit => widget.workoutRef != null;

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
  bool tabataRunning = false;

  int tabataRound = 0;
  String tabataExercise = "";
  TabataPhase? tabataPhase;
  final Set<int> completedTabataBlocks = {};
  final Map<int, Map<String, int>> tabataRpeResults = {};

  // series
  final Map<String, List<Map<String, dynamic>>> seriesData = {};

  @override
  void dispose() {
    tabataTimer.stop(); // 🔴 CLAVE
    super.dispose();
  }

@override
void initState() {
  super.initState();
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

void _loadSuggestionIfNeeded(
  String exercise,
  int reps,
) async {
  final key = "$exercise-$reps";

  if (_suggestedWeightCache.containsKey(key)) return;

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
    "Sugerido: ${value.toStringAsFixed(1)} kg",
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

  availableExercisesCatalog =
      snap.docs.map((d) => d.data()).toList();
}



void _loadWorkoutForEdit() {
  final workout = widget.existingWorkout!;
  final performed = List<Map<String, dynamic>>.from(workout['performed']);

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
  int circuitBlockCursor = 0; // 👈 DECLARACIÓN LOCAL CORRECTA

  for (final e in performed) {

    // ===================== SERIES (YA LO TENÍAS) =====================
    if (e['type'] == 'Series') {
      final name = e['exercise'];
      final sets = List<Map<String, dynamic>>.from(e['sets']);

      final key = seriesData.keys.firstWhere(
        (k) => k.endsWith(name),
        orElse: () => '',
      );

      if (key.isEmpty) continue;

      for (int i = 0; i < sets.length && i < seriesData[key]!.length; i++) {
        seriesData[key]![i]['reps'] = sets[i]['reps'];
        seriesData[key]![i]['weight'] = sets[i]['weight'];
        seriesData[key]![i]['rpe'] = sets[i]['rpe'];
        seriesData[key]![i]['done'] = true;
      }
    }

    // ===================== CIRCUITO =====================
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

      for (final r in rounds) {
        final int round = r['round'];

        circuitoReps[blockIndex]![round] = {};
        circuitoWeight[blockIndex]![round] = {};
        circuitoRpePorRonda[blockIndex]![round] = {};
        circuitoDone[blockIndex]![round] = {};

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
        }
      }
    }

    // ===================== TABATA =====================
    if (e['type'] == 'Tabata') {
      final int blockIndex = e['blockIndex'];
      final List exercises = e['exercises'] ?? [];

      startedTabataBlocks.add(blockIndex);
      completedTabataBlocks.add(blockIndex);

      tabataRpeResults[blockIndex] = {
        for (final ex in exercises)
          normalizeExerciseName(ex['exercise']): ex['rpe'],
      };
    }
  }
}


List<Map<String, dynamic>> _rebuildBlocksFromPerformed(
  List<Map<String, dynamic>> performed,
) {
  final List<Map<String, dynamic>> blocks = [];

  int? seriesBlockIndex;
  final List<Map<String, dynamic>> seriesExercises = [];

  void ensureSeriesBlockAtCurrentPosition() {
    if (seriesBlockIndex != null) return;
    seriesBlockIndex = blocks.length;
    blocks.add({
      'type': 'Series',
      'exercises': <Map<String, dynamic>>[],
    });
  }

  for (final e in performed) {
    final type = e['type'];

    // ================= SERIES (AGRUPADO EN 1 SOLO BLOQUE) =================
    if (type == 'Series') {
      ensureSeriesBlockAtCurrentPosition();

      final String name = normalizeExerciseName(e['exercise']);
      final List<Map<String, dynamic>> sets =
          List<Map<String, dynamic>>.from(e['sets'] ?? const []);

      if (name.isEmpty || sets.isEmpty) continue;

      // Evita duplicar el mismo ejercicio si aparece más de una vez
      if (seriesExercises.any((x) => normalizeExerciseName(x['name']) == name)) {
        continue;
      }

      final first = sets.first;
      final String valueType = (first['valueType'] ?? 'reps').toString();

      final int baseValue = valueType == 'time'
          ? (first['value'] is int ? first['value'] as int : int.tryParse("${first['value']}") ?? 0)
          : (first['reps'] is int ? first['reps'] as int : int.tryParse("${first['reps']}") ?? 0);

      final dynamic w = first['weight'];
      final double? weight = w == null
          ? null
          : (w is num ? w.toDouble() : double.tryParse("$w"));

      seriesExercises.add({
        'name': name,
        'series': sets.length,
        'valueType': valueType,
        'value': baseValue,
        'reps': valueType == 'reps' ? baseValue : null,
        if (weight != null) 'weight': weight,
      });

      continue;
    }

    // ================= CIRCUITO =================
    if (type == 'Circuito') {
      final List exercises = [];

      final roundsRaw = (e['rounds'] as List?) ?? const [];
      for (final r in roundsRaw) {
        final exs = (r['exercises'] as List?) ?? const [];
        for (final ex in exs) {
          final exName = normalizeExerciseName(ex['exercise']);
          if (exName.isEmpty) continue;

          if (!exercises.any((x) => normalizeExerciseName(x['name']) == exName)) {
            exercises.add({
              'name': exName,
              'reps': ex['reps'] ?? 1,
              'perSide': ex['perSide'] == true,
            });
          }
        }
      }

      blocks.add({
        'type': 'Circuito',
        'rounds': roundsRaw.length,
        'exercises': exercises,
      });
      continue;
    }

    // ================= TABATA =================
    if (type == 'Tabata') {
      final exs = (e['exercises'] as List?) ?? const [];
      blocks.add({
        'type': 'Tabata',
        'work': e['work'],
        'rest': e['rest'],
        'rounds': e['rounds'],
        'exercises': exs
            .map((x) => {'name': normalizeExerciseName(x['exercise'] ?? x['name'])})
            .toList(),
      });
      continue;
    }
  }

  // Inyecta los ejercicios Series al bloque agrupado
  if (seriesBlockIndex != null) {
    blocks[seriesBlockIndex!]['exercises'] = seriesExercises;
  }

  return blocks;
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


  void _markTabataCompleted(int blockIndex, Map<String, int> rpeByExercise) {
    setState(() {
      completedTabataBlocks.add(blockIndex);
      tabataRpeResults[blockIndex] = rpeByExercise;
    });
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



  // ================= CIRCUITO =================

 Widget _buildCircuitBlock(int index, Map<String, dynamic> block) {
  if (!(expandedBlocks[index] ?? false)) return const SizedBox();

  final int totalRounds = block['rounds'] ?? 1;
  final int currentRound = circuitoRound[index] ?? 1;

  circuitoWeight.putIfAbsent(index, () => {});
  circuitoReps.putIfAbsent(index, () => {});
  circuitoRpePorRonda.putIfAbsent(index, () => {});

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (int round = 1; round <= currentRound; round++) ...[
        _circuitRoundCard(index, block, round, totalRounds),
        const SizedBox(height: 16),
      ],

      if (currentRound < totalRounds)
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.forward),
            label: Text("Completar ronda ${currentRound + 1}"),
            onPressed: () {
              setState(() {
                circuitoRound[index] = currentRound + 1;
              });
            },
          ),
        ),
    ],
  );
}
Widget _circuitRoundCard(
  int blockIndex,
  Map<String, dynamic> block,
  int round,
  int totalRounds,
) {
  circuitoWeight[blockIndex]!.putIfAbsent(round, () => {});
  circuitoReps[blockIndex]!.putIfAbsent(round, () => {});
  circuitoRpePorRonda[blockIndex]!.putIfAbsent(round, () => {});

  return Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Ronda $round / $totalRounds",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          for (final ex in block['exercises'])
            _circuitExerciseRow(blockIndex, round, ex),
        ],
      ),
    ),
  );
}
Widget _circuitExerciseRow(
  int blockIndex,
  int round,
  Map<String, dynamic> ex,
) {
  final String name = normalizeExerciseName(ex['name']);

  circuitoReps[blockIndex]![round]!.putIfAbsent(
    name,
    () => TextEditingController(
      text: (ex['reps'] ?? 1).toString(),
    ),
  );

  circuitoWeight[blockIndex]![round]!.putIfAbsent(
    name,
    () => TextEditingController(
      text: (ex['weight'] ?? 0).toString(),
    ),
  );

  circuitoRpePorRonda[blockIndex]![round]!.putIfAbsent(name, () => 5);

  circuitoDone.putIfAbsent(blockIndex, () => {});
circuitoDone[blockIndex]!.putIfAbsent(round, () => {});
circuitoDone[blockIndex]![round]!.putIfAbsent(
  name,
  () => ValueNotifier<bool>(false),
);



  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),

      Row(
        children: [
          Expanded(
            child: TextField(
              controller: circuitoReps[blockIndex]![round]![name],
              decoration: const InputDecoration(labelText: "Reps"),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: TextField(
              controller: circuitoWeight[blockIndex]![round]![name],
              decoration: const InputDecoration(labelText: "Peso"),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),

          DropdownButton<int>(
            value: circuitoRpePorRonda[blockIndex]![round]![name],
            items: List.generate(
              10,
              (i) => DropdownMenuItem(
                value: i + 1,
                child: Text("RPE ${i + 1}"),
              ),
            ),
            onChanged: (v) {
              setState(() {
                circuitoRpePorRonda[blockIndex]![round]![name] = v!;
              });
            },
          ),

          ValueListenableBuilder<bool>(
  valueListenable: circuitoDone[blockIndex]![round]![name]!,
  builder: (_, checked, __) {
    return Checkbox(
  value: checked,
  fillColor: MaterialStateProperty.resolveWith((states) {
    if (states.contains(MaterialState.selected)) {
      return Theme.of(context).colorScheme.primary; // 🟢 verde
    }
    return Colors.transparent; // ⬜ transparente
  }),
  checkColor: Colors.black,
  side: const BorderSide(color: Colors.grey),
  onChanged: (v) {
    circuitoDone[blockIndex]![round]![name]!.value = v!;
  },
);

  },
),


        ],
      ),

      const SizedBox(height: 12),
    ],
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


  // ================= SERIES =================

  Widget _buildSeriesBlock(int index, Map<String, dynamic> block) {
  if (!(expandedBlocks[index] ?? false)) return const SizedBox();


  return Column(
    children: [
      // ================= EJERCICIOS =================
      for (final ex in block['exercises'])
  Builder(
    builder: (_) {
      final String name = normalizeExerciseName(ex['name']);
      final String key = "$index-$name";

      // 🛡️ PROTECCIÓN CRÍTICA
      if (!seriesData.containsKey(key) || seriesData[key]!.isEmpty) {
        return const SizedBox();
      }

      final bool isTimeBased =
          seriesData[key]![0]['valueType'] == 'time';

            return Column(
              children: [
                const SizedBox(height: 12),

                // ================= HEADER EJERCICIO =================
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (_getEquipment(ex) != null)
                            Text(
                              _getEquipment(ex)!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          if (_isPerSide(ex))
                            const Text(
                              "Por lado",
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),

                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => _showExerciseInfo(ex),
                    ),IconButton(
  icon: const Icon(Icons.close, size: 18),
  tooltip: "Eliminar ejercicio",
  onPressed: () => _confirmDeleteExercise(index, name),
),


                  ],
                ),

                const SizedBox(height: 8),

                // ================= TABLA SERIES =================
                Table(
                  columnWidths: const {
                    0: FixedColumnWidth(50),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                    3: FlexColumnWidth(),
                    4: FixedColumnWidth(40),
                  },
                  children: [
                    TableRow(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Text("Serie"),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(isTimeBased ? "Tiempo (s)" : "Reps"),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Text("Peso"),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Text("RPE"),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Text("✔"),
                        ),
                      ],
                    ),

                    for (int i = 0; i < seriesData[key]!.length; i++)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text("${i + 1}"),
                          ),

                          // REPS / TIEMPO
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: TextField(
  controller: seriesRepsCtrl[key]![i],
  keyboardType: TextInputType.number,
  textInputAction: TextInputAction.done, // 👈 para que salga "Done"
  onChanged: (v) {
    seriesData[key]![i]['reps'] = int.tryParse(v);
  },
  onSubmitted: (v) {
    final reps = int.tryParse(v) ?? 0;
    seriesData[key]![i]['reps'] = reps;

    if (reps > 0) {
      // no borres el del mismo reps, borra “todos” los de ese ejercicio:
      _suggestedWeightCache.removeWhere((k, _) => k.startsWith("$name-"));

      // dispara sugerencia con reps final
      _loadSuggestionIfNeeded(name, reps);
    }

    // fuerza rebuild para que aparezca el texto "Sugerido..."
    setState(() {});
  },
),


                          ),

                          // PESO
                          Padding(
  padding: const EdgeInsets.all(4),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ================= PESO =================
      TextField(
  controller: seriesWeightCtrl[key]![i],
  keyboardType: TextInputType.number,
  onChanged: (v) {
    seriesData[key]![i]['weight'] = int.tryParse(v) ?? 0;
  },
),


      // ================= SUGERENCIA =================
      if (seriesData[key]![i]['reps'] != null)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: _suggestedWeightText(
      name,
      seriesData[key]![i]['reps'],
    ),
  ),

    ],
  ),
),


                          // RPE
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: DropdownButton<int>(
                              value: seriesData[key]![i]['rpe'],
                              items: List.generate(
                                10,
                                (r) => DropdownMenuItem(
                                  value: r + 1,
                                  child: Text("${r + 1}"),
                                ),
                              ),
                              onChanged: (v) => setState(() {
                                seriesData[key]![i]['rpe'] = v!;
                              }),
                            ),
                          ),

                          // DONE
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Checkbox(
                              value: seriesData[key]![i]['done'],
                              fillColor:
                                  MaterialStateProperty.resolveWith((states) {
                                if (states.contains(MaterialState.selected)) {
                                  return Theme.of(context)
                                      .colorScheme
                                      .primary;
                                }
                                return Colors.transparent;
                              }),
                              checkColor: Colors.black,
                              side: const BorderSide(color: Colors.grey),
                              onChanged: (v) => setState(() {
                                seriesData[key]![i]['done'] = v!;
                              }),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // ================= BOTONES SERIES +/- =================
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
  icon: const Icon(Icons.remove_circle_outline),
  onPressed: seriesData[key]!.length > 1
      ? () {
          setState(() {
            seriesData[key]!.removeLast();
            seriesRepsCtrl[key]!.removeLast();
            seriesWeightCtrl[key]!.removeLast();
          });
        }
      : null,
),

                    IconButton(
  icon: const Icon(Icons.add_circle_outline),
  onPressed: () {
    setState(() {
      final last = seriesData[key]!.last;

      // 1️⃣ Agregar data
      seriesData[key]!.add({
        'valueType': last['valueType'],
        'value': last['value'],
        'reps': last['reps'],
        'weight': last['weight'],
        'rpe': last['rpe'],
        'done': false,
      });

      // 2️⃣ Agregar controllers SINCRONIZADOS
      seriesRepsCtrl[key]!.add(
        TextEditingController(
          text: last['reps']?.toString() ?? '',
        ),
      );

      seriesWeightCtrl[key]!.add(
        TextEditingController(
          text: last['weight']?.toString() ?? '',
        ),
      );
    });
  },
),

                  ],
                ),
              ],
            );
          },
        ),

      const SizedBox(height: 16),

      // ================= BOTÓN ÚNICO DEL BLOQUE =================
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text("Agregar ejercicio"),
          onPressed: () => _addExerciseToSeries(index),
        ),
      ),
    ],
  );
}


  Widget _buildTabataBlock(int index, Map<String, dynamic> block) {
  if (!(expandedBlocks[index] ?? false)) {
    return const SizedBox();
  }

  final int work = block['work'];
  final int rest = block['rest'];
  final int rounds = block['rounds'];
  final List exercises = block['exercises'];

  final bool started = startedTabataBlocks.contains(index);
  final bool completed = completedTabataBlocks.contains(index);
  final Map<String, int>? rpeResults = tabataRpeResults[index];

  return Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Tabata",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text("Trabajo: $work s · Descanso: $rest s · Rondas: $rounds"),

          const SizedBox(height: 12),

          // ================= EJERCICIOS + RPE =================
          if (completed && rpeResults != null) ...[
            const Text(
              "Resultados:",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            for (final ex in exercises)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(ex['name']),
                  Text(
                    "RPE ${rpeResults[ex['name']] ?? '-'}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
          ] else ...[
            // 🔹 No ejecutado aún
            ...exercises.map((e) => Text("• ${e['name']}")),
          ],

          const SizedBox(height: 16),

          // ================= BOTÓN =================
          Align(
  alignment: Alignment.centerRight,
  child: completed
      ? OutlinedButton.icon(
          icon: const Icon(Icons.replay),
          label: const Text("Repetir Tabata"),
          onPressed: () {
            setState(() {
              completedTabataBlocks.remove(index);
              tabataRpeResults.remove(index);
            });

            _startTabata(blockIndex: index, block: block);
          },
        )
      : ElevatedButton(
  onPressed: () {
  _startTabata(blockIndex: index, block: block);
},

  child: Text(started ? "Continuar Tabata" : "Iniciar Tabata"),
),

),
        ]
      ),
    ),
  );
}



  void _startTabata({
    required int blockIndex,
    required Map<String, dynamic> block,
  }) {
      startedTabataBlocks.add(blockIndex); // 👈 CLAVE

    setState(() {
      tabataRunning = true;
    });

    tabataTimer.start(
      workSeconds: block['work'],
      restSeconds: block['rest'],
      rounds: block['rounds'],
      exercises: List<Map<String, dynamic>>.from(block['exercises']),

      onTick: (round, exercise, phase, elapsed, total) {
        if (!mounted) return; // 🔥 CLAVE
        setState(() {
          tabataRound = round;
          tabataExercise = exercise['name'];
          tabataPhase = phase;
          tabataElapsed = elapsed;
          tabataTotal = total;
        });
      },

      onFinish: () {
        if (!mounted) return;
        setState(() {
          tabataRunning = false;
        });
        _askTabataRpe(blockIndex, block);
      },
    );
  }


void _skipTabata() async {
  // 1️⃣ Detener timer
  tabataTimer.stop();

  setState(() {
    tabataRunning = false;
  });

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

  for (final ex in block['exercises']) {
    final String name = normalizeExerciseName(ex['name']);

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
        final key = "$i-${ex['name']}";
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

    _markTabataCompleted(blockIndex, rpeByExercise);
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

  if (ok == true) {
  setState(() {
    routine!['blocks'].removeAt(index);

    expandedBlocks.remove(index);
    circuitoRound.remove(index);
    circuitoReps.remove(index);
    circuitoWeight.remove(index);
    circuitoRpePorRonda.remove(index);
    circuitoDone.remove(index);
    startedTabataBlocks.remove(index);
    completedTabataBlocks.remove(index);
    tabataRpeResults.remove(index);
  });
}

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
            _buildCircuitBlock(i, routine!['blocks'][i]),

          if (routine!['blocks'][i]['type'] == 'Series')
            _buildSeriesBlock(i, routine!['blocks'][i]),

          if (routine!['blocks'][i]['type'] == 'Tabata')
            _buildTabataBlock(i, routine!['blocks'][i]),

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
    if (tabataRunning) _tabataOverlay(),
  ],
),

    );
  }

  // ================= VALIDATION =================


Widget _tabataOverlay() {
  final bool isWork = tabataPhase == TabataPhase.work;

  return Positioned.fill(
    child: Container(
      color: Colors.black.withOpacity(0.45), // fondo oscurecido
      child: Center(
        child: Card(
          elevation: 16,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "TABATA",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                Text(
                  "Ronda $tabataRound",
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),

                Text(
                  tabataExercise,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  isWork ? "TRABAJO" : "DESCANSO",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: isWork ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  "$tabataElapsed / $tabataTotal s",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                TextButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text("Finalizar Tabata"),
                  onPressed: _skipTabata,
                ),
              ],
            ),
          ),
        ),
      ),
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
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text("¿Cómo quieres entrenar hoy?"),
      content: const Text(
        "Puedes seguir una rutina asignada o entrenar libremente.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, "free"),
          child: const Text("Entrenamiento libre"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, "routine"),
          child: const Text("Usar rutina asignada"),
        ),
      ],
    ),
  );

  if (result == "free") {
    _startFreeWorkout();
  } else {
    await _loadAvailableRoutines();
  }
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

    // 🔹 Si nunca se inició, NO bloquea finalizar
    if (!startedTabataBlocks.contains(i)) continue;

    // 🔹 Si se inició, debe completarse
    if (!completedTabataBlocks.contains(i)) return false;
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



  Future<void> _saveWorkout() async {
    
    if (_saving) return;

    void setStep(String step) {
      setState(() {
        _saving = true;
        _savingStep = step;
      });
    }

    void finish() {
      setState(() {
        _saving = false;
        _savingStep = "";
      });
    }

    try {
      setStep("Preparando datos…");

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();

      final List<Map<String, dynamic>> performed = [];
      final List<WorkoutSet> workoutSets = [];

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

      // ======================================================
      // 1️⃣ SERIES
      // ======================================================
      setStep("Procesando series…");

      for (final entry in seriesData.entries) {
        final exerciseName = entry.key.split('-').last;

        final exSnap = await FirebaseFirestore.instance
            .collection('exercises')
            .where('name', isEqualTo: exerciseName)
            .limit(1)
            .get();

        if (exSnap.docs.isEmpty) continue;

        final exData = exSnap.docs.first.data();
        final muscleWeights = resolveMuscleWeights(exData);
        final bool perSide = exData['perSide'] == true;


        for (final s in entry.value) {
          if (s['done'] != true) continue;

          final bool isTimeBased = s['valueType'] == 'time';

final int reps = isTimeBased
    ? 1
    : (s['reps'] ?? 0);

final int seconds = isTimeBased
    ? (s['value'] ?? 0)
    : 0;

if ((isTimeBased && seconds <= 0) || (!isTimeBased && reps <= 0)) continue;


          final int stimulus = isTimeBased
              ? (s['value'] ?? 0)
              : (s['reps'] ?? 0);

          if (stimulus <= 0) continue; // 🔒 evita basura

          workoutSets.add(
  WorkoutSet(
    exercise: exerciseName,
    sets: 1,
    reps: reps,
    rpe: (s['rpe'] as num).toDouble(),
    weight: (s['weight'] as num?)?.toDouble(),
    muscleWeights: muscleWeights,
    sourceType: 'Series',
    perSide: perSide, // 👈 NUEVO
  ),
);

        }

       performed.add({
  'type': 'Series',
  'exercise': normalizeExerciseName(exData['name']),
  'sets': entry.value.map((s) {
    return {
      ...s,
      'perSide': perSide, // 👈 CLAVE
    };
  }).toList(),
});


      }

      // ======================================================
      // 2️⃣ CIRCUITOS
      // ======================================================
      setStep("Procesando circuitos…");

      for (final entry in circuitoRound.entries) {
        final blockIndex = entry.key;
        final block = routine!['blocks'][blockIndex];
        final completedRounds =
    _countCompletedCircuitRounds(blockIndex, block);


        if (completedRounds == 0) continue;

        final List<Map<String, dynamic>> roundsData = [];

        for (int r = 1; r <= completedRounds; r++) {
          final List<Map<String, dynamic>> exercisesData = [];

          for (final ex in block['exercises']) {
            final String name = normalizeExerciseName(ex['name']);

            final int? rpe = circuitoRpePorRonda[blockIndex]?[r]?[name];

            if (rpe == null) continue;
            final weightText = circuitoWeight[blockIndex]?[r]?[name]?.text;

            final double? weight = weightText != null && weightText.isNotEmpty
                ? double.tryParse(weightText)
                : null;

            final repsText = circuitoReps[blockIndex]?[r]?[name]?.text;
final int reps = repsText != null && repsText.isNotEmpty
    ? int.tryParse(repsText) ?? 1
    : 1;
 // estímulo lógico si es por tiempo

exercisesData.add({
  'exercise': name,
  'rpe': rpe,
  'reps': reps,
  'perSide': ex['perSide'] == true, // 👈 AQUÍ
  if (weight != null) 'weight': weight,
  if (ex['value'] != null) 'seconds': ex['value'],
});



            final exSnap = await FirebaseFirestore.instance
                .collection('exercises')
                .where('name', isEqualTo: name)
                .limit(1)
                .get();

            if (exSnap.docs.isNotEmpty) {
              final muscleWeights = resolveMuscleWeights(
                exSnap.docs.first.data(),
              );

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
          }

          if (exercisesData.isNotEmpty) {
            roundsData.add({'round': r, 'exercises': exercisesData});
          }
        }

        if (roundsData.isNotEmpty) {
          performed.add({
            'type': 'Circuito',
            'blockIndex': blockIndex,
            'name': block['name'] ?? 'Circuito ${blockIndex + 1}',
            'rounds': roundsData,
          });
        }
      }

      // ======================================================
      // 2️⃣ TABATA
      // ======================================================
      setStep("Procesando tabata…");

      for (final entry in tabataRpeResults.entries) {
        final blockIndex = entry.key;
        final rpeByExercise = entry.value;
        final block = routine!['blocks'][blockIndex];

        final List<Map<String, dynamic>> exercisesData = [];

        for (final ex in block['exercises']) {
          final String name = ex['name'];
          final int? rpe = rpeByExercise[name];
          if (rpe == null) continue;

          exercisesData.add({'exercise': name, 'rpe': rpe});

          final exSnap = await FirebaseFirestore.instance
              .collection('exercises')
              .where('name', isEqualTo: name)
              .limit(1)
              .get();

          if (exSnap.docs.isNotEmpty) {
            final muscleWeights = resolveMuscleWeights(
              exSnap.docs.first.data(),
            );

            workoutSets.add(
              WorkoutSet(
                exercise: name,
                sets: 1, // estímulo lógico
                reps: 1,
                rpe: rpe.toDouble(),
                muscleWeights: muscleWeights,
                sourceType: 'Tabata',
              ),
            );
          }
        }

        if (exercisesData.isNotEmpty) {
          performed.add({
            'type': 'Tabata',
            'blockIndex': blockIndex,
            'name': block['name'] ?? 'Tabata ${blockIndex + 1}',
            'work': block['work'],
            'rest': block['rest'],
            'rounds': block['rounds'],
            'exercises': exercisesData,
          });
        }
      }

      // ======================================================
      // 3️⃣ GUARDAR ENTRENAMIENTO
      // ======================================================
      setStep("Guardando entrenamiento…");

      DocumentReference workoutRef;

if (isEdit) {
  // ✏️ EDITAR ENTRENAMIENTO EXISTENTE
  workoutRef = widget.workoutRef!;

  await workoutRef.update({
    'performed': performed,
    'updatedAt': FieldValue.serverTimestamp(),
  });
} else {
  // 🆕 CREAR NUEVO ENTRENAMIENTO
  workoutRef = await FirebaseFirestore.instance
      .collection('workouts_logged')
      .add({
        'userId': uid,
        'routineId': routine!['id'],
        'routineName': routine!['name'],
        'date': Timestamp.fromDate(now),
        'performed': performed,
      });
}


      // ======================================================
      // 4️⃣ CALCULAR CARGA MUSCULAR
      // ======================================================
      setStep("Calculando carga muscular…");


      final muscleLoad = await WorkoutLoadService.calculateLoadFromWorkout({
        'performed': performed,
      });

      // ======================================================
      // 5️⃣ ACTUALIZAR FATIGA (MODELO CONTINUO POR HORA)
      // ======================================================
      setStep("Actualizando fatiga muscular…");

      final muscleStateRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('muscle_state');

      for (final entry in muscleLoad.entries) {
        final muscle = entry.key;
        final sessionMuscleLoad = entry.value;

        final docRef = muscleStateRef.doc(muscle.name);
        final snap = await docRef.get();

        // Estado previo
        MuscleFatigueState state;

        if (snap.exists) {
          state = MuscleFatigueState(
            fatigue: (snap['fatigue'] ?? 0).toDouble(),
            lastUpdate: (snap['lastUpdated'] as Timestamp).toDate(),
          );
        } else {
          state = MuscleFatigueState(fatigue: 0, lastUpdate: now);
        }

        // 🏋️ Actualizar tras esta sesión
        final updatedState = FatigueService.updateAfterSession(
          state: state,
          sessionTime: now,
          sessionLoad: sessionMuscleLoad,
        );

        // 💾 Guardar estado resumido
        await docRef.set({
          'fatigue': updatedState.fatigue,
          'lastUpdated': Timestamp.fromDate(updatedState.lastUpdate),
        });
      }

      await workoutRef.update({
        'muscleLoad': {for (final e in muscleLoad.entries) e.key.name: e.value},
      });

      finish();
      Navigator.pop(context);
    } catch (e) {
      finish();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error al guardar: $e")));
    }
  }
}
