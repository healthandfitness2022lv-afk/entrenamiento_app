import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'progress_screen.dart';
import 'exercises_screen.dart';
import 'routines_screen.dart';
import 'assign_routine_screen.dart';
import 'log_workout_screen.dart';
import 'planning_screen.dart';
import 'my_workouts_screen.dart';
import 'profile_screen.dart';
import '../services/workout_volume_service.dart';



class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late Future<Map<String, dynamic>> _statsFuture;

  

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide =
        Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(_fade);
    _controller.forward();
    _statsFuture = _loadStats();

  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  Future<Map<String, String>> _getUserInfo() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final snap =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

  final data = snap.data() ?? {};

  return {
    'role': data['role'] ?? 'athlete',
    'name': data['name'] ?? 'Atleta',
  };
}

Future<Map<String, dynamic>> _loadStats() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;

  // =========================
  // 🔹 SESIONES + VOLUMEN
  // =========================
  final workoutsSnap = await FirebaseFirestore.instance
      .collection('workouts_logged')
      .where('userId', isEqualTo: uid)
      .get();

  final sessions = workoutsSnap.docs.length;

  double totalVolume = 0;

for (final doc in workoutsSnap.docs) {
  final data = doc.data();

  final performed =
      List<Map<String, dynamic>>.from(data['performed'] ?? []);

  totalVolume +=
      WorkoutVolumeService.calculateWorkoutVolume(performed);
}



  // =========================
  // 🔹 FATIGA GENERAL
  // =========================
  final userDoc = await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .get();

final fatigue =
    (userDoc.data()?['globalFatigue'] ?? 0).toDouble();


  return {
    'sessions': sessions,
    'volume': totalVolume,
    'fatigue': fatigue,
  };
}



  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>
(      future: _getUserInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data!['role']!;
final name = snapshot.data!['name']!;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Colors.tealAccent.shade700,
            icon: const Icon(Icons.play_arrow, color: Colors.black),
            label: const Text(
              "Entrenar ahora",
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const LogWorkoutScreen()),
  );

  if (!mounted) return;

setState(() {
  _statsFuture = _loadStats();
});
},

          ),

          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ================= HEADER =================
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Hola, $name 👋",
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                 

                                ],
                              ),
                            ),
                            IconButton(
  icon: const Icon(Icons.person_outline,
      color: Colors.white, size: 30),
  onPressed: () async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ProfileScreen()),
  );

  if (!mounted) return;

  setState(() {
    _statsFuture = _loadStats();
  });
},

),

                          ],
                        ),

                        const SizedBox(height: 20),

                        // ================= STATS =================
                        FutureBuilder<Map<String, dynamic>>(
  future: _statsFuture, // ✅ USAR EL FUTURE
  builder: (context, snapshot) {
    if (!snapshot.hasData) {
      return Row(
        children: const [
          _StatCard("Sesiones", "—"),
          _StatCard("Volumen", "—"),
          _StatCard("Fatiga", "—"),
        ],
      );
    }

    final data = snapshot.data!;

    return Row(
      children: [
        _StatCard("Sesiones", data['sessions'].toString()),
        _StatCard(
          "Volumen",
          "${(data['volume'] / 1000).toStringAsFixed(1)}k",
        ),
        _StatCard(
          "Fatiga",
          "${data['fatigue'].toStringAsFixed(2)}%",
        ),
      ],
    );
  },
),



                        const SizedBox(height: 10),

                        // ================= LISTA =================
                        Expanded(
                          child: ListView(
                            physics: const BouncingScrollPhysics(),
                            children: [
                              _HomeCard(
                                icon: Icons.history,
                                title: "Mis entrenamientos",
                                subtitle: "Historial y análisis",
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const MyWorkoutsScreen(),
                                    ),
                                  );
                                },
                              ),

                              _HomeCard(
                                icon: Icons.bar_chart_rounded,
                                title: "Progreso",
                                subtitle: "Carga, volumen y fatiga",
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ProgressScreen(),
                                    ),
                                  );
                                },
                              ),

                              const _SectionTitle("Gestión"),

                              _HomeCard(
                                icon: Icons.fitness_center,
                                title: "Ejercicios",
                                subtitle: "Catálogo",
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ExercisesScreen(),
                                    ),
                                  );
                                },
                              ),

                              _HomeCard(
                                icon: Icons.fitness_center,
                                title: "Planificación",
                                subtitle: "Planifica tus entrenamientos",
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PlanningScreen(),
                                    ),
                                  );
                                },
                              ),

                              _HomeCard(
                                icon: Icons.view_list,
                                title: "Rutinas",
                                subtitle: "Planes disponibles",
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const RoutinesScreen(),
                                    ),
                                  );
                                },
                              ),

                              if (role == 'administrador')
                                _HomeCard(
                                  icon: Icons.assignment_ind,
                                  title: "Asignar rutinas",
                                  subtitle: "Gestiona atletas",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AssignRoutineScreen(),
                                      ),
                                    );
                                  },
                                ),

                              const SizedBox(height: 16),

                              Center(
                                child: TextButton.icon(
                                  icon: const Icon(Icons.logout,
                                      color: Colors.white70),
                                  label: const Text(
                                    "Cerrar sesión",
                                    style:
                                        TextStyle(color: Colors.white70),
                                  ),
                                  onPressed: () async {
                                    await FirebaseAuth.instance.signOut();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ================= COMPONENTES =================

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
