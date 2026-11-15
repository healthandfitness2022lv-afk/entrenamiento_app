import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/body_heatmap.dart';
import '../models/muscle_catalog.dart';
import '../services/report_service.dart';
import '../services/training_imbalance_service.dart';
import '../services/training_identity_service.dart';
import '../services/workout_rm_service.dart';
import '../services/training_review_service.dart';
import 'load_adjustment_alerts_screen.dart';
import '../theme/app_theme.dart';

class UnifiedWeeklyReviewScreen extends StatefulWidget {
  final String athleteId;
  final String athleteName;
  final DateTime initialDate;

  /// Acceso rápido a "Progresión por ejercicio" desde la pestaña
  /// Cumplimiento. Vive como método privado en PlanningScreen (depende de
  /// mucho estado interno de esa pantalla), así que en vez de duplicarlo o
  /// forzar un refactor grande se pasa como callback opcional al abrir esta
  /// pantalla desde ahí.
  final VoidCallback? onProgressionByExercise;

  const UnifiedWeeklyReviewScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.initialDate,
    this.onProgressionByExercise,
  });

  @override
  State<UnifiedWeeklyReviewScreen> createState() =>
      _UnifiedWeeklyReviewScreenState();
}

/// Tarjeta oscura reusable: reemplaza el patrón repetido a mano en todo el
/// archivo (`AppColors.surface` + `borderRadius` + `Border.all(white10)`)
/// por un único punto de estilo, para que las ~15 tarjetas de la pantalla
/// se vean consistentes entre sí.
class _DarkCard extends StatelessWidget {
  final Widget child;
  static const EdgeInsetsGeometry padding = EdgeInsets.all(16);
  static const double borderRadius = 20;

  const _DarkCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}

/// Selector compacto de día en una sola fila de chips horizontales. Antes
/// existían dos versiones casi idénticas (Cumplimiento a 60px, Ejercicios a
/// 40px, con `selectedColor` distinto) — se unifican en este único widget
/// de 36px para no gastar tanto alto de pantalla en un simple selector.
class _DayChipSelector extends StatelessWidget {
  final List<DateTime> days;
  final DateTime? selectedDay; // null = "todos" cuando allowAll es true
  final ValueChanged<DateTime?> onSelected;
  final String Function(DateTime) labelFor;
  final bool allowAll;
  final String allLabel;

  const _DayChipSelector({
    required this.days,
    required this.selectedDay,
    required this.onSelected,
    required this.labelFor,
    this.allowAll = false,
    this.allLabel = "Todos",
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = days.length + (allowAll ? 1 : 0);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final isAllChip = allowAll && index == 0;
          final day = isAllChip ? null : days[index - (allowAll ? 1 : 0)];
          final selected = isAllChip ? selectedDay == null : selectedDay == day;
          return ChoiceChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(
              isAllChip ? allLabel : labelFor(day!),
              style: const TextStyle(fontSize: 12),
            ),
            selected: selected,
            selectedColor: AppColors.accent.withOpacity(0.25),
            onSelected: (_) => onSelected(day),
          );
        },
      ),
    );
  }
}

/// Un paso de la cadena de cálculo de aporte a un perfil, para mostrarlo
/// explicado en la UI (ver `_buildCalcStepRow`).
class _CalcStep {
  final String title;
  final String explanation;
  final String formula;
  final double runningTotal;

  _CalcStep(this.title, this.explanation, this.formula, this.runningTotal);
}


/// Color fijo por perfil, en un orden categórico estable (nunca ciclado):
/// validado contra CVD y contraste en modo oscuro sobre el surface
/// `#1B1B1B` que ya usa esta pantalla.
const Map<TrainingProfile, Color> _kProfileColors = {
  TrainingProfile.powerlifting: AppColors.info, // blue
  TrainingProfile.athlete: Color(0xFFD95926), // orange
  TrainingProfile.hypertrophy: Color(0xFF199E70), // aqua
  TrainingProfile.conditioning: Color(0xFFC98500), // yellow
  TrainingProfile.bodyweight: Color(0xFFD55181), // magenta
};

/// Color fijo por factor del desglose de puntuación (`scoreBreakdown`),
/// mismo criterio: orden estable, nunca reasignado por valor.
const Map<String, Color> _kScoreFactorColors = {
  'Distribución base por tipo': AppColors.info,
  'Ajuste por repeticiones': Color(0xFFD95926),
  'Ajuste por porcentaje de 1RM': Color(0xFF199E70),
  'Coherencia entre intención e intensidad': Color(0xFFC98500),
  'Ajuste por estructura del bloque': Color(0xFFD55181),
  'Ajuste por implemento': Color(0xFF9085E9), // violet
  'Ajuste por atributos': Color(0xFFE66767), // red
  'Bonificación por equilibrio': Color(0xFF008300), // green
  'Límite de dominancia (70%)': Color(0xFF52514E), // muted (siempre negativo)
  'Redistribución de equilibrio': Color(0xFFC3C2B7), // muted claro
};

class _UnifiedWeeklyReviewScreenState extends State<UnifiedWeeklyReviewScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;
  final ScrollController _muscleTableVerticalController = ScrollController();
  bool _loading = true;

  // Captura de "resumen + perfil + carga real" de Cumplimiento como PNG (ver
  // _exportComplianceSummaryPng). No incluye RPE/tendencia/alertas/
  // progresión/detalle diario — solo el tramo pedido.
  final GlobalKey _complianceExportKey = GlobalKey();
  bool _exportingPng = false;

  // Atleta actualmente mostrado. Empieza en lo que llegó por widget, pero es
  // mutable: el selector del appbar permite cambiar de atleta sin salir de
  // la pantalla (ver _buildAthleteSwitcher).
  late String _athleteId;
  late String _athleteName;

  // Data for Load Distribution
  Map<DateTime, Map<String, double>> dailyLoads = {};
  Map<String, double> totalLoad = {};
  Map<String, double> exerciseTypeLoad = {};
  Map<DateTime, Map<String, List<Map<String, dynamic>>>> dailyDetails = {};
  List<ImbalanceAlert> imbalanceAlerts = [];
  TrainingIdentityResult? trainingIdentity;
  TrainingIdentityResult? plannedTrainingIdentity;
  TrainingIdentityResult? loggedTrainingIdentity;
  Map<String, double> blockTypeLoad = {};
  Map<TrainingIntentFamily, double> intentFamilyLoad = {};
  Map<String, double> repRangeLoad = {};
  double trackedRmLoad = 0;
  double compoundLoad = 0;
  double isolationLoad = 0;
  double freeLoad = 0;
  double guidedLoad = 0;
  double bodyweightLoad = 0;
  double bilateralLoad = 0;
  double unilateralLoad = 0;
  List<TrainingIdentityExerciseContribution> identityExercises = [];

  // Aggregated Details for Charts
  Map<AnatomicalGroup, List<Map<String, dynamic>>> anatomicalGroupDetails = {};
  Map<String, List<Map<String, dynamic>>> exerciseTypeDetails = {};

  // Data for Detailed Review
  Map<String, List<DayResultItem>> reviewByDay = {};
  Map<String, List<Map<String, dynamic>>> extrasByDay = {};
  List<String> sortedDayKeys = [];
  String? selectedReviewDayKey;

  // Global Compliance Stats
  double weeklyPlannedVol = 0;
  double weeklyAchievedVol = 0;
  double plannedToDateVol = 0;
  double achievedToDateVol = 0;
  int plannedDaysCount = 0;
  int achievedDaysCount = 0;

  // Weight (kg) compliance, RPE real y tendencia multi-semana — paralelos al
  // conteo de series de arriba, ver _calculateWeightCompliance.
  List<ExerciseLoadCompliance> exerciseLoadCompliance = [];
  double weeklyPlannedKg = 0;
  double weeklyAchievedKg = 0;
  double weeklyAvgRpe = 0;
  List<WeeklyComplianceSummary> weeklyTrend = [];
  bool _loadingTrend = false;

  late DateTime startOfWeek;
  late DateTime endOfWeek;

  final List<Color> anatomicalPalette = [
    const Color(0xFFE53935), // rojo
    const Color(0xFF1E88E5), // azul
    const Color(0xFF43A047), // verde
    const Color(0xFFFF9800), // naranja
    const Color(0xFF8E24AA), // morado
    const Color(0xFFFBC02D), // amarillo
    const Color(0xFF00ACC1), // cyan
    const Color(0xFF7CB342), // verde claro
    const Color(0xFFFF5252), // rosa/rojo
    const Color(0xFF5C6BC0), // indigo
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _athleteId = widget.athleteId;
    _athleteName = widget.athleteName;

    final base = widget.initialDate;
    startOfWeek = DateTime(
      base.year,
      base.month,
      base.day,
    ).subtract(Duration(days: base.weekday - 1));
    endOfWeek = startOfWeek.add(const Duration(days: 7));

    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _muscleTableVerticalController.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    final calc = TrainingReviewCalculator(
      athleteId: _athleteId,
      rangeStart: startOfWeek,
      rangeEnd: endOfWeek,
    );
    await calc.run();
    if (!mounted) return;
    setState(() {
      dailyLoads = calc.dailyLoads;
      totalLoad = calc.totalLoad;
      exerciseTypeLoad = calc.exerciseTypeLoad;
      dailyDetails = calc.dailyDetails;
      imbalanceAlerts = calc.imbalanceAlerts;
      trainingIdentity = calc.trainingIdentity;
      plannedTrainingIdentity = calc.plannedTrainingIdentity;
      loggedTrainingIdentity = calc.loggedTrainingIdentity;
      blockTypeLoad = calc.blockTypeLoad;
      intentFamilyLoad = calc.intentFamilyLoad;
      repRangeLoad = calc.repRangeLoad;
      trackedRmLoad = calc.trackedRmLoad;
      compoundLoad = calc.compoundLoad;
      isolationLoad = calc.isolationLoad;
      freeLoad = calc.freeLoad;
      guidedLoad = calc.guidedLoad;
      bodyweightLoad = calc.bodyweightLoad;
      bilateralLoad = calc.bilateralLoad;
      unilateralLoad = calc.unilateralLoad;
      identityExercises = calc.identityExercises;
      anatomicalGroupDetails = calc.anatomicalGroupDetails;
      exerciseTypeDetails = calc.exerciseTypeDetails;
      reviewByDay = calc.reviewByDay;
      extrasByDay = calc.extrasByDay;
      sortedDayKeys = calc.sortedDayKeys;
      selectedReviewDayKey = calc.selectedReviewDayKey;
      weeklyPlannedVol = calc.weeklyPlannedVol;
      weeklyAchievedVol = calc.weeklyAchievedVol;
      plannedToDateVol = calc.plannedToDateVol;
      achievedToDateVol = calc.achievedToDateVol;
      plannedDaysCount = calc.plannedDaysCount;
      achievedDaysCount = calc.achievedDaysCount;
      exerciseLoadCompliance = calc.exerciseLoadCompliance;
      weeklyPlannedKg = calc.weeklyPlannedKg;
      weeklyAchievedKg = calc.weeklyAchievedKg;
      weeklyAvgRpe = calc.weeklyAvgRpe;
      _loading = false;
    });
  }

  /// Tendencia de cumplimiento (series % y kg %) y RPE real de las últimas
  /// [weeks] semanas (incluida la actual), para el gráfico de línea. Corre
  /// bajo demanda (no en `_loadAllData`) porque agrega varias semanas.
  Future<void> _loadWeeklyTrend({int weeks = 6}) async {
    setState(() => _loadingTrend = true);
    final summaries = await TrainingReviewCalculator(
      athleteId: _athleteId,
      rangeStart: startOfWeek,
      rangeEnd: endOfWeek,
    ).loadWeeklyTrend(weeks: weeks);
    if (!mounted) return;
    setState(() {
      weeklyTrend = summaries;
      _loadingTrend = false;
    });
  }

  /// Exporta el tramo "resumen + perfil + carga real" de Cumplimiento como
  /// una sola imagen PNG (sin RPE/tendencia/alertas/progresión/detalle
  /// diario, que quedan fuera del RepaintBoundary marcado con
  /// `_complianceExportKey`). Comparte el archivo con Share.shareXFiles,
  /// que en web dispara la descarga del navegador y en Android abre el
  /// share sheet nativo (guardar en galería, WhatsApp, etc.).
  Future<void> _exportComplianceSummaryPng() async {
    setState(() => _exportingPng = true);
    try {
      final boundary =
          _complianceExportKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      final fileName =
          "cumplimiento_${_athleteName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}"
          "_${_dayKey(startOfWeek)}.png";

      // XFile.fromData en vez de escribir a disco: funciona igual en web
      // (dart:io/path_provider no tienen filesystem real ahí — File()
      // compila pero lanza UnsupportedError en runtime) y en Android/iOS.
      await Share.shareXFiles([
        XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName),
      ], text: "Cumplimiento semanal · $_athleteName");
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No se pudo exportar la imagen: $e")),
      );
    } finally {
      if (mounted) setState(() => _exportingPng = false);
    }
  }

  /// Selector de atleta directo en el appbar (dropdown sobre el nombre), sin
  /// salir de la pantalla — antes solo se podía cambiar de atleta cerrando
  /// Cumplimiento y volviendo a elegirlo desde Planificación.
  Widget _buildAthleteSwitcher() {
    return PopupMenuButton<Map<String, String>>(
      tooltip: "Cambiar atleta",
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (athlete) {
        final id = athlete['id']!;
        if (id == _athleteId) return;
        setState(() {
          _athleteId = id;
          _athleteName = athlete['name']!;
        });
        _loadAllData();
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem<Map<String, String>>(
            enabled: false,
            child: Text(
              "Cambiar atleta",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<Map<String, String>>(
            enabled: false,
            child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future:
                  FirebaseFirestore.instance
                      .collection('users')
                      .where('role', whereIn: ['atleta', 'administrador'])
                      .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    width: 220,
                    height: 60,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final users =
                    snapshot.data!.docs..sort(
                      (a, b) => (a.data()['name'] ?? '').toString().compareTo(
                        (b.data()['name'] ?? '').toString(),
                      ),
                    );
                return SizedBox(
                  width: 260,
                  height: 320,
                  child: ListView(
                    shrinkWrap: true,
                    children:
                        users.map((doc) {
                          final name =
                              (doc.data()['name'] ?? 'Atleta').toString();
                          final selected = doc.id == _athleteId;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            leading: Icon(
                              Icons.person,
                              size: 18,
                              color: selected ? AppColors.accent : Colors.grey,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap:
                                () => Navigator.pop(context, {
                                  'id': doc.id,
                                  'name': name,
                                }),
                          );
                        }).toList(),
                  ),
                );
              },
            ),
          ),
        ];
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _athleteName,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAthleteSwitcher(),
            Text(
              "${startOfWeek.day}/${startOfWeek.month} al ${endOfWeek.subtract(const Duration(days: 1)).day}/${endOfWeek.month}",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
              color: Colors.redAccent,
            ),
            tooltip: "Reporte PDF",
            onPressed:
                () => ReportService.generateWeeklyReport(
                  context: context,
                  athleteId: _athleteId,
                  range: DateTimeRange(
                    start: startOfWeek,
                    end: endOfWeek.subtract(const Duration(seconds: 1)),
                  ),
                ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          tabs: const [
            Tab(height: 40, text: "Carga"),
            Tab(height: 40, text: "Perfil"),
            Tab(height: 40, text: "Diario"),
            Tab(height: 40, text: "Cumplimiento"),
          ],
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildLoadDistributionTab(),
                  _buildTrainingProfileTab(),
                  _buildDailyLoadTab(),
                  _buildComplianceTab(),
                ],
              ),
    );
  }

  Widget _buildLoadDistributionTab() {
    if (totalLoad.isEmpty) {
      return _buildEmptyState("No hay datos de carga esta semana.");
    }

    final normalizedHeatmap = _normalizeAbsolute(_toMuscleMap(totalLoad));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            return Card(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      "Esquema Corporal de Carga",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: isWide ? 550 : 800,
                      child:
                          isWide
                              ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: BodyHeatmap(
                                      heatmap: normalizedHeatmap,
                                      showBack: false,
                                    ),
                                  ),
                                  Expanded(
                                    child: BodyHeatmap(
                                      heatmap: normalizedHeatmap,
                                      showBack: true,
                                    ),
                                  ),
                                  const VerticalDivider(
                                    color: Colors.white10,
                                    width: 30,
                                  ),
                                  Expanded(flex: 3, child: _buildMuscleTable()),
                                ],
                              )
                              : Column(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: BodyHeatmap(
                                            heatmap: normalizedHeatmap,
                                            showBack: false,
                                          ),
                                        ),
                                        Expanded(
                                          child: BodyHeatmap(
                                            heatmap: normalizedHeatmap,
                                            showBack: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Expanded(flex: 3, child: _buildMuscleTable()),
                                ],
                              ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        _buildPieCharts(),
        const SizedBox(height: 20),
        _buildImbalanceCard(),
      ],
    );
  }

  Widget _buildTrainingProfileTab() {
    final identity = trainingIdentity;
    if (identity == null || identity.exercises.isEmpty) {
      return _buildEmptyState(
        "No hay datos suficientes para estimar el perfil de entrenamiento esta semana.",
      );
    }

    final groupedExercises =
        <String, List<TrainingIdentityExerciseContribution>>{};
    final groupOrder = <String, int>{};
    for (var index = 0; index < identity.exercises.length; index++) {
      final exercise = identity.exercises[index];
      // La fecha (normalizada al día) es parte de la key: el mismo
      // ejercicio en días distintos de la semana puede tener carga/reps
      // diferentes y NO debe mezclarse en un mismo grupo, o el agrupado por
      // día pierde por completo ese ejercicio en todos los días salvo el
      // primero de la lista.
      final day = DateTime(
        exercise.date.year,
        exercise.date.month,
        exercise.date.day,
      );
      final key =
          '$day|${exercise.source}|${exercise.name}|${exercise.blockTitle}|${exercise.exerciseType}|${exercise.blockType}';
      groupedExercises.putIfAbsent(key, () => []).add(exercise);
      groupOrder.putIfAbsent(key, () => index);
    }
    // Preserve the execution order produced by the planned blocks. The
    // profile view should read like the workout, not like a ranking by load.
    final groupedEntries =
        groupedExercises.entries.toList()..sort(
          (a, b) => (groupOrder[a.key] ?? 0).compareTo(groupOrder[b.key] ?? 0),
        );
    final groupedEntriesByDay =
        <DateTime, List<List<TrainingIdentityExerciseContribution>>>{};
    for (final entry in groupedEntries) {
      final seriesList = entry.value;
      final firstDate = seriesList.first.date;
      final normalizedDay = DateTime(
        firstDate.year,
        firstDate.month,
        firstDate.day,
      );
      groupedEntriesByDay.putIfAbsent(normalizedDay, () => []).add(seriesList);
    }
    final orderedDays =
        groupedEntriesByDay.keys.toList()..sort((a, b) => a.compareTo(b));

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: "Resumen"),
                Tab(text: "Desglose"),
                Tab(text: "Ejercicios"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildProfileMetricsCard(identity),
                    const SizedBox(height: 16),
                    _buildBaseMetricsCard(identity),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [_buildScoreBreakdownCard(identity)],
                ),
                _buildExercisesTab(orderedDays, groupedEntriesByDay),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRadarCard(TrainingIdentityResult identity) {
    final relativeScores = _relativeProfilePercentages(identity.scores);
    final profiles =
        TrainingProfile.values
            .where((p) => identity.scores.containsKey(p))
            .toList();

    final plannedRel =
        plannedTrainingIdentity != null
            ? _relativeProfilePercentages(plannedTrainingIdentity!.scores)
            : null;
    final loggedRel =
        loggedTrainingIdentity != null
            ? _relativeProfilePercentages(loggedTrainingIdentity!.scores)
            : null;
    final hasComparison = plannedRel != null && loggedRel != null;

    List<RadarEntry> entriesFor(Map<TrainingProfile, double> rel) =>
        profiles.map((p) => RadarEntry(value: rel[p] ?? 0)).toList();

    final dataSets = <RadarDataSet>[
      if (!hasComparison)
        RadarDataSet(
          fillColor: AppColors.accent.withOpacity(0.25),
          borderColor: AppColors.accent,
          borderWidth: 2,
          entryRadius: 3,
          dataEntries: entriesFor(relativeScores),
        )
      else ...[
        RadarDataSet(
          fillColor: AppColors.info.withOpacity(0.2),
          borderColor: AppColors.info,
          borderWidth: 2,
          entryRadius: 3,
          dataEntries: entriesFor(plannedRel),
        ),
        RadarDataSet(
          fillColor: const Color(0xFFD95926).withOpacity(0.2),
          borderColor: const Color(0xFFD95926),
          borderWidth: 2,
          entryRadius: 3,
          dataEntries: entriesFor(loggedRel),
        ),
      ],
    ];

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.radar, color: AppColors.accent),
              SizedBox(width: 10),
              Text(
                "Forma del perfil semanal",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Perfil principal: ${identity.primaryProfile.label} (${_formatProfilePercent(relativeScores[identity.primaryProfile] ?? 0)})",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                tickCount: 4,
                ticksTextStyle: const TextStyle(
                  color: Colors.transparent,
                  fontSize: 0,
                ),
                radarBorderData: const BorderSide(color: Colors.white24),
                gridBorderData: const BorderSide(
                  color: Colors.white12,
                  width: 1,
                ),
                tickBorderData: const BorderSide(color: Colors.white12),
                radarBackgroundColor: Colors.transparent,
                titleTextStyle: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                getTitle: (index, angle) {
                  return RadarChartTitle(text: profiles[index].label);
                },
                dataSets: dataSets,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (!hasComparison)
                _legendDot(AppColors.accent, "Perfil de la semana")
              else ...[
                _legendDot(AppColors.info, "Planificado"),
                _legendDot(const Color(0xFFD95926), "Realizado"),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildProfileMetricsCard(TrainingIdentityResult identity) {
    final relativeScores = _relativeProfilePercentages(identity.scores);
    final orderedScores =
        identity.scores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final plannedRel =
        plannedTrainingIdentity != null
            ? _relativeProfilePercentages(plannedTrainingIdentity!.scores)
            : null;
    final loggedRel =
        loggedTrainingIdentity != null
            ? _relativeProfilePercentages(loggedTrainingIdentity!.scores)
            : null;
    final hasComparison = plannedRel != null && loggedRel != null;

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasComparison
                ? "Puntuación por perfil: planificado vs desarrollado"
                : "Puntuación por perfil",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 14),
          if (hasComparison)
            ...orderedScores.map((entry) {
              final plannedValue = plannedRel[entry.key] ?? 0;
              final loggedValue = loggedRel[entry.key] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const SizedBox(
                          width: 60,
                          child: Text(
                            "Plan",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (plannedValue / 100).clamp(0.0, 1.0),
                              backgroundColor: Colors.white10,
                              color: AppColors.info,
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 40,
                          child: Text(
                            _formatProfilePercent(plannedValue),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.info,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(
                          width: 60,
                          child: Text(
                            "Real",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (loggedValue / 100).clamp(0.0, 1.0),
                              backgroundColor: Colors.white10,
                              color: const Color(0xFFD95926),
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 40,
                          child: Text(
                            _formatProfilePercent(loggedValue),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFD95926),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            })
          else
            ...orderedScores.map((entry) {
              final relativeValue = relativeScores[entry.key] ?? 0;
              final color = _kProfileColors[entry.key] ?? AppColors.accent;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              entry.key.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _formatProfilePercent(relativeValue),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (relativeValue / 100).clamp(0.0, 1.0),
                        backgroundColor: Colors.white10,
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (identity.biases.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  identity.biases
                      .map((bias) => Chip(label: Text(bias)))
                      .toList(),
            ),
          ],
          const SizedBox(height: 8),
          ...identity.evidence.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                "- $item",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaseMetricsCard(TrainingIdentityResult identity) {
    final m = identity.debugMetrics;

    final intentFamilies = <String, double>{
      'Fuerza': (m['strengthRatio'] ?? 0) * 100,
      'Potencia': (m['powerRatio'] ?? 0) * 100,
      'Hipertrofia': (m['hypertrophyRatio'] ?? 0) * 100,
      'Accesorios': (m['accessoryRatio'] ?? 0) * 100,
      'Control y coordinación': (m['bodyweightIntentRatio'] ?? 0) * 100,
      'Estabilidad': (m['stabilityRatio'] ?? 0) * 100,
      'Acondicionamiento': (m['conditioningRatio'] ?? 0) * 100,
    };

    final repRanges = <String, double>{
      '1-3': (m['reps1to3'] ?? 0) * 100,
      '4-6': (m['reps4to6'] ?? 0) * 100,
      '7-8': (m['reps7to8'] ?? 0) * 100,
      '9-10': (m['reps9to10'] ?? 0) * 100,
      '11-12': (m['reps11to12'] ?? 0) * 100,
      '13+': (m['reps13Plus'] ?? 0) * 100,
    };

    final structure = <String, double>{
      'Bilateral': (m['bilateralRatio'] ?? 0) * 100,
      'Unilateral': (m['unilateralRatio'] ?? 0) * 100,
      'Peso libre': (m['freeRatio'] ?? 0) * 100,
      'Guiado': (m['guidedRatio'] ?? 0) * 100,
      'Compuesto': (m['compoundRatio'] ?? 0) * 100,
      'Aislamiento': (m['isolationRatio'] ?? 0) * 100,
      'Con seguimiento de RM': (m['trackedRmRatio'] ?? 0) * 100,
    };

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights, color: AppColors.accent),
              SizedBox(width: 10),
              Text(
                "Métricas base",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _metricBarGroup("Intención por tipo", intentFamilies, AppColors.info),
          const SizedBox(height: 20),
          _metricRepsPie(repRanges),
          const SizedBox(height: 20),
          _metricBarGroup(
            "Estructura técnica",
            structure,
            const Color(0xFF199E70),
          ),
          const SizedBox(height: 20),
          _metricBalanceRow(
            (m['pushPullBalance'] ?? 0) * 100,
            (m['upperLowerBalance'] ?? 0) * 100,
          ),
        ],
      ),
    );
  }

  Widget _metricBarGroup(String title, Map<String, double> data, Color color) {
    final entries =
        data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 10),
        ...entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (entry.value / 100).clamp(0.0, 1.0),
                      backgroundColor: Colors.white10,
                      color: color,
                      minHeight: 6,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    _formatProfilePercent(entry.value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _metricRepsPie(Map<String, double> repRanges) {
    final total = repRanges.values.fold<double>(0, (acc, v) => acc + v);
    final entries =
        repRanges.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    const repColors = [
      AppColors.info,
      Color(0xFFD95926),
      Color(0xFF199E70),
      Color(0xFFC98500),
      Color(0xFFD55181),
      Color(0xFF9085E9),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Rango de repeticiones",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (total <= 0)
          const Text(
            "Sin datos suficientes",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          )
        else
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 26,
                    sections: List.generate(entries.length, (index) {
                      final entry = entries[index];
                      return PieChartSectionData(
                        value: entry.value,
                        color: repColors[index % repColors.length],
                        radius: 34,
                        title: "${entry.value.toStringAsFixed(0)}%",
                        titleStyle: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < entries.length; i++)
                      _legendDot(
                        repColors[i % repColors.length],
                        "${entries[i].key} reps",
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _metricBalanceRow(double pushPull, double upperLower) {
    Widget gauge(String label, double value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (value / 100).clamp(0.0, 1.0),
                backgroundColor: Colors.white10,
                color: const Color(0xFFD55181),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatProfilePercent(value),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Balance corporal (100% = perfecto equilibrio)",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            gauge("Empuje / Tracción", pushPull),
            const SizedBox(width: 16),
            gauge("Superior / Inferior", upperLower),
          ],
        ),
      ],
    );
  }

  Widget _buildScoreBreakdownCard(TrainingIdentityResult identity) {
    final orderedScores =
        identity.scores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    // Solo los factores positivos entran a la barra apilada (los negativos,
    // como el recorte por límite de dominancia, se muestran aparte como nota
    // — apilar un valor negativo distorsiona la lectura de la barra).
    final allFactorKeys = <String>{};
    for (final entry in orderedScores) {
      final breakdown = identity.scoreBreakdown[entry.key] ?? {};
      allFactorKeys.addAll(
        breakdown.entries.where((f) => f.value > 0).map((f) => f.key),
      );
    }
    final legendFactors =
        allFactorKeys.toList()..sort(
          (a, b) => (_kScoreFactorColors.keys.toList().indexOf(
            a,
          )).compareTo(_kScoreFactorColors.keys.toList().indexOf(b)),
        );

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stacked_bar_chart, color: AppColors.accent),
              SizedBox(width: 10),
              Text(
                "De qué está hecho cada score",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "Cada barra es la suma de los factores que aportaron a ese perfil",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...orderedScores.map((entry) {
            final breakdown = identity.scoreBreakdown[entry.key] ?? {};
            final positiveFactors =
                breakdown.entries.where((f) => f.value > 0).toList();
            final negativeFactors =
                breakdown.entries.where((f) => f.value < 0).toList();
            final positiveTotal = positiveFactors.fold<double>(
              0,
              (total, f) => total + f.value,
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        entry.value.toStringAsFixed(2),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (positiveTotal > 0)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 22,
                        child: Row(
                          children:
                              positiveFactors.map((factor) {
                                final flex = (factor.value /
                                        positiveTotal *
                                        1000)
                                    .round()
                                    .clamp(1, 1000);
                                final color =
                                    _kScoreFactorColors[factor.key] ??
                                    Colors.grey;
                                return Expanded(
                                  flex: flex,
                                  child: Container(
                                    color: color,
                                    margin: const EdgeInsets.only(right: 1),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "Sin factores positivos",
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ),
                  if (negativeFactors.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ...negativeFactors.map(
                      (factor) => Text(
                        "${factor.key}: ${factor.value.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children:
                legendFactors
                    .map(
                      (key) => _legendDot(
                        _kScoreFactorColors[key] ?? Colors.grey,
                        key,
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExercisesTab(
    List<DateTime> orderedDays,
    Map<DateTime, List<List<TrainingIdentityExerciseContribution>>>
    groupedEntriesByDay,
  ) {
    return _ExercisesTabContent(
      orderedDays: orderedDays,
      groupedEntriesByDay: groupedEntriesByDay,
      identityInputFor: TrainingReviewCalculator.identityInputFor,
      formatDetailDay: _formatDetailDay,
      identitySourceLabel: _identitySourceLabel,
      spanishTechnicalLabel: _spanishTechnicalLabel,
      identityContributionRow: _identityContributionRow,
      showExerciseSeriesBreakdown: _showExerciseSeriesBreakdown,
      relativeProfilePercentages: _relativeProfilePercentages,
      formatProfilePercent: _formatProfilePercent,
    );
  }

  void _showExerciseSeriesBreakdown(
    String exerciseName,
    List<TrainingIdentityExerciseContribution> sets,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: .75,
            minChildSize: .4,
            maxChildSize: .95,
            expand: false,
            builder:
                (context, controller) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      exerciseName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Desglose del ejercicio completo por perfil',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sets.length} ${sets.length == 1 ? 'serie' : 'series'} · '
                      'carga total ${sets.fold<double>(0, (t, s) => t + s.load).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed:
                          () => _editExerciseProfileDistribution(
                            context,
                            exerciseName,
                            sets,
                          ),
                      icon: const Icon(Icons.tune),
                      label: const Text('Editar punto de partida del tipo'),
                    ),
                    const SizedBox(height: 8),
                    _buildExerciseCalculationExplainer(exerciseName, sets),
                  ],
                ),
          ),
    );
  }

  Future<void> _editExerciseProfileDistribution(
    BuildContext sheetContext,
    String exerciseName,
    List<TrainingIdentityExerciseContribution> sets,
  ) async {
    final beforeScores = <TrainingProfile, double>{
      ...(trainingIdentity?.scores ?? const <TrainingProfile, double>{}),
    };
    const editableProfiles = [
      TrainingProfile.powerlifting,
      TrainingProfile.athlete,
      TrainingProfile.hypertrophy,
      TrainingProfile.conditioning,
      TrainingProfile.bodyweight,
    ];
    final draft = <TrainingProfile, double>{};
    for (final profile in editableProfiles) {
      final values =
          sets
              .map(
                (set) =>
                    (set.profileDistributionOverride.isNotEmpty
                        ? set.profileDistributionOverride[profile]
                        : set.baseProfileDistribution[profile]) ??
                    0,
              )
              .toList();
      draft[profile] =
          values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
    }
    final percentageControllers = {
      for (final profile in editableProfiles)
        profile: TextEditingController(
          text: (draft[profile]! * 100).round().toString(),
        ),
    };
    final edited = await showDialog<bool>(
      context: sheetContext,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text('Punto de partida: ${sets.first.exerciseType}'),
                  content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const Text(
                            'Ajusta la distribución inicial. Se normalizará al guardar para que sume 100%.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          Builder(
                            builder: (_) {
                              final total = draft.values.fold<double>(
                                0,
                                (sum, value) => sum + value,
                              );
                              final isComplete = (total - 1).abs() < 0.005;
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total distribuido',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${(total * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color:
                                          isComplete
                                              ? Colors.greenAccent
                                              : Colors.orangeAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          ...editableProfiles.map(
                            (profile) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(profile.label)),
                                    SizedBox(
                                      width: 72,
                                      child: TextField(
                                        controller:
                                            percentageControllers[profile],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.right,
                                        decoration: const InputDecoration(
                                          suffixText: '%',
                                          isDense: true,
                                        ),
                                        onChanged: (text) {
                                          final parsed = double.tryParse(text);
                                          if (parsed == null) return;
                                          setDialogState(
                                            () =>
                                                draft[profile] = (parsed / 100)
                                                    .clamp(0.0, 1.0),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: draft[profile]!.clamp(0.0, 1.0),
                                  min: 0,
                                  max: 1,
                                  divisions: 100,
                                  onChanged:
                                      (value) => setDialogState(() {
                                        draft[profile] = value;
                                        percentageControllers[profile]!.text =
                                            (value * 100).round().toString();
                                      }),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed:
                          (draft.values.fold<double>(
                                            0,
                                            (sum, value) => sum + value,
                                          ) -
                                          1)
                                      .abs() <
                                  0.005
                              ? () => Navigator.of(dialogContext).pop(true)
                              : null,
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );
    for (final controller in percentageControllers.values) {
      controller.dispose();
    }
    if (edited != true || !mounted) return;

    final total = draft.values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final exerciseType = sets.first.exerciseType;
    final normalizedType = WorkoutRMService.normalizeExerciseName(exerciseType);
    final normalizedProfiles = <String, double>{
      for (final entry in draft.entries) entry.key.name: entry.value / total,
    };
    await FirebaseFirestore.instance
        .collection('exercise_profile_overrides')
        .doc('type_$normalizedType')
        .set({
          'exerciseName': exerciseName,
          'exerciseType': exerciseType,
          'scope': 'exerciseType',
          'profiles': normalizedProfiles,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    if (!mounted) return;
    await _loadAllData();
    if (mounted) {
      await _showProfileVariationDialog(
        beforeScores,
        trainingIdentity?.scores ?? const <TrainingProfile, double>{},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ponderaciones iniciales actualizadas.')),
      );
    }
  }

  Future<void> _showProfileVariationDialog(
    Map<TrainingProfile, double> before,
    Map<TrainingProfile, double> after,
  ) async {
    final profiles = [
      TrainingProfile.powerlifting,
      TrainingProfile.athlete,
      TrainingProfile.hypertrophy,
      TrainingProfile.conditioning,
      TrainingProfile.bodyweight,
    ];
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Variación acumulada de perfiles'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Cambio en el perfil semanal después de aplicar la nueva ponderación:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ...profiles.map((profile) {
                  final oldValue = before[profile] ?? 0;
                  final newValue = after[profile] ?? 0;
                  final delta = newValue - oldValue;
                  final color = _kProfileColors[profile] ?? AppColors.accent;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(profile.label),
                    subtitle: Text(
                      '${oldValue.toStringAsFixed(2)} → ${newValue.toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}',
                      style: TextStyle(
                        color:
                            delta.abs() < 0.005
                                ? Colors.grey
                                : (delta > 0
                                    ? Colors.greenAccent
                                    : Colors.redAccent),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    leading: CircleAvatar(radius: 5, backgroundColor: color),
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  /// Explica, perfil por perfil, cómo el EJERCICIO COMPLETO (todas sus
  /// series juntas) llegó a su aporte final. Cada paso de la cadena se
  /// suma a través de todas las series — mismo criterio que usa
  /// `scoreBreakdown` a nivel semanal — para que el desglose sea
  /// consistente con el resto del cálculo, sin repetir la explicación
  /// serie por serie.
  Widget _buildExerciseCalculationExplainer(
    String exerciseName,
    List<TrainingIdentityExerciseContribution> sets,
  ) {
    if (sets.isEmpty) return const SizedBox.shrink();

    final totalDose = sets.fold<double>(0, (t, s) => t + s.dose);
    final totalContributions = <TrainingProfile, double>{};
    for (final s in sets) {
      s.finalProfileContributions.forEach((profile, value) {
        totalContributions[profile] =
            (totalContributions[profile] ?? 0) + value;
      });
    }
    final orderedProfiles =
        totalContributions.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (orderedProfiles.isEmpty) return const SizedBox.shrink();

    final first = sets.first;
    final usesRpe = sets.any((s) => s.reportedRpe != null);
    final usesPercent1RM = sets.any((s) => s.percent1RM != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este ejercicio se clasificó como "${first.doseClassification}". '
                'Sumando la dosis de estímulo de sus ${sets.length} ${sets.length == 1 ? 'serie' : 'series'} '
                'da un total de ${totalDose.toStringAsFixed(2)}.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                'Intensidad usada: '
                '${usesRpe
                    ? 'según el RPE reportado en cada serie'
                    : usesPercent1RM
                    ? 'según %1RM de cada serie'
                    : 'neutra, por falta de referencia de RPE o %1RM'}.',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        ...orderedProfiles.map(
          (entry) => _buildProfileCalculationTile(sets, entry.key),
        ),
      ],
    );
  }

  Widget _buildProfileCalculationTile(
    List<TrainingIdentityExerciseContribution> sets,
    TrainingProfile profile,
  ) {
    final color = _kProfileColors[profile] ?? AppColors.accent;
    final first = sets.first;

    // Cada paso se suma a través de todas las series del ejercicio, igual
    // criterio que `scoreBreakdown` a nivel semanal en `analyze()`.
    double baseValue = 0, afterEquipment = 0, afterReps = 0;
    double afterPercent = 0, afterCoherence = 0, afterBlock = 0, finalValue = 0;
    for (final s in sets) {
      final baseShare = s.baseProfileDistribution[profile] ?? 0;
      final base = s.dose * s.technicalDoseMultiplier * s.intensity * baseShare;
      final eq = base * (s.equipmentProfileModifiers[profile] ?? 1);
      final reps = eq * (s.repsProfileModifiers[profile] ?? 1);
      final pct = reps * (s.percent1RMProfileModifiers[profile] ?? 1);
      final coh = pct * (s.coherenceProfileModifiers[profile] ?? 1);
      final blk = coh * (s.blockProfileModifiers[profile] ?? 1);
      final fin = s.finalProfileContributions[profile] ?? 0;
      baseValue += base;
      afterEquipment += eq;
      afterReps += reps;
      afterPercent += pct;
      afterCoherence += coh;
      afterBlock += blk;
      finalValue += fin;
    }
    // Los modificadores mostrados son "efectivos" (relación entre el total
    // antes/después de ese paso): con series de distinto peso/RPE, el
    // modificador real puede variar serie a serie, así que se muestra el
    // efecto neto sobre el total, no un promedio simple.
    double effectiveMod(double before, double after) =>
        before.abs() < 1e-9 ? 1.0 : after / before;
    final equipmentMod = effectiveMod(baseValue, afterEquipment);
    final repsMod = effectiveMod(afterEquipment, afterReps);
    final percentMod = effectiveMod(afterReps, afterPercent);
    final coherenceMod = effectiveMod(afterPercent, afterCoherence);
    final blockMod = effectiveMod(afterCoherence, afterBlock);
    final attributeMod = effectiveMod(afterBlock, finalValue);
    final repBuckets = sets.map((s) => s.repBucket).toSet().join(', ');

    final steps = <_CalcStep>[
      _CalcStep(
        'Punto de partida',
        'Este tipo de ejercicio reparte su estímulo entre perfiles; a "${profile.label}" le toca en promedio una parte de la dosis total de cada serie.',
        'Suma de (dosis × cuota de este perfil)',
        baseValue,
      ),
      _CalcStep(
        'Implemento usado',
        equipmentMod == 1
            ? 'El implemento no cambia este perfil (ajuste neutro).'
            : equipmentMod > 1
            ? 'El implemento usado (peso libre / guiado / corporal) refuerza este perfil.'
            : 'El implemento usado le resta peso a este perfil.',
        '× ${equipmentMod.toStringAsFixed(2)} (efecto neto)',
        afterEquipment,
      ),
      _CalcStep(
        'Repeticiones ($repBuckets)',
        repsMod == 1
            ? 'Este rango de repeticiones no cambia el perfil.'
            : repsMod > 1
            ? 'Este rango de repeticiones es típico de este perfil, así que suma.'
            : 'Este rango de repeticiones no es típico de este perfil, así que resta.',
        '× ${repsMod.toStringAsFixed(2)} (efecto neto)',
        afterReps,
      ),
      _CalcStep(
        '% de 1RM usado',
        sets.every((s) => s.percent1RM == null && s.reportedRpe == null)
            ? 'No hay referencia de intensidad (ni %1RM ni RPE), así que este ajuste queda neutro.'
            : percentMod == 1
            ? 'La intensidad relativa no cambia este perfil.'
            : percentMod > 1
            ? 'La intensidad relativa usada favorece este perfil.'
            : 'La intensidad relativa usada no es típica de este perfil.',
        '× ${percentMod.toStringAsFixed(2)} (efecto neto)',
        afterPercent,
      ),
      _CalcStep(
        'Coherencia entre tipo y dosis real',
        coherenceMod == 1
            ? 'La dosis real coincide con lo esperable para el tipo declarado.'
            : coherenceMod > 1
            ? 'La dosis real (reps/intensidad) confirma aún más este perfil, aunque el tipo declarado fuera otro.'
            : 'La dosis real (reps/intensidad) no calza con el tipo declarado, así que se corrige hacia abajo.',
        '× ${coherenceMod.toStringAsFixed(2)} (efecto neto)',
        afterCoherence,
      ),
      _CalcStep(
        'Estructura del bloque (${_spanishTechnicalLabel(first.blockType)})',
        blockMod == 1
            ? 'El tipo de bloque no cambia este perfil.'
            : blockMod > 1
            ? 'Hacerlo dentro de un bloque ${_spanishTechnicalLabel(first.blockType)} refuerza este perfil.'
            : 'Hacerlo dentro de un bloque ${_spanishTechnicalLabel(first.blockType)} le resta a este perfil.',
        '× ${blockMod.toStringAsFixed(2)} (efecto neto)',
        afterBlock,
      ),
      _CalcStep(
        'Atributos del ejercicio',
        _attributeSummaryForSets(sets),
        '× ${attributeMod.toStringAsFixed(2)} (efecto neto)',
        finalValue,
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profile.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '+${finalValue.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              _buildCalcStepRow(i + 1, steps[i]),
              if (i < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Icon(
                    Icons.arrow_downward,
                    size: 14,
                    color: Colors.white24,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _attributeSummaryForSets(
    List<TrainingIdentityExerciseContribution> sets,
  ) {
    if (sets.isEmpty) return 'Sin atributos adicionales.';
    final tags = <String>{};
    for (final setItem in sets) {
      tags.add(setItem.unilateral ? 'unilateral' : 'bilateral');
      if (setItem.trackRm) tags.add('con seguimiento de RM');
      if (setItem.compound) tags.add('compuesto');
      if (setItem.isolation) tags.add('aislamiento');
      if (setItem.bodyweight) tags.add('peso corporal');
      if (setItem.rotational) tags.add('rotacional/anti-rotacional');
    }
    return 'Características de este ejercicio: ${tags.join(', ')}.';
  }

  Widget _buildCalcStepRow(int stepNumber, _CalcStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$stepNumber',
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  step.explanation,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                step.formula,
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
              Text(
                '= ${step.runningTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _identityContributionRow(String label, String bucket, double load) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text("$label: $bucket")),
          Text(load.toStringAsFixed(2)),
        ],
      ),
    );
  }

  Map<TrainingProfile, double> _relativeProfilePercentages(
    Map<TrainingProfile, double> scores,
  ) {
    final total = scores.values.fold<double>(
      0,
      (accumulated, value) => accumulated + value,
    );
    if (total <= 0) {
      return {for (final entry in scores.entries) entry.key: 0};
    }

    return {
      for (final entry in scores.entries)
        entry.key: (entry.value / total) * 100,
    };
  }

  String _formatProfilePercent(double value) {
    if (value > 0 && value < 1) return '<1%';
    if (value < 10) return '${value.toStringAsFixed(1)}%';
    return '${value.toStringAsFixed(0)}%';
  }

  String _identitySourceLabel(String source) {
    switch (source.toLowerCase().trim()) {
      case 'planned':
        return 'Planificado';
      case 'logged':
        return 'Realizado';
      default:
        return _spanishTechnicalLabel(source);
    }
  }

  String _spanishTechnicalLabel(String value) {
    const labels = {
      'bodyweight': 'Peso corporal',
      'weightlifting': 'Levantamientos olímpicos',
      'compound': 'Compuesto',
      'isolation': 'Aislamiento',
      'guided': 'Guiado',
      'free': 'Peso libre',
      'unknown': 'Sin clasificar',
      'athleticpower': 'Potencia deportiva',
      'conditioning': 'Acondicionamiento',
      'strength': 'Fuerza',
      'accessory': 'Accesorios',
    };
    final key = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return labels[key] ?? value;
  }

  String _formatDetailDay(DateTime day) {
    const weekdays = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final weekday = weekdays[day.weekday - 1];
    final month = months[day.month - 1];
    return '$weekday ${day.day} de $month';
  }

  Widget _buildDailyLoadTab() {
    if (dailyLoads.isEmpty) {
      return _buildEmptyState("No hay carga distribuida por día esta semana.");
    }

    final entries =
        dailyLoads.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final date = entry.key;
        final muscles = entry.value;
        final normalizedHeatmap = _normalizeAbsolute(_toMuscleMap(muscles));
        final total = muscles.values.fold<double>(0, (a, b) => a + b);
        final topMuscles =
            muscles.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

        return Card(
          color: AppColors.surface,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${date.day}/${date.month}/${date.year}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Carga total ${total.toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.list_alt, color: AppColors.info),
                      tooltip: "Ver desglose muscular",
                      onPressed: () {
                        final strongest =
                            topMuscles.isNotEmpty ? topMuscles.first.key : null;
                        if (strongest != null) {
                          _showMuscleDetails(strongest, date);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: Row(
                    children: [
                      Expanded(
                        child: BodyHeatmap(
                          heatmap: normalizedHeatmap,
                          showBack: false,
                        ),
                      ),
                      Expanded(
                        child: BodyHeatmap(
                          heatmap: normalizedHeatmap,
                          showBack: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      topMuscles
                          .where((e) => e.value > 0)
                          .take(4)
                          .map(
                            (e) => Chip(
                              label: Text(
                                "${_muscleLabel(e.key)} ${e.value.toStringAsFixed(1)}",
                              ),
                            ),
                          )
                          .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMuscleTable() {
    final muscles =
        totalLoad.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final dates = dailyLoads.keys.toList()..sort();

    return Scrollbar(
      controller: _muscleTableVerticalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _muscleTableVerticalController,
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 15,
            headingRowHeight: 40,
            dataRowHeight: 45,
            columns: [
              const DataColumn(
                label: Text(
                  "Músculo",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              ...dates.map(
                (d) => DataColumn(
                  label: Text("${d.day}", style: const TextStyle(fontSize: 11)),
                ),
              ),
              const DataColumn(
                label: Text(
                  "Total",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            rows:
                muscles.map((m) {
                  final rowTotal = m.value;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          _muscleLabel(m.key),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ...dates.map((d) {
                        final val = dailyLoads[d]?[m.key] ?? 0;
                        return DataCell(
                          InkWell(
                            onTap:
                                val > 0
                                    ? () => _showMuscleDetails(m.key, d)
                                    : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration:
                                  val > 0
                                      ? BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      )
                                      : null,
                              child: Text(
                                val > 0 ? val.toStringAsFixed(1) : "-",
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      val > 0
                                          ? Colors.blue
                                          : Colors.grey.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      DataCell(
                        Text(
                          rowTotal.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }

  void _showMuscleDetails(String muscleKey, DateTime date) {
    final details = dailyDetails[date]?[muscleKey] ?? [];
    _showDetailsList(
      title: "Desglose: ${_muscleLabel(muscleKey)} (${date.day}/${date.month})",
      details: details,
    );
  }

  void _showDetailsList({
    required String title,
    required List<Map<String, dynamic>> details,
  }) {
    // 1. Agrupar por nombre de ejercicio, bloque y fecha
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var d in details) {
      final dateStr =
          d['date'] != null
              ? "${(d['date'] as DateTime).day}/${(d['date'] as DateTime).month}"
              : "";
      final groupKey = "${d['name']}_${d['blockTitle']}_$dateStr";
      grouped.putIfAbsent(groupKey, () => []).add(d);
    }

    final sortedGroups =
        grouped.entries.toList()..sort((a, b) {
          // Ordenar por fecha desc y luego nombre
          final dateA = a.value.first['date'] as DateTime?;
          final dateB = b.value.first['date'] as DateTime?;
          if (dateA != null && dateB != null) {
            final cmp = dateB.compareTo(dateA);
            if (cmp != 0) return cmp;
          }
          return a.value.first['name'].toString().compareTo(
            b.value.first['name'].toString(),
          );
        });

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sortedGroups.length,
                itemBuilder: (context, index) {
                  final group = sortedGroups[index];
                  final items = group.value;
                  final first = items.first;
                  final totalLoad = items.fold<double>(
                    0,
                    (accumulated, item) =>
                        accumulated + (item['load'] as double),
                  );

                  final dateStr =
                      first['date'] != null
                          ? "${(first['date'] as DateTime).day}/${(first['date'] as DateTime).month}"
                          : "";

                  return Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                      childrenPadding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        bottom: 8,
                      ),
                      title: Text(
                        first['name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        "${first['blockTitle']} ${dateStr.isNotEmpty ? "• $dateStr" : ""}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Text(
                        totalLoad.toStringAsFixed(2),
                        style: const TextStyle(
                          color: AppColors.info,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      iconColor: Colors.grey,
                      collapsedIconColor: Colors.grey,
                      children:
                          items.map((d) {
                            final muscleLabel =
                                d['muscle'] != null
                                    ? _muscleLabel(d['muscle'])
                                    : "";
                            final muscleWeightPct =
                                (d['value'] as num).toDouble() * 100;
                            final muscleWeightStr =
                                muscleWeightPct == muscleWeightPct.toInt()
                                    ? muscleWeightPct.toStringAsFixed(0)
                                    : muscleWeightPct.toStringAsFixed(1);

                            final double sets =
                                (d['sets'] as num?)?.toDouble() ?? 1.0;
                            final double typeFactor =
                                (d['factor'] as num?)?.toDouble() ?? 1.0;
                            final double structFactor =
                                (d['structFactor'] as num?)?.toDouble() ?? 1.0;
                            final double finalLoad =
                                (d['load'] as num?)?.toDouble() ?? 0.0;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white10,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        muscleLabel,
                                        style: const TextStyle(
                                          color: AppColors.info,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        finalLoad.toStringAsFixed(2),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Línea de la Fórmula
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _formulaPart(
                                          "Cant",
                                          sets.toStringAsFixed(1),
                                          Colors.grey,
                                        ),
                                        _formulaOperator("×"),
                                        _formulaPart(
                                          "Tipo",
                                          typeFactor.toStringAsFixed(1),
                                          Colors.orangeAccent,
                                        ),
                                        if (structFactor != 1.0) ...[
                                          _formulaOperator("×"),
                                          _formulaPart(
                                            "Estr",
                                            structFactor.toStringAsFixed(1),
                                            Colors.purpleAccent,
                                          ),
                                        ],
                                        _formulaOperator("×"),
                                        _formulaPart(
                                          "Peso músc",
                                          "$muscleWeightStr%",
                                          Colors.greenAccent,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Entendido"),
              ),
            ],
          ),
    );
  }

  Widget _formulaPart(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formulaOperator(String op) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(op, style: const TextStyle(color: Colors.grey, fontSize: 10)),
    );
  }

  Widget _buildPieCharts() {
    final groupLoads = _groupLoadsFrom(totalLoad);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSmallPieCard("Grupos Anatómicos", groupLoads),
        _buildSmallPieCard("Tipos de Ejercicio", exerciseTypeLoad),
      ],
    );
  }

  Widget _buildImbalanceCard() {
    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.balance, color: Colors.orangeAccent),
              SizedBox(width: 10),
              Text(
                "Desbalances detectados",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (imbalanceAlerts.isEmpty)
            const Text(
              "No se detectaron desbalances relevantes en esta semana.",
            )
          else
            ...imbalanceAlerts.map((alert) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(alert.explanation),
                    const SizedBox(height: 6),
                    Text(
                      "${alert.dominantLabel}: ${alert.dominantLoad.toStringAsFixed(1)} • "
                      "${alert.weakerLabel}: ${alert.weakerLoad.toStringAsFixed(1)}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSmallPieCard(String title, Map<dynamic, double> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 380,
      height: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildPieChart(
              data: data,
              colorBase:
                  title.contains("Anatómicos") ? Colors.blue : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart({
    required Map<dynamic, double> data,
    required Color colorBase,
  }) {
    final total = data.values.fold<double>(0, (a, b) => a + b);
    final entries =
        data.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final displayEntries = entries;

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  if (!event.isInterestedForInteractions ||
                      pieTouchResponse == null ||
                      pieTouchResponse.touchedSection == null) {
                    return;
                  }
                  final index =
                      pieTouchResponse.touchedSection!.touchedSectionIndex;
                  if (index < 0 || index >= displayEntries.length) return;

                  final entry = displayEntries[index];
                  final label =
                      entry.key is AnatomicalGroup
                          ? (entry.key as AnatomicalGroup).label
                          : entry.key.toString();

                  if (event is FlTapUpEvent) {
                    if (entry.key is AnatomicalGroup) {
                      _showDetailsList(
                        title: "Desglose: $label",
                        details: anatomicalGroupDetails[entry.key] ?? [],
                      );
                    } else {
                      _showDetailsList(
                        title: "Desglose: $label",
                        details:
                            exerciseTypeDetails[entry.key.toString()] ?? [],
                      );
                    }
                  }
                },
              ),
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: List.generate(displayEntries.length, (index) {
                final entry = displayEntries[index];
                final percent = total == 0 ? 0 : (entry.value / total) * 100;
                return PieChartSectionData(
                  value: entry.value,
                  color:
                      entry.key is AnatomicalGroup
                          ? anatomicalPalette[index % anatomicalPalette.length]
                          : anatomicalPalette[(index + 3) %
                              anatomicalPalette
                                  .length], // Offset para diferenciar si ambos gráficos se ven juntos
                  radius: 50,
                  title: "${percent.toStringAsFixed(0)}%",
                  titleStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: ListView.builder(
            itemCount: displayEntries.length,
            itemBuilder: (context, index) {
              final entry = displayEntries[index];
              final label =
                  entry.key is AnatomicalGroup
                      ? (entry.key as AnatomicalGroup).label
                      : entry.key.toString();
              return InkWell(
                onTap: () {
                  if (entry.key is AnatomicalGroup) {
                    _showDetailsList(
                      title: "Desglose: $label",
                      details: anatomicalGroupDetails[entry.key] ?? [],
                    );
                  } else {
                    _showDetailsList(
                      title: "Desglose: $label",
                      details: exerciseTypeDetails[entry.key.toString()] ?? [],
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              entry.key is AnatomicalGroup
                                  ? anatomicalPalette[index %
                                      anatomicalPalette.length]
                                  : anatomicalPalette[(index + 3) %
                                      anatomicalPalette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        entry.value.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.info,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildComplianceTab() {
    if (sortedDayKeys.isEmpty) {
      return _buildEmptyState(
        "No hay planificación ni entrenamientos esta semana.",
      );
    }

    final dayResults = reviewByDay[selectedReviewDayKey] ?? [];
    final okItems =
        dayResults.where((r) => r.achieved >= r.planned.plannedVol).toList();
    final partialItems =
        dayResults
            .where((r) => r.achieved > 0 && r.achieved < r.planned.plannedVol)
            .toList();
    final missingItems = dayResults.where((r) => r.achieved == 0).toList();
    final extrasList = extrasByDay[selectedReviewDayKey] ?? [];

    final identity = trainingIdentity;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RepaintBoundary(
          key: _complianceExportKey,
          child: Container(
            color: AppColors.bg,
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _athleteName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Text(
                      "${startOfWeek.day}/${startOfWeek.month} al "
                      "${endOfWeek.subtract(const Duration(days: 1)).day}/${endOfWeek.month}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildComplianceSummaryHeader(),
                if (identity != null && identity.exercises.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildProfileRadarCard(identity),
                ],
                const SizedBox(height: 16),
                _buildWeightComplianceCard(),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _exportingPng ? null : _exportComplianceSummaryPng,
            icon:
                _exportingPng
                    ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.image_outlined, size: 18),
            label: const Text("Exportar como imagen"),
          ),
        ),
        const SizedBox(height: 16),
        _buildRpeKpiCard(),
        const SizedBox(height: 16),
        _buildWeeklyTrendCard(),
        const SizedBox(height: 16),
        _buildLoadAdjustmentAlertsCard(),
        const SizedBox(height: 16),
        _buildProgressionShortcutCard(),
        const SizedBox(height: 24),
        const Text(
          "Detalle diario (series)",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _DayChipSelector(
          days: sortedDayKeys.map(DateTime.parse).toList(),
          selectedDay:
              selectedReviewDayKey == null
                  ? null
                  : DateTime.parse(selectedReviewDayKey!),
          labelFor: (day) => _dayKey(day).substring(5), // MM-DD
          onSelected:
              (day) => setState(() => selectedReviewDayKey = _dayKey(day!)),
        ),
        const SizedBox(height: 8),
        if (okItems.isNotEmpty)
          _buildComplianceSection("Completado", okItems, Colors.green),
        if (partialItems.isNotEmpty)
          _buildComplianceSection("Parcial", partialItems, Colors.orange),
        if (missingItems.isNotEmpty)
          _buildComplianceSection("Pendiente", missingItems, Colors.red),
        if (extrasList.isNotEmpty) _buildExtrasSection(extrasList),
      ],
    );
  }

  Widget _buildWeightComplianceCard() {
    if (exerciseLoadCompliance.isEmpty) {
      return const SizedBox();
    }
    final pct = weeklyPlannedKg > 0 ? weeklyAchievedKg / weeklyPlannedKg : 0.0;
    final topExercises = exerciseLoadCompliance.take(8).toList();
    final maxKg =
        topExercises.isEmpty
            ? 1.0
            : topExercises
                .map(
                  (e) =>
                      e.plannedKg > e.achievedKg ? e.plannedKg : e.achievedKg,
                )
                .fold(1.0, (a, b) => a > b ? a : b);

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fitness_center, color: Colors.amberAccent),
              SizedBox(width: 10),
              Text(
                "Carga real (kg): plan vs realizado a la fecha",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "${weeklyAchievedKg.toStringAsFixed(0)} kg de ${weeklyPlannedKg.toStringAsFixed(0)} kg planificados hasta hoy"
            " (${(pct * 100).toStringAsFixed(0)}%)",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ...topExercises.map((e) => _weightBarRow(e, maxKg)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              _legendDot(AppColors.info, "Planificado"),
              _legendDot(const Color(0xFFD95926), "Realizado"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weightBarRow(ExerciseLoadCompliance e, double maxKg) {
    final plannedFrac = (e.plannedKg / maxKg).clamp(0.0, 1.0);
    final achievedFrac = (e.achievedKg / maxKg).clamp(0.0, 1.0);
    final pctLabel =
        e.plannedKg > 0 ? "${(e.pct * 100).toStringAsFixed(0)}%" : "extra";
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showSetBySetDialog(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    e.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  pctLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color:
                        e.pct >= 1
                            ? Colors.greenAccent
                            : e.pct >= 0.7
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 4),
            Stack(
              children: [
                _barTrack(plannedFrac, AppColors.info.withOpacity(0.35)),
                _barTrack(achievedFrac, const Color(0xFFD95926)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Desglose serie a serie al tocar un ejercicio: peso/reps planificados
  /// vs cada serie realmente ejecutada (con su variante y RPE si difiere de
  /// la planificada — ej. cambio de máquina por equipo ocupado).
  void _showSetBySetDialog(ExerciseLoadCompliance e) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(e.name),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e.plannedSets.isNotEmpty) ...[
                      const Text(
                        "Planificado",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.info,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < e.plannedSets.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            "Serie ${i + 1}: ${e.plannedSets[i].weight.toStringAsFixed(1)} kg × "
                            "${e.plannedSets[i].reps.toStringAsFixed(0)} reps"
                            "${e.plannedSets[i].variantLabel != null ? ' · ${e.plannedSets[i].variantLabel}' : ''}",
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (e.achievedSets.isNotEmpty) ...[
                      const Text(
                        "Realizado",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD95926),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < e.achievedSets.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            "Serie ${i + 1}: ${e.achievedSets[i].weight.toStringAsFixed(1)} kg × "
                            "${e.achievedSets[i].reps.toStringAsFixed(0)} reps"
                            "${e.achievedSets[i].rpe != null ? ' · RPE ${e.achievedSets[i].rpe!.toStringAsFixed(0)}' : ''}"
                            "${e.achievedSets[i].variantLabel != null ? ' · ${e.achievedSets[i].variantLabel}' : ''}",
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    if (e.plannedSets.isEmpty && e.achievedSets.isEmpty)
                      const Text(
                        "Sin detalle de series disponible.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    if (e.achievedSets.isNotEmpty &&
                        e.plannedSets.isNotEmpty &&
                        e.achievedSets.any(
                          (s) =>
                              s.variantLabel != null &&
                              s.variantLabel !=
                                  e.plannedSets.first.variantLabel,
                        ))
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          "⚠ Se ejecutó con una variante distinta a la planificada "
                          "(mismo movimiento, distinto equipo).",
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Cerrar"),
              ),
            ],
          ),
    );
  }

  Widget _barTrack(double frac, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: frac,
          minHeight: 8,
          backgroundColor: Colors.transparent,
          color: color,
        ),
      ),
    );
  }

  Widget _buildRpeKpiCard() {
    if (weeklyAvgRpe <= 0) return const SizedBox();
    return _DarkCard(
      child: Row(
        children: [
          const Icon(Icons.speed, color: Colors.pinkAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "RPE promedio real de la semana",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                const Text(
                  "El plan no define un RPE objetivo — este es el esfuerzo percibido "
                  "real reportado por el atleta.",
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            weeklyAvgRpe.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.pinkAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTrendCard() {
    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: AppColors.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Tendencia de cumplimiento (últimas semanas)",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (weeklyTrend.isEmpty)
                TextButton.icon(
                  onPressed: _loadingTrend ? null : () => _loadWeeklyTrend(),
                  icon:
                      _loadingTrend
                          ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.refresh, size: 18),
                  label: const Text("Cargar"),
                ),
            ],
          ),
          if (weeklyTrend.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(height: 200, child: _weeklyTrendChart()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                _legendDot(AppColors.accent, "% Series"),
                _legendDot(Colors.amberAccent, "% Kg"),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _weeklyTrendChart() {
    final seriesSpots = <FlSpot>[];
    final kgSpots = <FlSpot>[];
    for (var i = 0; i < weeklyTrend.length; i++) {
      seriesSpots.add(FlSpot(i.toDouble(), weeklyTrend[i].seriesPct * 100));
      kgSpots.add(FlSpot(i.toDouble(), weeklyTrend[i].kgPct * 100));
    }
    return LineChart(
      LineChartData(
        minY: 0,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget:
                  (v, _) => Text(
                    "${v.toInt()}%",
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= weeklyTrend.length) return const SizedBox();
                final d = weeklyTrend[i].weekStart;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "${d.day}/${d.month}",
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine:
              (_) => const FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: seriesSpots,
            isCurved: false,
            color: AppColors.accent,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: kgSpots,
            isCurved: false,
            color: Colors.amberAccent,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadAdjustmentAlertsCard() {
    return _DarkCard(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('load_adjustment_alerts')
                .where('athleteId', isEqualTo: _athleteId)
                .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? const [];
          final pending =
              docs.where((d) => d.data()['status'] == 'pending').toList()
                ..sort((a, b) {
                  final ad =
                      (a.data()['workoutDate'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  final bd =
                      (b.data()['workoutDate'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  return bd.compareTo(ad);
                });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.notification_important_outlined,
                    color: Colors.orangeAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Alertas de ajuste de carga (${pending.length} pendientes)",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => LoadAdjustmentAlertsScreen(
                                  athleteId: _athleteId,
                                  athleteName: _athleteName,
                                ),
                          ),
                        ),
                    child: const Text("Ver todas"),
                  ),
                ],
              ),
              if (pending.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "No hay ajustes de carga pendientes.",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              else
                ...pending.take(3).map((doc) {
                  final data = doc.data();
                  final direction = data['direction']?.toString();
                  final date = (data['workoutDate'] as Timestamp?)?.toDate();
                  final highPriority = data['priority'] == 'high';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      direction == 'lower'
                          ? Icons.trending_down
                          : direction == 'higher'
                          ? Icons.trending_up
                          : Icons.swap_vert,
                      color:
                          highPriority
                              ? Colors.redAccent
                              : (direction == 'lower'
                                  ? Colors.orange
                                  : Colors.teal),
                    ),
                    title: Text(
                      data['exerciseName']?.toString() ?? 'Ejercicio',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      date == null
                          ? ''
                          : "${date.day}/${date.month}/${date.year}"
                              "${data['isTrend'] == true ? ' · Tendencia' : ''}",
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressionShortcutCard() {
    if (widget.onProgressionByExercise == null) return const SizedBox();
    return _DarkCard(
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: Colors.lightBlueAccent),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Planificar la progresión de carga para la próxima semana",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          FilledButton(
            onPressed: widget.onProgressionByExercise,
            child: const Text("Progresión por ejercicio"),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceSection(
    String title,
    List<DayResultItem> items,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        ...items.map(
          (r) => Card(
            color: AppColors.surface,
            child: ListTile(
              title: Text(r.planned.name),
              subtitle: Text(
                "${r.planned.blockLabel}\nPlan: ${r.planned.plannedVol.toStringAsFixed(0)} • Hecho: ${r.achieved.toStringAsFixed(0)}"
                "${r.substitutedBy != null ? '\n↔ Hecho con variante: ${r.substitutedBy}' : ''}",
              ),
              trailing: Icon(
                r.achieved >= r.planned.plannedVol
                    ? Icons.check_circle
                    : Icons.pending,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExtrasSection(List<Map<String, dynamic>> extras) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            "Extras Realizados",
            style: TextStyle(
              color: AppColors.info,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        ...extras.map(
          (e) => Card(
            color: AppColors.surface,
            child: ListTile(
              title: Text(e['name']),
              subtitle: Text(
                "Volumen extra: ${e['volume'].toStringAsFixed(0)}",
              ),
              leading: const Icon(
                Icons.add_circle_outline,
                color: AppColors.info,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComplianceSummaryHeader() {
    final weeklyProgress =
        weeklyPlannedVol > 0 ? (weeklyAchievedVol / weeklyPlannedVol) : 0.0;
    final paceProgress =
        plannedToDateVol > 0 ? (achievedToDateVol / plannedToDateVol) : 1.0;

    final paceColor =
        paceProgress >= 0.95
            ? Colors.greenAccent
            : (paceProgress >= 0.7 ? Colors.orangeAccent : Colors.redAccent);
    final paceLabel =
        paceProgress >= 1.05
            ? "Adelantado"
            : (paceProgress >= 0.95 ? "Al día" : "Atrasado");

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryStatCard(
                  "Progreso Semanal",
                  "${(weeklyProgress * 100).toStringAsFixed(0)}%",
                  subtitle:
                      "${weeklyAchievedVol.toStringAsFixed(0)} / ${weeklyPlannedVol.toStringAsFixed(0)} sets",
                  progress: weeklyProgress,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryStatCard(
                  "Ritmo a la Fecha",
                  paceLabel,
                  subtitle:
                      "${(paceProgress * 100).toStringAsFixed(0)}% del plan",
                  progress: paceProgress.clamp(0.0, 1.0),
                  color: paceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniStat(
                Icons.calendar_today,
                "$achievedDaysCount / $plannedDaysCount días",
                "Consistencia",
              ),
              const Spacer(),
              _miniStat(
                Icons.bolt,
                "${(weeklyAchievedVol - weeklyPlannedVol).clamp(0, double.infinity).toStringAsFixed(1)} sets",
                "Volumen Extra",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStatCard(
    String title,
    String mainValue, {
    required String subtitle,
    required double progress,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            mainValue,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white10,
            color: color,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // ==========================================================
  // HELPER METHODS
  // ==========================================================
  String _dayKey(DateTime d) => TrainingReviewCalculator.dayKey(d);

  Map<AnatomicalGroup, double> _groupLoadsFrom(Map<String, double> source) {
    final Map<AnatomicalGroup, double> result = {};
    for (final group in AnatomicalGroup.values) {
      double sum = 0;
      final muscles = anatomicalGroups[group]!;
      for (final m in muscles) {
        sum += source[m.name] ?? 0;
      }
      result[group] = sum;
    }
    return result;
  }

  Map<Muscle, double> _toMuscleMap(Map<String, double> input) {
    final Map<Muscle, double> result = {};
    for (final entry in input.entries) {
      try {
        final muscle = Muscle.values.firstWhere((m) => m.name == entry.key);
        result[muscle] = entry.value;
      } catch (_) {}
    }
    return result;
  }

  Map<Muscle, double> _normalizeAbsolute(Map<Muscle, double> input) {
    final Map<Muscle, double> scaled = {};
    input.forEach((muscle, value) {
      // Usamos un factor de escala para el heatmap visual
      final percent = (value / 15) * 100;
      scaled[muscle] = percent.clamp(0, 100);
    });
    return scaled;
  }

  String _muscleLabel(String key) {
    try {
      final muscle = Muscle.values.firstWhere((m) => m.name == key);
      return muscle.label;
    } catch (_) {
      return key;
    }
  }
}

/// Contenido de la pestaña "Ejercicios" del modal de detalle del perfil.
/// Es un widget con estado propio (no solo un método del State principal)
/// porque necesita recordar qué día está seleccionado mientras el usuario
/// navega entre pestañas del `DefaultTabController` del diálogo.
class _ExercisesTabContent extends StatefulWidget {
  final List<DateTime> orderedDays;
  final Map<DateTime, List<List<TrainingIdentityExerciseContribution>>>
  groupedEntriesByDay;
  final TrainingIdentityInput Function(
    Iterable<TrainingIdentityExerciseContribution>,
  )
  identityInputFor;
  final String Function(DateTime) formatDetailDay;
  final String Function(String) identitySourceLabel;
  final String Function(String) spanishTechnicalLabel;
  final Widget Function(String, String, double) identityContributionRow;
  final void Function(String, List<TrainingIdentityExerciseContribution>)
  showExerciseSeriesBreakdown;
  final Map<TrainingProfile, double> Function(Map<TrainingProfile, double>)
  relativeProfilePercentages;
  final String Function(double) formatProfilePercent;

  const _ExercisesTabContent({
    required this.orderedDays,
    required this.groupedEntriesByDay,
    required this.identityInputFor,
    required this.formatDetailDay,
    required this.identitySourceLabel,
    required this.spanishTechnicalLabel,
    required this.identityContributionRow,
    required this.showExerciseSeriesBreakdown,
    required this.relativeProfilePercentages,
    required this.formatProfilePercent,
  });

  @override
  State<_ExercisesTabContent> createState() => _ExercisesTabContentState();
}

class _ExercisesTabContentState extends State<_ExercisesTabContent> {
  DateTime? _selectedDay; // null = todos los días de la semana

  @override
  Widget build(BuildContext context) {
    final days = widget.orderedDays;
    final visibleDays = _selectedDay == null ? days : [_selectedDay!];

    // Planificado y realizado SIEMPRE por separado: antes el perfil del día
    // mezclaba ambas fuentes y no mostraba en qué se desvió lo entrenado.
    final scopeExercises = <TrainingIdentityExerciseContribution>[
      for (final d in visibleDays)
        for (final series
            in widget.groupedEntriesByDay[d] ??
                const <List<TrainingIdentityExerciseContribution>>[])
          ...series,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DayChipSelector(
          days: days,
          selectedDay: _selectedDay,
          allowAll: true,
          allLabel: "Toda la semana",
          labelFor: widget.formatDetailDay,
          onSelected: (day) => setState(() => _selectedDay = day),
        ),
        const SizedBox(height: 12),
        if (scopeExercises.isNotEmpty) ...[
          _buildPlanVsRealCard(scopeExercises),
          const SizedBox(height: 20),
        ],
        if (_selectedDay == null) ...[
          _buildDailyLoadBarChartStatic(days, widget.groupedEntriesByDay),
          const SizedBox(height: 20),
        ],
        const Text(
          "Aporte por ejercicio",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...visibleDays.expand(
          (day) => _buildDaySection(
            day,
            widget.groupedEntriesByDay[day] ??
                const <List<TrainingIdentityExerciseContribution>>[],
          ),
        ),
      ],
    );
  }

  static const _kPlanColor = AppColors.info;
  static const _kRealColor = Color(0xFFD95926);

  /// Contraste planificado vs realizado del alcance visible (un día o toda
  /// la semana): carga total y distribución por perfil, lado a lado.
  Widget _buildPlanVsRealCard(
    List<TrainingIdentityExerciseContribution> exercises,
  ) {
    final planned = exercises.where((e) => e.source == 'planned').toList();
    final logged = exercises.where((e) => e.source == 'logged').toList();
    double loadOf(List<TrainingIdentityExerciseContribution> list) =>
        list.fold<double>(0, (total, e) => total + e.load);
    Map<TrainingProfile, double> relOf(
      List<TrainingIdentityExerciseContribution> list,
    ) =>
        list.isEmpty
            ? const {}
            : widget.relativeProfilePercentages(
              TrainingIdentityService.analyze(
                widget.identityInputFor(list),
              ).scores,
            );

    final plannedLoad = loadOf(planned);
    final loggedLoad = loadOf(logged);
    final plannedRel = relOf(planned);
    final loggedRel = relOf(logged);
    final profiles =
        {...plannedRel.keys, ...loggedRel.keys}.toList()..sort(
          (a, b) => ((loggedRel[b] ?? plannedRel[b] ?? 0)).compareTo(
            loggedRel[a] ?? plannedRel[a] ?? 0,
          ),
        );
    final loadDiffPct =
        plannedLoad > 0 ? (loggedLoad - plannedLoad) / plannedLoad * 100 : null;

    Widget legendDot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );

    Widget bar(double value, Color color) => ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: (value / 100).clamp(0.0, 1.0),
        backgroundColor: Colors.white10,
        color: color,
        minHeight: 6,
      ),
    );

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selectedDay == null
                      ? "Planificado vs realizado · semana"
                      : "Planificado vs realizado · ${widget.formatDetailDay(_selectedDay!)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Carga ──
          Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              legendDot(_kPlanColor, "Plan ${plannedLoad.toStringAsFixed(1)}"),
              legendDot(_kRealColor, "Real ${loggedLoad.toStringAsFixed(1)}"),
              if (loadDiffPct != null)
                Text(
                  "Carga ${loadDiffPct >= 0 ? '+' : ''}${loadDiffPct.toStringAsFixed(0)}%",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color:
                        loadDiffPct.abs() <= 10
                            ? AppColors.accentSoft
                            : Colors.amber,
                  ),
                ),
            ],
          ),
          if (planned.isEmpty || logged.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                planned.isEmpty
                    ? "Sin planificación en este período: solo se muestra lo realizado."
                    : "Aún no hay entrenamiento registrado en este período.",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          // ── Distribución por perfil ──
          for (final profile in profiles) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (plannedRel.isNotEmpty && loggedRel.isNotEmpty)
                  Builder(
                    builder: (_) {
                      final delta =
                          (loggedRel[profile] ?? 0) -
                          (plannedRel[profile] ?? 0);
                      return Text(
                        "${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)} pp",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color:
                              delta.abs() < 5
                                  ? Colors.grey
                                  : (delta > 0 ? _kRealColor : _kPlanColor),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: bar(plannedRel[profile] ?? 0, _kPlanColor)),
                SizedBox(
                  width: 44,
                  child: Text(
                    widget.formatProfilePercent(plannedRel[profile] ?? 0),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(child: bar(loggedRel[profile] ?? 0, _kRealColor)),
                SizedBox(
                  width: 44,
                  child: Text(
                    widget.formatProfilePercent(loggedRel[profile] ?? 0),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyLoadBarChartStatic(
    List<DateTime> orderedDays,
    Map<DateTime, List<List<TrainingIdentityExerciseContribution>>>
    groupedEntriesByDay,
  ) {
    if (orderedDays.isEmpty) return const SizedBox.shrink();

    // Dos barras por día (plan / real). Antes era una sola que sumaba ambas
    // fuentes, así que un día cumplido mostraba el doble de carga.
    Map<DateTime, double> loadBySource(String source) => {
      for (final day in orderedDays)
        day: (groupedEntriesByDay[day] ?? const [])
            .expand((series) => series)
            .where((item) => item.source == source)
            .fold<double>(0, (total, item) => total + item.load),
    };
    final plannedByDay = loadBySource('planned');
    final loggedByDay = loadBySource('logged');
    final maxLoad = [
      ...plannedByDay.values,
      ...loggedByDay.values,
    ].fold<double>(0, (max, v) => v > max ? v : max);

    return _DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Carga por día",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Wrap(
            spacing: 16,
            children: [
              _LegendSwatch(color: _kPlanColor, label: "Planificado"),
              _LegendSwatch(color: _kRealColor, label: "Realizado"),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child:
                maxLoad <= 0
                    ? const Center(
                      child: Text(
                        "Sin carga registrada",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                    : BarChart(
                      BarChartData(
                        maxY: maxLoad * 1.15,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= orderedDays.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    widget.formatDetailDay(orderedDays[index]),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, _, rod, __) {
                              return BarTooltipItem(
                                rod.toY.toStringAsFixed(1),
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        barGroups: [
                          for (int i = 0; i < orderedDays.length; i++)
                            BarChartGroupData(
                              x: i,
                              barsSpace: 3,
                              barRods: [
                                BarChartRodData(
                                  toY: plannedByDay[orderedDays[i]] ?? 0,
                                  color: _kPlanColor,
                                  width: 11,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                BarChartRodData(
                                  toY: loggedByDay[orderedDays[i]] ?? 0,
                                  color: _kRealColor,
                                  width: 11,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDaySection(
    DateTime day,
    List<List<TrainingIdentityExerciseContribution>> entriesForDay,
  ) {
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 12, top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.teal.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.formatDetailDay(day),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              "${entriesForDay.length} ejercicios",
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
      ..._pairPlannedWithLogged(
        entriesForDay,
      ).map((pair) => _buildComparisonTile(pair.planned, pair.logged)),
    ];
  }

  // ======================================================
  // PLANIFICADO vs REALIZADO POR EJERCICIO
  // ======================================================

  static String _normName(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Nombre del movimiento sin la variante ("Remo - Barra" → "remo"), para
  /// emparejar una sustitución por variante con lo planificado.
  static String _movementBase(String s) => _normName(s.split(' - ').first);

  /// Empareja cada ejercicio planificado del día con su ejecución: primero
  /// por nombre exacto y, si no, por el mismo movimiento con otra variante.
  /// Lo ejecutado que sobra se muestra como extra (sin planificar).
  List<
    ({
      List<TrainingIdentityExerciseContribution>? planned,
      List<TrainingIdentityExerciseContribution>? logged,
    })
  >
  _pairPlannedWithLogged(
    List<List<TrainingIdentityExerciseContribution>> entriesForDay,
  ) {
    final planned =
        entriesForDay.where((s) => s.first.source == 'planned').toList();
    final logged = entriesForDay.where((s) => s.first.source != 'planned');
    final remaining = [...logged];
    final pairs =
        <
          ({
            List<TrainingIdentityExerciseContribution>? planned,
            List<TrainingIdentityExerciseContribution>? logged,
          })
        >[];

    List<TrainingIdentityExerciseContribution>? take(
      bool Function(TrainingIdentityExerciseContribution) test,
    ) {
      final index = remaining.indexWhere((s) => test(s.first));
      return index == -1 ? null : remaining.removeAt(index);
    }

    // Pasada 1: nombre exacto (evita que una sustitución "robe" el match
    // de un ejercicio que sí se hizo tal cual).
    final exact = <int, List<TrainingIdentityExerciseContribution>?>{};
    for (var i = 0; i < planned.length; i++) {
      final name = _normName(planned[i].first.name);
      exact[i] = take((e) => _normName(e.name) == name);
    }
    // Pasada 2: mismo movimiento, otra variante.
    for (var i = 0; i < planned.length; i++) {
      final base = _movementBase(planned[i].first.name);
      final match = exact[i] ?? take((e) => _movementBase(e.name) == base);
      pairs.add((planned: planned[i], logged: match));
    }
    for (final extra in remaining) {
      pairs.add((planned: null, logged: extra));
    }
    return pairs;
  }

  Widget _buildComparisonTile(
    List<TrainingIdentityExerciseContribution>? planned,
    List<TrainingIdentityExerciseContribution>? logged,
  ) {
    final stats = _ExerciseSideStats.from;
    final p = planned == null ? null : stats(planned);
    final r = logged == null ? null : stats(logged);
    final title = (planned ?? logged)!.first.name;
    final substituted =
        planned != null &&
        logged != null &&
        _normName(planned.first.name) != _normName(logged.first.name);

    final pRel =
        p == null
            ? const <TrainingProfile, double>{}
            : widget.relativeProfilePercentages(p.profile);
    final rRel =
        r == null
            ? const <TrainingProfile, double>{}
            : widget.relativeProfilePercentages(r.profile);
    final loadDelta =
        (p != null && r != null && p.load > 0)
            ? (r.load - p.load) / p.load * 100
            : null;

    final status =
        planned == null
            ? ('Extra', AppColors.info)
            : logged == null
            ? ('No realizado', Colors.redAccent)
            : substituted
            ? ('Variante', Colors.amber)
            : (loadDelta != null && loadDelta.abs() <= 10)
            ? ('Según plan', AppColors.accentSoft)
            : ('Distinto', Colors.amber);

    String fmt(double? v, {int decimals = 0, String suffix = ''}) =>
        v == null ? '—' : '${v.toStringAsFixed(decimals)}$suffix';

    TableRow row(String label, String plan, String real) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        Text(
          plan,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          real,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );

    // Perfiles con mayor cambio (o los principales si solo hay un lado).
    final profileKeys =
        {...pRel.keys, ...rRel.keys}.toList()..sort(
          (a, b) => ((rRel[b] ?? 0) - (pRel[b] ?? 0)).abs().compareTo(
            ((rRel[a] ?? 0) - (pRel[a] ?? 0)).abs(),
          ),
        );

    final reasons = _explainDifference(planned, logged, p, r, substituted);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.$2.withOpacity(0.35)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (substituted)
                      Text(
                        "↔ Hecho: ${logged.first.name}",
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status.$2.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.$1,
                  style: TextStyle(
                    color: status.$2,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.4),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      children: [
                        const SizedBox.shrink(),
                        Text(
                          "Plan",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: _kPlanColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Real",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: _kRealColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    row("Series", fmt(p?.sets), fmt(r?.sets)),
                    row(
                      "Reps promedio",
                      fmt(p?.avgReps, decimals: 1),
                      fmt(r?.avgReps, decimals: 1),
                    ),
                    if (p?.avgWeight != null || r?.avgWeight != null)
                      row(
                        "Peso promedio",
                        fmt(p?.avgWeight, decimals: 1, suffix: ' kg'),
                        fmt(r?.avgWeight, decimals: 1, suffix: ' kg'),
                      ),
                    if (r?.avgRpe != null)
                      row(
                        "RPE promedio",
                        fmt(p?.avgRpe, decimals: 1),
                        fmt(r?.avgRpe, decimals: 1),
                      ),
                    row(
                      "Carga",
                      fmt(p?.load, decimals: 2),
                      "${fmt(r?.load, decimals: 2)}${loadDelta == null ? '' : ' (${loadDelta >= 0 ? '+' : ''}${loadDelta.toStringAsFixed(0)}%)'}",
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Desplegado: solo lo que la tabla no dice, sin repetir datos.
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reasons.isNotEmpty) ...[
              _detailHeading("Por qué da distinto"),
              for (final reason in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    "• $reason",
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (profileKeys.isNotEmpty) ...[
              _detailHeading("Aporte al perfil"),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.6),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(0.9),
                },
                children: [
                  for (final profile in [...profileKeys]..sort(
                    (a, b) => (rRel[b] ?? pRel[b] ?? 0).compareTo(
                      rRel[a] ?? pRel[a] ?? 0,
                    ),
                  ))
                    if ((pRel[profile] ?? 0) >= 0.5 ||
                        (rRel[profile] ?? 0) >= 0.5)
                      _profileRow(profile, pRel[profile], rRel[profile]),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _detailHeading("Clasificación"),
            Text(
              _characteristicsLine(planned?.first, logged?.first),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (planned != null)
                  TextButton.icon(
                    onPressed:
                        () => widget.showExerciseSeriesBreakdown(
                          planned.first.name,
                          [...planned]
                            ..sort((a, b) => a.setLabel.compareTo(b.setLabel)),
                        ),
                    icon: const Icon(Icons.format_list_bulleted, size: 18),
                    label: const Text("Series planificadas"),
                  ),
                if (logged != null)
                  TextButton.icon(
                    onPressed:
                        () => widget.showExerciseSeriesBreakdown(
                          logged.first.name,
                          [...logged]
                            ..sort((a, b) => a.setLabel.compareTo(b.setLabel)),
                        ),
                    icon: const Icon(Icons.format_list_bulleted, size: 18),
                    label: const Text("Series realizadas"),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Explicación en lenguaje simple de por qué el aporte ejecutado difiere
  /// del planificado, en el mismo orden en que pesan en el cálculo del
  /// perfil: qué se hizo, cuánto, con qué intensidad y con qué implemento.
  List<String> _explainDifference(
    List<TrainingIdentityExerciseContribution>? planned,
    List<TrainingIdentityExerciseContribution>? logged,
    _ExerciseSideStats? p,
    _ExerciseSideStats? r,
    bool substituted,
  ) {
    if (planned == null) {
      return ["No estaba planificado: suma carga y perfil extra a la semana."];
    }
    if (logged == null || r == null || p == null) {
      return [
        "No se registró: su aporte planificado queda sin realizar y el perfil real pierde esta parte.",
      ];
    }

    final reasons = <String>[];
    final pe = planned.first;
    final re = logged.first;

    if (substituted) {
      reasons.add(
        "Se hizo otra variante (${re.name}): cambia la ponderación muscular y, si cambia el implemento, también el perfil.",
      );
    }
    String implement(TrainingIdentityExerciseContribution e) =>
        e.bodyweight
            ? 'peso corporal'
            : e.guided
            ? 'máquina/polea'
            : e.freeWeight
            ? 'peso libre'
            : 'otro implemento';
    if (implement(pe) != implement(re)) {
      reasons.add(
        "Implemento: ${implement(pe)} → ${implement(re)}. Máquinas y poleas suman a Hipertrofia; peso libre suma a Fuerza y Rendimiento.",
      );
    }
    if (pe.unilateral != re.unilateral) {
      reasons.add(
        re.unilateral
            ? "Pasó a unilateral: suma a Rendimiento y Control."
            : "Pasó a bilateral: suma a Fuerza máxima.",
      );
    }
    if (pe.blockType != re.blockType) {
      final toCircuit = re.blockType.toLowerCase().trim() == 'circuito';
      final fromCircuit = pe.blockType.toLowerCase().trim() == 'circuito';
      reasons.add(
        "Estructura del bloque: ${widget.spanishTechnicalLabel(pe.blockType)} → ${widget.spanishTechnicalLabel(re.blockType)}."
        "${toCircuit
            ? ' En circuito los ejercicios van seguidos sin descanso: suma un plus a Acondicionamiento.'
            : fromCircuit
            ? ' Fuera de circuito pierde el plus de Acondicionamiento.'
            : ''}",
      );
    }

    if ((r.sets - p.sets).abs() >= 1) {
      reasons.add(
        r.sets > p.sets
            ? "Hizo ${r.sets.toStringAsFixed(0)} series de ${p.sets.toStringAsFixed(0)} planificadas: más volumen."
            : "Hizo ${r.sets.toStringAsFixed(0)} de ${p.sets.toStringAsFixed(0)} series: las no marcadas como hechas no cuentan.",
      );
    }

    if (p.avgReps > 0 && (r.avgReps - p.avgReps).abs() >= 2) {
      final more = r.avgReps > p.avgReps;
      final bucketChange =
          pe.repBucket != re.repBucket
              ? " (rango ${pe.repBucket} → ${re.repBucket})"
              : "";
      final strength =
          re.exerciseType.toLowerCase().contains('fuerza') &&
          re.blockType.toLowerCase().trim() != 'circuito';
      final String effect;
      if (!more) {
        effect =
            'Menos reps inclinan hacia Fuerza máxima y restan Hipertrofia.';
      } else if (strength && r.avgReps <= 15) {
        effect =
            'En fuerza, sobre 10 reps resta Fuerza máxima y eso pasa a Hipertrofia (y algo a Control); hasta 15 reps no suma a Acondicionamiento.';
      } else if (strength) {
        effect =
            'En fuerza, sobre 15 reps ya suma algo a Acondicionamiento; lo que pierde Fuerza máxima pasa a Hipertrofia y Control.';
      } else {
        effect =
            'Más reps inclinan hacia Hipertrofia y Acondicionamiento y restan Fuerza máxima.';
      }
      reasons.add(
        "Repeticiones: ${p.avgReps.toStringAsFixed(0)} → ${r.avgReps.toStringAsFixed(0)}$bucketChange. $effect",
      );
    }

    if (p.avgWeight != null &&
        r.avgWeight != null &&
        p.avgWeight! > 0 &&
        ((r.avgWeight! - p.avgWeight!) / p.avgWeight!).abs() >= 0.05) {
      final pct = (r.avgWeight! - p.avgWeight!) / p.avgWeight! * 100;
      reasons.add(
        "Peso: ${p.avgWeight!.toStringAsFixed(1)} → ${r.avgWeight!.toStringAsFixed(1)} kg (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(0)}%).",
      );
    }

    if (r.avgRpe != null && p.avgRpe == null) {
      final estimated = TrainingIdentityService.percent1RMFromRpe(
        rpe: r.avgRpe!,
        reps: r.avgReps,
      );
      reasons.add(
        "Intensidad: se registró RPE ${r.avgRpe!.toStringAsFixed(1)} (≈${(estimated * 100).toStringAsFixed(0)}% del 1RM). "
        "Lo planificado no tiene RPE, así que ahí la intensidad queda neutra: "
        "${estimated >= 0.8
            ? 'lo real suma más a Fuerza máxima.'
            : estimated < 0.65
            ? 'lo real suma más a Acondicionamiento y Rendimiento.'
            : 'efecto moderado, cerca de Hipertrofia.'}",
      );
    }

    if (reasons.isEmpty) {
      reasons.add("Se ejecutó prácticamente como estaba planificado.");
    }
    return reasons;
  }

  Widget _detailHeading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
    ),
  );

  TableRow _profileRow(TrainingProfile profile, double? plan, double? real) {
    final delta = (plan != null && real != null) ? real - plan : null;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(profile.label, style: const TextStyle(fontSize: 12)),
        ),
        Text(
          plan == null ? '—' : widget.formatProfilePercent(plan),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12, color: _kPlanColor),
        ),
        Text(
          real == null ? '—' : widget.formatProfilePercent(real),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12, color: _kRealColor),
        ),
        Text(
          delta == null || delta.abs() < 1
              ? ''
              : "${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)} pp",
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  /// Tipo, implemento y estructura en una línea; si cambió entre plan y
  /// real se muestra "plan → real".
  String _characteristicsLine(
    TrainingIdentityExerciseContribution? planned,
    TrainingIdentityExerciseContribution? logged,
  ) {
    List<String> traits(TrainingIdentityExerciseContribution e) => [
      widget.spanishTechnicalLabel(e.exerciseType),
      e.bodyweight
          ? 'peso corporal'
          : e.guided
          ? 'máquina/polea'
          : e.freeWeight
          ? 'peso libre'
          : 'otro implemento',
      e.unilateral ? 'unilateral' : 'bilateral',
      e.compound ? 'compuesto' : (e.isolation ? 'aislado' : ''),
      widget.spanishTechnicalLabel(e.blockType),
    ];
    final a = planned == null ? null : traits(planned);
    final b = logged == null ? null : traits(logged);
    final base = a ?? b!;
    return [
      for (var i = 0; i < base.length; i++)
        if (a != null && b != null && a[i] != b[i])
          '${a[i]} → ${b[i]}'
        else if (base[i].isNotEmpty)
          base[i],
    ].join(' · ');
  }
}

/// Muestra de color + etiqueta para leyendas de gráficos (plan / real).
class _LegendSwatch extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

/// Resumen de un lado (planificado o realizado) de un ejercicio, para la
/// comparación por ejercicio de la pestaña "Ejercicios".
class _ExerciseSideStats {
  final double sets;
  final double avgReps;
  final double? avgWeight;
  final double? avgRpe;
  final double load;
  final Map<TrainingProfile, double> profile;

  const _ExerciseSideStats({
    required this.sets,
    required this.avgReps,
    required this.avgWeight,
    required this.avgRpe,
    required this.load,
    required this.profile,
  });

  static _ExerciseSideStats from(
    List<TrainingIdentityExerciseContribution> series,
  ) {
    final sets = series.fold<double>(0, (t, e) => t + e.baseSets);
    final avgReps =
        sets <= 0
            ? 0.0
            : series.fold<double>(0, (t, e) => t + e.targetReps * e.baseSets) /
                sets;
    final weights =
        series
            .map((e) => e.referenceWeight)
            .whereType<double>()
            .where((w) => w > 0)
            .toList();
    final rpes = series.map((e) => e.reportedRpe).whereType<double>().toList();
    final profile = <TrainingProfile, double>{};
    for (final e in series) {
      e.finalProfileContributions.forEach((k, v) {
        profile[k] = (profile[k] ?? 0) + v;
      });
    }
    return _ExerciseSideStats(
      sets: sets,
      avgReps: avgReps,
      avgWeight:
          weights.isEmpty
              ? null
              : weights.reduce((a, b) => a + b) / weights.length,
      avgRpe: rpes.isEmpty ? null : rpes.reduce((a, b) => a + b) / rpes.length,
      load: series.fold<double>(0, (t, e) => t + e.load),
      profile: profile,
    );
  }
}
