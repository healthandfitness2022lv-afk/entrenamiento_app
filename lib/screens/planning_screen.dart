import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/weekly_load_screen.dart';
import '../screens/routine_details_screen.dart';


class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
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

  String _blockTitle(Map<String, dynamic> block) {
  switch (block['type']) {
    case "Series":
      return "Series";
    case "Circuito":
      return "Circuito · ${block['rounds']} rondas";
    case "EMOM":
      return "EMOM · ${block['time']}s · ${block['rounds']} rondas";
    case "Tabata":
      return "Tabata ${block['work']}/${block['rest']} · ${block['rounds']} rondas";
    default:
      return block['type'] ?? '';
  }
}

IconData _blockIcon(String type) {
  switch (type) {
    case "Series":
      return Icons.fitness_center;
    case "Circuito":
      return Icons.loop;
    case "EMOM":
      return Icons.timer;
    case "Tabata":
      return Icons.flash_on;
    default:
      return Icons.category;
  }
}


  Widget _buildExpandedRoutine(DocumentSnapshot routineDoc) {
  final data = routineDoc.data() as Map<String, dynamic>;
  final blocks =
      List<Map<String, dynamic>>.from(data['blocks'] ?? []);

  return Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const Divider(),

        // 🔥 Nombre rutina
        Text(
          data['name'] ?? '',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 16),

        // 🔥 BLOQUES
        ...blocks.map((block) {
          final exercises =
              List<Map<String, dynamic>>.from(block['exercises'] ?? []);

          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // =============================
                // TÍTULO BLOQUE
                // =============================
                Row(
                  children: [
                    Icon(
                      _blockIcon(block['type']),
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _blockTitle(block),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // =============================
                // CONTENEDOR EJERCICIOS
                // =============================
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    children: exercises
                        .map((e) => _planningExerciseRow(e))
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    ),
  );
}

Widget _planningExerciseRow(Map<String, dynamic> e) {
  final bool perSide = e['perSide'] == true;
  final num weight = (e['weight'] ?? 0);

  String mainValue = "";

  // 🔥 SERIES
  if (e['series'] != null && e['reps'] != null) {
    mainValue = "${e['series']}×${e['reps']} reps";
  }

  // 🔥 TIEMPO / REPS dinámico
  else if (e['value'] != null && e['valueType'] != null) {
    mainValue = e['valueType'] == "time"
        ? "${e['value']} s"
        : "${e['value']} reps";
  }

  final String sideLabel = perSide ? " · por lado" : "";
  final String weightLabel =
      weight > 0 ? " · ${weight}kg" : "";

  final String rightText =
      [mainValue, sideLabel, weightLabel]
          .where((s) => s.isNotEmpty)
          .join("");

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const Icon(
          Icons.play_arrow,
          size: 16,
          color: Colors.grey,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            e['name'] ?? '',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Text(
          rightText,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    ),
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
],

),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2030),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) =>
                isSameDay(_selectedDay, day),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
              _loadPlannedForDay(selected);
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
          "${_selectedDay!.toLocal().toString().split(' ')[0]}",
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
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
            _buildExpandedRoutine(
              _routineCache[w['routineId']]!,
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
