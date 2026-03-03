import 'dart:ui';
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(_fade);
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
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

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

      final performed = List<Map<String, dynamic>>.from(
        data['performed'] ?? [],
      );

      totalVolume += WorkoutVolumeService.calculateWorkoutVolume(performed);
    }

    // =========================
    // 🔹 FATIGA GENERAL
    // =========================
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final fatigue = (userDoc.data()?['globalFatigue'] ?? 0).toDouble();

    return {'sessions': sessions, 'volume': totalVolume, 'fatigue': fatigue};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _getUserInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F2027),
            body: Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            ),
          );
        }

        final role = snapshot.data!['role']!;
        final name = snapshot.data!['name']!;

        return Scaffold(
          extendBodyBehindAppBar: true,

          // ================= CALL TO ACTION PRINCIPAL =================
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black87,
            elevation: 8,
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
            icon: const Icon(Icons.play_arrow_rounded, size: 24),
            label: const Text(
              "Entrenar",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),

          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Imagen de fondo con opacidad
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.35,
                    child: Image.asset(
                      'assets/images/home_bg.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            // Reducimos padding inferior para ganar más espacio
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 90),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight - 110,
                              ),
                              child: IntrinsicHeight(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ================= HEADER =================
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Hola, $name 👋",
                                                style: const TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                  letterSpacing: -0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                "¿Listo para romper tus límites?",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.white
                                                      .withOpacity(0.7),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const ProfileScreen(),
                                              ),
                                            );

                                            if (!mounted) return;
                                            setState(() {
                                              _statsFuture = _loadStats();
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.1,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withOpacity(
                                                  0.2,
                                                ),
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.person_outline_rounded,
                                              color: Colors.white,
                                              size: 26,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // ================= STATS =================
                                    const Text(
                                      "Resumen Semanal",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    FutureBuilder<Map<String, dynamic>>(
                                      future: _statsFuture,
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData) {
                                          return const Row(
                                            children: [
                                              _StatCard(
                                                "Sesiones",
                                                "—",
                                                Icons.bolt_rounded,
                                              ),
                                              SizedBox(width: 12),
                                              _StatCard(
                                                "Volumen",
                                                "—",
                                                Icons.fitness_center_rounded,
                                              ),
                                              SizedBox(width: 12),
                                              _StatCard(
                                                "Fatiga",
                                                "—",
                                                Icons.battery_alert_rounded,
                                              ),
                                            ],
                                          );
                                        }

                                        final data = snapshot.data!;
                                        return Row(
                                          children: [
                                            _StatCard(
                                              "Sesiones",
                                              data['sessions'].toString(),
                                              Icons.bolt_rounded,
                                            ),
                                            const SizedBox(width: 8),
                                            _StatCard(
                                              "Volumen",
                                              "${(data['volume'] / 1000).toStringAsFixed(1)}k",
                                              Icons.fitness_center_rounded,
                                            ),
                                            const SizedBox(width: 8),
                                            _StatCard(
                                              "Fatiga",
                                              "${data['fatigue'].toStringAsFixed(0)}%",
                                              Icons.battery_alert_rounded,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 24),

                                    // ================= ACCIONES (GRID) =================
                                    const Text(
                                      "Explorar",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    SizedBox(
                                      width: double.infinity,
                                      child: Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 16,
                                        runSpacing: 24,
                                        children: [
                                          _ActionIcon(
                                            title: "Historial",
                                            icon: Icons.history_rounded,
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
                                          _ActionIcon(
                                            title: "Progreso",
                                            icon: Icons.bar_chart_rounded,
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
                                          _ActionIcon(
                                            title: "Ejercicios",
                                            icon: Icons.monitor_weight_rounded,
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
                                          _ActionIcon(
                                            title: "Planes",
                                            icon: Icons.calendar_month_rounded,
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
                                          _ActionIcon(
                                            title: "Rutinas",
                                            icon: Icons.view_list_rounded,
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
                                            _ActionIcon(
                                              title: "Asignar",
                                              icon:
                                                  Icons.assignment_ind_rounded,
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
                                        ],
                                      ),
                                    ),

                                    const Spacer(), // Empuja el botón hacia abajo
                                    const SizedBox(height: 24),

                                    // ================= LOGOUT =================
                                    Center(
                                      child: TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white60,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              30,
                                            ),
                                            side: BorderSide(
                                              color: Colors.white.withOpacity(
                                                0.1,
                                              ),
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.logout_rounded,
                                          size: 20,
                                        ),
                                        label: const Text(
                                          "Cerrar sesión",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onPressed: () async {
                                          await FirebaseAuth.instance.signOut();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ================= COMPONENTES VISUALES MODERNOS =================

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  const _GlassCard({required this.child, this.onTap, this.padding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.tealAccent.withOpacity(0.1),
            highlightColor: Colors.tealAccent.withOpacity(0.05),
            child: Container(
              padding: padding ?? const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1.5,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.tealAccent, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width:
            100, // 🔹 Ajuste estricto: evita que se expanda a lo loco en tabletas
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: Colors.tealAccent, size: 34),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
