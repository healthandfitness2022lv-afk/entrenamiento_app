import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/muscle_catalog.dart';
import '../services/fatigue_recalculation_service.dart';
import '../services/fatigue_service.dart';
import '../utils/svg_utils.dart';

enum AuditViewMode {
  muscle,
  anatomical,
  functional,
}


class FatigueAuditScreen extends StatefulWidget {
  final List<FatigueRecalculationStep> steps;
  

  const FatigueAuditScreen({
    super.key,
    required this.steps,
  });

  @override
  State<FatigueAuditScreen> createState() => _FatigueAuditScreenState();
}

class _FatigueAuditScreenState extends State<FatigueAuditScreen> {
  Set<Muscle> chartMuscles = {};
  Set<Muscle> pendingChartMuscles = {};
  Set<AnatomicalGroup> selectedAnatomicalGroups = {};
Set<FunctionalGroup> selectedFunctionalGroups = {};



  DateTimeRange? chartRange;
  bool hasPendingChanges = false;
  bool showGlobalFatigue = true;
  AuditViewMode viewMode = AuditViewMode.muscle;



  @override
void initState() {
  super.initState();

  final now = DateTime.now();

  chartRange = DateTimeRange(
    start: now.subtract(const Duration(days: 6)),
    end: now,
  );

  chartMuscles = {Muscle.values.first};
  pendingChartMuscles = {...chartMuscles};
}


  List<FatigueRecalculationStep> _filterStepsByRange(
  List<FatigueRecalculationStep> steps,
) {
  final now = DateTime.now();

  final from = chartRange?.start ??
      now.subtract(const Duration(days: 30));

  final rawTo = chartRange?.end ?? now;

  // 🔥 convertir a fin del día
  final to = DateTime(
    rawTo.year,
    rawTo.month,
    rawTo.day,
    23, 59, 59, 999,
  );

  return steps.where((s) {
    return !s.workoutDate.isBefore(from) &&
        !s.workoutDate.isAfter(to);
  }).toList();
}



List<FlSpot> _buildMuscleTimeline(
  Muscle muscle,
  List<FatigueRecalculationStep> filtered,
) {
  if (filtered.isEmpty) return [];

  final startDate = DateTime(
    filtered.first.workoutDate.year,
    filtered.first.workoutDate.month,
    filtered.first.workoutDate.day,
  );

  final endDate = DateTime(
    filtered.last.workoutDate.year,
    filtered.last.workoutDate.month,
    filtered.last.workoutDate.day,
  );

  // Agrupar sesiones por día
  final stepsByDay = <DateTime, List<FatigueRecalculationStep>>{};
  for (final s in filtered) {
    final day = DateTime(
      s.workoutDate.year,
      s.workoutDate.month,
      s.workoutDate.day,
    );
    stepsByDay.putIfAbsent(day, () => []);
    stepsByDay[day]!.add(s);
  }

  double currentFatigue =
      filtered.first.fatigueBefore[muscle] ?? 0;

  DateTime lastUpdate =
      filtered.first.workoutDate;

  final spots = <FlSpot>[];
  DateTime cursor = startDate;

  while (!cursor.isAfter(endDate)) {
    final dayIndex =
        cursor.difference(startDate).inHours / 24.0;

    // 🔵 Recuperación hasta inicio del día
    currentFatigue = FatigueService.recoverToNow(
      fatigue: currentFatigue,
      lastUpdate: lastUpdate,
      now: cursor,
    );

    spots.add(FlSpot(dayIndex, currentFatigue));
    lastUpdate = cursor;

    // 🔴 Aplicar sesiones del día
    final sessions = stepsByDay[cursor] ?? [];

    sessions.sort(
      (a, b) => a.workoutDate.compareTo(b.workoutDate),
    );

    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];

      currentFatigue = FatigueService.recoverToNow(
        fatigue: currentFatigue,
        lastUpdate: lastUpdate,
        now: s.workoutDate,
      );

      lastUpdate = s.workoutDate;

      final load =
          (s.fatigueAfter[muscle] ?? 0) -
          (s.fatigueAfterRecovery[muscle] ?? 0);

      currentFatigue += load;

      final offset = 0.25 + (i * 0.15);

      spots.add(FlSpot(dayIndex + offset, currentFatigue));
    }

    cursor = cursor.add(const Duration(days: 1));
  }

  return spots;
}

List<FlSpot> _buildGroupTimeline(
  List<Muscle> muscles,
  List<FatigueRecalculationStep> filtered,
) {
  final Map<double, double> aggregated = {};

  for (final m in muscles) {
    final timeline = _buildMuscleTimeline(m, filtered);

    for (final spot in timeline) {
      aggregated.update(
        spot.x,
        (value) => value + spot.y,
        ifAbsent: () => spot.y,
      );
    }
  }

  return aggregated.entries
      .map((e) => FlSpot(e.key, e.value))
      .toList()
    ..sort((a, b) => a.x.compareTo(b.x));
}









Widget _auditFatigueChart(List<FatigueRecalculationStep> steps) {
  final filtered = _filterStepsByRange(steps);
  final startDate = filtered.first.workoutDate;


  if (filtered.isEmpty) {
  return const Center(
    child: Text(
      "No hay datos en este rango",
      style: TextStyle(color: Colors.grey),
    ),
  );
}



final series = <String, List<FlSpot>>{};

if (viewMode == AuditViewMode.muscle) {
  for (final m in chartMuscles) {
    series[m.label] = [];
  }
}

else if (viewMode == AuditViewMode.anatomical) {
  for (final group in selectedAnatomicalGroups) {
    series[group.label] = [];
  }
}

else if (viewMode == AuditViewMode.functional) {
  for (final group in selectedFunctionalGroups) {
    series[group.label] = [];
  }
}



  if (viewMode == AuditViewMode.muscle) {
  for (final m in chartMuscles) {
    series[m.label] =
        _buildMuscleTimeline(m, filtered);
  }
}

if (viewMode == AuditViewMode.anatomical) {
  for (final group in selectedAnatomicalGroups) {
    series[group.label] =
        _buildGroupTimeline(
          anatomicalGroups[group]!,
          filtered,
        );
  }
}

if (viewMode == AuditViewMode.functional) {
  for (final group in selectedFunctionalGroups) {
    series[group.label] =
        _buildGroupTimeline(
          functionalGroups[group]!,
          filtered,
        );
  }


}
final globalSeries = <FlSpot>[];

if (showGlobalFatigue) {
  final Map<double, Map<Muscle, double>> fatigueByX = {};

  // 1️⃣ Construir fatiga por músculo en cada punto X
  for (final m in Muscle.values) {
    final timeline = _buildMuscleTimeline(m, filtered);

    for (final spot in timeline) {
      fatigueByX.putIfAbsent(spot.x, () => {});
      fatigueByX[spot.x]![m] = spot.y;
    }
  }

  // 2️⃣ En cada X tomar los 6 mayores
  for (final entry in fatigueByX.entries) {
    final x = entry.key;
    final values = entry.value.values.toList();

    if (values.isEmpty) continue;

    values.sort((a, b) => b.compareTo(a));

    final top6 = values.take(6).toList();

    final avg =
        top6.reduce((a, b) => a + b) / top6.length;

    globalSeries.add(FlSpot(x, avg));
  }

  globalSeries.sort((a, b) => a.x.compareTo(b.x));
}





double maxYValue = 100;

for (final entry in series.values) {
  for (final spot in entry) {
    if (spot.y > maxYValue) {
      maxYValue = spot.y;
    }
  }
}

for (final spot in globalSeries) {
  if (spot.y > maxYValue) {
    maxYValue = spot.y;
  }
}

final totalDays = filtered.last.workoutDate
    .difference(startDate)
    .inDays + 1;

double maxXValue = 0;

for (final entry in series.values) {
  if (entry.isNotEmpty) {
    final lastX = entry.last.x;
    if (lastX > maxXValue) {
      maxXValue = lastX;
    }
  }
}



  return SizedBox(
  height: 360,
  child: InteractiveViewer(
    constrained: false,
    boundaryMargin: const EdgeInsets.all(20),
    minScale: 1,
    maxScale: 4,
    child: SizedBox(
      
width: (totalDays * 60.0).clamp(
  MediaQuery.of(context).size.width,
  double.infinity,
),


      height: 360,
      child: LineChart(
        LineChartData(
        minX: 0,

maxX: maxXValue + 0.5,

minY: 0,
maxY: maxYValue + 10,

        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    interval: 20,
    reservedSize: 40,
    getTitlesWidget: (value, _) {
      return Text(
        value.toInt().toString(),
        style: const TextStyle(fontSize: 11),
      );
    },
  ),
),
      rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    interval: 1,
    getTitlesWidget: (value, _) {
      final dayOffset = value.floor();

      final date = startDate.add(
        Duration(days: dayOffset),
      );

      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          "${date.day}/${date.month}",
          style: const TextStyle(fontSize: 11),
        ),
      );
    },
  ),
),


        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipRoundedRadius: 10,
            tooltipPadding: const EdgeInsets.all(10),
            getTooltipItems: (touchedSpots) {
  if (touchedSpots.isEmpty) return [];

  final dayOffset = touchedSpots.first.x.floor();

  final tooltipDate = startDate.add(
    Duration(days: dayOffset),
  );

  final fechaTxt =
      "${tooltipDate.day.toString().padLeft(2, '0')}/"
      "${tooltipDate.month.toString().padLeft(2, '0')}/"
      "${tooltipDate.year}";

  return touchedSpots.map((spot) {
    final key = series.keys.elementAt(spot.barIndex);

    return LineTooltipItem(
      "$fechaTxt\n$key\nFatiga: ${spot.y.toStringAsFixed(1)}%",
      TextStyle(
        color: heatmapColor(spot.y),
        fontWeight: FontWeight.bold,
      ),
    );
  }).toList();
},
         ),
        ),
        lineBarsData: [
          ...series.entries.map((e) {
  final index = series.keys.toList().indexOf(e.key);

  return LineChartBarData(

              spots: e.value,
              isCurved: false,
              barWidth: 2,
              color: heatmapColor(40 + index * 5),

              dotData: FlDotData(show: true),
            );
          }),
          if (showGlobalFatigue && globalSeries.isNotEmpty)
    LineChartBarData(
      spots: globalSeries,
      isCurved: false,
      barWidth: 4,
      color: const Color.fromARGB(255, 221, 0, 0),
      dotData: FlDotData(show: false),
      dashArray: [6, 4], // punteada profesional
    ),
],
      ),
    ),
  ),));
}

Widget _buildSelector() {
  switch (viewMode) {
    case AuditViewMode.muscle:
      return _muscleSelector();

    case AuditViewMode.anatomical:
      return _anatomicalSelector();

    case AuditViewMode.functional:
      return _functionalSelector();
  }
}

Widget _anatomicalSelector() {
  return Wrap(
    spacing: 6,
    children: anatomicalGroups.keys.map((group) {
      final selected = selectedAnatomicalGroups.contains(group);


      return FilterChip(
        label: Text(group.label,
            style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (v) {
          setState(() {
            if (v) {
  selectedAnatomicalGroups.add(group);
} else {
  selectedAnatomicalGroups.remove(group);
}

          });
        },
      );
    }).toList(),
  );
}


Widget _functionalSelector() {
  return Wrap(
    spacing: 6,
    children: functionalGroups.keys.map((group) {
      final selected = selectedFunctionalGroups.contains(group);


      return FilterChip(
        label: Text(group.label,
            style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (v) {
          setState(() {
            if (v) {
  selectedFunctionalGroups.add(group);
} else {
  selectedFunctionalGroups.remove(group);
}

          });
        },
      );
    }).toList(),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Evolución de fatiga"),
        actions: [
          Switch(
            value: showGlobalFatigue,
            onChanged: (v) {
              setState(() {
                showGlobalFatigue = v;
              });
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: Text("Promedio")),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    ChoiceChip(
  label: const Text("Músculo"),
  selected: viewMode == AuditViewMode.muscle,
  onSelected: (_) {
    setState(() {
      viewMode = AuditViewMode.muscle;
    });
  },
),

    const SizedBox(width: 8),
ChoiceChip(
  label: const Text("Grupo"),
  selected: viewMode == AuditViewMode.anatomical,
  onSelected: (_) {
    setState(() {
      viewMode = AuditViewMode.anatomical;
      selectedAnatomicalGroups = {anatomicalGroups.keys.first};
    });
  },
),
    const SizedBox(width: 8),
ChoiceChip(
  label: const Text("Funcional"),
  selected: viewMode == AuditViewMode.functional,
  onSelected: (_) {
    setState(() {
      viewMode = AuditViewMode.functional;
      selectedFunctionalGroups = {functionalGroups.keys.first};
    });
  },
),
  ],
),


            /// RANGO
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();

                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now,
                      initialDateRange:
                          chartRange ??
                          DateTimeRange(
                            start: now.subtract(const Duration(days: 30)),
                            end: now,
                          ),
                    );

                    if (range != null) {
                      setState(() => chartRange = range);
                    }
                  },
                  icon: const Icon(Icons.date_range),
                  label: const Text("Rango"),
                ),
                const Spacer(),
              ],
            ),

            const SizedBox(height: 16),

            Expanded(
  child: _auditFatigueChart(widget.steps),
),

            const SizedBox(height: 16),

            _buildSelector(),

          ],
        ),
      ),
    );
  }

  Widget _muscleSelector() {
    return Wrap(
      spacing: 6,
      children: Muscle.values.map((m) {
        final selected = pendingChartMuscles.contains(m);

        return FilterChip(
          label: Text(m.label, style: const TextStyle(fontSize: 11)),
          selected: selected,
          onSelected: (v) {
            setState(() {
              v
                  ? pendingChartMuscles.add(m)
                  : pendingChartMuscles.remove(m);

              chartMuscles = {...pendingChartMuscles};
            });
          },
        );
      }).toList(),
    );
  }
}
