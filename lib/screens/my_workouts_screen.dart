import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/workout_rpe_utils.dart';
import 'my_workout_details_screen.dart';
import '../services/workout_volume_service.dart';
import '../models/routine_session_summary.dart';
import 'routine_exercise_progress_screen.dart';
import 'log_workout_screen.dart';





class MyWorkoutsScreen extends StatefulWidget {
  const MyWorkoutsScreen({super.key});

  @override
  State<MyWorkoutsScreen> createState() => _MyWorkoutsScreenState();
}

class _MyWorkoutsScreenState extends State<MyWorkoutsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString()) ?? 0;
}

double _parseDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}


  // ======================================================
  // 🔹 Helpers fechas (America/Santiago -> usamos local)
  // ======================================================
  DateTime _startOfWeek(DateTime now) {
    // Lunes como inicio
    final int diff = now.weekday - DateTime.monday;
    final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: diff));
    return d; // 00:00
  }

  DateTime _endOfToday(DateTime now) {
    // fin del día 23:59:59.999
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  

Widget _performedWorkoutView(List<Map<String, dynamic>> performed) {
  final series = performed.where((p) => p['type'] == 'Series').toList();
  final circuitos = performed.where((p) => p['type'] == 'Circuito').toList();
  final tabatas = performed.where((p) => p['type'] == 'Tabata').toList();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (series.isNotEmpty) _seriesBlockGroup(series),
      ...circuitos.map(_circuitBlockView),
      ...tabatas.map(_tabataBlockView),
    ],
  );
}

Widget _seriesBlockGroup(List<Map<String, dynamic>> seriesBlocks) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Series",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),

        ...seriesBlocks.map(_seriesExerciseRow),
      ],
    ),
  );
}

Widget _seriesExerciseRow(Map<String, dynamic> p) {
  final String name = p['exercise'];
  final List sets = p['sets'] ?? [];

  if (sets.isEmpty) return const SizedBox();

  final bool perSide =
    (p['perSide'] == true) || sets.any((s) => s['perSide'] == true);


  final int sideMultiplier = perSide ? 2 : 1;

  double totalWeight = 0;

  for (final s in sets) {
    final int reps = _parseInt(s['reps']);
final double weight = _parseDouble(s['weight']);


    totalWeight += reps * weight * sideMultiplier;
  }

  final String sideLabel = perSide ? " · por lado ×2" : "";

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$name$sideLabel · ${totalWeight.toStringAsFixed(0)} kg",
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        ...List.generate(sets.length, (i) {
          final s = sets[i];
          return Text(
            "• ${i + 1}: ${s['reps']} reps · ${s['weight'] ?? 0} kg · RPE ${s['rpe']}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          );
        }),
      ],
    ),
  );
}



Widget _circuitBlockView(Map<String, dynamic> p) {
  final List rounds = p['rounds'] ?? [];

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Circuito · ${rounds.length} rondas",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),

        ...rounds.map((r) {
  final List exs = r['exercises'] ?? [];

  double roundTotal = 0;
  bool anyPerSide = false;

  for (final e in exs) {
    final int reps = _parseInt(e['reps']);
final double weight = _parseDouble(e['weight']);


    final bool perSide = e['perSide'] == true;
    if (perSide) anyPerSide = true;

    roundTotal += reps * weight * (perSide ? 2 : 1);
  }

  final String sideLabel = anyPerSide ? "" : "";

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Ronda ${r['round']} · ${roundTotal.toStringAsFixed(0)} kg$sideLabel",
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        ...exs.map((e) {
          final bool perSide = e['perSide'] == true;
          final String sideText = perSide ? " · por lado" : "";

          return Text(
            "• ${e['exercise']}$sideText · ${e['reps']} reps · ${e['weight'] ?? 0} kg · RPE ${e['rpe']}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          );
        }),
      ],
    ),
  );
}),

      ],
    ),
  );
}


Widget _tabataBlockView(Map<String, dynamic> p) {
  final List exs = p['exercises'] ?? [];

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Tabata · ${p['work']}/${p['rest']} · ${p['rounds']} rondas",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),

        ...exs.map((e) => Text(
              "• ${e['exercise']} · RPE ${e['rpe']}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            )),
      ],
    ),
  );
}


Map<String, List<RoutineSessionSummary>> _groupByRoutine(
  List<QueryDocumentSnapshot> docs,
) {
  final Map<String, List<RoutineSessionSummary>> grouped = {};

  for (final d in docs) {
    final data = d.data() as Map<String, dynamic>;

    final String? routineId = data['routineId'];
    if (routineId == null) continue;

    final DateTime date =
        (data['date'] as Timestamp).toDate();

    final performed =
        List<Map<String, dynamic>>.from(data['performed'] ?? []);

    final double volume =
        WorkoutVolumeService.calculateWorkoutVolume(performed);

    final double avgRpe =
        calculateAverageWorkoutRPE(performed);

    grouped.putIfAbsent(routineId, () => []).add(
      RoutineSessionSummary(
        date: date,
        volume: volume,
        avgRpe: avgRpe,
      ),
    );
  }

  // 🔥 Ordenar cada rutina por fecha
  for (final list in grouped.values) {
    list.sort((a, b) => a.date.compareTo(b.date));
  }

  return grouped;
}

  bool _hasProgress(List<RoutineSessionSummary> sessions) {
  if (sessions.length < 2) return false;

  final first = sessions.first;
  final last = sessions.last;

  return (last.volume != first.volume) ||
         ((last.avgRpe - first.avgRpe).abs() >= 0.3);
}

  // ======================================================
  // 🔹 Listado reutilizable según rango
  // ======================================================
  Widget _buildList({
    required List<QueryDocumentSnapshot> docs,
    required DateFormat dateFmt,
    required DateTime start,
    required DateTime end,
  }) {
    // Filtrar por rango (inclusive)
    final filtered = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final ts = data['date'];
      if (ts == null) return false;
      final date = (ts as Timestamp).toDate();
      return !date.isBefore(start) && !date.isAfter(end);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          "No hay entrenamientos en este período",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
  padding: const EdgeInsets.symmetric(vertical: 8),
  itemCount: filtered.length,
  itemBuilder: (context, i) {
    final d = filtered[i];
    final data = d.data() as Map<String, dynamic>;

    final date = (data['date'] as Timestamp).toDate();

    final performed = List<Map<String, dynamic>>.from(
      data['performed'] ?? [],
    );

    // 🔥 CÁLCULOS (AQUÍ, ANTES DE USARLOS)
    final double volume =
        WorkoutVolumeService.calculateWorkoutVolume(performed);

    final double avgRpe =
    calculateAverageWorkoutRPE(performed);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: const Icon(
          Icons.fitness_center,
          color: Colors.blueAccent,
        ),
        title: Text(
          data['routineName'] ?? 'Entrenamiento',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          dateFmt.format(date),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          "${volume.toStringAsFixed(0)} kg",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
        if (avgRpe > 0)
          Text(
            "RPE ${avgRpe.toStringAsFixed(1)}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.orangeAccent,
            ),
          ),
      ],
    ),

    const SizedBox(width: 6),

    IconButton(
  icon: const Icon(Icons.edit, size: 20),
  tooltip: "Editar entrenamiento",
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LogWorkoutScreen(
          existingWorkout: d.data() as Map<String, dynamic>,
          workoutRef: d.reference,
        ),
      ),
    );
  },
),

  ],
),

        children: [
          const Divider(height: 1),
          Padding(
  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
  child: _performedWorkoutView(performed),
),



Builder(
  builder: (_) {
    final allByRoutine =
        _groupByRoutine(filtered);

    final routineId = data['routineId'];
    final sessions = routineId != null
        ? allByRoutine[routineId]
        : null;

    if (sessions == null || !_hasProgress(sessions)) {
      return const SizedBox();
    }

    return TextButton.icon(
      icon: const Icon(Icons.trending_up),
      label: const Text("Ver progreso de la rutina"),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoutineExerciseProgressScreen(
  routineName: data['routineName'] ?? 'Rutina',
  workouts: filtered
      .where((w) => w['routineId'] == data['routineId'])
      .toList(),
),



          ),
        );
      },
    );
  },
),

TextButton.icon(
  icon: const Icon(Icons.open_in_new),
  label: const Text("Ver detalle completo"),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyWorkoutDetailsScreen(workout: d),
      ),
    );
  },
),

        ],
      ),
    );
  },
);

  }

  // ======================================================
  // 🔹 Rango picker
  // ======================================================
  Future<void> _pickRange() async {
    final now = DateTime.now();

    final initialStart = _rangeStart ?? now.subtract(const Duration(days: 6));
    final initialEnd = _rangeEnd ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: "Elegir rango de fechas",
      confirmText: "Aplicar",
      cancelText: "Cancelar",
      locale: const Locale('es', 'ES'),
    );

    if (picked == null) return;

    setState(() {
      _rangeStart = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _rangeEnd = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final dateFmt = DateFormat('dd MMM yyyy · HH:mm', 'es_ES');
    final now = DateTime.now();

    final weekStart = _startOfWeek(now);
    final weekEnd = _endOfToday(now);

    final last10Start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 9));
    final last10End = _endOfToday(now);

    final rangeStart = _rangeStart ?? weekStart; // por defecto, mismo que semana
    final rangeEnd = _rangeEnd ?? weekEnd;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis entrenamientos"),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: "Esta semana"),
            Tab(text: "Últimos 10 días"),
            Tab(text: "Rango"),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: uid)
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.cast<QueryDocumentSnapshot>();

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "Aún no tienes entrenamientos registrados",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return TabBarView(
            controller: _tabCtrl,
            children: [
              // ✅ Esta semana (default)
              _buildList(
                docs: docs,
                dateFmt: dateFmt,
                start: weekStart,
                end: weekEnd,
              ),

              // ✅ Últimos 10 días
              _buildList(
                docs: docs,
                dateFmt: dateFmt,
                start: last10Start,
                end: last10End,
              ),

              // ✅ Rango
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range),
                            label: Text(
                              _rangeStart == null && _rangeEnd == null
                                  ? "Elegir rango"
                                  : "${DateFormat('dd MMM', 'es_ES').format(rangeStart)} → ${DateFormat('dd MMM', 'es_ES').format(rangeEnd)}",
                            ),
                            onPressed: _pickRange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: "Limpiar",
                          onPressed: () {
                            setState(() {
                              _rangeStart = null;
                              _rangeEnd = null;
                            });
                          },
                          icon: const Icon(Icons.clear),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _buildList(
                      docs: docs,
                      dateFmt: dateFmt,
                      start: rangeStart,
                      end: rangeEnd,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
