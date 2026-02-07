import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// ======================================================
/// 📊 STATS DE UN EJERCICIO EN UNA SESIÓN
/// ======================================================
class ExerciseSessionStats {
  final DateTime date;

  final int totalSeries;
  final int totalReps;
  final double totalLoad;

  final double bestWeight;
  final int bestReps;
  final double estimatedRM;

  ExerciseSessionStats({
    required this.date,
    required this.totalSeries,
    required this.totalReps,
    required this.totalLoad,
    required this.bestWeight,
    required this.bestReps,
    required this.estimatedRM,
  });
}

/// ======================================================
/// 📈 PROGRESO POR EJERCICIO
/// ======================================================
class RoutineExerciseProgressScreen extends StatelessWidget {
  final String routineName;
  final List<QueryDocumentSnapshot> workouts;

  const RoutineExerciseProgressScreen({
    super.key,
    required this.routineName,
    required this.workouts,
  });

  // ======================================================
  // 🔢 RM ESTIMADA (EPLEY)
  // ======================================================
  double _estimateRM(double weight, int reps) {
    if (reps <= 1) return weight;
    return weight * (1 + reps / 30);
  }

  // ======================================================
  // 🔍 CONSTRUIR HISTORIAL POR EJERCICIO
  // ======================================================
  Map<String, List<ExerciseSessionStats>> _buildExerciseHistory() {
    final Map<String, List<ExerciseSessionStats>> map = {};

    for (final w in workouts) {
      final data = w.data() as Map<String, dynamic>;
      final DateTime sessionDate =
          (data['date'] as Timestamp).toDate();

      final performed =
          List<Map<String, dynamic>>.from(data['performed'] ?? []);

      final Map<String, ExerciseSessionStats> sessionTotals = {};

      for (final p in performed) {
        // ================= SERIES =================
        if (p['type'] == 'Series') {
          final String name = p['exercise'];
          final List sets = p['sets'] ?? [];

          int series = 0;
          int reps = 0;
          double load = 0;

          double bestWeight = 0;
          int bestReps = 0;

          for (final s in sets) {
            final int r = s['reps'] ?? 0;
            final double w = (s['weight'] as num?)?.toDouble() ?? 0;
            final bool perSide = s['perSide'] == true;
            final int mult = perSide ? 2 : 1;

            series += 1;
            reps += r * mult;
            load += r * w * mult;

            if (w > bestWeight || (w == bestWeight && r > bestReps)) {
              bestWeight = w;
              bestReps = r;
            }
          }

          sessionTotals[name] = ExerciseSessionStats(
            date: sessionDate,
            totalSeries: series,
            totalReps: reps,
            totalLoad: load,
            bestWeight: bestWeight,
            bestReps: bestReps,
            estimatedRM: _estimateRM(bestWeight, bestReps),
          );
        }

        // ================= CIRCUITO =================
        if (p['type'] == 'Circuito') {
          final List rounds = p['rounds'] ?? [];

          for (final r in rounds) {
            final List exs = r['exercises'] ?? [];

            for (final e in exs) {
              final String name = e['exercise'];
              final int reps = e['reps'] ?? 0;
              final double w = (e['weight'] as num?)?.toDouble() ?? 0;
              final bool perSide = e['perSide'] == true;
              final int mult = perSide ? 2 : 1;

              final prev = sessionTotals[name];

              final double bestWeight =
                  prev == null || w > prev.bestWeight ? w : prev.bestWeight;
              final int bestReps =
                  prev == null || w > prev.bestWeight ? reps : prev.bestReps;

              sessionTotals[name] = ExerciseSessionStats(
                date: sessionDate,
                totalSeries: (prev?.totalSeries ?? 0) + 1,
                totalReps: (prev?.totalReps ?? 0) + reps * mult,
                totalLoad:
                    (prev?.totalLoad ?? 0) + reps * w * mult,
                bestWeight: bestWeight,
                bestReps: bestReps,
                estimatedRM: _estimateRM(bestWeight, bestReps),
              );
            }
          }
        }
      }

      sessionTotals.forEach((name, stats) {
        map.putIfAbsent(name, () => []).add(stats);
      });
    }

    return map;
  }

  // ======================================================
  // 🧱 CARD DE PROGRESO
  // ======================================================
  Widget _exerciseProgressCard({
    required String exercise,
    required ExerciseSessionStats first,
    required ExerciseSessionStats last,
  }) {
    final double volDiff = last.totalLoad - first.totalLoad;
    final double volPct =
        first.totalLoad > 0 ? (volDiff / first.totalLoad) * 100 : 0;

    final double rmDiff = last.estimatedRM - first.estimatedRM;
    final double rmPct =
        first.estimatedRM > 0 ? (rmDiff / first.estimatedRM) * 100 : 0;

    final Color volColor =
        volDiff > 0 ? Colors.green : volDiff < 0 ? Colors.red : Colors.grey;
    final Color rmColor =
        rmDiff > 0 ? Colors.green : rmDiff < 0 ? Colors.red : Colors.grey;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            _metricRow(
              label: "Volumen",
              from: "${first.totalLoad.toStringAsFixed(0)} kg",
              to: "${last.totalLoad.toStringAsFixed(0)} kg",
              pct: volPct,
              color: volColor,
            ),

            _metricRow(
              label: "RM estimada",
              from: "${first.estimatedRM.toStringAsFixed(1)} kg",
              to: "${last.estimatedRM.toStringAsFixed(1)} kg",
              pct: rmPct,
              color: rmColor,
            ),

            const SizedBox(height: 6),

            _simpleRow(
              label: "Series",
              from: first.totalSeries,
              to: last.totalSeries,
            ),

            _simpleRow(
              label: "Reps totales",
              from: first.totalReps,
              to: last.totalReps,
            ),

            const SizedBox(height: 10),

            LinearProgressIndicator(
              value: (volPct.clamp(-50, 50) + 50) / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              color: volColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow({
    required String label,
    required String from,
    required String to,
    required double pct,
    required Color color,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(from),
        const SizedBox(width: 6),
        const Icon(Icons.arrow_forward, size: 14),
        const SizedBox(width: 6),
        Text(to),
        const SizedBox(width: 8),
        Text(
          pct == 0 ? "—" : "${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%",
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _simpleRow({
    required String label,
    required int from,
    required int to,
  }) {
    final diff = to - from;
    final color = diff > 0 ? Colors.green : diff < 0 ? Colors.red : Colors.grey;

    return Row(
      children: [
        Expanded(child: Text(label)),
        Text("$from → $to"),
        const SizedBox(width: 8),
        Text(
          diff == 0 ? "—" : "${diff > 0 ? '+' : ''}$diff",
          style: TextStyle(color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (workouts.length < 2) {
      return Scaffold(
        appBar: AppBar(title: Text(routineName)),
        body: const Center(
          child: Text("Se necesitan al menos 2 sesiones"),
        ),
      );
    }

    final history = _buildExerciseHistory();
    final dateFmt = DateFormat('dd MMM yyyy', 'es_ES');

    final firstDate =
        (workouts.last['date'] as Timestamp).toDate();
    final lastDate =
        (workouts.first['date'] as Timestamp).toDate();

    return Scaffold(
      appBar: AppBar(title: const Text("Progreso por ejercicio")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            routineName,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            "${dateFmt.format(firstDate)} → ${dateFmt.format(lastDate)}",
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),

          ...history.entries.map((entry) {
            final list = entry.value;
            if (list.length < 2) return const SizedBox();

            final ordered = List<ExerciseSessionStats>.from(list)
              ..sort((a, b) => a.date.compareTo(b.date));

            return _exerciseProgressCard(
              exercise: entry.key,
              first: ordered.first, // más antigua
              last: ordered.last,   // más reciente
            );
          }),
        ],
      ),
    );
  }
}
