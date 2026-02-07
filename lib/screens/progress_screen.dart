import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'exercise_rm_detail_screen.dart';
import '../services/workout_metrics_service.dart';
import '../services/workout_rm_service.dart';
import '../services/progress_alert_service.dart';
import '../utils/rpe_factor.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Set<String> _trackedExercises = {};
  bool _loadingTracked = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    _loadTrackedExercises();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrackedExercises() async {
    final snap = await FirebaseFirestore.instance
        .collection('exercises')
        .where('trackRM', isEqualTo: true)
        .get();

    setState(() {
      _trackedExercises = snap.docs.map((d) => d['name'].toString()).toSet();
      _loadingTracked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (_loadingTracked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Progreso"),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: "Resumen"),
            Tab(text: "Ejercicios"),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: uid)
            .orderBy('date')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("Aún no tienes entrenamientos"));
          }

          return TabBarView(
            controller: _tabCtrl,
            children: [
              _buildSummary(docs),
              _buildExercisePRs(docs),
            ],
          );
        },
      ),
    );
  }

  String formatDate(DateTime d) {
    return "${d.day.toString().padLeft(2, '0')}/"
        "${d.month.toString().padLeft(2, '0')}/"
        "${d.year}";
  }

  // ======================================================
  // 📊 RESUMEN + ALERTAS
  // ======================================================
  Widget _buildSummary(List<QueryDocumentSnapshot> docs) {
    int totalSessions = docs.length;
    double totalVolume = 0;
    double rpeSum = 0;
    int rpeCount = 0;

    // 🔹 RM history (Map puro)
    final Map<String, List<Map<String, dynamic>>> rmHistory = {};

    // 🔹 Volumen semanal
    final Map<DateTime, double> volumeByWeek = {};

    for (final d in docs) {
      final date = (d['date'] as Timestamp).toDate();
      final performed = WorkoutMetricsService.performedFromDoc(d);

      final metrics = WorkoutMetricsService.computeFromPerformed(performed);

      totalVolume += metrics.totalVolumeKg;

      if (metrics.avgRpe > 0) {
        rpeSum += metrics.avgRpe;
        rpeCount++;
      }

      // ---------- volumen semanal ----------
      final weekStart = DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(Duration(days: date.weekday - 1));

      volumeByWeek[weekStart] =
          (volumeByWeek[weekStart] ?? 0.0) + metrics.totalVolumeKg;

      // ---------- RM history ----------
      final sets = WorkoutRMService
    .extractAllValidRMSetCandidates(performed)
    .where((s) => _trackedExercises.contains(s['exercise']))
    .toList();


      for (final s in sets) {
        final ex = s['exercise'];
        final rm = WorkoutRMService.estimate1RM(
  weight: (s['weight'] as num).toDouble(),
  reps: (s['reps'] as num).toInt(),
  rpe: (s['rpe'] as num).toDouble(),
  rpeFactor: rpeFactor,
);


        rmHistory.putIfAbsent(ex, () => []);
        rmHistory[ex]!.add({
  'date': date,
  'rm': rm,
  'rpe': s['rpe'],
  'weight': (s['weight'] as num?)?.toDouble(),
  'reps': (s['reps'] as num?)?.toInt(),
});

      }
    }

    final avgRpe = rpeCount > 0 ? rpeSum / rpeCount : 0.0;

    final alerts = ProgressAlertService.analyze(
      rmHistory: rmHistory,
      weeklyVolume: volumeByWeek.entries
          .map((e) => {'week': e.key, 'volume': e.value})
          .toList(),
    );

    alerts.sort((a, b) {
      final da = a.evidence['date'] as DateTime?;
      final db = b.evidence['date'] as DateTime?;

      if (da == null && db == null) return 0;
      if (da == null) return 1; // sin fecha → abajo
      if (db == null) return -1; // con fecha → arriba

      return db.compareTo(da); // 🔥 más reciente primero
    });

    Widget card(String label, String value) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "Resumen global",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            card("Sesiones", totalSessions.toString()),
            card("Volumen total", "${totalVolume.toStringAsFixed(0)} kg"),
            card("RPE promedio", avgRpe > 0 ? avgRpe.toStringAsFixed(1) : "—"),
          ],
        ),

        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            "Alertas",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...alerts.map(
            (a) => ListTile(
              leading: Icon(
                a.type == ProgressAlertType.newPR
                    ? Icons.emoji_events
                    : a.type == ProgressAlertType.stagnation
                    ? Icons.trending_flat
                    : Icons.warning,
                color: a.type == ProgressAlertType.newPR
                    ? Colors.amber
                    : a.type == ProgressAlertType.stagnation
                    ? Colors.orange
                    : Colors.red,
              ),
              title: Text(a.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.explanation),
                  const SizedBox(height: 4),
                  if (a.evidence['date'] != null)
                    Text(
                      "Fecha: ${formatDate(a.evidence['date'] as DateTime)}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ======================================================
  // 🏋️ PR POR EJERCICIO
  // ======================================================
  Widget _buildExercisePRs(List<QueryDocumentSnapshot> docs) {
    final Set<String> exercises = {};

    for (final d in docs) {
      final performed = WorkoutMetricsService.performedFromDoc(d);

      final sets = WorkoutRMService.extractAllValidRMSetCandidates(performed)
;

      for (final s in sets) {
        if (_trackedExercises.contains(s['exercise'])) {
          exercises.add(s['exercise']);
        }
      }
    }

    final exerciseList = exercises.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: exerciseList.length,
      itemBuilder: (context, i) {
        final exercise = exerciseList[i];

        return Card(
          child: ListTile(
            leading: const Icon(Icons.fitness_center),
            title: Text(exercise),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ExerciseRMDetailScreen(exercise: exercise, docs: docs),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
