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
  Map<DateTime, Map<String, List<Map<String, dynamic>>>> dailyDetails = {};




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

final List<Color> anatomicalPalette = [
  const Color(0xFFE53935), // rojo
  const Color(0xFF1E88E5), // azul
  const Color(0xFF43A047), // verde
  const Color(0xFFFF9800), // naranja
  const Color(0xFF8E24AA), // morado
  const Color(0xFFFBC02D), // amarillo
  const Color(0xFF00ACC1), // cyan
];

void _openMuscleDetail({
  required DateTime date,
  required String muscle,
  required List<Map<String, dynamic>> exercises,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              "${_muscleLabel(muscle)} - ${date.day}/${date.month}",
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            if (exercises.isEmpty)
              const Text("No hay ejercicios.")
            else
              Expanded(
                child: ListView.builder(
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final ex = exercises[index];

                    return Card(
                      child: ListTile(
                        title: Text(ex['name']),
                        subtitle: Text(
                          "Sets: ${ex['sets']} | Tipo: ${ex['type']}",
                        ),
                        trailing: Text(
                          ex['load'].toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}



Widget _buildMuscleTable() {
  if (dailyLoads.isEmpty) {
    return const Text("Sin datos en el rango.");
  }

  final dates = dailyLoads.keys.toList()
    ..sort((a, b) => a.compareTo(b));

  final muscles = totalLoad.entries.toList()
  ..sort((a, b) => b.value.compareTo(a.value));

final muscleKeys = muscles.map((e) => e.key).toList();


  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 40,
        dataRowHeight: 36,
        columns: [
          const DataColumn(
            label: Text(
              "Músculo",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          // 🔥 Columnas por día
          ...dates.map(
            (d) => DataColumn(
              label: Text(
                "${d.day}/${d.month}",
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),

          const DataColumn(
            label: Text(
              "Total",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
        rows: muscleKeys.map((muscle) {

          double rowTotal = 0;

          final cells = <DataCell>[
            DataCell(
              Text(
                _muscleLabel(muscle),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ];

          for (final d in dates) {
            final value = dailyLoads[d]?[muscle] ?? 0;
            rowTotal += value;

            cells.add(
  DataCell(
    GestureDetector(
      onTap: value > 0
          ? () {
              final exercises =
                  dailyDetails[d]?[muscle] ?? [];

              _openMuscleDetail(
                date: d,
                muscle: muscle,
                exercises: exercises,
              );
            }
          : null,
      child: Text(
        value > 0 ? value.toStringAsFixed(1) : "-",
        style: TextStyle(
          fontSize: 12,
          color: value > 0
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
          fontWeight:
              value > 0 ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  ),
);

          }

          cells.add(
            DataCell(
              Text(
                rowTotal.toStringAsFixed(1),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );

          return DataRow(cells: cells);
        }).toList(),
      ),
    ),
  );
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
    dailyDetails.clear();


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

  final String blockType =
    (block['type'] ?? 'normal').toString().toLowerCase();


  int blockMultiplier = 1;

  // 🔁 CIRCUITO
  if (blockType == 'circuito') {
  blockMultiplier = block['rounds'] ?? 1;
}
else if (blockType == 'tabata') {
  blockMultiplier = block['rounds'] ?? 1;
}
else if (blockType == 'emom') {
  blockMultiplier = block['rounds'] ?? 1;
}


  final exercises = List<Map<String, dynamic>>.from(
    block['exercises'] ?? [],
  );


        for (final ex in exercises) {
  final String name = ex['name'];
  final int baseSets = ex['series'] ?? 1;
final int sets = baseSets * blockMultiplier;

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

  // 🔥 Asegurar fecha en ambos mapas
  dailyLoads.putIfAbsent(normalizedDate, () => {});
  dailyDetails.putIfAbsent(normalizedDate, () => {});

  // 🔥 Carga muscular
  dailyLoads[normalizedDate]![muscle] =
      (dailyLoads[normalizedDate]![muscle] ?? 0) + load;

  totalLoad[muscle] =
      (totalLoad[muscle] ?? 0) + load;

  exerciseTypeLoad[type] =
      (exerciseTypeLoad[type] ?? 0) + load;

  // 🔥 GUARDAR DETALLE
  dailyDetails[normalizedDate]!
      .putIfAbsent(muscle, () => []);

  dailyDetails[normalizedDate]![muscle]!.add({
    'name': name,
    'sets': sets,
    'load': load,
    'type': type,
  });
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

  AnatomicalGroup.values.map((g) {
    final v = groupLoads[g] ?? 0;
    if (maxGroup == 0) return 0.0;
    return (v / maxGroup) * 100;
  }).toList();

  final maxType = exerciseTypeLoad.isEmpty
      ? 1.0
      : exerciseTypeLoad.values.reduce((a, b) => a > b ? a : b);

  exerciseTypeLoad.keys.toList();

  exerciseTypeLoad.values.map<double>((v) {
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
        // 🔥 BLOQUE SUPERIOR → Heatmap + Tabla
SizedBox(
  height: 340,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [

      // 🔥 CUERPO
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

      // 🔥 TABLA
      Expanded(
        flex: 3,
        child: _buildMuscleTable(),
      ),
    ],
  ),
),

const SizedBox(height: 16),

// 🔥 BLOQUE INFERIOR → PIE CHARTS
SizedBox(
  height: 300,
  child: Row(
    children: [

      // ===============================
      // 🧠 GRUPOS ANATÓMICOS
      // ===============================
      Expanded(
        child: _buildPieChart(
          title: "Grupos Anatómicos",
          data: groupLoads,
          colorBase: Colors.blue,
        ),
      ),

      const SizedBox(width: 16),

      // ===============================
      // 🏋 TIPOS DE EJERCICIO
      // ===============================
      Expanded(
        child: _buildPieChart(
          title: "Tipos de Ejercicio",
          data: exerciseTypeLoad,
          colorBase: Colors.green,
        ),
      ),
    ],
  ),
),

      ],
    ),
  );
}


Widget _buildPieChart({
  required String title,
  required Map<dynamic, double> data,
  required Color colorBase,
}) {
  if (data.isEmpty) {
    return const Center(child: Text("Sin datos"));
  }

  final total = data.values.fold<double>(0, (a, b) => a + b);

  final entries = data.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  List<Color> colors = [];

for (int i = 0; i < entries.length; i++) {
  final entry = entries[i];

  if (entry.key is AnatomicalGroup) {
    colors.add(
      anatomicalPalette[i % anatomicalPalette.length],
    );
  } else {
    // Para tipos de ejercicio dejamos gradiente base
    final factor = 0.4 + (i * 0.12);
    colors.add(
      colorBase.withOpacity(factor.clamp(0.4, 0.9)),
    );
  }
}

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

      Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),

      const SizedBox(height: 12),

      Expanded(
        child: Row(
          children: [

            // ===========================
            // 🥧 PIE
            // ===========================
            Expanded(
              flex: 2,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 35,
                  sections: List.generate(entries.length, (index) {
                    final entry = entries[index];
                    final value = entry.value;
                    final percent =
                        total == 0 ? 0 : (value / total) * 100;

                    return PieChartSectionData(
                      value: value,
                      color: colors[index],
                      radius: 65,
                      title: "${percent.toStringAsFixed(0)}%",
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // ===========================
            // 📊 LEYENDA AL LADO
            // ===========================
            Expanded(
              flex: 3,
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final value = entry.value;
                  final percent =
                      total == 0 ? 0 : (value / total) * 100;

                  final label = entry.key is AnatomicalGroup
                      ? (entry.key as AnatomicalGroup).label
                      : entry.key.toString();

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [

                        // 🔵 Indicador de color
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colors[index],
                            borderRadius:
                                BorderRadius.circular(4),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                            ),
                          ),
                        ),

                        Text(
                          value.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(width: 6),

                        Text(
                          "(${percent.toStringAsFixed(0)}%)",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ],
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
