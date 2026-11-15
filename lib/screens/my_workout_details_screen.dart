import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_set.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';
import '../widgets/workout_story_export.dart';
import '../services/workout_load_service.dart';
import '../services/fatigue_recalculation_service.dart';
import '../services/workout_metrics_service.dart';
import '../utils/workout_block_order.dart';
import '../utils/rpe_factor.dart';
import '../utils/variant_resolver.dart';
import '../utils/responsive.dart';
import 'log_workout_screen.dart';
import 'muscle_weight_editor_screen.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────
// PALETA DARK ENERGIZER (Alineada con main.dart)
// ─────────────────────────────────────────────────────────
const _kBg = AppColors.bg;
const _kSurface = AppColors.surface;
const _kSurface2 = AppColors.surface2;
const _kAccent = AppColors.accent; // Verde Neón
const _kAccentSoft = AppColors.accentSoft; // Verde Secundario
const _kTextPrimary = AppColors.textPrimary;
const _kTextSecondary = AppColors.textSecondary;
const _kDivider = AppColors.divider;

const _kSeriesColor = AppColors.accent;
const _kCircuitoColor = AppColors.circuit;
const _kTabataColor = AppColors.tabata;

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
  final Map<String, double> dynamicFactors = {};

  int totalSets = 0;
  int totalVolume = 0;
  double avgRpe = 0;
  bool _exportingStory = false;

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
    _sortPerformedBlocks();
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
    final metrics = WorkoutMetricsService.computeFromPerformed(
      performed,
      onlyDoneSets: true,
    );
    totalSets = metrics.totalSets;
    totalVolume = metrics.totalVolumeKg;
    avgRpe = metrics.avgRpe;
  }

  void _sortPerformedBlocks() {
    performed.sort(comparePerformedBlocks);
  }

  // ======================================================
  // 🔎 CARGAR EJERCICIOS
  // ======================================================
  Future<void> _loadExercises() async {
    final results = await Future.wait([
      WorkoutLoadService.loadExercisesForPerformed(performed),
      WorkoutLoadService.fetchExerciseFolders(),
    ]);
    exercisesMap
      ..clear()
      ..addAll(results[0] as Map<String, Map<String, dynamic>>);
    dynamicFactors
      ..clear()
      ..addAll(results[1] as Map<String, double>);
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

  double _structureFactor(WorkoutSet s) =>
      WorkoutLoadService.structureFactor(s.sourceType);

  void _editWorkout() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LogWorkoutScreen(
              existingWorkout: workoutData,
              workoutRef: widget.workout.reference,
            ),
      ),
    );

    setState(() => loading = true);
    workoutData = widget.workout.data() as Map<String, dynamic>;
    performed = List<Map<String, dynamic>>.from(workoutData['performed']);
    _sortPerformedBlocks();
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
      if (type == 'Series' ||
          type == 'Series descendentes' ||
          type == 'Buscar RM') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        for (final ex in exercises) {
          final exData = exercisesMap[ex['exercise']];
          if (exData == null) continue;
          final String exType = exData['exerciseType'] ?? '';
          final double typeMult =
              (exType == 'Fuerza' || exType == 'weightlifting') ? 1.5 : 1.0;
          final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
          for (final s in sets) {
            final double rpe =
                (s['rpe'] as num?)?.toDouble() ??
                WorkoutLoadService.defaultSeriesRpe;
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
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Normaliza datos antiguos y evita mostrar "Original" cuando el catálogo
  /// solo tiene una variante para ese movimiento.
  String _visibleExerciseName(Map ex) =>
      WorkoutStoryExporter.visibleExerciseName(
        ex,
        exercisesMap[(ex['exercise'] ?? '').toString()],
      );

  Future<void> _exportStoryPng() async {
    if (_exportingStory) return;
    setState(() => _exportingStory = true);
    try {
      await WorkoutStoryExporter(
        workoutData: workoutData,
        centralizedLoad: centralizedLoad,
        nameOf: _visibleExerciseName,
      ).show(context);
    } finally {
      if (mounted) setState(() => _exportingStory = false);
    }
  }

  // ======================================================
  // 🖥 UI PRINCIPAL
  // ======================================================
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }

    final heatmap = centralizedLoad;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text("ANÁLISIS DE ENTRENAMIENTO"),
        backgroundColor: _kBg,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 700;
                return ListView(
                  padding: centeredListPadding(context),
                  children: [
                    _header(),
                    const SizedBox(height: 24),

                    // ─── NOTA DEL ATLETA ───────────────────────────────
                    if ((workoutData['notes'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                      _notesCard(workoutData['notes'].toString().trim()),
                      const SizedBox(height: 24),
                    ],

                    // ─── HEATMAP SECTION ───────────────────────────────
                    _heatmapSection(heatmap, isMobile),

                    const SizedBox(height: 24),

                    // ─── STATS ROW ─────────────────────────────────────
                    _statsRow(),

                    const SizedBox(height: 32),

                    // ─── DETALLE ───────────────────────────────────────
                    _workoutDetailCompact(),

                    const SizedBox(height: 60),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesCard(String notes) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kDivider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sticky_note_2_outlined,
            color: _kAccentSoft,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notes,
              style: const TextStyle(color: _kTextPrimary, fontSize: 14),
            ),
          ),
        ],
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
                  workoutData['sessionName']?.toUpperCase() ??
                      workoutData['routineName']?.toUpperCase() ??
                      'ENTRENAMIENTO',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _kAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Descargar historia',
                onPressed: _exportingStory ? null : _exportStoryPng,
                icon:
                    _exportingStory
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kAccent,
                          ),
                        )
                        : const Icon(
                          Icons.download_rounded,
                          color: _kAccent,
                          size: 22,
                        ),
              ),
              IconButton(
                onPressed: _editWorkout,
                icon: const Icon(
                  Icons.settings_outlined,
                  color: _kAccent,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 12,
                color: _kAccentSoft,
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(date).toUpperCase(),
                style: const TextStyle(
                  color: _kTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
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
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _kTextSecondary,
                      letterSpacing: 0.8,
                    ),
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
                  Icon(
                    Icons.query_stats_rounded,
                    color: _kAccentSoft,
                    size: 20,
                  ),
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
                    const Text(
                      'FRONTAL',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: _kTextSecondary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: isMobile ? 260 : 300,
                      child: BodyHeatmap(heatmap: heatmap, showBack: false),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 200,
                color: _kDivider.withOpacity(0.5),
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'POSTERIOR',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: _kTextSecondary,
                        letterSpacing: 1,
                      ),
                    ),
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
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: _kAccent,
        ),
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
                AppColors.accent, // Neón
                Color(0xFFD32F2F), // Rojo
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              'REPOSO',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: _kTextSecondary,
              ),
            ),
            Text(
              'FATIGA BALANCEADA',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: _kTextSecondary,
              ),
            ),
            Text(
              'ESTÍMULO MÁXIMO',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: _kTextSecondary,
              ),
            ),
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
            _statBox(
              'RPE PROMEDIO',
              avgRpe.toStringAsFixed(1),
              Icons.blur_on_rounded,
              _kAccentSoft,
              boxW,
            ),
            _statBox(
              'SERIES TOTALES',
              totalSets.toString(),
              Icons.layers_rounded,
              _kSeriesColor,
              boxW,
            ),
            _statBox(
              'CARGA NEURAL',
              _calculateNeuralLoad().toStringAsFixed(0),
              Icons.psychology_rounded,
              Colors.purpleAccent,
              boxW,
            ),
            _statBox(
              'EJERCICIOS',
              exercisesMap.length.toString(),
              Icons.fitness_center_rounded,
              _kTabataColor,
              boxW,
            ),
          ],
        );
      },
    );
  }

  Widget _statBox(
    String label,
    String value,
    IconData icon,
    Color color,
    double width,
  ) {
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
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _kTextPrimary,
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: _kTextSecondary,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  void _showFatigueInfoDialog(
    BuildContext context, {
    required double rpe,
    required double fRpe,
    required double exerciseFactor,
    required String exerciseType,
    required double blockF,
    required double totalFatigue,
  }) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: _kSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kDivider),
          ),
          title: Row(
            children: const [
              Icon(
                Icons.local_fire_department,
                color: Colors.deepOrangeAccent,
                size: 24,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CÁLCULO DE FATIGA',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _kTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'La fatiga de esta serie se calculó usando multiplicadores sobre el involucramiento muscular del ejercicio:',
                style: TextStyle(fontSize: 11, color: _kTextSecondary),
              ),
              const SizedBox(height: 16),
              _buildFormulaRow(
                'Esfuerzo Base (RPE)',
                rpe.toStringAsFixed(1),
                'x',
              ),
              _buildFormulaRow(
                'Factor Exponencial RPE',
                fRpe.toStringAsFixed(2),
                'x',
              ),
              _buildFormulaRow(
                'Multiplicador de Ejercicio ($exerciseType)',
                exerciseFactor.toStringAsFixed(2),
                'x',
              ),
              _buildFormulaRow(
                'Multiplicador de Estructura',
                blockF.toStringAsFixed(2),
                '=',
              ),
              const Divider(color: _kDivider, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CARGA TOTAL APORTADA:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: _kTextSecondary,
                    ),
                  ),
                  Text(
                    totalFatigue.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.deepOrangeAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ENTENDIDO',
                style: TextStyle(color: _kAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFormulaRow(String label, String value, String operatorStr) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: _kTextPrimary),
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _kAccentLight,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 10,
                child: Text(
                  operatorStr,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _kTextSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _kAccentLight = Color(
    0xFF67FF4F,
  ); // just a light accent for formula values

  // ──────────────────────────────────────────────────────
  // 🔍 DETALLE TÉCNICO
  // ──────────────────────────────────────────────────────
  Widget _workoutDetailCompact() {
    final Map<Muscle, double> totalAcc = {};
    final List<Widget> blocks = [];

    for (int blockIndex = 0; blockIndex < performed.length; blockIndex++) {
      final e = performed[blockIndex];
      final type = e['type'] ?? 'Series';

      if (type == 'Series' || type == 'Buscar RM') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        final List<Widget> exWidgets = [];

        for (final ex in exercises) {
          final rawExName = ex['exercise'];
          final exName = _visibleExerciseName(ex);
          final exData = exercisesMap[rawExName];

          final Map<Muscle, double> acc = {};
          final setsList = List<Map<String, dynamic>>.from(ex['sets'] ?? []);

          int doneSetsCount = 0;
          final List<Widget> setsBreakdown = [];
          double rpeTotal = 0;

          for (int i = 0; i < setsList.length; i++) {
            final s = setsList[i];
            if (s.containsKey('done') && s['done'] != true) continue;

            doneSetsCount++;
            final double rpe =
                (s['rpe'] as num?)?.toDouble() ??
                WorkoutLoadService.defaultSeriesRpe;
            final double weight = (s['weight'] as num?)?.toDouble() ?? 0.0;
            final int reps = (s['reps'] as num?)?.toInt() ?? 0;
            final bool perSide =
                (ex['perSide'] == true) || (s['perSide'] == true);

            rpeTotal += rpe;
            double setFatigue = 0.0;

            if (exData != null) {
              final muscleWeights =
                  WorkoutLoadService.resolveMuscleWeightsFromExercise(
                    exData,
                    variantId: ex['variantId']?.toString(),
                    variantLabel: ex['variantLabel']?.toString(),
                  );
              final tempSet = WorkoutSet(
                exercise: exName,
                sets: 1,
                reps: reps,
                rpe: rpe,
                weight: weight,
                muscleWeights: muscleWeights,
                sourceType: type,
              );
              final blockF = _structureFactor(tempSet);
              final effectiveFactor = _getEffectiveExerciseFactor(
                exData['exerciseType'],
                weight,
              );

              for (final entry in muscleWeights.entries) {
                final v =
                    1 *
                    rpe *
                    effectiveFactor *
                    rpeFactor(rpe) *
                    blockF *
                    entry.value;
                acc[entry.key] = (acc[entry.key] ?? 0) + v;
                totalAcc[entry.key] = (totalAcc[entry.key] ?? 0) + v;
                setFatigue += v;
              }
            }

            setsBreakdown.add(
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Serie ${i + 1}: $reps reps · ${weight.toStringAsFixed(1)} kg${perSide ? ' (x lado)' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: _kTextSecondary,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'RPE ${rpe.toStringAsFixed(1)}  |  🔥 ${setFatigue.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: _kAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap:
                              () => _showFatigueInfoDialog(
                                context,
                                rpe: rpe,
                                fRpe: rpeFactor(rpe),
                                exerciseFactor: _getEffectiveExerciseFactor(
                                  exData!['exerciseType'],
                                  weight,
                                ),
                                exerciseType: _getEffectiveTypeLabel(
                                  exData['exerciseType'],
                                  weight,
                                ),
                                blockF: _structureFactor(
                                  WorkoutSet(
                                    exercise: exName,
                                    sets: 1,
                                    reps: reps,
                                    rpe: rpe,
                                    weight: weight,
                                    muscleWeights: const {},
                                    sourceType: type,
                                  ),
                                ),
                                totalFatigue: setFatigue,
                              ),
                          child: const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          if (doneSetsCount == 0) continue;

          double avgExRpe = rpeTotal / doneSetsCount;

          exWidgets.add(
            _exerciseItem(
              name: exName,
              rpe: avgExRpe,
              detailsWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: setsBreakdown,
              ),
              color: _sourceColor(type),
              muscleAcc: acc,
              exerciseId: ex['exerciseId']?.toString(),
              variantId: ex['variantId']?.toString(),
              variantLabel: ex['variantLabel']?.toString(),
            ),
          );
        }

        if (exWidgets.isNotEmpty) {
          blocks.add(
            _blockLayout(
              '$type ${blockIndex + 1}'.toUpperCase(),
              _sourceColor(type),
              Column(children: exWidgets),
            ),
          );
        }
      } else if (type == 'Series descendentes') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        if (exercises.isEmpty) continue;

        final List<Widget> sdWidgets = [];

        int maxSets = 0;
        for (final ex in exercises) {
          final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
          if (sets.length > maxSets) maxSets = sets.length;
        }

        for (int i = 0; i < maxSets; i++) {
          final List<Widget> innerExWidgets = [];

          int indicativeReps = 0;
          for (final ex in exercises) {
            final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
            if (sets.length > i && (sets[i]['reps'] ?? 0) > 0) {
              indicativeReps = sets[i]['reps'];
              break;
            }
          }

          sdWidgets.add(
            Container(
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _sourceColor(type).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${indicativeReps > 0 ? '$indicativeReps REPS' : 'SERIE ${i + 1}'}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _sourceColor(type),
                  letterSpacing: 1,
                ),
              ),
            ),
          );

          for (final ex in exercises) {
            final setsList = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
            if (i >= setsList.length) continue;
            final s = setsList[i];
            if (s.containsKey('done') && s['done'] != true) continue;

            final rawExName = ex['exercise'];
            final exName = _visibleExerciseName(ex);
            final exData = exercisesMap[rawExName];

            final double rpe =
                (s['rpe'] as num?)?.toDouble() ??
                WorkoutLoadService.defaultSeriesRpe;
            final double weight = (s['weight'] as num?)?.toDouble() ?? 0.0;
            final int reps = (s['reps'] as num?)?.toInt() ?? 0;
            final bool perSide =
                (ex['perSide'] == true) || (s['perSide'] == true);

            final Map<Muscle, double> acc = {};
            double setFatigue = 0.0;

            if (exData != null) {
              final muscleWeights =
                  WorkoutLoadService.resolveMuscleWeightsFromExercise(
                    exData,
                    variantId: ex['variantId']?.toString(),
                    variantLabel: ex['variantLabel']?.toString(),
                  );
              final tempSet = WorkoutSet(
                exercise: exName,
                sets: 1,
                reps: reps,
                rpe: rpe,
                weight: weight,
                muscleWeights: muscleWeights,
                sourceType: type,
              );
              final blockF = _structureFactor(tempSet);
              final effectiveFactor = _getEffectiveExerciseFactor(
                exData['exerciseType'],
                weight,
              );

              for (final entry in muscleWeights.entries) {
                final v =
                    1 *
                    rpe *
                    effectiveFactor *
                    rpeFactor(rpe) *
                    blockF *
                    entry.value;
                setFatigue += v;
                acc[entry.key] = (acc[entry.key] ?? 0) + v;
                totalAcc[entry.key] = (totalAcc[entry.key] ?? 0) + v;
              }
            }

            innerExWidgets.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            exName.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: _kTextPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _sourceColor(type).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'RPE ${rpe.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              color: _sourceColor(type),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$reps reps · ${weight.toStringAsFixed(1)} kg${perSide ? ' (x lado)' : ''}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: _kTextSecondary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '🔥 ${setFatigue.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.deepOrangeAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap:
                                  () => _showFatigueInfoDialog(
                                    context,
                                    rpe: rpe,
                                    fRpe: rpeFactor(rpe),
                                    exerciseFactor: _getEffectiveExerciseFactor(
                                      exData!['exerciseType'],
                                      weight,
                                    ),
                                    exerciseType: _getEffectiveTypeLabel(
                                      exData['exerciseType'],
                                      weight,
                                    ),
                                    blockF: _structureFactor(
                                      WorkoutSet(
                                        exercise: exName,
                                        sets: 1,
                                        reps: reps,
                                        rpe: rpe,
                                        weight: weight,
                                        muscleWeights: const {},
                                        sourceType: type,
                                      ),
                                    ),
                                    totalFatigue: setFatigue,
                                  ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: _kTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _muscleChips(acc),
                  ],
                ),
              ),
            );
          }

          if (innerExWidgets.isNotEmpty) {
            sdWidgets.addAll(innerExWidgets);
          }
        }

        if (sdWidgets.isNotEmpty) {
          blocks.add(
            _blockLayout(
              '$type ${blockIndex + 1}'.toUpperCase(),
              _sourceColor(type),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sdWidgets,
              ),
            ),
          );
        }
      } else if (type == 'Circuito') {
        final rounds = List<Map<String, dynamic>>.from(e['rounds'] ?? []);
        final List<Widget> roundWidgets = [];

        for (final round in rounds) {
          final int r = round['round'];
          final exercises = List<Map<String, dynamic>>.from(
            round['exercises'] ?? [],
          );
          final List<Widget> exWidgets = [];

          roundWidgets.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kCircuitoColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'RONDA $r',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _kCircuitoColor,
                  letterSpacing: 1,
                ),
              ),
            ),
          );

          for (final ex in exercises) {
            final rawExName = ex['exercise'];
            final exName = _visibleExerciseName(ex);
            final exData = exercisesMap[rawExName];
            final double rpe = (ex['rpe'] as num?)?.toDouble() ?? 5.0;
            final double weight = (ex['weight'] as num?)?.toDouble() ?? 0.0;
            final bool perSide = ex['perSide'] == true;

            final Map<Muscle, double> acc = {};
            double circuitFatigue = 0.0;
            double fRpe = 1.0;
            double blockF = 1.0;

            if (exData != null) {
              final muscleWeights =
                  WorkoutLoadService.resolveMuscleWeightsFromExercise(
                    exData,
                    variantId: ex['variantId']?.toString(),
                    variantLabel: ex['variantLabel']?.toString(),
                  );
              final tempSet = WorkoutSet(
                exercise: exName,
                sets: 1,
                reps: ex['reps'] ?? 1,
                rpe: rpe,
                weight: weight,
                muscleWeights: muscleWeights,
                sourceType: 'Circuito',
              );
              blockF = _structureFactor(tempSet);
              fRpe = rpeFactor(rpe);
              final effectiveFactor = _getEffectiveExerciseFactor(
                exData['exerciseType'],
                weight,
              );

              for (final entry in muscleWeights.entries) {
                final v = rpe * fRpe * effectiveFactor * blockF * entry.value;
                acc[entry.key] = (acc[entry.key] ?? 0) + v;
                totalAcc[entry.key] = (totalAcc[entry.key] ?? 0) + v;
                circuitFatigue += v;
              }
            }

            final detailsStr =
                '${ex['reps'] ?? ex['seconds'] ?? '-'} ${ex['reps'] != null ? 'REPS' : 'S'} · ${weight.toStringAsFixed(1)} KG${perSide ? ' (x lado)' : ''}';
            exWidgets.add(
              _exerciseItem(
                name: exName,
                rpe: rpe,
                detailsWidget: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      detailsStr,
                      style: const TextStyle(
                        fontSize: 10,
                        color: _kTextSecondary,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🔥 ${circuitFatigue.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: _kAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap:
                              () => _showFatigueInfoDialog(
                                context,
                                rpe: rpe,
                                fRpe: fRpe,
                                exerciseFactor: _getEffectiveExerciseFactor(
                                  exData!['exerciseType'],
                                  weight,
                                ),
                                exerciseType: _getEffectiveTypeLabel(
                                  exData['exerciseType'],
                                  weight,
                                ),
                                blockF: blockF,
                                totalFatigue: circuitFatigue,
                              ),
                          child: const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                color: _kCircuitoColor,
                muscleAcc: acc,
                exerciseId: ex['exerciseId']?.toString(),
                variantId: ex['variantId']?.toString(),
                variantLabel: ex['variantLabel']?.toString(),
              ),
            );
          }

          roundWidgets.addAll(exWidgets);
        }

        if (roundWidgets.isNotEmpty) {
          blocks.add(
            _blockLayout(
              'CIRCUITO ${blockIndex + 1}',
              _kCircuitoColor,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: roundWidgets,
              ),
            ),
          );
        }
      } else if (type == 'Tabata') {
        final exercises = List<Map<String, dynamic>>.from(e['exercises'] ?? []);
        final List<Widget> exWidgets = [];

        for (final ex in exercises) {
          final rawExName = ex['exercise'];
          final exName = _visibleExerciseName(ex);
          final exData = exercisesMap[rawExName];
          final double rpe = (ex['rpe'] as num?)?.toDouble() ?? 5.0;

          final Map<Muscle, double> acc = {};
          double tabataFatigue = 0.0;
          double fRpe = 1.0;
          double blockF = 1.0;

          if (exData != null) {
            final muscleWeights =
                WorkoutLoadService.resolveMuscleWeightsFromExercise(
                  exData,
                  variantId: ex['variantId']?.toString(),
                  variantLabel: ex['variantLabel']?.toString(),
                );
            final bool perSide = ex['perSide'] == true;
            final tempSet = WorkoutSet(
              exercise: exName,
              sets: 1,
              reps: 1,
              rpe: rpe,
              perSide: perSide,
              muscleWeights: muscleWeights,
              sourceType: 'Tabata',
            );
            blockF = _structureFactor(tempSet);
            fRpe = rpeFactor(rpe);
            final effectiveFactor = _getEffectiveExerciseFactor(
              exData['exerciseType'],
              0.1,
            ); // Tabata se asume intenso aunque sea bodyweight, pero si hay mas peso, el factor ya es alto

            for (final entry in muscleWeights.entries) {
              final v = rpe * fRpe * effectiveFactor * blockF * entry.value;
              acc[entry.key] = (acc[entry.key] ?? 0) + v;
              totalAcc[entry.key] = (totalAcc[entry.key] ?? 0) + v;
              tabataFatigue += v;
            }
          }

          exWidgets.add(
            _exerciseItem(
              name: exName,
              rpe: rpe,
              detailsWidget: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TABATA',
                    style: TextStyle(fontSize: 10, color: _kTextSecondary),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🔥 ${tabataFatigue.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: _kAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap:
                            () => _showFatigueInfoDialog(
                              context,
                              rpe: rpe,
                              fRpe: fRpe,
                              exerciseFactor: _getEffectiveExerciseFactor(
                                exData!['exerciseType'],
                                0,
                              ),
                              exerciseType: _getEffectiveTypeLabel(
                                exData['exerciseType'],
                                0,
                              ),
                              blockF: blockF,
                              totalFatigue: tabataFatigue,
                            ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: _kTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              color: _kTabataColor,
              muscleAcc: acc,
              exerciseId: ex['exerciseId']?.toString(),
              variantId: ex['variantId']?.toString(),
              variantLabel: ex['variantLabel']?.toString(),
            ),
          );
        }

        if (exWidgets.isNotEmpty) {
          blocks.add(
            _blockLayout(
              'TABATA ${blockIndex + 1}',
              _kTabataColor,
              Column(children: exWidgets),
            ),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            "COMPOSICIÓN DE LA SESIÓN",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: _kAccentSoft,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...blocks,
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(bottom: BorderSide(color: color.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Icon(Icons.token_rounded, color: color, size: 14),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(20), child: content),
        ],
      ),
    );
  }

  Widget _exerciseItem({
    required String name,
    required double rpe,
    required Widget detailsWidget,
    required Color color,
    required Map<Muscle, double> muscleAcc,
    String? exerciseId,
    String? variantId,
    String? variantLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: _kTextPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (exerciseId != null && exerciseId.isNotEmpty)
                IconButton(
                  // Área táctil de 40 px (antes 16 px: casi imposible de
                  // acertar con el dedo) sin agrandar el ícono.
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: _kTextSecondary,
                  ),
                  tooltip: 'Editar ponderación de esta variante',
                  onPressed:
                      () => _editVariantMuscleWeights(
                        exerciseId: exerciseId,
                        variantId: variantId,
                        variantLabel: variantLabel,
                        exerciseName: name,
                      ),
                ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'RPE ${rpe.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          detailsWidget,
          const SizedBox(height: 12),
          _muscleChips(muscleAcc),
        ],
      ),
    );
  }

  /// El id de variante guardado ya no existe en el catálogo: el usuario
  /// elige a cuál corresponde (se guardará como alias).
  Future<Map<String, dynamic>?> _pickVariantForOrphan({
    required String exerciseName,
    required String storedVariantId,
    required List<Map<String, dynamic>> variants,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('¿Qué variante es "$exerciseName"?'),
            content: SizedBox(
              width: 480,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'La variante "$storedVariantId" ya no existe en el catálogo '
                    '(probablemente se renombró). Elige a cuál corresponde; '
                    'se recordará para este y otros entrenamientos.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  for (final v in variants)
                    ListTile(
                      dense: true,
                      title: Text((v['label'] ?? v['id']).toString()),
                      subtitle: Text((v['id'] ?? '').toString()),
                      onTap: () => Navigator.pop(dialogContext, v),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
            ],
          ),
    );
  }

  Future<void> _editVariantMuscleWeights({
    required String exerciseId,
    required String? variantId,
    String? variantLabel,
    required String exerciseName,
  }) async {
    final exerciseRef = FirebaseFirestore.instance
        .collection('exercises')
        .doc(exerciseId);
    final doc = await exerciseRef.get();
    if (!doc.exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el ejercicio en el catálogo.'),
          ),
        );
      }
      return;
    }

    final data = doc.data()!;
    final variants = List<Map<String, dynamic>>.from(
      (data['variants'] as List? ?? const []).map(
        (v) => Map<String, dynamic>.from(v as Map),
      ),
    );
    // Id tal como quedó guardado en el workout (puede estar obsoleto).
    final storedVariantId =
        (variantId == null || variantId.isEmpty) ? 'original' : variantId;

    // Resolver por id → alias → label. Si nada coincide (id renombrado sin
    // alias), se pregunta ANTES de abrir el editor cuál variante es, y se
    // guarda como alias para que ese id viejo no vuelva a quedar huérfano.
    var resolved = resolveCatalogVariant(
      data,
      variantId: storedVariantId,
      variantLabel: variantLabel,
    );
    final aliasUpdates = <String, dynamic>{};
    if (resolved == null) {
      if (!mounted || variants.isEmpty) return;
      resolved = await _pickVariantForOrphan(
        exerciseName: exerciseName,
        storedVariantId: storedVariantId,
        variants: variants,
      );
      if (resolved == null) return;
      aliasUpdates['variantAliases.$storedVariantId'] = resolved['id'];
    }
    final resolvedVariantId = (resolved['id'] ?? '').toString();
    final variantIndex = variants.indexWhere(
      (v) => (v['id'] ?? '').toString() == resolvedVariantId,
    );

    // Punto de partida: la ponderación propia de la variante si ya tiene
    // override, o si no, la ponderación base del ejercicio padre — así el
    // editor nunca arranca vacío, aunque el resultado siempre se guarda
    // como override de ESTA variante, sin tocar el padre ni otras variantes.
    Map<Muscle, double> initialWeights = {};
    if (variantIndex >= 0) {
      final rawOverride = variants[variantIndex]['muscleWeightOverrides'];
      if (rawOverride is Map && rawOverride.isNotEmpty) {
        initialWeights = {
          for (final entry in rawOverride.entries)
            if (Muscle.values.any((m) => m.name == entry.key))
              Muscle.values.firstWhere((m) => m.name == entry.key):
                  (entry.value as num).toDouble(),
        };
      }
    }
    if (initialWeights.isEmpty) {
      initialWeights = WorkoutLoadService.resolveMuscleWeightsFromExercise(
        data,
      );
    }

    if (!mounted) return;
    final result = await Navigator.push<Map<Muscle, double>>(
      context,
      MaterialPageRoute(
        builder:
            (_) => MuscleWeightEditorScreen(initialWeights: initialWeights),
      ),
    );
    if (result == null) return;

    variants[variantIndex] = {
      ...variants[variantIndex],
      'muscleWeightOverrides': {
        for (final entry in result.entries) entry.key.name: entry.value,
      },
    };

    await exerciseRef.update({'variants': variants, ...aliasUpdates});

    if (!mounted) return;
    // El heatmap principal (`centralizedLoad`) se calcula con su propia
    // consulta a Firestore, independiente de `exercisesMap` — hay que
    // recargar todo para que el override recién guardado se refleje ahí
    // también, no solo en el desglose por ejercicio.
    setState(() => loading = true);

    // La carga guardada en cada workout (y con ella la fatiga) se calculó
    // con la ponderación vieja: se recalcula la de los workouts del atleta
    // que usan esta variante y se rehace su fatiga.
    final athleteId = workoutData['userId']?.toString();
    String message = 'Ponderación actualizada para "$exerciseName".';
    if (athleteId != null && athleteId.isNotEmpty) {
      try {
        final updated =
            await FatigueRecalculationService.refreshLoadForVariantChange(
              uid: athleteId,
              exerciseId: exerciseId,
              // Workouts con el id viejo y con el actual usan la misma
              // ponderación: se recalculan ambos.
              variantIds: {storedVariantId, resolvedVariantId},
            );
        message +=
            ' Recalculados $updated entrenamiento${updated == 1 ? '' : 's'} y la fatiga.';
      } catch (e) {
        message += ' No se pudo recalcular la fatiga: $e';
      }
    }

    await _loadAndCalculate();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  double _regulate(double val) => WorkoutLoadService.saturate(val);

  double _getEffectiveExerciseFactor(String? type, double weight) =>
      WorkoutLoadService.effectiveExerciseFactor(dynamicFactors, type, weight);

  String _getEffectiveTypeLabel(String? type, double weight) {
    if (type == null) return 'Desconocido';
    double factor = dynamicFactors[type] ?? 1.0;
    if (weight > 7 && factor < 0.8) return '$type (Escalado)';
    return type;
  }

  Widget _muscleChips(Map<Muscle, double> acc) {
    // Solo mostrar músculos con impacto razonablemente mayor a 0 para no saturar.
    final regulatedMap = {
      for (final e in acc.entries) e.key: _regulate(e.value),
    };

    final sorted =
        regulatedMap.entries.where((e) => e.value >= 0.1).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    // Si la fatiga residual es muy pequeña y fue filtrada, igual la mostramos sumada como 'OTROS'
    final double totalFiltered = regulatedMap.entries
        .where((e) => e.value < 0.1)
        .fold(0, (sum, e) => sum + e.value);

    final List<Widget> chips =
        sorted.map((e) {
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
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _kTextSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '+${e.value.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: _kAccent,
                  ),
                ),
              ],
            ),
          );
        }).toList();

    if (totalFiltered >= 0.1) {
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _kSurface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kDivider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'OTROS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _kTextSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '+${totalFiltered.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: _kAccent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
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
          colors: [_kSurface, _kAccent.withOpacity(0.08)],
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: _kTextPrimary,
                  letterSpacing: 1.2,
                ),
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
