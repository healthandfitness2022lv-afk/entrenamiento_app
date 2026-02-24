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

List<FatigueRecalculationStep> _sortSteps(List<FatigueRecalculationStep> steps) {
  final sorted = [...steps]..sort((a, b) => a.workoutDate.compareTo(b.workoutDate));
  return sorted;
}

List<FlSpot> _buildGlobalTimeline(
  List<FatigueRecalculationStep> steps,
  DateTime endTime, {
  int topK = 6,
}) {
  if (steps.isEmpty) return [];

  final sorted = _sortSteps(steps);

  final start = sorted.first.workoutDate;
  final end = endTime;

  // Estado por músculo: fatiga + lastUpdate
  final Map<Muscle, double> fatigue = {
    for (final m in Muscle.values) m: 0.0,
  };
  final Map<Muscle, DateTime> lastUpdate = {
    for (final m in Muscle.values) m: start,
  };

  // índice de workouts (steps) que tienen update real
  int i = 0;

  // helper: aplica todos los steps con workoutDate <= t
  void applyStepsUpTo(DateTime t) {
    while (i < sorted.length && !sorted[i].workoutDate.isAfter(t)) {
      final step = sorted[i];
      final wTime = step.workoutDate;

      for (final m in Muscle.values) {
        // recuperar hasta la hora exacta del workout
        fatigue[m] = FatigueService.recoverToNow(
          fatigue: fatigue[m] ?? 0,
          lastUpdate: lastUpdate[m] ?? start,
          now: wTime,
        );
        lastUpdate[m] = wTime;

        // aplicar el "salto" del workout si hay dato
        // (fatigueAfter es el estado post-carga)
        final after = step.fatigueAfter[m];
        if (after != null) {
          fatigue[m] = after;
          lastUpdate[m] = wTime;
        }
      }

      i++;
    }
  }

  final spots = <FlSpot>[];

  DateTime cursor = start;
  while (!cursor.isAfter(end)) {
    applyStepsUpTo(cursor);

    // recuperar desde lastUpdate hasta cursor
    final values = <double>[];
    for (final m in Muscle.values) {
      final v = FatigueService.recoverToNow(
        fatigue: fatigue[m] ?? 0,
        lastUpdate: lastUpdate[m] ?? start,
        now: cursor,
      );

      // deja esta línea si quieres ignorar ruido
      // (si quieres que se comporte EXACTO como las otras sin umbral, quítala)
      if (v >= 5) values.add(v);
    }

    double global = 0;
    if (values.isNotEmpty) {
      values.sort((a, b) => b.compareTo(a));
      final top = values.take(topK).toList();
      global = top.reduce((a, b) => a + b) / top.length;
    }

    final x = cursor.difference(start).inMinutes / 60.0 / 24.0;
    spots.add(FlSpot(x, global));

    cursor = cursor.add(const Duration(days: 1));
  }

  // 🔥 Recuperación final exacta hasta endTime
applyStepsUpTo(endTime);

final values = <double>[];

for (final m in Muscle.values) {
  final v = FatigueService.recoverToNow(
    fatigue: fatigue[m] ?? 0,
    lastUpdate: lastUpdate[m] ?? start,
    now: endTime,
  );

  if (v >= 5) values.add(v);
}

double global = 0;

if (values.isNotEmpty) {
  values.sort((a, b) => b.compareTo(a));
  final top = values.take(topK).toList();
  global = top.reduce((a, b) => a + b) / top.length;
}

final finalX =
    endTime.difference(start).inMinutes / 60.0 / 24.0;

spots.add(FlSpot(finalX, global));

  return spots;
}






List<FlSpot> _buildMuscleTimeline(
  Muscle muscle,
  List<FatigueRecalculationStep> steps, {
  required DateTime endTime,
}) {
  if (steps.isEmpty) return [];

  final sorted = [...steps]
    ..sort((a, b) => a.workoutDate.compareTo(b.workoutDate));

  final start = sorted.first.workoutDate;

  double fatigue = 0;
  DateTime lastUpdate = start;
  int i = 0;

  final spots = <FlSpot>[]; // 🔥 MOVER AQUÍ ARRIBA

  void applyStepsUpTo(DateTime t) {
    while (i < sorted.length && !sorted[i].workoutDate.isAfter(t)) {
      final step = sorted[i];
      final wTime = step.workoutDate;

      // recuperar hasta workout
      fatigue = FatigueService.recoverToNow(
        fatigue: fatigue,
        lastUpdate: lastUpdate,
        now: wTime,
      );

      final xBefore =
          wTime.difference(start).inMinutes / 60 / 24;

      // 🔥 punto antes
      spots.add(FlSpot(xBefore, fatigue));

      // aplicar carga
      final load = step.loadApplied[muscle] ?? 0;
      fatigue += load;

      lastUpdate = wTime;

      // 🔥 punto después
      spots.add(FlSpot(xBefore + 0.0001, fatigue));

      i++;
    }
  }

  DateTime cursor =
      DateTime(start.year, start.month, start.day);

  final endDay =
      DateTime(endTime.year, endTime.month, endTime.day, 23, 59, 59, 999);

  while (!cursor.isAfter(endDay)) {
    applyStepsUpTo(cursor);

    final value = FatigueService.recoverToNow(
      fatigue: fatigue,
      lastUpdate: lastUpdate,
      now: cursor,
    );

    final x =
        cursor.difference(start).inMinutes / 60 / 24;

    spots.add(FlSpot(x, value));

    cursor = cursor.add(const Duration(days: 1));
  }

  // punto final exacto
  applyStepsUpTo(endTime);

  final finalValue = FatigueService.recoverToNow(
    fatigue: fatigue,
    lastUpdate: lastUpdate,
    now: endTime,
  );

  final finalX =
      endTime.difference(start).inMinutes / 60 / 24;

  spots.add(FlSpot(finalX, finalValue));

  return spots;
}

List<FlSpot> _buildGroupTimeline(
  List<Muscle> muscles,
  List<FatigueRecalculationStep> filtered,
  DateTime endTime,
) {
  final Map<double, List<double>> aggregated = {};

  for (final m in muscles) {
    final timeline = _buildMuscleTimeline(
      m,
      filtered,
      endTime: endTime,
    );

    for (final spot in timeline) {
      final x = (spot.x * 1000).round() / 1000;

      aggregated.putIfAbsent(x, () => []);
      aggregated[x]!.add(spot.y);
    }
  }

  final result = aggregated.entries.map((e) {
    final avg =
        e.value.reduce((a, b) => a + b) / e.value.length;
    return FlSpot(e.key, avg);
  }).toList();

  result.sort((a, b) => a.x.compareTo(b.x));

  return result;
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
final now = DateTime.now();

// si hay chartRange, usar su end; si no, usar now

// si el usuario eligió rango futuro (no debería), lo capamos a now
final timelineEnd = now;

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
    _buildMuscleTimeline(
      m,
      filtered,
      endTime: timelineEnd,
    );
  }
}

if (viewMode == AuditViewMode.anatomical) {
  for (final group in selectedAnatomicalGroups) {
    series[group.label] =
    _buildGroupTimeline(
      anatomicalGroups[group]!,
      filtered,
      timelineEnd,
    );
  }
}

if (viewMode == AuditViewMode.functional) {
  for (final group in selectedFunctionalGroups) {
    series[group.label] =
    _buildGroupTimeline(
      functionalGroups[group]!,
      filtered,
      timelineEnd,
    );
  }


}
final globalSeries = <FlSpot>[];

if (showGlobalFatigue) {
  globalSeries.addAll(
  _buildGlobalTimeline(
    filtered,
    timelineEnd,
    topK: 6,
  ),
);
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
