import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../models/muscle_catalog.dart';
import '../services/fatigue_performance_correlation_service.dart';
import '../services/workout_metrics_service.dart';
import '../services/workout_rm_service.dart';
import '../theme/app_theme.dart';

class ExerciseSessionStats {
  final DateTime date;
  final int totalSeries;
  final int totalReps;
  final double totalLoad;
  final double estimatedRM;
  final double bestWeight;
  final int bestReps;

  ExerciseSessionStats({
    required this.date,
    required this.totalSeries,
    required this.totalReps,
    required this.totalLoad,
    required this.estimatedRM,
    required this.bestWeight,
    required this.bestReps,
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
  State<ExerciseRMDetailScreen> createState() => _ExerciseRMDetailScreenState();
}

class _ExerciseRMDetailScreenState extends State<ExerciseRMDetailScreen> {
  int _selectedChartIndex = 0; // 0: Evolución 1RM, 2: Volumen, 3: Perfil RM

  late List<ExerciseSessionStats> _progress;
  late Map<int, double> _realRM;
  late Map<DateTime, List<Map<String, dynamic>>> _sessionSets;
  FatiguePerformanceCorrelationResult? _fatigueCorrelation;
  bool _loadingFatigueCorrelation = true;

  @override
  void initState() {
    super.initState();
    _calculateStats();
    _loadFatigueCorrelation();
  }

  void _calculateStats() {
    _progress = _buildExerciseProgressHistory();
    _realRM = _buildRealRM();
    _sessionSets = _buildSessionSets();
  }

  Future<void> _loadFatigueCorrelation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadingFatigueCorrelation = false);
      return;
    }

    final result = await FatiguePerformanceCorrelationService.analyzeExercise(
      uid: user.uid,
      exercise: widget.exercise,
      docs: widget.docs,
    );

    if (!mounted) return;

    setState(() {
      _fatigueCorrelation = result;
      _loadingFatigueCorrelation = false;
    });
  }

  String norm(String s) => WorkoutRMService.normalizeExerciseName(s);

  List<ExerciseSessionStats> _buildExerciseProgressHistory() {
    final List<ExerciseSessionStats> list = [];
    final targetNorm = norm(widget.exercise);

    for (final d in widget.docs) {
      final DateTime date = (d['date'] as Timestamp).toDate();
      final performed = WorkoutMetricsService.performedFromDoc(d);

      int series = 0;
      int reps = 0;
      double load = 0;
      double bestWeight = 0;
      int bestReps = 0;

      final sets = WorkoutRMService.extractAllValidRMSetCandidates(performed);

      for (final s in sets) {
        final raw = s['exercise']?.toString();
        if (raw == null || norm(raw) != targetNorm) continue;

        final int r = s['reps'] ?? 0;
        final double w = (s['weight'] as num?)?.toDouble() ?? 0;
        final bool perSide = s['perSide'] == true;
        final mult = perSide ? 2 : 1;

        final bool isBodyweight = w <= 0;

        series += 1;
        reps += r * mult;

        if (isBodyweight) {
          load += r * mult;
        } else {
          load += r * w * mult;
        }

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
            bestWeight: bestWeight,
            bestReps: bestReps,
            estimatedRM:
                bestWeight > 0
                    ? WorkoutRMService.estimate1RM(
                      weight: bestWeight,
                      reps: bestReps,
                    )
                    : bestReps.toDouble(), // Bodyweight mode
          ),
        );
      }
    }

    list.sort((a, b) => a.date.compareTo(b.date));
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

    final double rm1 = realRM.containsKey(1) ? realRM[1]! : last.estimatedRM;

    Color c(double v) =>
        v > 0
            ? Colors.green
            : v < 0
            ? Colors.red
            : Colors.grey;

    Widget rmRow(int reps) {
      final value = _resolveRM(reps: reps, realRM: realRM, rm1: rm1);

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("${reps}RM"),
          Text(
            "${formatSmart(value)} kg",
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

            const SizedBox(height: 6),

            _simple("Series", first.totalSeries, last.totalSeries),
            _simple("Reps totales", first.totalReps, last.totalReps),
          ],
        ),
      ),
    );
  }

  String _correlationLabel(double value) {
    final abs = value.abs();
    if (abs >= 0.7) return value < 0 ? "Muy fuerte inversa" : "Muy fuerte";
    if (abs >= 0.45) return value < 0 ? "Moderada inversa" : "Moderada";
    if (abs >= 0.2) return value < 0 ? "Leve inversa" : "Leve";
    return "Débil";
  }

  Color _correlationColor(double value) {
    if (value <= -0.45) return Colors.green;
    if (value >= 0.45) return Colors.redAccent;
    return Colors.orangeAccent;
  }

  Widget _fatigueCorrelationCard(FatiguePerformanceCorrelationResult? result) {
    if (_loadingFatigueCorrelation) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text("Analizando correlación fatiga-rendimiento"),
            ],
          ),
        ),
      );
    }

    if (result == null || result.points.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "No hay datos suficientes de fatiga auditada para este ejercicio.",
          ),
        ),
      );
    }

    final muscles = result.primaryMuscles.map((m) => m.label).join(", ");
    final rmColor = _correlationColor(result.rmCorrelation);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Fatiga vs rendimiento",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Músculos base: $muscles",
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: rmColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Correlación con RM: ${result.rmCorrelation.toStringAsFixed(2)}",
                      style: TextStyle(
                        color: rmColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _correlationLabel(result.rmCorrelation),
                    style: TextStyle(
                      color: rmColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              result.rmCorrelation <= -0.2
                  ? "Tu rendimiento tiende a caer cuando llegas con más fatiga previa."
                  : result.rmCorrelation >= 0.2
                  ? "La fatiga no parece explicar una caída de rendimiento; revisa volumen, técnica o contexto."
                  : "Por ahora la relación entre fatiga previa y rendimiento es débil.",
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _correlationChip("RM", result.rmCorrelation),
                _correlationChip("Volumen", result.volumeCorrelation),
                _correlationChip("Eficiencia", result.efficiencyCorrelation),
                Chip(label: Text("${result.points.length} sesiones")),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _correlationChip(String label, double value) {
    final color = _correlationColor(value);
    return Chip(
      backgroundColor: color.withOpacity(0.12),
      label: Text(
        "$label ${value.toStringAsFixed(2)}",
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _correlationEvidenceList(FatiguePerformanceCorrelationResult? result) {
    if (_loadingFatigueCorrelation || result == null || result.points.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Series usadas en la correlación",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...result.points.reversed.map((point) {
              return ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  "${point.date.day}/${point.date.month}/${point.date.year}",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  "Fatiga ${point.preSessionFatigue.toStringAsFixed(1)}% • RM ${point.estimatedRM.toStringAsFixed(1)}",
                ),
                children:
                    point.sets.map((set) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          "${set.reps} x ${formatSmart(set.weight)} kg",
                        ),
                        subtitle: Text(
                          "RPE ${set.rpe > 0 ? set.rpe.toStringAsFixed(1) : "-"} • RM ${set.estimatedRM.toStringAsFixed(1)}",
                        ),
                      );
                    }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _fatigueCorrelationChart(FatiguePerformanceCorrelationResult? result) {
    if (_loadingFatigueCorrelation) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (result == null || !result.hasEnoughData) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            "Se necesitan al menos 3 sesiones con fatiga auditada.",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final points = result.points;
    final spots = List.generate(points.length, (i) {
      return FlSpot(points[i].preSessionFatigue, points[i].estimatedRM);
    });

    final minX = points.map((p) => p.preSessionFatigue).reduce(min);
    final maxX = points.map((p) => p.preSessionFatigue).reduce(max);
    final minY = points.map((p) => p.estimatedRM).reduce(min);
    final maxY = points.map((p) => p.estimatedRM).reduce(max);

    return SizedBox(
      height: 320,
      child: ScatterChart(
        ScatterChartData(
          minX: (minX - 5).clamp(0, 100).toDouble(),
          maxX: (maxX + 5).clamp(0, 100).toDouble(),
          minY: minY * 0.95,
          maxY: maxY * 1.05,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine:
                (value) => FlLine(color: Colors.grey.withOpacity(0.15)),
            getDrawingVerticalLine:
                (value) => FlLine(color: Colors.grey.withOpacity(0.15)),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text("Fatiga previa (%)"),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget:
                    (value, _) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text("RM estimado"),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget:
                    (value, _) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
              ),
            ),
          ),
          scatterTouchData: ScatterTouchData(
            enabled: true,
            touchTooltipData: ScatterTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItems: (touchedSpot) {
                final data = points.firstWhere(
                  (point) =>
                      (point.preSessionFatigue - touchedSpot.x).abs() < 0.001 &&
                      (point.estimatedRM - touchedSpot.y).abs() < 0.001,
                  orElse: () => points.first,
                );
                return ScatterTooltipItem(
                  "${data.date.day}/${data.date.month}/${data.date.year}\n"
                  "Fatiga: ${data.preSessionFatigue.toStringAsFixed(1)}%\n"
                  "RM: ${data.estimatedRM.toStringAsFixed(1)} kg\n"
                  "RPE: ${data.avgRpe > 0 ? data.avgRpe.toStringAsFixed(1) : "—"}",
                  textStyle: const TextStyle(color: Colors.white),
                );
              },
            ),
          ),
          scatterSpots: List.generate(spots.length, (i) {
            return ScatterSpot(
              spots[i].x,
              spots[i].y,
              dotPainter: FlDotCirclePainter(
                radius: 6,
                color: _correlationColor(
                  result.rmCorrelation,
                ).withOpacity(0.85),
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _sessionProgressChart(List<ExerciseSessionStats> progress) {
    if (progress.length < 2) return const SizedBox();

    final spots = List.generate(progress.length, (i) {
      return FlSpot(i.toDouble(), progress[i].totalLoad);
    });

    return Container(
      height: 300,
      padding: const EdgeInsets.only(right: 16, top: 16),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor:
                  (touchedSpots) => Colors.blueGrey.withOpacity(0.8),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((s) {
                  return LineTooltipItem(
                    "${s.y.toStringAsFixed(0)} kg",
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (value) =>
                    FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= progress.length) return const SizedBox();
                  final d = progress[i].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "${d.day}/${d.month}",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget:
                    (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 4,
              isStrokeCapRound: true,
              color: AppColors.info,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.info.withOpacity(0.3),
                    AppColors.info.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rmEvolutionChart(List<ExerciseSessionStats> progress) {
    if (progress.length < 2) return const SizedBox();

    final spots = List.generate(progress.length, (i) {
      return FlSpot(i.toDouble(), progress[i].estimatedRM);
    });

    return Container(
      height: 300,
      padding: const EdgeInsets.only(right: 16, top: 16),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor:
                  (touchedSpots) => Colors.deepPurple.withOpacity(0.8),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((s) {
                  return LineTooltipItem(
                    "1RM: ${s.y.toStringAsFixed(1)} kg",
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (v) => FlLine(color: Colors.grey.withOpacity(0.1)),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= progress.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "${progress[i].date.day}/${progress[i].date.month}",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget:
                    (v, _) => Text(
                      v.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 4,
              color: Colors.deepPurpleAccent,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurpleAccent.withOpacity(0.3),
                    Colors.deepPurpleAccent.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: const FlDotData(show: true),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Text(
            from.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            to.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              pct == 0
                  ? "—"
                  : "${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%",
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _simple(String label, int from, int to) {
    final diff = to - from;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Text(
            "$from → $to",
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 12),
          if (diff != 0)
            Text(
              "${diff > 0 ? '+' : ''}$diff",
              style: TextStyle(
                color: diff > 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  // ======================================================
  // 🏋️ RM REALES (1–15)
  // ======================================================
  Map<int, double> _buildRealRM() {
    final Map<int, double> rm = {};
    final targetNorm = norm(widget.exercise);

    for (final d in widget.docs) {
      final performed = WorkoutMetricsService.performedFromDoc(d);
      final sets = WorkoutRMService.extractAllValidRMSetCandidates(performed);

      for (final s in sets) {
        final rawExercise = s['exercise']?.toString();
        if (rawExercise == null || norm(rawExercise) != targetNorm) continue;

        final int reps = (s['reps'] as num).toInt();
        final double weight = (s['weight'] as num).toDouble();

        if (reps <= 0 || reps > 15 || weight <= 0) continue;

        for (int r = 1; r <= reps; r++) {
          if (!rm.containsKey(r) || weight > rm[r]!) {
            rm[r] = weight;
          }
        }
      }
    }
    return rm;
  }

  String formatSmart(double value) {
    final rounded = double.parse(value.toStringAsFixed(1));

    if (rounded % 1 == 0) {
      return rounded.toInt().toString();
    }

    return rounded.toString();
  }

  // ======================================================
  // 📐 ESTIMACIONES
  // ======================================================
  double _estimate1RMFromRealRM(Map<int, double> realRM) {
    double best = 0;

    realRM.forEach((reps, weight) {
      final rm1 = WorkoutRMService.estimate1RM(weight: weight, reps: reps);
      if (rm1 > best) best = rm1;
    });

    return best;
  }

  // ======================================================
  // 📊 GRÁFICO
  // ======================================================
  Widget _rmRepsWeightChartWithEstimate(Map<int, double> realRM) {
    if (realRM.isEmpty)
      return const Center(
        child: Text(
          "No hay datos suficientes",
          style: TextStyle(color: Colors.grey),
        ),
      );

    final realSpots =
        realRM.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList()
          ..sort((a, b) => a.x.compareTo(b.x));

    final double estimated1RM = _estimate1RMFromRealRM(realRM);
    final estimatedSpots = List.generate(15, (i) {
      final reps = i + 1;
      return FlSpot(
        reps.toDouble(),
        WorkoutRMService.estimateWeightForReps(
          oneRepMax: estimated1RM,
          targetReps: reps,
        ),
      );
    });

    return Container(
      height: 300,
      padding: const EdgeInsets.only(right: 16, top: 16),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor:
                  (touchedSpots) => Colors.blueGrey.withOpacity(0.9),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((s) {
                  final isReal = s.barIndex == 0;
                  return LineTooltipItem(
                    "${isReal ? 'Real' : 'Estimado'}: ${s.y.toStringAsFixed(1)} kg",
                    TextStyle(
                      color: isReal ? Colors.greenAccent : Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (v) => FlLine(color: Colors.grey.withOpacity(0.1)),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 2,
                getTitlesWidget:
                    (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        "${v.toInt()}RM",
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget:
                    (v, _) => Text(
                      formatSmart(v),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: realSpots,
              isCurved: false,
              barWidth: 4,
              color: Colors.greenAccent,
              dotData: const FlDotData(show: true),
            ),
            LineChartBarData(
              spots: estimatedSpots,
              isCurved: true,
              barWidth: 2,
              dashArray: [6, 4],
              color: Colors.orangeAccent.withOpacity(0.6),
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Map<DateTime, List<Map<String, dynamic>>> _buildSessionSets() {
    final Map<DateTime, List<Map<String, dynamic>>> sessions = {};
    final targetNorm = norm(widget.exercise);

    for (final d in widget.docs) {
      final DateTime date = (d['date'] as Timestamp).toDate();
      final performed = WorkoutMetricsService.performedFromDoc(d);
      final sets = WorkoutRMService.extractAllValidRMSetCandidates(performed);

      final matchingSets =
          sets.where((s) {
            final ex = s['exercise']?.toString();
            if (ex == null) return false;
            return norm(ex) == targetNorm;
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
    final dates =
        sessions.keys.toList()
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
      children:
          dates.map((date) {
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
                subtitle:
                    stats == null
                        ? null
                        : Text(
                          "Tonelaje: ${stats.totalLoad.toStringAsFixed(0)} kg · "
                          "RPE prom: ${avgRpe > 0 ? avgRpe.toStringAsFixed(1) : "—"}",
                          style: const TextStyle(fontSize: 12),
                        ),

                children:
                    sets.map((s) {
                      final reps = s['reps'];
                      final weight = s['weight'];
                      final rpe = s['rpe'];

                      return ListTile(
                        dense: true,
                        title: Text(
                          "${reps ?? "—"} reps · ${weight ?? "—"} kg",
                        ),
                        subtitle: Text("RPE ${rpe?.toStringAsFixed(1) ?? "—"}"),
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
          trailing:
              real != null
                  ? Text(
                    "${formatSmart(real)} kg",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  )
                  : const Text("—", style: TextStyle(color: Colors.grey)),
        );
      }),
    );
  }

  double _resolveRM({
    required int reps,
    required Map<int, double> realRM,
    required double rm1,
  }) {
    final estimated = WorkoutRMService.estimateWeightForReps(
      oneRepMax: rm1,
      targetReps: reps,
    );

    if (realRM.containsKey(reps)) {
      return max(realRM[reps]!, estimated);
    }

    return estimated;
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

  // ======================================================
  // 🖥 UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    if (_progress.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.exercise)),
        body: const Center(
          child: Text(
            "No hay suficientes datos para este ejercicio",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.exercise),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Resumen"),
              Tab(text: "Gráficos"),
              Tab(text: "Historial"),
            ],
            indicatorColor: Colors.greenAccent,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: TabBarView(
          children: [
            // 1. RESUMEN
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _exerciseOverviewCard(
                  realRM: _realRM,
                  first: _progress.first,
                  last: _progress.last,
                ),
                const SizedBox(height: 16),
                _fatigueCorrelationCard(_fatigueCorrelation),
                const SizedBox(height: 16),
                _correlationEvidenceList(_fatigueCorrelation),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "💡 Tip",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "El 1RM estimado se calcula usando la fórmula de Epley basada en tus mejores sets de cada sesión.",
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 2. GRÁFICOS
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Seleccionar métrica",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _chartSelector(),
                const SizedBox(height: 8),
                const SizedBox(height: 24),
                if (_selectedChartIndex == 0) ...[
                  const Text(
                    "Evolución del 1RM Estimado",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _rmEvolutionChart(_progress),
                ] else if (_selectedChartIndex == 1) ...[
                  const Text(
                    "Volumen por Sesión (Tonelaje)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _sessionProgressChart(_progress),
                ] else ...[
                  const Text(
                    "Perfil de Fuerza (Real vs Teórico)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _rmRepsWeightChartWithEstimate(_realRM),
                ],
                const SizedBox(height: 24),
                const Text(
                  "Correlación Fatiga vs RM",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _fatigueCorrelationChart(_fatigueCorrelation),
              ],
            ),

            // 3. HISTORIAL
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Sesiones recientes",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _sessionTableByDay(_sessionSets, _progress),
                const SizedBox(height: 24),
                const Text(
                  "Mejores pesos por RM",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _rmTable(_realRM),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _chartBtn("1RM", 0),
          _chartBtn("Volumen", 1),
          _chartBtn("Perfil", 2),
        ],
      ),
    );
  }

  Widget _chartBtn(String label, int index) {
    final isSelected = _selectedChartIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedChartIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? Colors.greenAccent.withOpacity(0.2)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: Colors.greenAccent) : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.greenAccent : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
