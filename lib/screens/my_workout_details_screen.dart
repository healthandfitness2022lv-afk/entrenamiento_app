import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_set.dart';
import '../models/muscle_catalog.dart';
import '../utils/exercise_catalogs.dart';
import '../widgets/body_heatmap.dart';
import '../utils/svg_utils.dart';
import '../services/workout_load_service.dart';
import '../utils/rpe_factor.dart';
import 'log_workout_screen.dart';
 import '../utils/workout_rpe_utils.dart';




class MyWorkoutDetailsScreen extends StatefulWidget {
  final DocumentSnapshot workout;

  const MyWorkoutDetailsScreen({super.key, required this.workout});

  @override
  State<MyWorkoutDetailsScreen> createState() => _MyWorkoutDetailsScreenState();
}

class _MyWorkoutDetailsScreenState extends State<MyWorkoutDetailsScreen> {
  late Map<String, dynamic> workoutData;
  late List<Map<String, dynamic>> performed;
  Map<Muscle, double> centralizedLoad = {};

  bool loading = true;

  /// name -> exercise document
  final Map<String, Map<String, dynamic>> exercisesMap = {};

  /// métricas generales
  int totalSets = 0;
  int totalVolume = 0;
  double avgRpe = 0;

  /// toggle heatmap
  bool showBack = false;

  // ======================================================
  // 🚀 INIT
  // ======================================================
  @override
  void initState() {
    super.initState();
    workoutData = widget.workout.data() as Map<String, dynamic>;
    performed = List<Map<String, dynamic>>.from(workoutData['performed']);
    _loadAndCalculate();
  }

  


  // ======================================================
  // 🔄 LOAD & CALCULATE
  // ======================================================
  Future<void> _loadAndCalculate() async {
  await _loadExercises();
  _calculateStats();

  // 🔥 CARGA CENTRALIZADA
  centralizedLoad =
      await WorkoutLoadService.calculateLoadFromWorkout(
    workoutData,
  );

  setState(() => loading = false);
}





void _calculateStats() {
  totalSets = 0;
  totalVolume = 0;

  for (final e in performed) {
    // =======================
    // 🔵 SERIES
    // =======================
    if (e['type'] == 'Series') {
      for (final s in e['sets']) {
        if (s['done'] != true) continue;

        totalSets++;

        final double weight =
            (s['weight'] as num?)?.toDouble() ?? 0;
        final int reps =
            (s['reps'] as num?)?.toInt() ?? 0;
        final bool perSide = s['perSide'] == true;

        final double effectiveWeight =
            perSide ? weight * 2 : weight;

        if (reps > 0 && effectiveWeight > 0) {
          totalVolume += (effectiveWeight * reps).round();
        }
      }
    }

    // =======================
    // 🔴 CIRCUITO
    // =======================
    if (e['type'] == 'Circuito') {
      for (final round in e['rounds'] ?? []) {
        for (final ex in round['exercises'] ?? []) {
          totalSets++;

          final double weight =
              (ex['weight'] as num?)?.toDouble() ?? 0;
          final int reps =
              (ex['reps'] as num?)?.toInt() ?? 0;
          final bool perSide = ex['perSide'] == true;

          final double effectiveWeight =
              perSide ? weight * 2 : weight;

          if (reps > 0 && effectiveWeight > 0) {
            totalVolume += (effectiveWeight * reps).round();
          }
        }
      }
    }

    // =======================
    // 🟣 TABATA
    // =======================
    if (e['type'] == 'Tabata') {
      for (final _ in e['exercises'] ?? []) {
        totalSets++;
      }
    }
  }

  // 🔥 RPE PROMEDIO (FUENTE ÚNICA)
  avgRpe = calculateAverageWorkoutRPE(performed);
}



  // ======================================================
  // 🔎 CARGAR EJERCICIOS
  // ======================================================
  Future<void> _loadExercises() async {
    final Set<String> names = {};

    for (final e in performed) {
      if (e['type'] == 'Series') {
        // 🟢 nuevo formato
        if (e['exercise'] != null) {
          names.add(e['exercise']);
        }
        // 🔵 formato antiguo
        else if (e['exerciseKey'] != null) {
          names.add(e['exerciseKey'].toString().split('-').last);
        }
      }

      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final ex in round['exercises'] ?? []) {
            names.add(ex['exercise']);
          }
        }
      }
      if (e['type'] == 'Tabata') {
  for (final ex in e['exercises'] ?? []) {
    names.add(ex['exercise']);
  }
}

    }

    if (names.isEmpty) return;

    final snap = await FirebaseFirestore.instance
        .collection('exercises')
        .where('name', whereIn: names.toList())
        .get();

    for (final d in snap.docs) {
      exercisesMap[d['name']] = d.data();
    }
  }


 List<Widget> _heatmapLegendRowsCompact() {
  return [
    _legendCompact(3, "Muy baja", "<5"),
    _legendCompact(10, "Baja", "5–17"),
    _legendCompact(24, "Media", "18–29"),
    _legendCompact(38, "M-alta", "30–47"),
    _legendCompact(52, "Alta", "48–55"),
    _legendCompact(65, "Muy alta", ">55"),
  ];
}


Widget _legendCompact(double value, String label, String range) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: heatmapColor(value)
,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(fontSize: 10),
      ),
      Text(
        range,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.grey,
        ),
      ),
    ],
  );
}

  // ======================================================
  // 🧠 RESOLVER MÚSCULOS DESDE CATÁLOGO
  // ======================================================
  Map<Muscle, double> _resolveMuscles(List<String> muscleNames) {
    final Map<Muscle, double> result = {};

    for (final name in muscleNames) {
      final mapping = normalizedMuscleCatalogMap[normalizeKey(name)];

      if (mapping == null) {
        debugPrint("❌ Músculo no mapeado: $name");
        continue;
      }

      mapping.forEach((muscle, weight) {
        result[muscle] = (result[muscle] ?? 0) + weight;
      });
    }

    return result;
  }

  // ======================================================
  // 🧱 CONSTRUIR WorkoutSet PARA HEATMAP
  // ======================================================
  List<WorkoutSet> _buildWorkoutSetsForHeatmap() {
  final List<WorkoutSet> result = [];

  for (final e in performed) {
    // ==================================================
    // 🔵 SERIES
    // ==================================================
    if (e['type'] == 'Series') {
      final String? name =
          e['exercise'] ??
          (e['exerciseKey'] != null
              ? e['exerciseKey'].toString().split('-').last
              : null);

      if (name == null) continue;

      final ex = exercisesMap[name];
      if (ex == null) continue;

      final muscleWeights = _resolveMuscleWeightsFromExercise(ex);

      final setsList = List<Map<String, dynamic>>.from(e['sets'] ?? []);

for (int i = 0; i < setsList.length; i++) {
  final s = setsList[i];
  if (s['done'] != true) continue;

  result.add(
    WorkoutSet(
  exercise: name,
  sets: 1,
  reps: (s['reps'] as num?)?.toInt() ?? 1,
  rpe: (s['rpe'] as num).toDouble(),
  weight: (s['weight'] as num?)?.toDouble(),
  perSide: s['perSide'] == true, // 👈 CLAVE
  setIndex: i + 1,
  muscleWeights: muscleWeights,
  sourceType: 'Series',
),

  );
}
  }

    // ==================================================
    // 🟣 TABATA
    // ==================================================
    if (e['type'] == 'Tabata') {
      for (final exEntry in e['exercises'] ?? []) {
        final String name = exEntry['exercise'];

        final ex = exercisesMap[name];
        if (ex == null) continue;

        final muscleWeights = _resolveMuscleWeightsFromExercise(ex);

        result.add(
          WorkoutSet(
            exercise: name,
            sets: 1, // 1 estímulo lógico por ejercicio
            reps: 1,
            rpe: (exEntry['rpe'] as num).toDouble(),
            muscleWeights: muscleWeights,
            sourceType: 'Tabata',
          ),
        );
      }
    }

    // ==================================================
    // 🔴 CIRCUITO
    // ==================================================
    if (e['type'] == 'Circuito') {
      for (final round in e['rounds'] ?? []) {
        for (final exEntry in round['exercises'] ?? []) {
          final String name = exEntry['exercise'];

          final ex = exercisesMap[name];
          if (ex == null) continue;

          final muscleWeights = _resolveMuscleWeightsFromExercise(ex);
          final int reps = (exEntry['reps'] as num?)?.toInt() ?? 1;


          result.add(
            WorkoutSet(
  exercise: name,
  sets: 1,
  reps: reps,
  rpe: (exEntry['rpe'] as num).toDouble(),
  weight: (exEntry['weight'] as num?)?.toDouble(),
  perSide: exEntry['perSide'] == true, // 👈 CLAVE
  muscleWeights: muscleWeights,
  sourceType: 'Circuito',
),

          );
        }
      }
    }
  }

  return result;
}


  // ======================================================
  // 🧠 USAR PONDERACIÓN DEL EJERCICIO (FUENTE ÚNICA)
  // ======================================================
  Map<Muscle, double> _resolveMuscleWeightsFromExercise(
    Map<String, dynamic> ex,
  ) {
    final Map<Muscle, double> result = {};

    final raw = ex['muscleWeights'];

    // ======================================================
    // 🟢 CASO 1: ponderación moderna (enum en inglés)
    // ======================================================
    if (raw is Map && raw.isNotEmpty) {
      raw.forEach((k, v) {
        final key = k.toString();
        final value = (v as num).toDouble();

        // 🔥 mapping DIRECTO por enum.name
        final match = Muscle.values.where((m) => m.name == key).toList();

        if (match.isNotEmpty) {
          result[match.first] = (result[match.first] ?? 0) + value;
        } else {
          debugPrint("❌ Muscle enum no reconocido: $key");
        }
      });

      // ⛔️ CLAVE: si tenía muscleWeights, NO fallback
      return result;
    }

    // ======================================================
    // 🔁 CASO 2: ejercicios antiguos (sin ponderación)
    // ======================================================
    debugPrint("! Usando fallback por músculos clásicos");

    final muscleNames = <String>[
      ex['primaryMuscle'],
      ...?ex['secondaryMuscles'],
    ];

    return _resolveMuscles(muscleNames);
  }

  void _showHeatmapFullscreen(
    BuildContext context,
    Map<Muscle, double> heatmap,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: Row(
            children: [
              // =======================
              // 🧍 FRONTAL
              // =======================
              Expanded(
                flex: 2,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: AspectRatio(
                    aspectRatio: 3 / 5,
                    child: BodyHeatmap(heatmap: heatmap, showBack: false),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // =======================
              // 🧍 POSTERIOR
              // =======================
              Expanded(
                flex: 2,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: AspectRatio(
                    aspectRatio: 3 / 5,
                    child: BodyHeatmap(heatmap: heatmap, showBack: true),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // =======================
              // 📋 LISTA DE MÚSCULOS
              // =======================
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.black87,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Expanded(
                        child: SingleChildScrollView(
                          child: Column(
  children: (() {
    final entries = heatmap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.map((e) {
      final m = e.key;
      final value = e.value;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                m.label,
                style: TextStyle(
                  color: value == 0 ? Colors.grey : Colors.white,
                ),
              ),
            ),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(
                color: value == 0 ? Colors.grey : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }).toList();
  })(),
),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // =======================
              // ❌ CERRAR
              // =======================
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }



  // ======================================================
  // 🖥 UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final workoutSets = _buildWorkoutSetsForHeatmap(); // 👈 solo para detalle
final heatmap = centralizedLoad;



    return Scaffold(
  appBar: AppBar(title: const Text("Detalle entrenamiento")),
  body: LayoutBuilder(
    builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 700;

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 4),

          if (isMobile) ...[
            // =========================
            // 📱 MOBILE
            // ========================

            // 🧍🧍 FRONTAL + POSTERIOR
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 360,
                    child: GestureDetector(
                      onTap: () =>
                          _showHeatmapFullscreen(context, heatmap),
                      child: BodyHeatmap(
                        heatmap: heatmap,
                        showBack: false,

                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 360,
                    child: GestureDetector(
                      onTap: () =>
                          _showHeatmapFullscreen(context, heatmap),
                      child: BodyHeatmap(
                        heatmap: heatmap,
                        showBack: true,

                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 📏 ESCALA MÁS ESTRECHA
            Wrap(
              spacing: 10,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: _heatmapLegendRowsCompact(),
            ),

            const SizedBox(height: 24),

            // 📋 DETALLE
            _workoutDetailCompact(workoutSets),

            const SizedBox(height: 24),
            _summary(),
          ] else ...[
            // =========================
            // 🖥 TABLET / DESKTOP
            // =========================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _workoutDetailCompact(workoutSets),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Text(
                              "Carga muscular",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _heatmapLegend(),
                          IconButton(
                            icon: const Icon(Icons.flip),
                            onPressed: () =>
                                setState(() => showBack = !showBack),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 320,
                        child: GestureDetector(
                          onTap: () =>
                              _showHeatmapFullscreen(context, heatmap),
                          child: BodyHeatmap(
                            heatmap: heatmap,
                            showBack: showBack,

                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            _summary(),
          ],
        ],
      );
    },
  ),
);

  }

  Color _sourceColor(String type) {
  switch (type) {
    case 'Circuito':
      return Colors.orange;
    case 'Tabata':
      return Colors.red;
    default:
      return Colors.blue;
  }
}

double _structureFactor(WorkoutSet s) {
  switch (s.sourceType) {
    case 'Circuito':
      return 1.0;
    case 'Tabata':
      return 2.5;
    default:
      return 1.0;
  }
}

void _editWorkout() async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => LogWorkoutScreen(
        existingWorkout: workoutData,
        workoutRef: widget.workout.reference,
      ),
    ),
  );

  // 🔄 Al volver, recargar por si hubo cambios
  setState(() {
    loading = true;
  });

  workoutData = widget.workout.data() as Map<String, dynamic>;
  performed = List<Map<String, dynamic>>.from(workoutData['performed']);
  _loadAndCalculate();
}

double _calculateSessionFatiguePercent() {
  final values = centralizedLoad.values
      .where((v) => v > 10)
      .toList();

  if (values.isEmpty) return 0;

  final avg = values.reduce((a, b) => a + b) / values.length;

  // 🔥 normalización empírica
  // 100 ≈ sesión brutal (ajusta si quieres)
  final percent = (avg / 100) * 100;

  return percent.clamp(0, 100);
}





  // ======================================================
  // 🔍 DETALLE TRANSPARENTE DEL CÁLCULO
  // ======================================================
 Widget _workoutDetailCompact(List<WorkoutSet> sets) {
  // ====== agrupar Series / Tabata desde WorkoutSet ======
  final Map<String, Map<String, List<WorkoutSet>>> byBlock = {};

  for (final s in sets) {
    byBlock.putIfAbsent(s.sourceType, () => {});
    byBlock[s.sourceType]!.putIfAbsent(s.exercise, () => []);
    byBlock[s.sourceType]![s.exercise]!.add(s);
  }

  // acumulado global
  final Map<Muscle, double> totalAcc = {};

  // orden visual
  final blockOrder = ['Series', 'Circuito', 'Tabata'];

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Detalle del entrenamiento",
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),

      ...blockOrder.map((blockType) {
        // ======================================================
        // 🔴 CIRCUITO → USAR performed (NO WorkoutSet)
        // ======================================================
        if (blockType == 'Circuito') {
          final circuitos =
              performed.where((e) => e['type'] == 'Circuito').toList();

          if (circuitos.isEmpty) return const SizedBox();

          return Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: circuitos.asMap().entries.map((entry) {
      final index = entry.key;
      final c = entry.value;

      final rounds =
          List<Map<String, dynamic>>.from(c['rounds']);

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🟥 TÍTULO POR CIRCUITO
            Text(
              "CIRCUITO ${index + 1}",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _sourceColor('Circuito'),
              ),
            ),
            const SizedBox(height: 6),

            ...rounds.map((round) {
              final int r = round['round'];
              final exercises =
                  List<Map<String, dynamic>>.from(round['exercises']);

              return Padding(
                padding: const EdgeInsets.only(
                  left: 8,
                  bottom: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Ronda $r",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),

                    ...exercises.map((ex) {
  final weight = ex['weight'];
  final reps = ex['reps'];
  final seconds = ex['seconds'];

  final double rpe = (ex['rpe'] as num).toDouble();
  final double fRpe = rpeFactor(rpe);

  final exData = exercisesMap[ex['exercise']];
  final double exerciseFactor =
      exerciseTypeFactorOf(exData?['exerciseType']);

  final double blockFactor = 1.0; // Circuito

  final double fatigue =
      rpe * fRpe * exerciseFactor * blockFactor;

  // ===============================
  // 🔥 CARGA MUSCULAR (POR EJERCICIO)
  // ===============================
  final Map<Muscle, double> acc = {};

  if (exData != null) {
    final muscleWeights =
        _resolveMuscleWeightsFromExercise(exData);

    for (final e in muscleWeights.entries) {
      final v =
          rpe *
          fRpe *
          exerciseFactor *
          blockFactor *
          e.value;

      acc[e.key] = (acc[e.key] ?? 0) + v;
      totalAcc[e.key] = (totalAcc[e.key] ?? 0) + v;

    }
  }

  final musclesSorted = acc.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===============================
        // 📌 TEXTO PRINCIPAL
        // ===============================
        Text(
          "• ${ex['exercise']}"
          "${reps != null ? " · $reps reps" : ""}"
          "${seconds != null ? " · $seconds s" : ""}"
          "${weight != null ? " × ${weight.toStringAsFixed(1)} kg" : ""}"
          " · RPE ${rpe.toStringAsFixed(1)}",
          style: const TextStyle(fontSize: 11),
        ),

        // ===============================
        // 🧮 FATIGA
        // ===============================
        Text(
          "   Fatiga = "
          "${rpe.toStringAsFixed(0)} × "
          "${fRpe.toStringAsFixed(2)} × "
          "${exerciseFactor.toStringAsFixed(2)} × "
          "${blockFactor.toStringAsFixed(2)}"
          " = ${fatigue.toStringAsFixed(2)}",
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),

        // ===============================
        // 💪 CARGA MUSCULAR
        // ===============================
        if (musclesSorted.isNotEmpty)
          Text(
            "   " +
                musclesSorted
                    .map(
                      (e) =>
                          "${e.key.label}: +${e.value.toStringAsFixed(2)}",
                    )
                    .join(" · "),
            style: const TextStyle(fontSize: 11),
          ),
      ],
    ),
  );
}).toList(),


                  ],
                ),
              );
            }).toList(),
          ],
        ),
      );
    }).toList(),
  ),
);

        }

        // ======================================================
        // 🔵 SERIES / 🟣 TABATA → WorkoutSet
        // ======================================================
        final exercises = byBlock[blockType];
        if (exercises == null) return const SizedBox();

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                blockType.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _sourceColor(blockType),
                ),
              ),
              const SizedBox(height: 6),

              ...exercises.entries.map((entry) {
                final exerciseName = entry.key;
                final groupSets = entry.value;

                final ex = exercisesMap[exerciseName];
                final String? exerciseType = ex?['exerciseType'];

                final exerciseFactor =
                    exerciseTypeFactorOf(exerciseType);
                final blockFactor =
                    _structureFactor(groupSets.first);

                // aporte muscular por ejercicio
                final Map<Muscle, double> acc = {};
                for (final s in groupSets) {
  final bool perSide = s.perSide == true;

  final double weightFactor =
      s.weight != null
          ? (perSide ? 2.0 : 1.0)
          : 1.0;

  for (final e in s.muscleWeights.entries) {
    final v =
        s.sets *
        s.rpe *
        exerciseFactor *
        rpeFactor(s.rpe) *
        blockFactor *
        weightFactor *
        e.value;

    acc[e.key] = (acc[e.key] ?? 0) + v;
    totalAcc[e.key] = (totalAcc[e.key] ?? 0) + v;
  }
}

                final musclesSorted = acc.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "• $exerciseName",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                     

                      // ===== detalle por set / intervalo =====
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 12, top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:
                              groupSets.asMap().entries.map((e) {
  final i = e.key;
  final s = e.value;

  final double rpe = s.rpe;
  final double fRpe = rpeFactor(rpe);

  final bool perSide = s.perSide == true;

  final double? displayWeight = s.weight;

  // 🔥 FATIGA REAL (SIN REPS)
  final double blockFactor = _structureFactor(s);

final double fatigue =
  rpe *
  fRpe *
  exerciseFactor *
  blockFactor;



  final String label =
      blockType == 'Series'
          ? "Serie ${i + 1}"
          : "Intervalo ${i + 1}";

  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
  "$label: "
  "${displayWeight != null ? " × ${displayWeight.toStringAsFixed(1)} kg" : ""}"
  "${perSide ? " por lado" : ""}"
  " · RPE ${rpe.toStringAsFixed(1)}"
  " · fRPE ${fRpe.toStringAsFixed(2)}"
  " · tipo ${exerciseFactor.toStringAsFixed(2)}"
  " · bloque ${blockFactor.toStringAsFixed(2)}",
  style: const TextStyle(fontSize: 11),
),
Text(
  "   Fatiga = "
  "${rpe.toStringAsFixed(1)} × "
  "${fRpe.toStringAsFixed(2)} × "
  "${exerciseFactor.toStringAsFixed(2)} × "
  "${blockFactor.toStringAsFixed(2)}"
  " = ${fatigue.toStringAsFixed(2)}",
  style: const TextStyle(
    fontSize: 10,
    color: Colors.grey,
  ),
),


      ],
    ),
  );
}).toList(),

                        ),
                      ),

                      Text(
                        "  " +
                            musclesSorted
                                .map((e) =>
                                    "${e.key.label}: +${e.value.toStringAsFixed(2)}")
                                .join(" · "),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      }).toList(),

      const Divider(),

      // ======================================================
      // 🧠 RESUMEN MUSCULAR
      // ======================================================
      const Text(
        "Resumen muscular (acumulado)",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),

      ...(() {
        final sorted = totalAcc.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return sorted.map(
          (e) => Text(
            "• ${e.key.label}: ${e.value.toStringAsFixed(2)}",
          ),
        );
      })(),
    ],
  );
}


  // ======================================================
  // 🔝 HEADER
  // ======================================================
  Widget _header() {
  final sessionFatigue = _calculateSessionFatiguePercent();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        onTap: _editWorkout,
        child: Row(
          children: [
            Expanded(
              child: Text(
                workoutData['routineName'],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(Icons.edit, size: 18, color: Colors.grey),
          ],
        ),
      ),

      const SizedBox(height: 4),

      Text(
        (workoutData['date'] as Timestamp).toDate().toString(),
        style: const TextStyle(color: Colors.grey),
      ),

      const SizedBox(height: 12),

      // ===============================
      // 🔥 FATIGA DE LA SESIÓN
      // ===============================
      Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: sessionFatigue / 100,
              minHeight: 10,
              backgroundColor: Colors.grey.shade800,
              color: heatmapColor(sessionFatigue),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "${sessionFatigue.toStringAsFixed(0)}%",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),

      const SizedBox(height: 4),
      const Text(
        "Fatiga promedio de la sesión",
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
    ],
  );
}


  // ======================================================
  // 📊 RESUMEN
  // ======================================================
  Widget _summary() {
  Widget card(String label, String value) {
    return SizedBox(
      width: 160, // 👈 controla overflow en móvil
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Resumen",
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),

      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          card("RPE promedio", avgRpe.toStringAsFixed(1)),
          card("Series totales", totalSets.toString()),
          card(
            "Volumen total",
            totalVolume > 0 ? "$totalVolume kg" : "—",
          ),
          card("Ejercicios", exercisesMap.length.toString()),
        ],
      ),
    ],
  );
}


  // ======================================================
  // 🎨 LEYENDA DE COLORES
  // ======================================================
  Widget _heatmapLegend() {
    Widget row(double value, String label, String range) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: heatmapColor(value)
,

                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11)),
                Text(
                  range,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    row(0.05, "Muy baja", "0–10%"),
    row(0.20, "Baja", "10–25%"),
    row(0.35, "Media", "25–40%"),
    row(0.55, "Media–alta", "40–60%"),
    row(0.75, "Alta", "60–80%"),
    row(0.95, "Muy alta", "80–100%"),
  ],
);
  }
}

class GroupedWorkout {
  final String sourceType;
  final String exercise;
  final List<WorkoutSet> sets;

  GroupedWorkout({
    required this.sourceType,
    required this.exercise,
    required this.sets,
  });
}
