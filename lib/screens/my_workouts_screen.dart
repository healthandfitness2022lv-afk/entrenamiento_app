import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/workout_rpe_utils.dart';
import 'my_workout_details_screen.dart';
import '../services/workout_volume_service.dart';
import '../models/routine_session_summary.dart';
import 'log_workout_screen.dart';

import '../models/achievement.dart';
import '../services/progress_alert_service.dart';
import '../services/workout_rm_service.dart';

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

  Widget _buildAchievementBadge(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

Widget _performedWorkoutView(List<Map<String, dynamic>> performed) {
  final List<Widget> children = [];

  for (final p in performed) {
    String type = p['type'] ?? 'Series';
    String blockTitle = (p['blockTitle']?.toString() ?? '').trim();

    // Fix if backend saved a default generic name or it is empty
    if (blockTitle.isEmpty || blockTitle == 'Series' || blockTitle == 'Circuito' || blockTitle == 'Tabata') {
      blockTitle = type;
    }

    if (type == 'Circuito') {
      final rounds = p['rounds'] as List? ?? [];
      blockTitle = "$blockTitle · ${rounds.length} rondas";
    } else if (type == 'Tabata') {
      blockTitle = "$blockTitle · ${p['work']}/${p['rest']} · ${p['rounds']} rondas";
    }

    children.add(
      Padding(
        padding: EdgeInsets.only(bottom: 6, top: children.isEmpty ? 0 : 8),
        child: Text(
          blockTitle.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
      ),
    );

    if (type == 'Circuito') {
      children.add(_circuitBlockView(p));
    } else if (type == 'Tabata') {
      children.add(_tabataBlockView(p));
    } else if (type == 'Series descendentes') {
      children.add(_descendingSeriesBlockView(p));
    } else if (type == 'Series' || type == 'Buscar RM') {
      final List exs = p['exercises'] ?? [];
      for (final ex in exs) {
        children.add(_seriesExerciseRow(Map<String, dynamic>.from(ex), type));
      }
    }
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
}

Widget _descendingSeriesBlockView(Map<String, dynamic> p) {
  final List exs = p['exercises'] ?? [];
  if (exs.isEmpty) return const SizedBox();

  int maxSets = 0;
  for (final ex in exs) {
    if (ex is! Map) continue;
    final sets = ex['sets'] as List? ?? [];
    if (sets.length > maxSets) {
      maxSets = sets.length;
    }
  }

  if (maxSets == 0) return const SizedBox();

  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(maxSets, (i) {
          int? roundReps;
          for (final ex in exs) {
            if (ex is! Map) continue;
            final sets = ex['sets'] as List? ?? [];
            if (i < sets.length) {
              roundReps = _parseInt(sets[i]['reps']);
              if (roundReps > 0) break;
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${roundReps ?? '-'} reps",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ...exs.map((ex) {
                  if (ex is! Map) return const SizedBox();
                  final String name = ex['exercise'] ?? 'Ejercicio';
                  final sets = ex['sets'] as List? ?? [];
                  if (i >= sets.length) return const SizedBox();

                  final s = sets[i];
                  final weight = s['weight'] ?? 0;
                  final rpe = s['rpe'] ?? '-';
                  
                  final bool exPerSide = ex['perSide'] == true;
                  final bool sPerSide = s['perSide'] == true;
                  final bool perSide = exPerSide || sPerSide;
                  final sideLabel = perSide ? " · por lado" : "";

                  return Text(
                    "• $name$sideLabel · $weight kg · RPE $rpe",
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

Widget _seriesExerciseRow(Map<String, dynamic> p, String blockType) {
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
  
  String headerText = "$name$sideLabel · ${totalWeight.toStringAsFixed(0)} kg";
  if (blockType == 'Series descendentes') {
      headerText = "$name (Descendentes)$sideLabel · ${totalWeight.toStringAsFixed(0)} kg";
  } else if (blockType == 'Buscar RM') {
      headerText = "$name (RM)$sideLabel · ${totalWeight.toStringAsFixed(0)} kg";
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headerText,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        ...List.generate(sets.length, (i) {
          final s = sets[i];
          if (blockType == 'Series descendentes') {
            return Text(
              "• Escalón ${i + 1}: ${s['reps']} reps · ${s['weight'] ?? 0} kg · RPE ${s['rpe']}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            );
          } else if (blockType == 'Buscar RM') {
            return Text(
              "• Intento ${i + 1}: ${s['reps']} reps · ${s['weight'] ?? 0} kg · RPE ${s['rpe']}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            );
          }
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
    required List<QueryDocumentSnapshot> allDocs,
    required List<QueryDocumentSnapshot> docs,
    required DateFormat dateFmt,
    required DateTime start,
    required DateTime end,
    required List<Map<String, dynamic>> userAchievements,
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
    final finishedTs = data['finishedAt'] as Timestamp? ?? data['date'] as Timestamp;
    final finishedDt = finishedTs.toDate();

    final performed = List<Map<String, dynamic>>.from(
      data['performed'] ?? [],
    );

    // 🔥 CÁLCULOS (AQUÍ, ANTES DE USARLOS)
    final double volume =
        WorkoutVolumeService.calculateWorkoutVolume(performed);

    final double avgRpe =
    calculateAverageWorkoutRPE(performed);

    final int duration =
    (data['durationMinutes'] as num?)?.toInt() ?? 0;

    // 🔥 LOGROS VITRINA
    final List<Achievement> sessionVitrina = [];
    for (var u in userAchievements) {
      if (u['unlockedAt'] == null) continue;
      final DateTime unlocked = (u['unlockedAt'] as Timestamp).toDate();
      if (unlocked.difference(finishedDt).inMinutes.abs() <= 5) {
        try {
          sessionVitrina.add(achievementsCatalog.firstWhere((a) => a.id == u['id']));
        } catch (_) {}
      }
    }

    // 🔥 LOGROS OTROS (PRs)
    final rmHistory = <String, List<Map<String, dynamic>>>{};
    for (final ad in allDocs) {
      final adDate = (ad['date'] as Timestamp).toDate();
      if (adDate.isAfter(date)) continue;
      final perf = List<Map<String,dynamic>>.from((ad.data() as Map)['performed'] ?? []);
      final sets = WorkoutRMService.extractAllValidRMSetCandidates(perf);
      for (final s in sets) {
        final weight = (s['weight'] as num).toDouble();
        final reps = (s['reps'] as num).toInt();
        rmHistory.putIfAbsent(s['exercise'], () => []).add({
          'date': adDate, 'rm': weight * (1 + reps / 30), 'weight': weight, 'reps': reps
        });
      }
    }

    final alerts = ProgressAlertService.analyzeSessionImpact(
      rmHistory: rmHistory,
      targetDate: date,
    );

    final List<Widget> badgeWidgets = [];
    for (final ach in sessionVitrina) {
      badgeWidgets.add(_buildAchievementBadge(ach.title, ach.icon, Colors.amber));
    }
    
    final Map<ProgressAlertType, int> alertCounts = {};
    for (final a in alerts) {
      if (a.type != ProgressAlertType.rpeWithoutProgress && a.type != ProgressAlertType.stagnation) {
         alertCounts[a.type] = (alertCounts[a.type] ?? 0) + 1;
      }
    }
    
    alertCounts.forEach((type, count) {
      String title = ""; IconData id; Color c;
      switch (type) {
        case ProgressAlertType.newPR: title = "Nuevo PR"; id = Icons.emoji_events; c = Colors.amber; break;
        case ProgressAlertType.heaviestSet: title = "Serie Pesada"; id = Icons.fitness_center; c = Colors.deepPurpleAccent; break;
        case ProgressAlertType.sessionVolumePR: title = "Récord Volumen"; id = Icons.bar_chart; c = Colors.blueAccent; break;
        case ProgressAlertType.bestWeekEver: title = "Mejor Sem."; id = Icons.calendar_today; c = Colors.green; break;
        case ProgressAlertType.improvedEfficiency: title = "Más Eficacia"; id = Icons.psychology; c = Colors.teal; break;
        default: title = "Logro"; id = Icons.star; c = Colors.orange; break;
      }
      if (count > 1) title = "$count $title";
      badgeWidgets.add(_buildAchievementBadge(title, id, c));
    });


    return Card(
      elevation: 4,
      shadowColor: badgeWidgets.isNotEmpty ? Colors.amber.withOpacity(0.2) : Colors.black26,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: badgeWidgets.isNotEmpty ? Colors.amber.withOpacity(0.4) : Colors.grey.withOpacity(0.1),
          width: 1,
        )
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.fitness_center,
            color: Colors.blueAccent,
            size: 24,
          ),
        ),
        title: Text(
          data['routineName'] ?? 'Entrenamiento',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              dateFmt.format(date),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (badgeWidgets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: badgeWidgets,
              ),
            ]
          ],
        ),
        trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Column(
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.end,
  children: [

    // 🕒 DURACIÓN
    if (duration > 0)
      Text(
        "$duration min",
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),

    const SizedBox(height: 2),

    // 🏋 VOLUMEN
    Text(
      "${volume.toStringAsFixed(0)} kg",
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.blueAccent,
      ),
    ),

    // 🔥 RPE
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
          existingWorkout: {
  'id': d.id,
  ...d.data() as Map<String, dynamic>,
},
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

    return const SizedBox();
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
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/training_action_2.png'),
            fit: BoxFit.cover,
            opacity: 0.15,
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('achievements').snapshots(),
          builder: (context, achSnapshot) {
            
            final userAchievements = achSnapshot.hasData
                ? achSnapshot.data!.docs.map((d) => {
                    'id': d.id,
                    'unlockedAt': (d.data() as Map<String, dynamic>)['unlockedAt'],
                  }).toList()
                : <Map<String, dynamic>>[];

            return StreamBuilder<QuerySnapshot>(
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
                allDocs: docs,
                docs: docs,
                dateFmt: dateFmt,
                start: weekStart,
                end: weekEnd,
                userAchievements: userAchievements,
              ),

              // ✅ Últimos 10 días
              _buildList(
                allDocs: docs,
                docs: docs,
                dateFmt: dateFmt,
                start: last10Start,
                end: last10End,
                userAchievements: userAchievements,
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
                      allDocs: docs,
                      docs: docs,
                      dateFmt: dateFmt,
                      start: rangeStart,
                      end: rangeEnd,
                      userAchievements: userAchievements,
                    ),      
                  ),
                ],
              ),
            ],
          );
        },
      );
      },
    ),
    ),
    );
  }
}
