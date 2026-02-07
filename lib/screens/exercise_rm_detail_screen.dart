import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../services/workout_metrics_service.dart';
import '../services/workout_rm_service.dart';
import '../utils/rpe_factor.dart';


enum ExerciseChartView {
  volume,
  rm,
}



class ExerciseSessionStats {
  final DateTime date;
  final int totalSeries;
  final int totalReps;
  final double totalLoad;
  final double estimatedRM;

  ExerciseSessionStats({
    required this.date,
    required this.totalSeries,
    required this.totalReps,
    required this.totalLoad,
    required this.estimatedRM,
  });
}


class ExerciseRMDetailScreen extends StatefulWidget {
  final String exercise;
  final List<QueryDocumentSnapshot> docs;

  const ExerciseRMDetailScreen({
    super.key,
    required this.exercise,
    required this.docs,
  });

  @override
  State<ExerciseRMDetailScreen> createState() =>
      _ExerciseRMDetailScreenState();
}

class _ExerciseRMDetailScreenState
    extends State<ExerciseRMDetailScreen> {
      ExerciseChartView _chartView = ExerciseChartView.volume;




  List<ExerciseSessionStats> _buildExerciseProgressHistory() {
  final List<ExerciseSessionStats> list = [];

  


  String norm(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  for (final d in widget.docs) {
    final DateTime date = (d['date'] as Timestamp).toDate();
    final performed = WorkoutMetricsService.performedFromDoc(d);

    int series = 0;
    int reps = 0;
    double load = 0;
    double bestWeight = 0;
    int bestReps = 0;

    final sets =
        WorkoutRMService.extractAllValidRMSetCandidates(performed);

    for (final s in sets) {
      final raw = s['exercise']?.toString();
      if (raw == null || norm(raw) != norm(widget.exercise)) continue;

      final int r = s['reps'] ?? 0;
final double w = (s['weight'] as num?)?.toDouble() ?? 0;
final bool perSide = s['perSide'] == true;
final mult = perSide ? 2 : 1;

final bool isBodyweight = w <= 0;

series += 1;
reps += r * mult;

// 🔥 volumen inteligente
if (isBodyweight) {
  load += r * mult; // reps como métrica
} else {
  load += r * w * mult;
}

// 🔥 progreso principal
if (isBodyweight) {
  if (r > bestReps) bestReps = r;
} else {
  if (w > bestWeight || (w == bestWeight && r > bestReps)) {
    bestWeight = w;
    bestReps = r;
  }
}

    }

    if (series > 0) {
      list.add(
        ExerciseSessionStats(
          date: date,
          totalSeries: series,
          totalReps: reps,
          totalLoad: load,
          estimatedRM: bestWeight > 0
    ? bestWeight * (1 + bestReps / 30) // fuerza
    : bestReps.toDouble(),             // calistenia

        ),
      );
    }
  }

  list.sort((a, b) => a.date.compareTo(b.date)); // 🔥 clave

  return list;
}

Widget _exerciseOverviewCard({
  required Map<int, double> realRM,
  required ExerciseSessionStats first,
  required ExerciseSessionStats last,
}) {
  

  final rmDiff = last.estimatedRM - first.estimatedRM;
  
final double rmPct =
    first.estimatedRM > 0 ? (rmDiff / first.estimatedRM) * 100 : 0.0;

  final double rm1 = realRM.containsKey(1)
      ? realRM[1]!
      : last.estimatedRM;

  Color c(double v) =>
      v > 0 ? Colors.green : v < 0 ? Colors.red : Colors.grey;

  Widget rmRow(int reps) {
    final value = _resolveRM(
      reps: reps,
      realRM: realRM,
      rm1: rm1,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("${reps}RM"),
        Text(
          "${value.toStringAsFixed(1)} kg",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  return Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Resumen del ejercicio",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          // ===== RM CLAVE =====
          rmRow(1),
          rmRow(3),
          rmRow(5),

          const Divider(height: 24),

          // ===== PROGRESO =====
          _metric(
  last.estimatedRM <= 30 ? "Reps máximas" : "RM estimada",
  first.estimatedRM,
  last.estimatedRM,
  rmPct,
  c(rmDiff),
),

          _metric(
            "RM estimada",
            first.estimatedRM,
            last.estimatedRM,
            rmPct,
            c(rmDiff),
          ),

          const SizedBox(height: 6),

          _simple("Series", first.totalSeries, last.totalSeries),
          _simple("Reps totales", first.totalReps, last.totalReps),
        ],
      ),
    ),
  );
}


Widget _sessionProgressChart(List<ExerciseSessionStats> progress) {
  if (progress.length < 2) return const SizedBox();

  final spots = List.generate(progress.length, (i) {
    return FlSpot(i.toDouble(), progress[i].totalLoad);
  });

  final maxY = spots.map((e) => e.y).reduce(max);

  return SizedBox(
    height: 260,
    child: LineChart(
      LineChartData(
        minX: 0,
        maxX: (progress.length - 1).toDouble(),
        minY: 0,
        maxY: maxY * 1.15,

        gridData: FlGridData(show: true),

        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),

          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= progress.length) return const SizedBox();
                final d = progress[i].date;
                return Text(
                  "${d.day}/${d.month}",
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),

          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: maxY / 4,
              getTitlesWidget: (v, _) =>
                  Text(v.toStringAsFixed(0)),
            ),
          ),
        ),

        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            dotData: FlDotData(show: true),
            color: Colors.greenAccent,
          ),
        ],
      ),
    ),
  );
}



Widget _metric(
  String label,
  double from,
  double to,
  double pct,
  Color color,
) {
  return Row(
    children: [
      Expanded(child: Text(label)),
      Text(from.toStringAsFixed(1)),
      const Icon(Icons.arrow_forward, size: 14),
      Text(to.toStringAsFixed(1)),
      const SizedBox(width: 8),
      Text(
        pct == 0 ? "—" : "${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%",
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

Widget _simple(String label, int from, int to) {
  final diff = to - from;
  return Row(
    children: [
      Expanded(child: Text(label)),
      Text("$from → $to"),
      const SizedBox(width: 8),
      Text(diff == 0 ? "—" : "${diff > 0 ? '+' : ''}$diff"),
    ],
  );
}





  // ======================================================
  // 🏋️ RM REALES (1–15)
  // ======================================================
  Map<int, double> _buildRealRM() {
  final Map<int, double> rm = {};

  String norm(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  for (final d in widget.docs) {
    final performed =
        WorkoutMetricsService.performedFromDoc(d);

    final sets =
        WorkoutRMService.extractAllValidRMSetCandidates(performed);

    for (final s in sets) {
      final rawExercise = s['exercise']?.toString();
      if (rawExercise == null) continue;

      // 🔑 mismo match que el gráfico
      if (norm(rawExercise) != norm(widget.exercise)) continue;

      final int reps = (s['reps'] as num).toInt();
      final double weight = (s['weight'] as num).toDouble();
      final double rpeRaw = (s['rpe'] as num?)?.toDouble() ?? 0.0;

      // 🔥 fallback RPE para circuitos
      final double effectiveRpe = rpeRaw > 0 ? rpeRaw : 7.5;

      if (reps <= 0 || reps > 15 || weight <= 0) continue;

      // 📐 RM estimado (Epley + RPE)
      WorkoutRMService.estimate1RM(
        weight: weight,
        reps: reps,
        rpe: effectiveRpe,
        rpeFactor: rpeFactor,
      );

      // 🔒 guardamos el mayor peso REAL observado para ese RM
      // (no el 1RM estimado)
      if (!rm.containsKey(reps) || weight > rm[reps]!) {
        rm[reps] = weight;
      }
    }
  }

  return rm;
}


  // ======================================================
  // 📐 ESTIMACIONES
  // ======================================================
  double _estimate1RMFromRealRM(Map<int, double> realRM) {
    double best = 0;

    realRM.forEach((reps, weight) {
      final rm1 = weight * (1 + reps / 30);
      if (rm1 > best) best = rm1;
    });

    return best;
  }

  double _estimateRMFrom1RM({
    required double rm1,
    required int targetReps,
  }) {
    return rm1 / (1 + targetReps / 30);
  }

  // ======================================================
  // 📊 GRÁFICO
  // ======================================================
  Widget _rmRepsWeightChartWithEstimate(Map<int, double> realRM) {
  if (realRM.isEmpty) {
    return const Text(
      "No hay datos suficientes",
      style: TextStyle(color: Colors.grey),
    );
  }

  // 🔵 REAL
    final realValues = <double>[];

  final realSpots = realRM.entries
    .map((e) => FlSpot(e.key.toDouble(), e.value))
    .toList()
  ..sort((a, b) => a.x.compareTo(b.x)); // 👈 CLAVE


  // 🟠 ESTIMADO
  final double estimated1RM = _estimate1RMFromRealRM(realRM);

  final estimatedSpots = <FlSpot>[];
  final estimatedValues = <double>[];

  for (int reps = 1; reps <= 15; reps++) {
    final est = estimated1RM / (1 + reps / 30);
    estimatedSpots.add(FlSpot(reps.toDouble(), est));
    estimatedValues.add(est);
  }

  final allValues = [...realValues, ...estimatedValues];
  final maxObserved = allValues.reduce((a, b) => a > b ? a : b);

  return SizedBox(
    height: 240,
    child: LineChart(
      LineChartData(
        minY: 0,
        maxY: maxObserved * 1.10, // 🔥 +10%
        minX: 1,
        maxX: 15,

        gridData: FlGridData(show: true),

        titlesData: FlTitlesData(
          // ❌ arriba
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),

          // ❌ derecha
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),

          // 🔽 abajo (1–15)
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 1 || i > 15) return const SizedBox();
                return Text(
                  "$i",
                  style: const TextStyle(fontSize: 11),
                );
              },
            ),
          ),

          // 🔼 izquierda (peso)
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxObserved / 4,
              getTitlesWidget: (v, _) {
                return Text(
                  v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),

        lineBarsData: [
          // 🔵 REAL
          LineChartBarData(
            spots: realSpots,
            isCurved: false,
            barWidth: 3,
            dotData: FlDotData(show: true),
            color: Colors.greenAccent,
          ),

          // 🟠 ESTIMADO
          LineChartBarData(
            spots: estimatedSpots,
            isCurved: true,
            barWidth: 2,
            dotData: FlDotData(show: false),
            dashArray: [6, 4],
            color: Colors.orangeAccent,
          ),
        ],
      ),
    ),
  );
}

Map<DateTime, List<Map<String, dynamic>>> _buildSessionSets() {
  final Map<DateTime, List<Map<String, dynamic>>> sessions = {};

  String norm(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  for (final d in widget.docs) {
    final DateTime date = (d['date'] as Timestamp).toDate();
    final performed = WorkoutMetricsService.performedFromDoc(d);

    final sets =
        WorkoutRMService.extractAllValidRMSetCandidates(performed);

    final matchingSets = sets.where((s) {
      final ex = s['exercise']?.toString();
      if (ex == null) return false;
      return norm(ex) == norm(widget.exercise);
    }).toList();

    if (matchingSets.isNotEmpty) {
      sessions[date] = matchingSets;
    }
  }

  return sessions;
}





  // ======================================================
  // 🧾 TABLA SESIONES
  // ======================================================
  Widget _sessionTableByDay(
  Map<DateTime, List<Map<String, dynamic>>> sessions,
  List<ExerciseSessionStats> progress,
) {
  final dates = sessions.keys.toList()
    ..sort((a, b) => b.compareTo(a)); // más reciente arriba

  ExerciseSessionStats? statsForDate(DateTime d) {
    return progress.firstWhere(
      (p) =>
          p.date.year == d.year &&
          p.date.month == d.month &&
          p.date.day == d.day,
    );
  }

  return Column(
    children: dates.map((date) {
      final sets = sessions[date]!;
      final stats = statsForDate(date);

      final avgRpe = _averageRPE(sets);

      return Card(
        child: ExpansionTile(
          title: Text(
            "${date.day}/${date.month}/${date.year}",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),

          // 🔥 RESUMEN DE SESIÓN
          subtitle: stats == null
              ? null
              : Text(
                  "Tonelaje: ${stats.totalLoad.toStringAsFixed(0)} kg · "
                  "RPE prom: ${avgRpe > 0 ? avgRpe.toStringAsFixed(1) : "—"}",
                  style: const TextStyle(fontSize: 12),
                ),

          children: sets.map((s) {
            final reps = s['reps'];
            final weight = s['weight'];
            final rpe = s['rpe'];

            return ListTile(
              dense: true,
              title: Text(
                "${reps ?? "—"} reps · ${weight ?? "—"} kg",
              ),
              subtitle: Text(
                "RPE ${rpe?.toStringAsFixed(1) ?? "—"}",
              ),
            );
          }).toList(),
        ),
      );
    }).toList(),
  );
}



  // ======================================================
  // 🧾 TABLA RM 1–15
  // ======================================================
  Widget _rmTable(Map<int, double> realRM) {
    return Column(
      children: List.generate(15, (i) {
        final reps = i + 1;
        final real = realRM[reps];

        return ListTile(
          dense: true,
          title: Text("$reps RM"),
          trailing: real != null
              ? Text(
                  "${real.toStringAsFixed(0)} kg",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                )
              : const Text(
                  "—",
                  style: TextStyle(color: Colors.grey),
                ),
        );
      }),
    );
  }

  double _resolveRM({
  required int reps,
  required Map<int, double> realRM,
  required double rm1,
}) {
  final estimated = _estimateRMFrom1RM(
    rm1: rm1,
    targetReps: reps,
  );

  if (realRM.containsKey(reps)) {
    return max(realRM[reps]!, estimated);
  }

  return estimated;
}



Widget _chartLegend() {
  Widget item(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  return Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      item(Colors.blueAccent, "Volumen"),
      item(Colors.purple, "Reps totales"),
    ],
  );
}

double _averageRPE(List<Map<String, dynamic>> sets) {
  double weighted = 0;
  int totalReps = 0;

  for (final s in sets) {
    final rpe = (s['rpe'] as num?)?.toDouble();
    final reps = (s['reps'] as num?)?.toInt() ?? 0;

    if (rpe == null || rpe <= 0 || reps <= 0) continue;

    weighted += rpe * reps;
    totalReps += reps;
  }

  if (totalReps == 0) return 0;
  return weighted / totalReps;
}


  // 👇 AQUÍ
  Widget _chartSelector() {
    Widget button(String label, ExerciseChartView view) {
      final selected = _chartView == view;

      return Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() {
              _chartView = view;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.greenAccent.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? Colors.greenAccent
                    : Colors.grey.shade600,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        button("Volumen", ExerciseChartView.volume),
        const SizedBox(width: 8),
        button("Progreso RM", ExerciseChartView.rm),
      ],
    );
  }

  // ... resto de métodos





  // ======================================================
  // 🖥 UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    final realRM = _buildRealRM();
    final sessionSets = _buildSessionSets();
                    final progress = _buildExerciseProgressHistory();



    return Scaffold(
      appBar: AppBar(title: Text(widget.exercise)),
      body: realRM.isEmpty
          ? const Center(
              child: Text(
                "No hay sets válidos para este ejercicio",
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [


if (progress.length >= 2) ...[
  _exerciseOverviewCard(
  realRM: realRM,
  first: progress.first,
  last: progress.last,
),

  const SizedBox(height: 20),
],

if (progress.length >= 2) ...[
  const Text(
  "Gráficos",
  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
),
const SizedBox(height: 8),

_chartSelector(),
const SizedBox(height: 12),

if (_chartView == ExerciseChartView.volume) ...[
  _chartLegend(),
  const SizedBox(height: 8),
  _sessionProgressChart(progress),
] else ...[
  _rmRepsWeightChartWithEstimate(realRM),
],

const SizedBox(height: 20),




                const SizedBox(height: 20),
                const Text(
  "Sesiones registradas",
  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
),
const SizedBox(height: 8),
_sessionTableByDay(sessionSets, progress),


                const SizedBox(height: 24),
                const Text(
                  "RM reales detectados",
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _rmTable(realRM),
              ],]
            ),
    );
  }
}