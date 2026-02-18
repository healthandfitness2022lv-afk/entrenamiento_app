import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/body_heatmap.dart';
import '../models/muscle_catalog.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/exercise_catalogs.dart';




class WeeklyLoadScreen extends StatefulWidget {
  final String athleteId;
  final DateTime initialDate;

  const WeeklyLoadScreen({
    super.key,
    required this.athleteId,
    required this.initialDate,
  });

  @override
  State<WeeklyLoadScreen> createState() => _WeeklyLoadScreenState();
}

class _WeeklyLoadScreenState extends State<WeeklyLoadScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  DateTimeRange? selectedRange;
  bool loading = false;

  Map<DateTime, Map<String, double>> dailyLoads = {};
  Map<String, double> totalLoad = {};
  Map<String, double> averageLoad = {};
  Map<String, double> exerciseTypeLoad = {};
  bool _showAverage = false; // false = acumulado, true = promedio



  @override
void initState() {
  super.initState();

  _tabController = TabController(length: 2, vsync: this);

  final start = widget.initialDate.subtract(
    Duration(days: widget.initialDate.weekday - 1),
  );
  final end = start.add(const Duration(days: 6));

  selectedRange = DateTimeRange(start: start, end: end);

  _calculateLoad();
}

@override
void dispose() {
  _tabController.dispose();
  super.dispose();
}




Map<AnatomicalGroup, double> _groupLoadsFrom(
  Map<String, double> source,
) {
  final Map<AnatomicalGroup, double> result = {};

  for (final group in AnatomicalGroup.values) {
    double sum = 0;

    final muscles = anatomicalGroups[group]!;

    for (final m in muscles) {
      sum += source[m.name] ?? 0;
    }

    result[group] = sum;
  }

  return result;
}





  // ==========================================================
  // RANGE PICKER
  // ==========================================================
  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: selectedRange,
    );

    if (range != null) {
      setState(() {
        selectedRange = range;
      });

      _calculateLoad();
    }
  }

  // ==========================================================
  // CORE CALCULATION
  // ==========================================================
  Future<void> _calculateLoad() async {
    exerciseTypeLoad.clear();
    if (selectedRange == null) return;


    setState(() => loading = true);

    dailyLoads.clear();
    totalLoad.clear();
    averageLoad.clear();

    final start = DateTime(
      selectedRange!.start.year,
      selectedRange!.start.month,
      selectedRange!.start.day,
    );

    final end = DateTime(
      selectedRange!.end.year,
      selectedRange!.end.month,
      selectedRange!.end.day + 1,
    );

    // 1️⃣ Traer TODOS los ejercicios una sola vez
    final exercisesSnapshot = await FirebaseFirestore.instance
        .collection('exercises')
        .get();

    final Map<String, Map<String, dynamic>> exerciseMap = {};

    for (final doc in exercisesSnapshot.docs) {
      final data = doc.data();
      exerciseMap[data['name']] = {
  'muscleWeights': Map<String, dynamic>.from(
    data['muscleWeights'] ?? {},
  ),
  'exerciseType': data['exerciseType'] ?? 'Otro',
};

    }

    // 2️⃣ Traer workouts del rango
    final workoutsSnapshot = await FirebaseFirestore.instance
        .collection('planned_workouts')
        .where('athleteId', isEqualTo: widget.athleteId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .get();

    for (final workout in workoutsSnapshot.docs) {
      final data = workout.data();
      final routineId = data['routineId'];

      final workoutDate = (data['date'] as Timestamp).toDate();

      final normalizedDate = DateTime(
        workoutDate.year,
        workoutDate.month,
        workoutDate.day,
      );

      dailyLoads.putIfAbsent(normalizedDate, () => {});

      final routineDoc = await FirebaseFirestore.instance
          .collection('routines')
          .doc(routineId)
          .get();

      final blocks = List<Map<String, dynamic>>.from(
        routineDoc.data()?['blocks'] ?? [],
      );

      for (final block in blocks) {
        final exercises = List<Map<String, dynamic>>.from(
          block['exercises'] ?? [],
        );

        for (final ex in exercises) {
  final String name = ex['name'];
  final int sets = ex['series'] ?? 1;
  final exerciseData = exerciseMap[name];

if (exerciseData == null) continue;

final weights =
    Map<String, dynamic>.from(exerciseData['muscleWeights'] ?? {});

final String type =
    exerciseData['exerciseType'] ?? 'Otro';


  weights.forEach((muscle, value) {
  final weightValue = (value as num).toDouble();

  final factor = exerciseTypeFactor[type] ?? 1.0;

  final load = sets * weightValue * factor;


    // Carga muscular (lo que ya tienes)
    dailyLoads[normalizedDate]![muscle] =
        (dailyLoads[normalizedDate]![muscle] ?? 0) + load;

    totalLoad[muscle] =
        (totalLoad[muscle] ?? 0) + load;

    // 🔥 NUEVO → carga por tipo de ejercicio
    exerciseTypeLoad[type] =
        (exerciseTypeLoad[type] ?? 0) + load;
  });
}

      }
    }

    final daysCount = selectedRange!.duration.inDays + 1;

    totalLoad.forEach((muscle, value) {
      averageLoad[muscle] = value / daysCount;
    });

    setState(() => loading = false);
  }

  Map<Muscle, double> _toMuscleMap(Map<String, double> input) {
    final Map<Muscle, double> result = {};

    for (final entry in input.entries) {
      try {
        final muscle = Muscle.values.firstWhere((m) => m.name == entry.key);

        result[muscle] = entry.value;
      } catch (_) {}
    }

    return result;
  }

  Map<Muscle, double> _normalizeAbsolute(Map<Muscle, double> input) {
    final Map<Muscle, double> scaled = {};

    input.forEach((muscle, value) {
      // Suponiendo que 15 series ponderadas es 100%
      final percent = (value / 15) * 100;
      scaled[muscle] = percent.clamp(0, 100);
    });

    return scaled;
  }

  List<MapEntry<String, double>> _sortedMuscles(Map<String, double> input) {
    final entries = input.entries.toList();

    entries.sort((a, b) => b.value.compareTo(a.value));

    return entries;
  }

  void _openDayDetail(
  DateTime date,
  Map<String, double> muscles,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {

      final normalized = _normalizeAbsolute(
        _toMuscleMap(muscles),
      );

      final sorted = _sortedMuscles(muscles)
          .where((e) => e.value > 0)
          .toList();

      return Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            Text(
              "Detalle ${date.day}/${date.month}/${date.year}",
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: BodyHeatmap(
                      heatmap: normalized,
                      showBack: false,
                    ),
                  ),
                  Expanded(
                    child: BodyHeatmap(
                      heatmap: normalized,
                      showBack: true,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView(
                children: sorted.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(_muscleLabel(e.key))),
                        Text(
                          e.value.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _muscleLabel(String key) {
  try {
    final muscle =
        Muscle.values.firstWhere((m) => m.name == key);
    return muscle.label;
  } catch (_) {
    return key;
  }
}



Widget _buildPerDayView() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Text(
          "${selectedRange!.start.toString().split(' ')[0]}  →  ${selectedRange!.end.toString().split(' ')[0]}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 16),

        SizedBox(
          height: 500,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: dailyLoads.entries.map((entry) {
                final date = entry.key;
                final muscles = entry.value;

                final normalized = _normalizeAbsolute(
                  _toMuscleMap(muscles),
                );

                final total = muscles.values.fold<double>(
                  0,
                  (a, b) => a + b,
                );

                return GestureDetector(
                  onTap: () {
                    _openDayDetail(date, muscles);
                  },
                  child: Container(
                    width: 500,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "${date.day}/${date.month}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          total.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: BodyHeatmap(
                                  heatmap: normalized,
                                  showBack: false,
                                ),
                              ),
                              Expanded(
                                child: BodyHeatmap(
                                  heatmap: normalized,
                                  showBack: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    ),
  );
}



Widget _buildSummaryUnifiedView() {
  final source = _showAverage ? averageLoad : totalLoad;
  final title = _showAverage ? "Promedio" : "Acumulado";

  final normalizedHeatmap = _normalizeAbsolute(_toMuscleMap(source));

  final groupLoads = _groupLoadsFrom(source);
  final maxGroup = groupLoads.values.isEmpty
      ? 1.0
      : groupLoads.values.reduce((a, b) => a > b ? a : b);

  final normalizedGroups = AnatomicalGroup.values.map((g) {
    final v = groupLoads[g] ?? 0;
    if (maxGroup == 0) return 0.0;
    return (v / maxGroup) * 100;
  }).toList();

  final maxType = exerciseTypeLoad.isEmpty
      ? 1.0
      : exerciseTypeLoad.values.reduce((a, b) => a > b ? a : b);

  final typeKeys = exerciseTypeLoad.keys.toList();

  final normalizedTypes = exerciseTypeLoad.values.map<double>((v) {
    if (maxType == 0) return 0.0;
    return (v / maxType) * 100;
  }).toList();

  return SingleChildScrollView(
    padding: const EdgeInsets.all(12), // 👈 más compacto
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // 🔹 Header compacto + switch
        Row(
          children: [
            Expanded(
              child: Text(
                "${selectedRange!.start.toString().split(' ')[0]} → ${selectedRange!.end.toString().split(' ')[0]}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Row(
              children: [
                const Text("Acum", style: TextStyle(fontSize: 12)),
                Switch(
                  value: _showAverage,
                  onChanged: (v) => setState(() => _showAverage = v),
                ),
                const Text("Prom", style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),

        const SizedBox(height: 6),

        Text(
          "Resumen $title",
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 10),

        // 🔥 Heatmap (un poco más alto, menos padding)
        SizedBox(
  height: 320,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [

      // 🔥 CUERPO (frente + espalda)
      Expanded(
        flex: 2,
        child: Row(
          children: [
            Expanded(
              child: BodyHeatmap(
                heatmap: normalizedHeatmap,
                showBack: false,
              ),
            ),
            Expanded(
              child: BodyHeatmap(
                heatmap: normalizedHeatmap,
                showBack: true,
              ),
            ),
          ],
        ),
      ),

      const SizedBox(width: 12),

      // 🔥 RADAR GRUPOS
      Expanded(
        flex: 1,
        child: RadarChart(
          RadarChartData(
            radarShape: RadarShape.polygon,
            dataSets: [
              RadarDataSet(
                fillColor: Colors.blue.withOpacity(0.25),
                borderColor: Colors.blue,
                borderWidth: 2,
                dataEntries: normalizedGroups
                    .map((v) => RadarEntry(value: v))
                    .toList(),
              ),
            ],
            getTitle: (index, angle) {
              final group = AnatomicalGroup.values[index];
              return RadarChartTitle(text: group.label);
            },
            tickCount: 4,
            ticksTextStyle: const TextStyle(
              color: Colors.transparent,
            ),
          ),
        ),
      ),

      const SizedBox(width: 12),

      // 🔥 RADAR TIPOS
      Expanded(
        flex: 1,
        child: RadarChart(
          RadarChartData(
            radarShape: RadarShape.polygon,
            dataSets: [
              RadarDataSet(
                fillColor: Colors.green.withOpacity(0.25),
                borderColor: Colors.green,
                borderWidth: 2,
                dataEntries: normalizedTypes
                    .map((v) => RadarEntry(value: v))
                    .toList(),
              ),
            ],
            getTitle: (index, angle) {
              return RadarChartTitle(text: typeKeys[index]);
            },
            tickCount: 4,
            ticksTextStyle: const TextStyle(
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    ],
  ),
),


        const SizedBox(height: 12),

        // 🔹 Lista muscular compacta (sin tanto aire)
        Text(
          "Músculos: ${source.length}",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),

        const SizedBox(height: 6),

        ..._sortedMuscles(source)
            .where((e) => e.value > 0)
            .take(14) // 👈 opcional: limita para que no sea eterno
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _muscleLabel(e.key),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      e.value.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

        const SizedBox(height: 8),

        Text(
          _showAverage
              ? "Promedio = total / días"
              : "Acumulado = sumatoria del rango",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    ),
  );
}


  // ==========================================================
  // UI
  // ==========================================================
  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text("Carga Planificada"),
      actions: [
        IconButton(
          icon: const Icon(Icons.date_range),
          onPressed: _pickRange,
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [

              const SizedBox(height: 8),

              TabBar(
  controller: _tabController,
  tabs: const [
    Tab(text: "Por día"),
    Tab(text: "Resumen"),
  ],
),


              Expanded(
                child: TabBarView(
  controller: _tabController,
  children: [
    _buildPerDayView(),
    _buildSummaryUnifiedView(),
  ],
),


              ),
            ],
          ),
  );
}

}
