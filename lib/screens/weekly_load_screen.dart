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
  Map<String, double> exerciseTypeLoad = {};
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text("Sin datos en el rango.", style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  final dates = dailyLoads.keys.toList()..sort((a, b) => a.compareTo(b));
  final muscles = totalLoad.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final muscleKeys = muscles.map((e) => e.key).toList();

  return Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2A2A2A)),
    ),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          columnSpacing: 24,
          horizontalMargin: 16,
          headingRowHeight: 48,
          dataRowHeight: 44,
          headingTextStyle: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
          ),
          columns: [
            const DataColumn(label: Text("Músculo")),
            ...dates.map(
              (d) => DataColumn(
                label: Text(
                  "${d.day}/${d.month}",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const DataColumn(label: Text("Total")),
          ],
          rows: muscleKeys.map((muscle) {
            double rowTotal = 0;
            final cells = <DataCell>[
              DataCell(
                Text(
                  _muscleLabel(muscle),
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
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
                            final exercises = dailyDetails[d]?[muscle] ?? [];
                            _openMuscleDetail(
                              date: d,
                              muscle: muscle,
                              exercises: exercises,
                            );
                          }
                        : null,
                    child: Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        value > 0 ? value.toStringAsFixed(1) : "-",
                        style: TextStyle(
                          fontSize: 12,
                          color: value > 0 ? Theme.of(context).primaryColor : Colors.grey[600],
                          fontWeight: value > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            cells.add(
              DataCell(
                Container(
                  alignment: Alignment.center,
                  child: Text(
                    rowTotal.toStringAsFixed(1),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            );

            return DataRow(cells: cells);
          }).toList(),
        ),
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

    dailyLoads.clear();
    totalLoad.clear();
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

    // 1️⃣ Catálogo de ejercicios (una sola query)
    final exercisesSnapshot = await FirebaseFirestore.instance
        .collection('exercises')
        .get();

    final Map<String, Map<String, dynamic>> exerciseMap = {};
    for (final doc in exercisesSnapshot.docs) {
      final data = doc.data();
      exerciseMap[data['name']] = {
        'muscleWeights': Map<String, dynamic>.from(data['muscleWeights'] ?? {}),
        'exerciseType': data['exerciseType'] ?? 'Otro',
      };
    }

    // 2️⃣ Planned workouts del rango
    final workoutsSnapshot = await FirebaseFirestore.instance
        .collection('planned_workouts')
        .where('athleteId', isEqualTo: widget.athleteId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .get();

    if (workoutsSnapshot.docs.isEmpty) {
      setState(() => loading = false);
      return;
    }

    // 3️⃣ Mapear blockId → fecha normalizada
    final Map<String, DateTime> blockIdToDate = {};

    for (final doc in workoutsSnapshot.docs) {
      final data = doc.data();
      final workoutDate = (data['date'] as Timestamp).toDate();
      final normalizedDate = DateTime(workoutDate.year, workoutDate.month, workoutDate.day);

      if (data['blockId'] != null) {
        final blockId = data['blockId'] as String;
        blockIdToDate[blockId] = normalizedDate;
        dailyLoads.putIfAbsent(normalizedDate, () => {});
        dailyDetails.putIfAbsent(normalizedDate, () => {});
      }
    }

    // 4️⃣ Fetch paralelo de todos los bloques
    final uniqueBlockIds = blockIdToDate.keys.toList();
    final blockDocs = await Future.wait(
      uniqueBlockIds.map((id) =>
          FirebaseFirestore.instance.collection('blocks').doc(id).get()),
    );

    final Map<String, Map<String, dynamic>> blocksCache = {};
    for (int i = 0; i < uniqueBlockIds.length; i++) {
      if (blockDocs[i].exists) {
        blocksCache[uniqueBlockIds[i]] = blockDocs[i].data()!;
      }
    }

    // 5️⃣ Calcular carga con los bloques cacheados
    for (final entry in blockIdToDate.entries) {
      final block = blocksCache[entry.key];
      final normalizedDate = entry.value;
      if (block == null) continue;

      final String blockType = (block['type'] ?? 'normal').toString().toLowerCase();
      int blockMultiplier = 1;
      if (blockType == 'circuito' || blockType == 'tabata' || blockType == 'emom') {
        blockMultiplier = (block['rounds'] as num?)?.toInt() ?? 1;
      }

      final exercises = List<Map<String, dynamic>>.from(block['exercises'] ?? []);

      for (final ex in exercises) {
        final String name = (ex['name'] ?? '').toString();
        if (name.isEmpty) continue;

        final int sets = ((ex['series'] as num?)?.toInt() ?? 1) * blockMultiplier;
        final exerciseData = exerciseMap[name];
        if (exerciseData == null) continue;

        final weights = Map<String, dynamic>.from(exerciseData['muscleWeights'] ?? {});
        final String exType = exerciseData['exerciseType'] ?? 'Otro';

        weights.forEach((muscle, value) {
          final load = sets * (value as num).toDouble() * (exerciseTypeFactor[exType] ?? 1.0);

          dailyLoads[normalizedDate]![muscle] =
              (dailyLoads[normalizedDate]![muscle] ?? 0) + load;
          totalLoad[muscle] = (totalLoad[muscle] ?? 0) + load;
          exerciseTypeLoad[exType] = (exerciseTypeLoad[exType] ?? 0) + load;

          dailyDetails[normalizedDate]!.putIfAbsent(muscle, () => []);
          dailyDetails[normalizedDate]![muscle]!.add({
            'name': name,
            'sets': sets,
            'load': load,
            'type': exType,
          });
        });
      }
    }

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
  if (dailyLoads.isEmpty) {
    return Center(
      child: Text("Selecciona un rango con datos", style: TextStyle(color: Colors.grey[600])),
    );
  }

  return ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: dailyLoads.length,
    itemBuilder: (context, index) {
      final entry = dailyLoads.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      final date = entry[index].key;
      final muscles = entry[index].value;

      final normalized = _normalizeAbsolute(_toMuscleMap(muscles));
      final total = muscles.values.fold<double>(0, (a, b) => a + b);

      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${date.day}/${date.month}",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        "Carga diaria",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      total.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            GestureDetector(
              onTap: () => _openDayDetail(date, muscles),
              child: Container(
                height: 240,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: BodyHeatmap(heatmap: normalized, showBack: false),
                    ),
                    Expanded(
                      child: BodyHeatmap(heatmap: normalized, showBack: true),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextButton.icon(
                onPressed: () => _openDayDetail(date, muscles),
                icon: Icon(Icons.zoom_in, size: 18, color: Theme.of(context).primaryColor.withOpacity(0.8)),
                label: const Text("Ver detalle muscular"),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}



Widget _buildSummaryUnifiedView() {
  final source = totalLoad;
  final normalizedHeatmap = _normalizeAbsolute(_toMuscleMap(source));
  final groupLoads = _groupLoadsFrom(source);

  return ListView(
    padding: const EdgeInsets.all(20),
    children: [
      // 🔥 CARD PRINCIPAL: HEATMAP + TABLA
      Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.accessibility_new, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Text(
                  "Distribución Muscular",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 380,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF2A2A2A)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: BodyHeatmap(heatmap: normalizedHeatmap, showBack: false),
                          ),
                          Expanded(
                            child: BodyHeatmap(heatmap: normalizedHeatmap, showBack: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 3,
                    child: _buildMuscleTable(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 24),

      // 🔥 PIE CHARTS EN FILA O COLUMNA
      LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          return Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              SizedBox(
                width: isWide ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth,
                height: 320,
                child: _buildPieChartCard(
                  title: "Grupos Anatómicos",
                  data: groupLoads,
                  colorBase: Colors.blue,
                ),
              ),
              SizedBox(
                width: isWide ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth,
                height: 320,
                child: _buildPieChartCard(
                  title: "Tipos de Ejercicio",
                  data: exerciseTypeLoad,
                  colorBase: Colors.green,
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 40),
    ],
  );
}

Widget _buildPieChartCard({
  required String title,
  required Map<dynamic, double> data,
  required Color colorBase,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
      border: Border.all(color: const Color(0xFF2A2A2A)),
    ),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _buildPieChart(
            title: title, // Title is passed but not used inside _buildPieChart now
            data: data,
            colorBase: colorBase,
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
      final factor = 0.4 + (i * 0.12);
      colors.add(
        colorBase.withOpacity(factor.clamp(0.4, 0.9)),
      );
    }
  }

  return Row(
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
              final percent = total == 0 ? 0 : (value / total) * 100;

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
            final percent = total == 0 ? 0 : (value / total) * 100;

            final label = entry.key is AnatomicalGroup
                ? (entry.key as AnatomicalGroup).label
                : entry.key.toString();

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[index],
                      borderRadius: BorderRadius.circular(4),
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
  );
}






  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        centerTitle: true,
        title: const Text(
          "Carga de Entrenamiento",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.calendar_today_rounded, size: 20, color: Theme.of(context).primaryColor),
              onPressed: _pickRange,
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Theme.of(context).primaryColor,
                    unselectedLabelColor: Colors.grey[600],
                    indicatorColor: Theme.of(context).primaryColor,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(text: "Historial Diario"),
                      Tab(text: "Resumen Total"),
                    ],
                  ),
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
