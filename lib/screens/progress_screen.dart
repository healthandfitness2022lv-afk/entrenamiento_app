import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'exercise_rm_detail_screen.dart';
import '../services/workout_metrics_service.dart';
import '../services/workout_rm_service.dart';
import '../services/progress_alert_service.dart';

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
    _tabCtrl = TabController(length: 3, vsync: this);

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
    Tab(text: "Logros"), // NUEVO
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
  _buildAchievementsTab(docs), // NUEVO
],

          );
        },
      ),
    );
  }

  Widget _legendRow(
    ProgressAlertType type, String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(
          _iconForAlert(type),
          color: _colorForAlert(type),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

Map<String, List<Map<String, dynamic>>> _buildFullRMHistoryUpToDate(
  List<QueryDocumentSnapshot> docs,
  DateTime targetDate,
) {
  final Map<String, List<Map<String, dynamic>>> rmHistory = {};

  for (final d in docs) {
    final date = (d['date'] as Timestamp).toDate();

    if (date.isAfter(targetDate)) continue;

    final performed =
        WorkoutMetricsService.performedFromDoc(d);

    final sets = WorkoutRMService
        .extractAllValidRMSetCandidates(performed)
        .where((s) => _trackedExercises.contains(s['exercise']))
        .toList();

    for (final s in sets) {
      final ex = s['exercise'];

      final weight = (s['weight'] as num).toDouble();
final reps = (s['reps'] as num).toInt();

final rm = weight * (1 + reps / 30);


      rmHistory.putIfAbsent(ex, () => []);

      rmHistory[ex]!.add({
        'date': date,
        'rm': rm,
        'weight': (s['weight'] as num?)?.toDouble(),
        'reps': (s['reps'] as num?)?.toInt(),
      });
    }
  }

  return rmHistory;
}





DateTimeRange? _achievementRange;

Widget _buildAchievementsTab(List<QueryDocumentSnapshot> docs) {
  final now = DateTime.now();

  final defaultStart = now.subtract(const Duration(days: 7));
  final range = _achievementRange ??
      DateTimeRange(start: defaultStart, end: now);

  final filteredDocs = docs.where((d) {
    final date = (d['date'] as Timestamp).toDate();
    return date.isAfter(range.start.subtract(const Duration(days: 1))) &&
        date.isBefore(range.end.add(const Duration(days: 1)));
  }).toList();

  final Map<DateTime, List<ProgressAlert>> achievementsByDate = {};

  for (final d in filteredDocs) {
    final date = (d['date'] as Timestamp).toDate();

    WorkoutMetricsService.performedFromDoc(d);

    final rmHistory = _buildFullRMHistoryUpToDate(docs, date);


    final alerts = ProgressAlertService.analyzeSessionImpact(
  rmHistory: rmHistory,
  targetDate: date,
);


    if (alerts.isNotEmpty) {
      final dayKey = DateTime(date.year, date.month, date.day);
      achievementsByDate[dayKey] = alerts;
    }
  }

  final sortedDates = achievementsByDate.keys.toList()
    ..sort((a, b) => b.compareTo(a));

  return Column(
    children: [
      const SizedBox(height: 8),

      // 🔹 Selector de rango
      Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    TextButton.icon(
      icon: const Icon(Icons.date_range),
      label: Text(
          "${formatDate(range.start)} - ${formatDate(range.end)}"),
      onPressed: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: range,
        );

        if (picked != null) {
          setState(() {
            _achievementRange = picked;
          });
        }
      },
    ),

    IconButton(
      icon: const Icon(Icons.help_outline),
      onPressed: () {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Significado de íconos"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendRow(ProgressAlertType.newPR, "Nuevo PR"),
                _legendRow(ProgressAlertType.heaviestSet,
                    "Serie más pesada histórica"),
                _legendRow(ProgressAlertType.sessionVolumePR,
                    "Récord de volumen"),
                _legendRow(ProgressAlertType.improvedEfficiency,
                    "Mejor eficiencia"),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cerrar"),
              )
            ],
          ),
        );
      },
    ),
  ],
),


      const Divider(),

      Expanded(
  child: sortedDates.isEmpty
      ? const Center(child: Text("Sin logros en este rango"))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final date = sortedDates[index];
            final alerts = achievementsByDate[date]!;

            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: const Icon(
                  Icons.emoji_events,
                  color: Colors.amber,
                ),
                title: Text(
                  formatDate(date),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "${alerts.length} logro${alerts.length > 1 ? 's' : ''}",
                ),
                children: [
  _buildCompactAchievementView(alerts),
],


              ),
            );
          },
        ),
),

    ],
  );

  
}

Widget _buildCompactAchievementView(
    List<ProgressAlert> alerts) {
  final Map<String, List<ProgressAlertType>> byExercise = {};

  for (final a in alerts) {
    final ex = a.evidence['exercise'] ?? 'Ejercicio';
    byExercise.putIfAbsent(ex, () => []);
    byExercise[ex]!.add(a.type);
  }

  return Column(
    children: byExercise.entries.map((entry) {
      final exercise = entry.key;
      final types = entry.value;

      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 8, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                exercise,
                style: const TextStyle(
                    fontWeight: FontWeight.w600),
              ),
            ),
            Row(
              children: types.map((type) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
  onTap: () {
  final exerciseAlerts = alerts
      .where((a) => a.evidence['exercise'] == exercise)
      .toList();

  _showExerciseAchievementDetails(exercise, exerciseAlerts);
},

  child: Icon(
    _iconForAlert(type),
    color: _colorForAlert(type),
    size: 22,
  ),
),

                );
              }).toList(),
            )
          ],
        ),
      );
    }).toList(),
  );
}

Widget _achievementMetricBlock({
  required String prev,
  required String curr,
  double? delta,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Anterior",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            prev,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Actual",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            curr,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      if (delta != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Mejora",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              "${delta >= 0 ? '+' : ''} ${(delta * 100).toStringAsFixed(1)}%",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
    ],
  );
}


void _showExerciseAchievementDetails(
  String exercise,
  List<ProgressAlert> alerts,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              exercise,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            ...alerts.map((a) {
  final prev = a.evidence['previous'];
  final curr = a.evidence['current'];
  final delta = a.evidence['deltaPct'];

  final prevSet = a.evidence['previousSet'];
  final currSet = a.evidence['currentSet'];


  return Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: Theme.of(context)
          .colorScheme
          .surfaceVariant
          .withOpacity(0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _iconForAlert(a.type),
              color: _colorForAlert(a.type),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                a.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // =========================
        // NEW PR
        // =========================
        if (a.type == ProgressAlertType.newPR &&
    currSet is Map)
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (prevSet is Map)
        _achievementMetricBlock(
          prev:
              "${prevSet['reps']} x ${prevSet['weight']} kg",
          curr:
              "${currSet['reps']} x ${currSet['weight']} kg",
          delta: delta,
        )
      else
        Text(
          "Primera marca registrada",
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),

      const SizedBox(height: 10),

      // 🔥 RM estimados
      if (prev != null)
        Text(
          "RM anterior: ${prev.toStringAsFixed(1)} kg",
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),

      Text(
        "RM actual: ${curr.toStringAsFixed(1)} kg",
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),
    ],
  ),

        // =========================
        // HEAVIEST SET
        // =========================
        if (a.type == ProgressAlertType.heaviestSet &&
    prevSet is Map &&
    currSet is Map)

  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _achievementMetricBlock(
        prev: "${prevSet['reps']} x ${prevSet['weight']} kg",
        curr: "${currSet['reps']} x ${currSet['weight']} kg",
        delta: delta,
      ),

      const SizedBox(height: 6),

      Text(
        "Total serie actual: ${(currSet['reps'] * currSet['weight']).toStringAsFixed(0)} kg",
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),
    ],
  ),
        // =========================
        // SESSION VOLUME
        // =========================
        if (a.type == ProgressAlertType.sessionVolumePR)
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _achievementMetricBlock(
        prev: "${prev.toStringAsFixed(1)} kg",
        curr: "${curr.toStringAsFixed(1)} kg",
        delta: delta,
      ),

      const SizedBox(height: 12),

      if (a.evidence['previousSets'] != null &&
          (a.evidence['previousSets'] as List).isNotEmpty) ...[
        const Text(
          "Sesión anterior récord:",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: (a.evidence['previousSets'] as List)
              .map<Widget>((s) => Chip(
                    label: Text(
                        "${s['reps']} x ${s['weight']} kg"),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
      ],

      const Text(
        "Sesión actual:",
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: (a.evidence['currentSets'] as List)
            .map<Widget>((s) => Chip(
                  label: Text(
                      "${s['reps']} x ${s['weight']} kg"),
                ))
            .toList(),
      ),
    ],
  ),


      ],
    ),
  );
}).toList(),


            const SizedBox(height: 10),
          ],
        ),
      );
    },
  );
}


  String formatDate(DateTime d) {
    return "${d.day.toString().padLeft(2, '0')}/"
        "${d.month.toString().padLeft(2, '0')}/"
        "${d.year}";
  }

  IconData _iconForAlert(ProgressAlertType type) {
  switch (type) {
    case ProgressAlertType.newPR:
      return Icons.emoji_events;

    case ProgressAlertType.heaviestSet:
      return Icons.fitness_center;

    case ProgressAlertType.sessionVolumePR:
      return Icons.bar_chart;

    case ProgressAlertType.bestWeekEver:
      return Icons.calendar_today;

    case ProgressAlertType.improvedEfficiency:
      return Icons.psychology;

    case ProgressAlertType.rpeWithoutProgress:
      return Icons.warning_amber;

    case ProgressAlertType.stagnation:
      return Icons.trending_flat;
  }
}

Color _colorForAlert(ProgressAlertType type) {
  switch (type) {
    case ProgressAlertType.newPR:
      return Colors.amber;

    case ProgressAlertType.heaviestSet:
      return Colors.deepPurple;

    case ProgressAlertType.sessionVolumePR:
      return Colors.blue;

    case ProgressAlertType.bestWeekEver:
      return Colors.green;

    case ProgressAlertType.improvedEfficiency:
      return Colors.teal;

    case ProgressAlertType.rpeWithoutProgress:
      return Colors.redAccent;

    case ProgressAlertType.stagnation:
      return Colors.orange;
  }
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
        final weight = (s['weight'] as num).toDouble();
final reps = (s['reps'] as num).toInt();

final rm = weight * (1 + reps / 30);



        rmHistory.putIfAbsent(ex, () => []);
        rmHistory[ex]!.add({
  'date': date,
  'rm': rm,
  'weight': (s['weight'] as num?)?.toDouble(),
  'reps': (s['reps'] as num?)?.toInt(),
});

      }
    }

    final avgRpe = rpeCount > 0 ? rpeSum / rpeCount : 0.0;

    final alerts = ProgressAlertService.analyzeHistorical(
      rmHistory: rmHistory,
  
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
