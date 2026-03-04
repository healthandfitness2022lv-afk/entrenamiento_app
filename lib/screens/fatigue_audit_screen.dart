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




List<FatigueRecalculationStep> _sortSteps(List<FatigueRecalculationStep> steps) {
  final sorted = [...steps]..sort((a, b) => a.workoutDate.compareTo(b.workoutDate));
  return sorted;
}

List<FlSpot> _buildGlobalTimeline(
  List<FatigueRecalculationStep> steps, {
  required DateTime startTime,
  required DateTime endTime,
  int topK = 6,
}) {
  if (steps.isEmpty) return [];

  final sorted = _sortSteps(steps);

  final globalStart = sorted.first.workoutDate;

  // Estado por músculo: fatiga + lastUpdate
  final Map<Muscle, double> fatigue = {
    for (final m in Muscle.values) m: 0.0,
  };
  final Map<Muscle, DateTime> lastUpdate = {
    for (final m in Muscle.values) m: globalStart,
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
          muscle: m,
          fatigue: fatigue[m] ?? 0,
          lastUpdate: lastUpdate[m] ?? globalStart,
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

  applyStepsUpTo(startTime.subtract(const Duration(microseconds: 1)));

  DateTime cursor = DateTime(startTime.year, startTime.month, startTime.day);

  while (!cursor.isAfter(endTime)) {
    applyStepsUpTo(cursor);

    if (!cursor.isBefore(startTime)) {
      final values = <double>[];
      for (final m in Muscle.values) {
        final v = FatigueService.recoverToNow(
          muscle: m,
          fatigue: fatigue[m] ?? 0,
          lastUpdate: lastUpdate[m] ?? globalStart,
          now: cursor,
        );

        if (v >= 5) values.add(v);
      }

      double global = 0;
      if (values.isNotEmpty) {
        values.sort((a, b) => b.compareTo(a));
        final top = values.take(topK).toList();
        global = top.reduce((a, b) => a + b) / top.length;
      }

      final x = cursor.difference(startTime).inMinutes / 60.0 / 24.0;
      spots.add(FlSpot(x, global));
    }

    cursor = cursor.add(const Duration(days: 1));
  }

  // 🔥 Recuperación final exacta hasta endTime
applyStepsUpTo(endTime);

final values = <double>[];

for (final m in Muscle.values) {
  final v = FatigueService.recoverToNow(
    muscle: m,
    fatigue: fatigue[m] ?? 0,
    lastUpdate: lastUpdate[m] ?? globalStart,
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
    endTime.difference(startTime).inMinutes / 60.0 / 24.0;

spots.add(FlSpot(finalX, global));

  return spots;
}






List<FlSpot> _buildMuscleTimeline(
  Muscle muscle,
  List<FatigueRecalculationStep> steps, {
  required DateTime startTime,
  required DateTime endTime,
}) {
  if (steps.isEmpty) return [];

  final sorted = [...steps]
    ..sort((a, b) => a.workoutDate.compareTo(b.workoutDate));

  final globalStart = sorted.first.workoutDate;

  double fatigue = 0;
  DateTime lastUpdate = globalStart;
  int i = 0;

  final spots = <FlSpot>[]; 

  void applyStepsUpTo(DateTime t) {
    while (i < sorted.length && !sorted[i].workoutDate.isAfter(t)) {
      final step = sorted[i];
      final wTime = step.workoutDate;

      fatigue = FatigueService.recoverToNow(
        muscle: muscle,
        fatigue: fatigue,
        lastUpdate: lastUpdate,
        now: wTime,
      );

      if (!wTime.isBefore(startTime)) {
        final xBefore = wTime.difference(startTime).inMinutes / 60 / 24;
        spots.add(FlSpot(xBefore, fatigue));
      }

      final load = step.loadApplied[muscle] ?? 0;
      fatigue += load;

      lastUpdate = wTime;

      if (!wTime.isBefore(startTime)) {
        final xAfter = wTime.difference(startTime).inMinutes / 60 / 24;
        spots.add(FlSpot(xAfter + 0.0001, fatigue));
      }

      i++;
    }
  }

  applyStepsUpTo(startTime.subtract(const Duration(microseconds: 1)));

  DateTime cursor = DateTime(startTime.year, startTime.month, startTime.day);
  final endDay = DateTime(endTime.year, endTime.month, endTime.day, 23, 59, 59, 999);

  while (!cursor.isAfter(endDay)) {
    applyStepsUpTo(cursor);

    if (!cursor.isBefore(startTime)) {
      final value = FatigueService.recoverToNow(
        muscle: muscle,
        fatigue: fatigue,
        lastUpdate: lastUpdate,
        now: cursor,
      );

      final x = cursor.difference(startTime).inMinutes / 60 / 24;
      spots.add(FlSpot(x, value));
    }

    cursor = cursor.add(const Duration(days: 1));
  }

  // punto final exacto
  applyStepsUpTo(endTime);

  final finalValue = FatigueService.recoverToNow(
    muscle: muscle,
    fatigue: fatigue,
    lastUpdate: lastUpdate,
    now: endTime,
  );

  final finalX = endTime.difference(startTime).inMinutes / 60 / 24;

  spots.add(FlSpot(finalX, finalValue));

  return spots;
}

List<FlSpot> _buildGroupTimeline(
  List<Muscle> muscles,
  List<FatigueRecalculationStep> steps, {
  required DateTime startTime,
  required DateTime endTime,
}) {
  final Map<double, List<double>> aggregated = {};

  for (final m in muscles) {
    final timeline = _buildMuscleTimeline(
      m,
      steps,
      startTime: startTime,
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
  if (steps.isEmpty) {
    return const Center(
      child: Text(
        "No hay datos",
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  final now = DateTime.now();
  final startDateRaw = chartRange?.start ?? now.subtract(const Duration(days: 30));
  final startDate = DateTime(startDateRaw.year, startDateRaw.month, startDateRaw.day);
  
  final endDateRaw = chartRange?.end ?? now;
  final timelineEnd = DateTime(endDateRaw.year, endDateRaw.month, endDateRaw.day, 23, 59, 59, 999);

  final series = <String, List<FlSpot>>{};

  if (viewMode == AuditViewMode.muscle) {
    for (final m in chartMuscles) {
      series[m.label] = _buildMuscleTimeline(
        m,
        steps,
        startTime: startDate,
        endTime: timelineEnd,
      );
    }
  } else if (viewMode == AuditViewMode.anatomical) {
    for (final group in selectedAnatomicalGroups) {
      series[group.label] = _buildGroupTimeline(
        anatomicalGroups[group]!,
        steps,
        startTime: startDate,
        endTime: timelineEnd,
      );
    }
  } else if (viewMode == AuditViewMode.functional) {
    for (final group in selectedFunctionalGroups) {
      series[group.label] = _buildGroupTimeline(
        functionalGroups[group]!,
        steps,
        startTime: startDate,
        endTime: timelineEnd,
      );
    }
  }

  final globalSeries = <FlSpot>[];

  if (showGlobalFatigue) {
    globalSeries.addAll(
      _buildGlobalTimeline(
        steps,
        startTime: startDate,
        endTime: timelineEnd,
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

  final totalDays = timelineEnd.difference(startDate).inDays + 1;

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

        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFF2A2A2A), strokeWidth: 1),
          getDrawingVerticalLine: (value) => const FlLine(color: Color(0xFF2A2A2A), strokeWidth: 1),
        ),
        backgroundColor: const Color(0xFF1B1B1B),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [
            HorizontalRangeAnnotation(
              y1: 85,
              y2: maxYValue + 15,
              color: Colors.redAccent.withOpacity(0.15),
            ),
          ],
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 85,
              color: Colors.redAccent.withOpacity(0.5),
              strokeWidth: 1,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 5, bottom: 2),
                style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                labelResolver: (_) => 'AL LÍMITE (85%+)',
              ),
            ),
          ],
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    interval: 20,
    reservedSize: 40,
    getTitlesWidget: (value, _) {
      return Text(
        value.toInt().toString(),
        style: const TextStyle(fontSize: 11, color: Colors.white70),
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
          style: const TextStyle(fontSize: 11, color: Colors.white70),
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
              barWidth: 3,
              color: heatmapColor(40 + index * 5),
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, barData) {
                  final i = barData.spots.indexOf(spot);
                  if (i == 0) return false;
                  final prev = barData.spots[i - 1];
                  // Si el salto vertical es repentino y sube, es un día de entreno!
                  return (spot.x - prev.x).abs() < 0.001 && spot.y > prev.y + 0.5;
                },
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: const Color(0xFF1B1B1B),
                    strokeWidth: 2,
                    strokeColor: barData.color ?? Colors.white,
                  );
                },
              ),
            );
          }),
          if (showGlobalFatigue && globalSeries.isNotEmpty)
            LineChartBarData(
              spots: globalSeries,
              isCurved: false,
              barWidth: 4,
              color: const Color(0xFF39FF14), // Color de acento neón de la app
              shadow: const Shadow(color: Color(0xFF39FF14), blurRadius: 4),
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


  Widget _buildQuickRangeBtn(String label, int days) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
      backgroundColor: const Color(0xFF222222),
      side: BorderSide.none,
      onPressed: () {
        final now = DateTime.now();
        setState(() {
          chartRange = DateTimeRange(
            start: now.subtract(Duration(days: days)),
            end: now,
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Evolución de fatiga", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B1B1B),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          Switch(
            value: showGlobalFatigue,
            activeColor: const Color(0xFF39FF14),
            onChanged: (v) {
              setState(() {
                showGlobalFatigue = v;
              });
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: Text("Promedio", style: TextStyle(color: Colors.white70))),
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF333333)),
                      backgroundColor: const Color(0xFF1B1B1B),
                    ),
                    onPressed: () async {
                      final now = DateTime.now();
                      final range = await showDateRangePicker(
                        context: context,
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFF39FF14),
                                onPrimary: Colors.black,
                                surface: Color(0xFF1B1B1B),
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                        firstDate: now.subtract(const Duration(days: 365)),
                        lastDate: now,
                        initialDateRange: chartRange ?? DateTimeRange(
                          start: now.subtract(const Duration(days: 30)),
                          end: now,
                        ),
                      );

                      if (range != null) {
                        setState(() => chartRange = range);
                      }
                    },
                    icon: const Icon(Icons.date_range, size: 16),
                    label: const Text("Rango", style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  _buildQuickRangeBtn("7 Días", 6),
                  const SizedBox(width: 8),
                  _buildQuickRangeBtn("1 Mes", 30),
                  const SizedBox(width: 8),
                  _buildQuickRangeBtn("3 Meses", 90),
                ],
              ),
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
