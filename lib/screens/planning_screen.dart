import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/weekly_load_screen.dart';
import '../widgets/routine_view.dart';


class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _DayPlannedItem {
  final String key; // name:xxx
  final String name;
  final String blockLabel; // "Series • Bloque 1 • Fuerza"
  final double plannedVol;

  _DayPlannedItem({
    required this.key,
    required this.name,
    required this.blockLabel,
    required this.plannedVol,
  });
}

class _DayResultItem {
  final _DayPlannedItem planned;
  final double achieved; // consumido desde “bolsa” semanal
  double get missing => (planned.plannedVol - achieved).clamp(0, double.infinity);

  _DayResultItem({required this.planned, required this.achieved});
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min, // ✅ clave anti-overflow
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _PlanningScreenState extends State<PlanningScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  final user = FirebaseAuth.instance.currentUser;

  String? role;
  String? selectedAthleteId;
  String? selectedAthleteName;

  List<Map<String, dynamic>> _plannedWorkouts = [];
  List<Map<String, dynamic>> _athleteRoutines = [];
  String? _expandedWorkoutId;
Map<String, DocumentSnapshot> _routineCache = {};


  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  // ====================================================
  // INIT
  // ====================================================
  Future<void> _initialize() async {
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .get();

    role = userDoc.data()?['role'];

    if (role == 'administrador') {
  selectedAthleteId = user!.uid;
  selectedAthleteName = userDoc.data()?['name'];
}
 else {
      selectedAthleteId = user!.uid;
      selectedAthleteName = userDoc.data()?['name'];
    }

    if (selectedAthleteId != null) {
      await _loadRoutines();
      await _loadPlannedForDay(_selectedDay!);
    }

    setState(() => _loading = false);
  }

  // ====================================================
  // SELECT ATHLETE (ADMIN)
  // ====================================================
  Future<void> _selectAthlete() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('role', whereIn: ['atleta', 'administrador'])
      .get();

  final users = snapshot.docs;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text("Seleccionar atleta"),
      content: SizedBox(
        width: 300,
        height: 400,
        child: ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final u = users[index];

            final isMe = u.id == user!.uid;

            return ListTile(
              leading: isMe
                  ? const Icon(Icons.person, color: Colors.blue)
                  : const Icon(Icons.fitness_center),
              title: Text(
                isMe ? "${u['name']} (Yo)" : u['name'],
              ),
              onTap: () {
                selectedAthleteId = u.id;
                selectedAthleteName = u['name'];
                Navigator.pop(context);
              },
            );
          },
        ),
      ),
    ),
  );
}



  // ====================================================
  // LOAD ROUTINES FROM routine_assignments
  // ====================================================
  Future<void> _loadRoutines() async {
    final assignmentSnapshot = await FirebaseFirestore.instance
        .collection('routine_assignments')
        .where('athleteId', isEqualTo: selectedAthleteId)
        .where('status', isEqualTo: 'active')
        .get();

    final routineIds = assignmentSnapshot.docs
        .map((doc) => doc['routineId'] as String)
        .toList();

    if (routineIds.isEmpty) {
      _athleteRoutines = [];
      return;
    }

    final routinesSnapshot = await FirebaseFirestore.instance
        .collection('routines')
        .where(FieldPath.documentId, whereIn: routineIds)
        .get();

    _athleteRoutines = routinesSnapshot.docs
        .map((d) => {...d.data(), 'id': d.id})
        .toList();
  }

  // ====================================================
  // LOAD PLANNED WORKOUTS
  // ====================================================
  Future<void> _loadPlannedForDay(DateTime date) async {
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));

  print("Searching between $start and $end");

  final snapshot = await FirebaseFirestore.instance
      .collection('planned_workouts')
      .where('athleteId', isEqualTo: selectedAthleteId)
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('date', isLessThan: Timestamp.fromDate(end))
      .get();

  print("FOUND: ${snapshot.docs.length}");

  _plannedWorkouts =
      snapshot.docs.map((d) => {...d.data(), 'id': d.id}).toList();

  setState(() {});
}

DateTime _normalizeDayLocal(DateTime d) {
  // 🔥 mediodía local evita corrimientos por UTC/DST
  return DateTime(d.year, d.month, d.day, 12);
}


Future<Map<String, double>> calculateWeeklyMuscleLoad() async {
  final startOfWeek = _selectedDay!
      .subtract(Duration(days: _selectedDay!.weekday - 1));

  final endOfWeek = startOfWeek.add(const Duration(days: 7));

  final workouts = await FirebaseFirestore.instance
      .collection('planned_workouts')
      .where('athleteId', isEqualTo: selectedAthleteId)
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
      .where('date', isLessThan: Timestamp.fromDate(endOfWeek))
      .get();

  Map<String, double> weeklyLoad = {};

  for (final w in workouts.docs) {
    final routineId = w['routineId'];

    final routineDoc = await FirebaseFirestore.instance
        .collection('routines')
        .doc(routineId)
        .get();

    final exercises = routineDoc.data()?['exercises'] ?? [];

    for (final ex in exercises) {
      final exerciseId = ex['exerciseId'];
      final sets = ex['sets'] ?? 0;

      final exerciseDoc = await FirebaseFirestore.instance
          .collection('exercises')
          .doc(exerciseId)
          .get();

      final weights =
          Map<String, dynamic>.from(exerciseDoc.data()?['muscleWeights'] ?? {});

      weights.forEach((muscle, value) {
        weeklyLoad[muscle] =
            (weeklyLoad[muscle] ?? 0) +
                (sets * (value as num).toDouble());
      });
    }
  }

  return weeklyLoad;
}



  // ====================================================
  // CREATE PLANNED WORKOUT FROM ROUTINE
  // ====================================================
  Future<void> _createPlannedWorkout() async {
    if (_athleteRoutines.isEmpty) return;

    String? selectedRoutineId;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Seleccionar rutina"),
        content: SizedBox(
          width: 300,
          height: 300,
          child: ListView.builder(
            itemCount: _athleteRoutines.length,
            itemBuilder: (context, index) {
              final r = _athleteRoutines[index];
              return ListTile(
                title: Text(r['name']),
                onTap: () {
                  selectedRoutineId = r['id'];
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );

    if (selectedRoutineId == null) return;

    final routine = _athleteRoutines
        .firstWhere((r) => r['id'] == selectedRoutineId);

    final normalized = DateTime(
  _selectedDay!.year,
  _selectedDay!.month,
  _selectedDay!.day,
);

    await FirebaseFirestore.instance
        .collection('planned_workouts')
        .add({
      'athleteId': selectedAthleteId,
      'athleteName': selectedAthleteName,
      'routineId': selectedRoutineId,
      'routineTitle': routine['name'],
      'date': Timestamp.fromDate(normalized),
      'status': 'planned',
      'createdAt': Timestamp.now(),
    });

    _loadPlannedForDay(_selectedDay!);
  }

  // ====================================================
  // DELETE
  // ====================================================
  Future<void> _deleteWorkout(String id) async {
    await FirebaseFirestore.instance
        .collection('planned_workouts')
        .doc(id)
        .delete();

    _loadPlannedForDay(_selectedDay!);
  }


String _norm(String s) {
  return s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

String normalizeExerciseName(dynamic raw) {
  if (raw == null) return '';
  if (raw is String) return raw.trim();
  if (raw is List && raw.isNotEmpty) return raw.first.toString().trim();
  return raw.toString().trim();
}

String _dayKey(DateTime d) {
  final x = DateTime(d.year, d.month, d.day);
  return "${x.year.toString().padLeft(4, '0')}-"
      "${x.month.toString().padLeft(2, '0')}-"
      "${x.day.toString().padLeft(2, '0')}";
}

DateTime _startOfWeekMonday(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

Future<void> _reviewWeekDetailedByDay() async {
  final base = _selectedDay ?? DateTime.now();
  final startOfWeek = _startOfWeekMonday(base);
  final endOfWeek = startOfWeek.add(const Duration(days: 7)); // exclusivo

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: SizedBox(height: 90, child: Center(child: CircularProgressIndicator())),
    ),
  );

  try {
    // =========================
    // 1) Traer planificados (planned_workouts)
    // =========================
    final plannedSnap = await FirebaseFirestore.instance
        .collection('planned_workouts')
        .where('athleteId', isEqualTo: selectedAthleteId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
        .where('date', isLessThan: Timestamp.fromDate(endOfWeek))
        .get();

    final plannedDocs = plannedSnap.docs.map((d) => d.data()).toList();

    // Cache rutinas
    final Map<String, Map<String, dynamic>> routineCache = {};

    // plannedByDay[YYYY-MM-DD] = [items...]
    final Map<String, List<_DayPlannedItem>> plannedByDay = {};

    String _blockLabel(int idx, Map<String, dynamic> block) {
      final type = (block['type'] ?? 'Bloque').toString();
      final title = (block['title'] ?? block['name'] ?? '').toString().trim();
      final t = title.isNotEmpty ? " • $title" : "";
      return "$type • Bloque ${idx + 1}$t";
    }

    // Extrae ejercicios planificados desde la rutina (y trae bloque)
    List<_DayPlannedItem> _extractPlannedItemsFromRoutine(
      Map<String, dynamic> routine,
    ) {
      final out = <_DayPlannedItem>[];

      final blocks = (routine['blocks'] is List) ? List.from(routine['blocks']) : const [];
      for (int i = 0; i < blocks.length; i++) {
        final bRaw = blocks[i];
        if (bRaw is! Map) continue;

        final block = Map<String, dynamic>.from(bRaw);
        final type = (block['type'] ?? '').toString();
        final label = _blockLabel(i, block);

        // SERIES: cada ejercicio tiene 'name' y 'series' (=sets)
        if (type == 'Series') {
          final exs = (block['exercises'] is List) ? List.from(block['exercises']) : const [];
          for (final exRaw in exs) {
            if (exRaw is! Map) continue;
            final ex = Map<String, dynamic>.from(exRaw);
            final name = normalizeExerciseName(ex['name']);
            final sets = (ex['series'] is num) ? (ex['series'] as num).toDouble() : 0.0;
            if (name.isEmpty || sets <= 0) continue;

            final key = "name:${_norm(name)}";
            out.add(_DayPlannedItem(
              key: key,
              name: name,
              blockLabel: label,
              plannedVol: sets,
            ));
          }
        }

        // CIRCUITO: block['rounds'] y exercises con name
        if (type == 'Circuito') {
          final rounds = (block['rounds'] is num) ? (block['rounds'] as num).toDouble() : 0.0;
          final exs = (block['exercises'] is List) ? List.from(block['exercises']) : const [];
          if (rounds <= 0) continue;

          for (final exRaw in exs) {
            if (exRaw is! Map) continue;
            final ex = Map<String, dynamic>.from(exRaw);
            final name = normalizeExerciseName(ex['name']);
            if (name.isEmpty) continue;

            final key = "name:${_norm(name)}";
            out.add(_DayPlannedItem(
              key: key,
              name: name,
              blockLabel: label,
              plannedVol: rounds, // 1 por ronda
            ));
          }
        }

        // TABATA: block['rounds'] y exercises con name
        if (type == 'Tabata') {
          final rounds = (block['rounds'] is num) ? (block['rounds'] as num).toDouble() : 1.0;
          final exs = (block['exercises'] is List) ? List.from(block['exercises']) : const [];
          for (final exRaw in exs) {
            if (exRaw is! Map) continue;
            final ex = Map<String, dynamic>.from(exRaw);
            final name = normalizeExerciseName(ex['name']);
            if (name.isEmpty) continue;

            final key = "name:${_norm(name)}";
            out.add(_DayPlannedItem(
              key: key,
              name: name,
              blockLabel: label,
              plannedVol: rounds, // si prefieres 1 por tabata, cambia rounds -> 1.0
            ));
          }
        }
      }

      return out;
    }

    // Construir plannedByDay
    for (final p in plannedDocs) {
      final ts = p['date'] as Timestamp?;
      if (ts == null) continue;
      final day = _dayKey(ts.toDate());

      final routineId = (p['routineId'] ?? '').toString();
      if (routineId.isEmpty) continue;

      Map<String, dynamic> routine;
      if (routineCache.containsKey(routineId)) {
        routine = routineCache[routineId]!;
      } else {
        final rDoc = await FirebaseFirestore.instance.collection('routines').doc(routineId).get();
        routine = (rDoc.data() ?? {});
        routineCache[routineId] = routine;
      }

      final items = _extractPlannedItemsFromRoutine(routine);
      plannedByDay.putIfAbsent(day, () => []).addAll(items);
    }

    // =========================
    // 2) Traer realizados (workouts_logged)
    // =========================
    final performedSnap = await FirebaseFirestore.instance
        .collection('workouts_logged')
        .where('userId', isEqualTo: selectedAthleteId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
        .where('date', isLessThan: Timestamp.fromDate(endOfWeek))
        .get();

    final performedDocs = performedSnap.docs.map((d) => d.data()).toList();

    final Map<String, double> doneWeekByKey = {};

    void addDone(String name, double vol) {
      if (name.trim().isEmpty || vol <= 0) return;
      final key = "name:${_norm(name)}";
      doneWeekByKey[key] = (doneWeekByKey[key] ?? 0) + vol;
    }

    for (final w in performedDocs) {
      final performed = w['performed'];
      if (performed is! List) continue;

      for (final it in performed) {
        if (it is! Map) continue;
        final e = Map<String, dynamic>.from(it);
        final type = (e['type'] ?? '').toString();

        if (type == 'Series') {
          final name = normalizeExerciseName(e['exercise']);
          final sets = (e['sets'] is List) ? (e['sets'] as List).length.toDouble() : 0.0;
          addDone(name, sets);
        }

        if (type == 'Circuito') {
          final rounds = (e['rounds'] is List) ? (e['rounds'] as List) : const [];
          if (rounds.isEmpty) continue;

          // contar 1 por ronda por ejercicio
          final Map<String, int> count = {};
          for (final r in rounds) {
            if (r is! Map) continue;
            final rm = Map<String, dynamic>.from(r);
            final exs = (rm['exercises'] is List) ? (rm['exercises'] as List) : const [];
            for (final ex in exs) {
              if (ex is! Map) continue;
              final exm = Map<String, dynamic>.from(ex);
              final name = normalizeExerciseName(exm['exercise']);
              if (name.isEmpty) continue;
              final k = _norm(name);
              count[k] = (count[k] ?? 0) + 1;
            }
          }
          count.forEach((k, v) => addDone(k, v.toDouble()));
        }

        if (type == 'Tabata') {
          final rounds = (e['rounds'] is num) ? (e['rounds'] as num).toDouble() : 1.0;
          final exs = (e['exercises'] is List) ? (e['exercises'] as List) : const [];
          for (final ex in exs) {
            if (ex is! Map) continue;
            final exm = Map<String, dynamic>.from(ex);
            final name = normalizeExerciseName(exm['exercise']);
            addDone(name, rounds); // si quieres 1 en vez de rounds -> 1.0
          }
        }
      }
    }

    // =========================
    // 3) Asignación “bolsa semanal” -> días planificados
    //    (cumple día1 aunque lo hayas hecho otro día)
    // =========================
    final remaining = Map<String, double>.from(doneWeekByKey);

    // Ordenar días
    final dayKeys = plannedByDay.keys.toList()..sort();

    // dayResults[day] = items con achieved/missing + bloque
    final Map<String, List<_DayResultItem>> dayResults = {};

    double totalPlanned = 0;
    double totalAchieved = 0;

    for (final day in dayKeys) {
      final items = plannedByDay[day]!;
      final results = <_DayResultItem>[];

      // agrupar por (exerciseKey + blockLabel) para que el bloque aparezca bien
      for (final it in items) {
        totalPlanned += it.plannedVol;

        final avail = remaining[it.key] ?? 0.0;
        final achieved = (avail >= it.plannedVol) ? it.plannedVol : avail;

        remaining[it.key] = (avail - achieved).clamp(0, double.infinity);
        totalAchieved += achieved;

        results.add(_DayResultItem(planned: it, achieved: achieved));
      }

      // ordenar: primero lo que falta
      results.sort((a, b) {
        final ma = a.missing;
        final mb = b.missing;
        if (ma == 0 && mb > 0) return 1;
        if (ma > 0 && mb == 0) return -1;
        return a.planned.name.compareTo(b.planned.name);
      });

      dayResults[day] = results;
    }

    // Extras (lo que sobró en la bolsa semanal)
    final extraTotal = remaining.values.fold<double>(0.0, (s, v) => s + v);

    final percent = totalPlanned == 0 ? 0.0 : (totalAchieved / totalPlanned);

    // cerrar loading
    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    // =========================
    // 4) UI (dialog con secciones por día)
    // =========================
    // Construir extras para la pestaña ➕
final extrasList = remaining.entries
    .where((e) => e.value > 0)
    .map((e) => {
          'key': e.key,
          'name': e.key.startsWith('name:')
              ? e.key.substring(5)
              : e.key,
          'volume': e.value,
        })
    .toList()
  ..sort((a, b) => (b['volume'] as double).compareTo(a['volume'] as double));

// Día seleccionado por defecto: primer día con planificación, o lunes
String initialDay = dayKeys.isNotEmpty ? dayKeys.first : _dayKey(startOfWeek);
String selectedDayKey = dayKeys.isNotEmpty ? dayKeys.first : _dayKey(startOfWeek);

showDialog(
  context: context,
  builder: (_) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
  constraints: BoxConstraints(
    maxWidth: 900,
    maxHeight: MediaQuery.of(context).size.height * 0.90, // ✅ evita overflow
  ),
  child: StatefulBuilder(
          builder: (context, setLocal) {

            List<_DayResultItem> dayItems() =>
                (dayResults[selectedDayKey] ?? const []);

            List<_DayResultItem> okItems() =>
                dayItems().where((x) => x.missing <= 0).toList();

            List<_DayResultItem> missingItems() =>
                dayItems().where((x) => x.missing > 0).toList();

            // contadores del día (para mostrar en subtitle si quieres)
            double plannedDayVol(List<_DayResultItem> items) =>
                items.fold(0, (s, r) => s + r.planned.plannedVol);
            double achievedDayVol(List<_DayResultItem> items) =>
                items.fold(0, (s, r) => s + r.achieved);

            final dayPlanned = plannedDayVol(dayItems());
            final dayAchieved = achievedDayVol(dayItems());
            final dayMissing = (dayPlanned - dayAchieved).clamp(0, double.infinity);

            return DefaultTabController(
              length: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // =======================
                    // HEADER (TÍTULO + DROPDOWN DÍA)
                    // =======================
                    Wrap(
  alignment: WrapAlignment.spaceBetween,
  crossAxisAlignment: WrapCrossAlignment.center,
  runSpacing: 8,
  children: [
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Text(
        "Semana (${_dayKey(startOfWeek)} → ${_dayKey(endOfWeek.subtract(const Duration(days: 1)))})",
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        overflow: TextOverflow.ellipsis,
      ),
    ),

    DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedDayKey,
        isDense: true,
        items: (dayKeys.isNotEmpty ? dayKeys : [initialDay])
            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setLocal(() {
            selectedDayKey = v;
            initialDay = v;
          });
        },
      ),
    ),
  ],
),

                    const SizedBox(height: 6),

                    // pequeña línea resumen del día seleccionado
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Día: Plan ${dayPlanned.toStringAsFixed(0)} • Hecho ${dayAchieved.toStringAsFixed(0)} • Falta ${dayMissing.toStringAsFixed(0)}",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // =======================
                    // MÉTRICAS ARRIBA EN 1 FILA (SCROLL HORIZONTAL)
                    // =======================
                    SizedBox(
                      height: 58,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          SizedBox(
                            width: 210,
                            child: _MetricTile(
                              label: "Consecución (volumen)",
                              value: "${(percent * 100).toStringAsFixed(0)}%",
                              icon: Icons.percent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 210,
                            child: _MetricTile(
                              label: "Vol. planificado",
                              value: totalPlanned.toStringAsFixed(0),
                              icon: Icons.event_note,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 210,
                            child: _MetricTile(
                              label: "Vol. logrado (del plan)",
                              value: totalAchieved.toStringAsFixed(0),
                              icon: Icons.check_circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 210,
                            child: _MetricTile(
                              label: "Extras semana",
                              value: extraTotal.toStringAsFixed(0),
                              icon: Icons.add_task,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // =======================
                    // TABS
                    // =======================
                    TabBar(
                      tabs: [
                        Tab(text: "OK (${okItems().length})"),
                        Tab(text: "Falta (${missingItems().length})"),
                        Tab(text: "Extras (${extrasList.length})"),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // =======================
                    // TAB CONTENT
                    // =======================
                    Expanded(
  child: TabBarView(
    children: [
                          // ========= TAB OK =========
                          _buildDayList(
                            context,
                            items: okItems(),
                            emptyText: "Nada OK para este día (o no hay planificación).",
                          ),

                          // ========= TAB FALTA =========
                          _buildDayList(
                            context,
                            items: missingItems(),
                            emptyText: "Nada pendiente 🎉",
                            showMissing: true,
                          ),

                          // ========= TAB EXTRAS =========
                          _buildExtrasList(
                            context,
                            extrasList: extrasList,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cerrar"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  },
);
  } catch (e) {
    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text("No pude generar la revisión semanal.\n\n$e"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}

Widget _buildDayList(
  BuildContext context, {
  required List<_DayResultItem> items,
  required String emptyText,
  bool showMissing = false,
}) {
  if (items.isEmpty) {
    return Center(
      child: Text(
        emptyText,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }

  return ListView.separated(
    itemCount: items.length,
    separatorBuilder: (_, __) => Divider(color: Colors.grey.shade300, height: 1),
    itemBuilder: (_, i) {
      final r = items[i];
      final missing = r.missing;

      return ListTile(
        dense: true,
        leading: Icon(
          showMissing ? Icons.cancel_outlined : Icons.check_circle_outline,
        ),
        title: Text(r.planned.name),
        subtitle: Text(
          "${r.planned.blockLabel}\n"
          "Plan: ${r.planned.plannedVol.toStringAsFixed(0)} • "
          "Hecho: ${r.achieved.toStringAsFixed(0)}"
          "${showMissing ? " • Falta: ${missing.toStringAsFixed(0)}" : ""}",
        ),
        isThreeLine: true,
      );
    },
  );
}

Widget _buildExtrasList(
  BuildContext context, {
  required List<Map<String, dynamic>> extrasList,
}) {
  if (extrasList.isEmpty) {
    return Center(
      child: Text(
        "No hay extras esta semana.",
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }

  return ListView.separated(
    itemCount: extrasList.length,
    separatorBuilder: (_, __) => Divider(color: Colors.grey.shade300, height: 1),
    itemBuilder: (_, i) {
      final e = extrasList[i];
      final name = (e['name'] ?? '').toString();
      final vol = (e['volume'] as double);

      return ListTile(
        dense: true,
        leading: const Icon(Icons.add_task),
        title: Text(name),
        subtitle: Text("Volumen extra: ${vol.toStringAsFixed(0)}"),
      );
    },
  );
}


  // ====================================================
  // UI
  // ====================================================
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final d = _selectedDay!;

    return Scaffold(
      appBar: AppBar(
  title: Text(
    role == 'administrador'
        ? "Planificando a $selectedAthleteName"
        : "Mi planificación",
  ),
  actions: [

  // 🔁 Cambiar atleta (solo admin)
  if (role == 'administrador')
    IconButton(
      icon: const Icon(Icons.switch_account),
      tooltip: "Cambiar atleta",
      onPressed: () async {
        await _selectAthlete();

        if (selectedAthleteId != null) {
          setState(() {
            _loading = true;
          });

          await _loadRoutines();
          await _loadPlannedForDay(_selectedDay!);

          setState(() {
            _loading = false;
          });
        }
      },
    ),

  // 📊 Ver carga semanal
  IconButton(
    icon: const Icon(Icons.analytics),
    tooltip: "Carga semanal",
    onPressed: () {
      if (selectedAthleteId == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeeklyLoadScreen(
            athleteId: selectedAthleteId!,
            initialDate: _selectedDay ?? DateTime.now(),
          ),
        ),
      );
    },
  ),
  IconButton(
  icon: const Icon(Icons.fact_check),
  tooltip: "Revisión semanal",
  onPressed: () async {
  if (selectedAthleteId == null) return;
  await _reviewWeekDetailedByDay(); // 👈
},
),
],

),
      body: Column(
        children: [
          TableCalendar(
  firstDay: DateTime.utc(2020),
  lastDay: DateTime.utc(2030),
  focusedDay: _focusedDay,

  // 👇 ESTO AGREGA
  startingDayOfWeek: StartingDayOfWeek.monday,

  selectedDayPredicate: (day) =>
      isSameDay(_selectedDay, day),

  onDaySelected: (selected, focused) {
  final normalized = _normalizeDayLocal(selected);
  

  setState(() {
    _selectedDay = normalized;
    _focusedDay = focused;
  });

  _loadPlannedForDay(normalized);
},
),

          const SizedBox(height: 12),
          Expanded(
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        

        // 🔥 Día seleccionado visible
        Text(
          "Día seleccionado:",
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 4),
        

        
Text(
  "${d.year.toString().padLeft(4,'0')}-"
  "${d.month.toString().padLeft(2,'0')}-"
  "${d.day.toString().padLeft(2,'0')}",
),

        const SizedBox(height: 16),

        if (_plannedWorkouts.isEmpty) ...[
          const Text(
            "Este día no tiene entrenamiento planificado.",
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (role == 'administrador')
  ElevatedButton.icon(
    onPressed: _createPlannedWorkout,
    icon: const Icon(Icons.add),
    label: const Text("Asignar rutina"),
  ),

        ] else ...[
          const Text(
            "Rutinas asignadas:",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
  itemCount: _plannedWorkouts.length,
  itemBuilder: (context, index) {
    final w = _plannedWorkouts[index];
    final isExpanded = _expandedWorkoutId == w['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [

          // =========================
          // HEADER
          // =========================
          ListTile(
            title: Text(
              w['routineTitle'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [

                if (role == 'administrador')
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteWorkout(w['id']),
                  ),

                Icon(
                  isExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
              ],
            ),
            onTap: () async {

              if (isExpanded) {
                setState(() {
                  _expandedWorkoutId = null;
                });
                return;
              }

              // Cargar rutina si no está en cache
              if (!_routineCache.containsKey(w['routineId'])) {
                final routineDoc = await FirebaseFirestore.instance
                    .collection('routines')
                    .doc(w['routineId'])
                    .get();

                _routineCache[w['routineId']] = routineDoc;
              }

              setState(() {
                _expandedWorkoutId = w['id'];
              });
            },
          ),

          // =========================
          // CONTENIDO EXPANDIDO
          // =========================
          if (isExpanded)
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: RoutineView(
      routine: _routineCache[w['routineId']]!.data() 
          as Map<String, dynamic>,
      compact: true, // 👈 importante para Planning
    ),
  ),

        ],
      ),
    );
  },
),
          ),
        ],
      ],
    ),
  ),
),

        ],
      ),
    );
  }
}
