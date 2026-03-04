import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_set.dart';
import '../models/muscle_catalog.dart';
import '../utils/exercise_catalogs.dart';
import '../widgets/body_heatmap.dart';
import '../utils/svg_utils.dart';
import '../services/workout_load_service.dart';
import '../utils/rpe_factor.dart';
import 'log_workout_screen.dart';
import '../utils/workout_rpe_utils.dart';

// ─────────────────────────────────────────────────────────
// PALETA DARK ENERGIZER (Alineada con main.dart)
// ─────────────────────────────────────────────────────────
const _kBg = Color(0xFF121212);
const _kSurface = Color(0xFF1B1B1B);
const _kSurface2 = Color(0xFF222222);
const _kAccent = Color(0xFF39FF14); // Verde Neón
const _kAccentSoft = Color(0xFF2ECC71); // Verde Secundario
const _kTextPrimary = Color(0xFFF5F5F5);
const _kTextSecondary = Color(0xFFB8B8B8);
const _kDivider = Color(0xFF2A2A2A);

const _kSeriesColor = Color(0xFF39FF14);
const _kCircuitoColor = Colors.orangeAccent;
const _kTabataColor = Colors.redAccent;

class MyWorkoutDetailsScreen extends StatefulWidget {
  final DocumentSnapshot workout;

  const MyWorkoutDetailsScreen({super.key, required this.workout});

  @override
  State<MyWorkoutDetailsScreen> createState() => _MyWorkoutDetailsScreenState();
}

class _MyWorkoutDetailsScreenState extends State<MyWorkoutDetailsScreen>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> workoutData;
  late List<Map<String, dynamic>> performed;
  Map<Muscle, double> centralizedLoad = {};
  final Map<Muscle, double> circuitAcc = {};

  bool loading = true;

  final Map<String, Map<String, dynamic>> exercisesMap = {};

  int totalSets = 0;
  int totalVolume = 0;
  double avgRpe = 0;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ======================================================
  // 🚀 INIT
  // ======================================================
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    workoutData = widget.workout.data() as Map<String, dynamic>;
    performed = List<Map<String, dynamic>>.from(workoutData['performed']);
    _loadAndCalculate();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ======================================================
  // 🔄 LOAD & CALCULATE
  // ======================================================
  Future<void> _loadAndCalculate() async {
    await _loadExercises();
    _calculateStats();

    centralizedLoad = await WorkoutLoadService.calculateLoadFromWorkout(
      workoutData,
    );

    setState(() => loading = false);
    _fadeCtrl.forward();
  }

  void _calculateStats() {
    totalSets = 0;
    totalVolume = 0;

    for (final e in performed) {
      if (e['type'] == 'Series' ||
          e['type'] == 'Series descendentes' ||
          e['type'] == 'Buscar RM') {
        final exercises =
            List<Map<String, dynamic>>.from(e['exercises'] ?? []);

        for (final ex in exercises) {
          final sets =
              List<Map<String, dynamic>>.from(ex['sets'] ?? []);

          for (final s in sets) {
            if (s.containsKey('done') && s['done'] != true) continue;

            totalSets++;

            final double weight = (s['weight'] as num?)?.toDouble() ?? 0;
            final int reps = (s['reps'] as num?)?.toInt() ?? 0;
            final bool perSide = s['perSide'] == true;
            final double effectiveWeight = perSide ? weight * 2 : weight;

            if (reps > 0 && effectiveWeight > 0) {
              totalVolume += (effectiveWeight * reps).round();
            }
          }
        }
      }

      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final ex in round['exercises'] ?? []) {
            totalSets++;

            final double weight =
                (ex['weight'] as num?)?.toDouble() ?? 0;
            final int reps = (ex['reps'] as num?)?.toInt() ?? 0;
            final bool perSide = ex['perSide'] == true;
            final double effectiveWeight = perSide ? weight * 2 : weight;

            if (reps > 0 && effectiveWeight > 0) {
              totalVolume += (effectiveWeight * reps).round();
            }
          }
        }
      }

      if (e['type'] == 'Tabata') {
        for (final _ in e['exercises'] ?? []) {
          totalSets++;
        }
      }
    }

    avgRpe = calculateAverageWorkoutRPE(performed);
  }

  // ======================================================
  // 🔎 CARGAR EJERCICIOS
  // ======================================================
  Future<void> _loadExercises() async {
    final Set<String> names = {};

    for (final e in performed) {
      if (e['type'] == 'Series' ||
          e['type'] == 'Series descendentes' ||
          e['type'] == 'Buscar RM') {
        for (final ex in e['exercises'] ?? []) {
          names.add(ex['exercise']);
        }
      }
      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final ex in round['exercises'] ?? []) {
            names.add(ex['exercise']);
          }
        }
      }
      if (e['type'] == 'Tabata') {
        for (final ex in e['exercises'] ?? []) {
          names.add(ex['exercise']);
        }
      }
    }

    if (names.isEmpty) return;

    final snap = await FirebaseFirestore.instance
        .collection('exercises')
        .where('name', whereIn: names.toList())
        .get();

    for (final d in snap.docs) {
      exercisesMap[d['name']] = d.data();
    }
  }

  // ======================================================
  // 🧠 RESOLVER MÚSCULOS
  // ======================================================
  Map<Muscle, double> _resolveMuscles(List<String> muscleNames) {
    final Map<Muscle, double> result = {};

    for (final name in muscleNames) {
      final mapping = normalizedMuscleCatalogMap[normalizeKey(name)];

      if (mapping == null) {
        debugPrint("❌ Músculo no mapeado: $name");
        continue;
      }

      mapping.forEach((muscle, weight) {
        result[muscle] = (result[muscle] ?? 0) + weight;
      });
    }

    return result;
  }

  // ======================================================
  // 🧱 CONSTRUIR WorkoutSet PARA HEATMAP
  // ======================================================
  List<WorkoutSet> _buildWorkoutSetsForHeatmap() {
    final List<WorkoutSet> result = [];

    for (final e in performed) {
      if (e['type'] == 'Series' ||
          e['type'] == 'Series descendentes' ||
          e['type'] == 'Buscar RM') {
        for (final exEntry in e['exercises']) {
          final String name = exEntry['exercise'];
          final ex = exercisesMap[name];
          if (ex == null) continue;

          final muscleWeights = _resolveMuscleWeightsFromExercise(ex);
          final setsList =
              List<Map<String, dynamic>>.from(exEntry['sets'] ?? []);

          for (int i = 0; i < setsList.length; i++) {
            final s = setsList[i];
            if (s.containsKey('done') && s['done'] != true) continue;

            result.add(
              WorkoutSet(
                exercise: name,
                sets: 1,
                reps: (s['reps'] as num?)?.toInt() ?? 1,
                rpe: (s['rpe'] as num).toDouble(),
                weight: (s['weight'] as num?)?.toDouble(),
                perSide: s['perSide'] == true,
                setIndex: i + 1,
                muscleWeights: muscleWeights,
                sourceType: 'Series',
              ),
            );
          }
        }
      }

      if (e['type'] == 'Tabata') {
        for (final exEntry in e['exercises'] ?? []) {
          final String name = exEntry['exercise'];
          final ex = exercisesMap[name];
          if (ex == null) continue;

          final muscleWeights = _resolveMuscleWeightsFromExercise(ex);

          result.add(
            WorkoutSet(
              exercise: name,
              sets: 1,
              reps: 1,
              rpe: (exEntry['rpe'] as num).toDouble(),
              muscleWeights: muscleWeights,
              sourceType: 'Tabata',
            ),
          );
        }
      }

      if (e['type'] == 'Circuito') {
        for (final round in e['rounds'] ?? []) {
          for (final exEntry in round['exercises'] ?? []) {
            final String name = exEntry['exercise'];
            final ex = exercisesMap[name];
            if (ex == null) continue;

            final muscleWeights = _resolveMuscleWeightsFromExercise(ex);
            final int reps = (exEntry['reps'] as num?)?.toInt() ?? 1;

            result.add(
              WorkoutSet(
                exercise: name,
                sets: 1,
                reps: reps,
                rpe: (exEntry['rpe'] as num).toDouble(),
                weight: exEntry['weight'] == null
                    ? null
                    : (exEntry['weight'] as num).toDouble(),
                perSide: exEntry['perSide'] == true,
                muscleWeights: muscleWeights,
                sourceType: 'Circuito',
              ),
            );
          }
        }
      }
    }

    return result;
  }

  Map<Muscle, double> _resolveMuscleWeightsFromExercise(
    Map<String, dynamic> ex,
  ) {
    final Map<Muscle, double> result = {};
    final raw = ex['muscleWeights'];

    if (raw is Map && raw.isNotEmpty) {
      raw.forEach((k, v) {
        final key = k.toString();
        final value = (v as num).toDouble();
        final match = Muscle.values.where((m) => m.name == key).toList();
        if (match.isNotEmpty) {
          result[match.first] = (result[match.first] ?? 0) + value;
        }
      });
      return result;
    }

    final muscleNames = <String>[
      ex['primaryMuscle'],
      ...?ex['secondaryMuscles'],
    ];
    return _resolveMuscles(muscleNames);
  }

  // ======================================================
  // HELPERS
  // ======================================================
  Color _sourceColor(String type) {
    switch (type) {
      case 'Circuito':
        return _kCircuitoColor;
      case 'Tabata':
        return _kTabataColor;
      default:
        return _kSeriesColor;
    }
  }

  IconData _sourceIcon(String type) {
    switch (type) {
      case 'Circuito':
        return Icons.loop_rounded;
      case 'Tabata':
        return Icons.timer_rounded;
      default:
        return Icons.fitness_center_rounded;
    }
  }

  double _structureFactor(WorkoutSet s) {
    switch (s.sourceType) {
      case 'Circuito':
        return 1.3;
      case 'Tabata':
        return 2.5;
      default:
        return 1.0;
    }
  }

  void _editWorkout() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LogWorkoutScreen(
          existingWorkout: workoutData,
          workoutRef: widget.workout.reference,
        ),
      ),
    );

    setState(() => loading = true);
    workoutData = widget.workout.data() as Map<String, dynamic>;
    performed = List<Map<String, dynamic>>.from(workoutData['performed']);
    _loadAndCalculate();
  }

  double _calculateSessionFatiguePercent() {
    final values = centralizedLoad.values.where((v) => v > 10).toList();
    if (values.isEmpty) return 0;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (avg / 100 * 100).clamp(0, 100);
  }

  double _calculateNeuralLoad() {
    double neuralAcc = 0;
    for (final e in performed) {
      final type = e['type'] ?? 'Series';
      if (type == 'Series' || type == 'Series descendentes' || type == 'Buscar RM') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        for (final ex in exercises) {
          final exData = exercisesMap[ex['exercise']];
          if (exData == null) continue;
          final String exType = exData['exerciseType'] ?? '';
          final double typeMult = (exType == 'Fuerza' || exType == 'weightlifting') ? 1.5 : 1.0;
          final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
          for (final s in sets) {
            final double rpe = (s['rpe'] as num?)?.toDouble() ?? 5;
            // El estrés neural crece exponencialmente con el RPE alto
            final double neuralSNC = rpe >= 9 ? 2.5 : (rpe >= 7 ? 1.2 : 0.5);
            neuralAcc += neuralSNC * typeMult;
          }
        }
      }
    }
    return neuralAcc;
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ======================================================
  // 🖥 UI PRINCIPAL
  // ======================================================
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(
          child: CircularProgressIndicator(color: _kAccent),
        ),
      );
    }

    final workoutSets = _buildWorkoutSetsForHeatmap();
    final heatmap = centralizedLoad;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text("ANÁLISIS DE ENTRENAMIENTO"),
        backgroundColor: _kBg,
        elevation: 0,
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 700;
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _header(),
                const SizedBox(height: 24),

                // ─── HEATMAP SECTION ───────────────────────────────
                _heatmapSection(heatmap, isMobile),

                const SizedBox(height: 24),

                // ─── STATS ROW ─────────────────────────────────────
                _statsRow(),

                const SizedBox(height: 32),

                // ─── DETALLE ───────────────────────────────────────
                _workoutDetailCompact(workoutSets),
                
                const SizedBox(height: 60),
              ],
            );
          },
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  // 🔝 HEADER
  // ──────────────────────────────────────────────────────
  Widget _header() {
    final sessionFatigue = _calculateSessionFatiguePercent();
    final date = (workoutData['date'] as Timestamp).toDate();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kDivider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  workoutData['routineName']?.toUpperCase() ?? 'ENTRENAMIENTO',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _kAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: _editWorkout,
                icon: const Icon(Icons.settings_outlined, color: _kAccent, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 12, color: _kAccentSoft),
              const SizedBox(width: 8),
              Text(
                _formatDate(date).toUpperCase(),
                style: const TextStyle(color: _kTextSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Fatiga bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CARGA SISTÉMICA DE LA SESIÓN',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kTextSecondary, letterSpacing: 0.8),
                  ),
                  Text(
                    '${sessionFatigue.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _kAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: sessionFatigue / 100,
                  minHeight: 12,
                  backgroundColor: _kSurface2,
                  valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  // 🔥 HEATMAP (SIEMPRE DUAL)
  // ──────────────────────────────────────────────────────
  Widget _heatmapSection(Map<Muscle, double> heatmap, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.query_stats_rounded, color: _kAccentSoft, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'CATASTRO MUSCULAR',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _kTextPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              _viewLabel('VISTA ANALÍTICA'),
            ],
          ),
          const SizedBox(height: 20),

          // Dual Heatmap
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('FRONTAL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _kTextSecondary, letterSpacing: 1)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: isMobile ? 260 : 300,
                      child: BodyHeatmap(heatmap: heatmap, showBack: false),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 200, color: _kDivider.withOpacity(0.5), margin: const EdgeInsets.symmetric(horizontal: 12)),
              Expanded(
                child: Column(
                  children: [
                    const Text('POSTERIOR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _kTextSecondary, letterSpacing: 1)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: isMobile ? 260 : 300,
                      child: BodyHeatmap(heatmap: heatmap, showBack: true),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _heatmapLegendGradient(),
        ],
      ),
    );
  }

  Widget _viewLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kAccent.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _kAccent),
      ),
    );
  }

  Widget _heatmapLegendGradient() {
    return Column(
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [
                Colors.transparent,
                Color(0xFF4FC3F7), // Celeste
                Color(0xFF1565C0), // Azul
                Color(0xFF39FF14), // Neón
                Color(0xFFD32F2F), // Rojo
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('REPOSO', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _kTextSecondary)),
            Text('FATIGA BALANCEADA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _kTextSecondary)),
            Text('ESTÍMULO MÁXIMO', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _kTextSecondary)),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  // 📊 STATS CARDS
  // ──────────────────────────────────────────────────────
  Widget _statsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.maxWidth / 2 - 10;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _statBox('RPE PROMEDIO', avgRpe.toStringAsFixed(1), Icons.blur_on_rounded, _kAccentSoft, boxW),
            _statBox('SERIES TOTALES', totalSets.toString(), Icons.layers_rounded, _kSeriesColor, boxW),
            _statBox('CARGA NEURAL', _calculateNeuralLoad().toStringAsFixed(0), Icons.psychology_rounded, Colors.purpleAccent, boxW),
            _statBox('EJERCICIOS', exercisesMap.length.toString(), Icons.fitness_center_rounded, _kTabataColor, boxW),
          ],
        );
      },
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _kTextPrimary),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _kTextSecondary, letterSpacing: 1.0),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  // 🔍 DETALLE TÉCNICO
  // ──────────────────────────────────────────────────────
  Widget _workoutDetailCompact(List<WorkoutSet> sets) {
    final Map<String, Map<String, List<WorkoutSet>>> byBlock = {};

    for (final s in sets) {
      byBlock.putIfAbsent(s.sourceType, () => {});
      byBlock[s.sourceType]!.putIfAbsent(s.exercise, () => []);
      byBlock[s.sourceType]![s.exercise]!.add(s);
    }

    final Map<Muscle, double> totalAcc = {};
    final blockOrder = ['Series', 'Circuito', 'Tabata'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            "COMPOSICIÓN DE LA SESIÓN",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: _kAccentSoft),
          ),
        ),
        const SizedBox(height: 20),

        ...blockOrder.map((blockType) {
          if (blockType == 'Circuito') {
            final circuitos = performed.where((e) => e['type'] == 'Circuito').toList();
            if (circuitos.isEmpty) return const SizedBox();

            return Column(
              children: circuitos.asMap().entries.map((entry) {
                final index = entry.key;
                final c = entry.value;
                final Map<Muscle, double> circuitAccLoc = {};
                final rounds = List<Map<String, dynamic>>.from(c['rounds']);

                return _blockLayout(
                  'CIRCUITO ${index + 1}',
                  _kCircuitoColor,
                  Column(
                    children: rounds.map((round) {
                      final int r = round['round'];
                      final exercises = List<Map<String, dynamic>>.from(round['exercises']);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: _kCircuitoColor.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text('RONDA $r', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _kCircuitoColor, letterSpacing: 1)),
                          ),
                          ...exercises.map((ex) {
                            final exData = exercisesMap[ex['exercise']];
                            final double rpe = (ex['rpe'] as num).toDouble();
                            final double fRpe = rpeFactor(rpe);
                            final double exerciseFactor = exerciseTypeFactorOf(exData?['exerciseType']);
                            final tempSet = WorkoutSet(exercise: ex['exercise'], sets: 1, reps: ex['reps'] ?? 1, rpe: rpe, weight: ex['weight']?.toDouble(), muscleWeights: const {}, sourceType: 'Circuito');
                            final double blockF = _structureFactor(tempSet);
                            
                            final Map<Muscle, double> acc = {};
                            if (exData != null) {
                              final muscleWeights = _resolveMuscleWeightsFromExercise(exData);
                              final eqFactor = equipmentFactorOf(exData['equipment']);
                              for (final e in muscleWeights.entries) {
                                final v = rpe * fRpe * exerciseFactor * eqFactor * blockF * e.value;
                                acc[e.key] = (acc[e.key] ?? 0) + v;
                                circuitAccLoc[e.key] = (circuitAccLoc[e.key] ?? 0) + v;
                                totalAcc[e.key] = (totalAcc[e.key] ?? 0) + v;
                              }
                            }

                            return _exerciseItem(
                              name: ex['exercise'],
                              rpe: rpe,
                              details: '${ex['reps'] ?? ex['seconds'] ?? '-'} ${ex['reps'] != null ? 'REPS' : 'S'} · ${ex['weight']?.toStringAsFixed(1) ?? '0'} KG',
                              color: _kCircuitoColor,
                              muscleAcc: acc,
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            );
          }

          final exercises = byBlock[blockType];
          if (exercises == null) return const SizedBox();

          return _blockLayout(
            blockType.toUpperCase(),
            _sourceColor(blockType),
            Column(
              children: exercises.entries.map((entry) {
                final exName = entry.key;
                final groupSets = entry.value;
                final exData = exercisesMap[exName];
                final exerciseFactor = exerciseTypeFactorOf(exData?['exerciseType']);
                final blockF = _structureFactor(groupSets.first);

                final Map<Muscle, double> acc = {};
                final eqFactor = equipmentFactorOf(exData?['equipment']);
                for (final s in groupSets) {
                  final vFactor = s.weight != null ? (s.perSide ? 2.0 : 1.0) : 1.0;
                  for (final e in s.muscleWeights.entries) {
                    final v = s.sets * s.rpe * exerciseFactor * eqFactor * rpeFactor(s.rpe) * blockF * vFactor * e.value;
                    acc[e.key] = (acc[e.key] ?? 0) + v;
                    totalAcc[e.key] = (totalAcc[e.key] ?? 0) + v;
                  }
                }

                return _exerciseItem(
                  name: exName,
                  rpe: groupSets.first.rpe,
                  details: '${groupSets.length} SERIES REALIZADAS',
                  color: _sourceColor(blockType),
                  muscleAcc: acc,
                );
              }).toList(),
            ),
          );
        }),

        if (totalAcc.isNotEmpty) _totalRecap(totalAcc),
      ],
    );
  }

  Widget _blockLayout(String title, Color color, Widget content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: color.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Icon(Icons.token_rounded, color: color, size: 14),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _exerciseItem({required String name, required double rpe, required String details, required Color color, required Map<Muscle, double> muscleAcc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _kTextPrimary, letterSpacing: 0.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text('RPE $rpe', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(details.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _kTextSecondary, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          _muscleChips(muscleAcc),
        ],
      ),
    );
  }

  Widget _muscleChips(Map<Muscle, double> acc) {
    final sorted = acc.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: sorted.take(5).map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _kSurface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kDivider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.key.label.toUpperCase(),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _kTextSecondary),
              ),
              const SizedBox(width: 4),
              Text(
                '+${e.value.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _kAccent),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _totalRecap(Map<Muscle, double> total) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kAccent.withOpacity(0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kSurface,
            _kAccent.withOpacity(0.08),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.analytics_rounded, color: _kAccentSoft, size: 20),
              const SizedBox(width: 10),
              const Text(
                "RESUMEN DE IMPACTO TOTAL",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _kTextPrimary, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _muscleChips(total),
        ],
      ),
    );
  }
}
