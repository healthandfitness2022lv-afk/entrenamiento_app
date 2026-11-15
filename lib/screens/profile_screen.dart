import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/svg_utils.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';
import 'my_workouts_screen.dart';
import 'fatigue_audit_screen.dart';
import 'achievements_screen.dart';
import '../services/fatigue_recalculation_service.dart';
import '../services/athlete_selection_service.dart';
import '../services/athlete_report_service.dart';
import 'stats_screen.dart';
import '../utils/responsive.dart';
import '../theme/app_theme.dart';

enum MuscleViewMode { muscle, anatomical, functional }

MuscleViewMode fatigueViewMode = MuscleViewMode.muscle;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Map<Muscle, double> heatmap = {};

  bool loading = true;
  bool calculatingFatigue = false;
  DateTime? lastFatigueCalculation;

  /// Último guardado/edición de un workout del atleta, para avisar cuando
  /// la fatiga mostrada es anterior (hay que recalcular).
  DateTime? latestWorkoutAt;
  List<FatigueRecalculationStep>? lastAuditSteps;
  late Set<Muscle> pendingChartMuscles;
  bool hasPendingChanges = false;
  bool showGlobalFatigue = true;

  final user = FirebaseAuth.instance.currentUser;
  String? role;
  String? selectedAthleteId;
  String? selectedAthleteName;

  Set<Muscle> chartMuscles = {};
  DateTimeRange? chartRange;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  String _heatmapSignature(Map<Muscle, double> heatmap) {
    final entries =
        heatmap.entries.toList()
          ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return entries
        .map((e) => '${e.key.name}:${e.value.toStringAsFixed(2)}')
        .join('|');
  }

  // ======================================================
  // 🔄 CARGA INICIAL (estado guardado + recuperación lazy)
  // ======================================================
  Future<void> _loadInitialState() async {
    if (user == null) return;

    final userDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();

    role = userDoc.data()?['role'];

    if (role == 'administrador') {
      final saved = await AthleteSelectionService.load();
      if (saved != null) {
        selectedAthleteId = saved['id'];
        selectedAthleteName = saved['name'];
      }
    }

    selectedAthleteId ??= user!.uid;
    selectedAthleteName ??= userDoc.data()?['name'];

    await _loadAthleteFatigue(selectedAthleteId!);

    if (!mounted) return;

    setState(() {
      pendingChartMuscles = {...chartMuscles};
      loading = false;
    });
  }

  Future<void> _loadAthleteFatigue(String uid) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    // 🔥 2) leer auditoría persistida (solo para la pantalla de auditoría)
    final auditSnap =
        await userRef.collection('fatigue_audit').orderBy('workoutDate').get();

    if (auditSnap.docs.isNotEmpty) {
      lastAuditSteps =
          auditSnap.docs
              .map((d) => FatigueRecalculationStep.fromJson(d.data()))
              .toList();
    } else {
      lastAuditSteps = null;
    }

    // 🔥 Heatmap: leído directo de fatigue_state/latest con recuperación
    // aplicada hasta ahora — misma fuente que usa el resto de la app, en vez
    // de reconstruir el algoritmo de recuperación aquí.
    final currentFatigue = await FatigueRecalculationService.readCurrentFatigue(
      uid: uid,
    );
    heatmap
      ..clear()
      ..addAll(currentFatigue);

    // 🔹 FECHA ÚLTIMO CÁLCULO
    final userDoc = await userRef.get();
    final userData = userDoc.data();
    if (userData?['lastFatigueCalculation'] != null) {
      lastFatigueCalculation =
          (userData!['lastFatigueCalculation'] as Timestamp).toDate();
    } else {
      lastFatigueCalculation = null;
    }

    // 🔹 ÚLTIMO WORKOUT (índice userId + date DESC ya existe)
    try {
      final latest =
          await FirebaseFirestore.instance
              .collection('workouts_logged')
              .where('userId', isEqualTo: uid)
              .orderBy('date', descending: true)
              .limit(1)
              .get();
      if (latest.docs.isEmpty) {
        latestWorkoutAt = null;
      } else {
        final data = latest.docs.first.data();
        final updated = (data['updatedAt'] as Timestamp?)?.toDate();
        final date = (data['date'] as Timestamp?)?.toDate();
        latestWorkoutAt =
            (updated != null && (date == null || updated.isAfter(date)))
                ? updated
                : date;
      }
    } catch (_) {
      // Solo alimenta el aviso de "desactualizado"; no bloquea el perfil.
      latestWorkoutAt = null;
    }
  }

  Future<void> _selectAthlete() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('users')
            .where('role', whereIn: ['atleta', 'administrador'])
            .get();

    final users = snapshot.docs;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
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
                    leading:
                        isMe
                            ? const Icon(Icons.person, color: Colors.blue)
                            : const Icon(Icons.fitness_center),
                    title: Text(isMe ? "${u['name']} (Yo)" : u['name']),
                    onTap: () {
                      setState(() {
                        selectedAthleteId = u.id;
                        selectedAthleteName = u['name'];
                        loading = true;
                      });
                      AthleteSelectionService.save(u.id, u['name']);
                      _loadAthleteFatigue(u.id).then((_) {
                        if (mounted) setState(() => loading = false);
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              ),
            ],
          ),
    );
  }

  Future<void> _recalculateFatigue() async {
    setState(() => calculatingFatigue = true);

    final uid = selectedAthleteId ?? user!.uid;

    final FatigueRecalculationResult result;
    try {
      result = await FatigueRecalculationService.recalculateAndPersist(
        uid: uid,
        forceRecalculateLoad: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => calculatingFatigue = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No se pudo recalcular la fatiga: $e")),
      );
      return;
    }

    if (!mounted) return;

    final now = DateTime.now();

    setState(() {
      lastAuditSteps = result.steps;
      heatmap
        ..clear()
        ..addAll(result.finalFatigue);
      lastFatigueCalculation = now;
      calculatingFatigue = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Fatiga y tabla actualizadas"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ======================================================
  // 🖥 UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment:
              compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            const Text("Perfil corporal", style: TextStyle(fontSize: 16)),
            if (selectedAthleteName != null)
              Text(
                selectedAthleteName!.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        centerTitle: !compact,
        actions: _appBarActions(compact),
      ),

      body:
          loading
              ? _loadingSkeleton()
              : RefreshIndicator(
                onRefresh: _reloadAthlete,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(compact ? 12 : 24),
                  child: ResponsiveCenter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _summaryCard(),
                        SizedBox(height: compact ? 20 : 32),
                        _bodyAndMusclesSection(),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  // ======================================================
  // 🔝 BARRA SUPERIOR
  // ======================================================
  /// En pantallas angostas: solo "cambiar atleta" a la vista y el resto en
  /// un menú ⋮ (5 íconos sin texto aplastaban el título y no se entendían).
  /// En tablet/PC: botones con texto. "Recalcular" vive en la tarjeta de
  /// estado, junto a la fecha del último cálculo.
  List<Widget> _appBarActions(bool compact) {
    final isAdmin = role == 'administrador';
    final auditAvailable = lastAuditSteps != null;

    if (compact) {
      return [
        if (isAdmin)
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: "Cambiar atleta",
            onPressed: _selectAthlete,
          ),
        PopupMenuButton<String>(
          tooltip: "Más opciones",
          onSelected: (value) {
            switch (value) {
              case 'stats':
                _openStats();
              case 'pdf':
                _generatePdf();
              case 'audit':
                _showAudit(lastAuditSteps!);
            }
          },
          itemBuilder:
              (_) => [
                const PopupMenuItem(
                  value: 'stats',
                  child: ListTile(
                    leading: Icon(Icons.bar_chart_rounded),
                    title: Text("Estadísticas"),
                  ),
                ),
                const PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text("Informe PDF"),
                  ),
                ),
                PopupMenuItem(
                  value: 'audit',
                  enabled: auditAvailable,
                  child: const ListTile(
                    leading: Icon(Icons.analytics_outlined),
                    title: Text("Auditoría de fatiga"),
                  ),
                ),
              ],
        ),
      ];
    }

    return [
      if (isAdmin)
        TextButton.icon(
          icon: const Icon(Icons.people_outline),
          label: const Text("Cambiar atleta"),
          onPressed: _selectAthlete,
        ),
      TextButton.icon(
        icon: const Icon(Icons.bar_chart_rounded),
        label: const Text("Estadísticas"),
        onPressed: _openStats,
      ),
      TextButton.icon(
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text("Informe PDF"),
        onPressed: _generatePdf,
      ),
      TextButton.icon(
        icon: const Icon(Icons.analytics_outlined),
        label: const Text("Auditoría"),
        onPressed: auditAvailable ? () => _showAudit(lastAuditSteps!) : null,
      ),
      const SizedBox(width: 8),
    ];
  }

  void _openStats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => StatsScreen(
              uid: selectedAthleteId ?? user!.uid,
              athleteName: selectedAthleteName,
              heatmap: heatmap.isNotEmpty ? Map.from(heatmap) : null,
            ),
      ),
    );
  }

  Future<void> _reloadAthlete() async {
    final uid = selectedAthleteId ?? user?.uid;
    if (uid == null) return;
    await _loadAthleteFatigue(uid);
    if (mounted) setState(() {});
  }

  /// Silueta gris del contenido mientras carga, en vez de una pantalla vacía
  /// con un spinner: se percibe más rápido y no "salta" el layout al cargar.
  Widget _loadingSkeleton() {
    final compact = context.isCompact;
    final base = Theme.of(context).colorScheme.onSurface.withOpacity(0.06);
    Widget box(double height) => Container(
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 12 : 24),
      child: ResponsiveCenter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            box(120),
            const SizedBox(height: 24),
            box(40),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: box(compact ? 260 : 380)),
                const SizedBox(width: 12),
                Expanded(child: box(compact ? 260 : 380)),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 5; i++) ...[
              box(28),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  double generalFatigueTopMuscles() {
    return FatigueRecalculationService.calculateGlobalFatigue(heatmap, topK: 5);
  }

  Widget _bodyAndMusclesSection() {
    if (heatmap.isEmpty) {
      return _buildEmptyState();
    }

    final heatmaps = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _bodyBlock("Frontal", false)),
        const SizedBox(width: 8),
        Expanded(child: _bodyBlock("Posterior", true)),
      ],
    );

    // Celular: una sola columna. Antes eran dos columnas fijas, y en 360 px
    // cada silueta quedaba de ~80 px de ancho y las barras comprimidas.
    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _buildViewModeTabs()),
          const SizedBox(height: 16),
          heatmaps,
          const SizedBox(height: 24),
          _sectionTitle("Fatiga por músculo"),
          _allMusclesList(),
          const SizedBox(height: 24),
          _actions(),
        ],
      );
    }

    // Tablet / PC: siluetas + cuenta a la izquierda, barras a la derecha.
    return Column(
      children: [
        _buildViewModeTabs(),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 10,
              child: Column(
                children: [heatmaps, const SizedBox(height: 24), _actions()],
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              flex: 11,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle("Fatiga por músculo"),
                  _allMusclesList(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
    ),
  );

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fitness_center, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              "Aún no hay datos de fatiga.",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.home),
              label: const Text("Ir al inicio"),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChoiceChip(
            label: const Text("Músculo"),
            selected: fatigueViewMode == MuscleViewMode.muscle,
            onSelected:
                (_) => setState(() => fatigueViewMode = MuscleViewMode.muscle),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text("Grupo"),
            selected: fatigueViewMode == MuscleViewMode.anatomical,
            onSelected:
                (_) =>
                    setState(() => fatigueViewMode = MuscleViewMode.anatomical),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text("Funcional"),
            selected: fatigueViewMode == MuscleViewMode.functional,
            onSelected:
                (_) =>
                    setState(() => fatigueViewMode = MuscleViewMode.functional),
          ),
        ],
      ),
    );
  }

  Widget _allMusclesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fatigueViewMode == MuscleViewMode.muscle) _buildMuscleView(),

        if (fatigueViewMode == MuscleViewMode.anatomical)
          _buildGroupView(anatomicalGroups, (g) => g.label),

        if (fatigueViewMode == MuscleViewMode.functional)
          _buildGroupView(functionalGroups, (g) => g.label),

        const SizedBox(height: 16),
        const Divider(),
        _heatmapLegendBar(),
      ],
    );
  }

  Widget _buildMuscleView() {
    final entries =
        heatmap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children:
          entries.map((e) {
            return _fatigueRow(e.key.label, e.value);
          }).toList(),
    );
  }

  Widget _buildGroupView<T>(
    Map<T, List<Muscle>> groups,
    String Function(T) labelGetter,
  ) {
    final results = <MapEntry<String, double>>[];

    for (final entry in groups.entries) {
      final muscles = entry.value;

      final values =
          muscles.map((m) => heatmap[m] ?? 0).where((v) => v >= 4).toList();

      if (values.isEmpty) continue;

      final avg = values.reduce((a, b) => a + b) / values.length;

      results.add(MapEntry(labelGetter(entry.key), avg));
    }

    results.sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children:
          results.map((e) {
            return _fatigueRow(e.key, e.value);
          }).toList(),
    );
  }

  Widget _fatigueRow(String label, double value) {
    final isLowValue = value < 4;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "${value.toStringAsFixed(1)}",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color:
                      isLowValue ? Colors.grey.shade600 : heatmapColor(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              color:
                  isLowValue
                      ? const Color(0xFF4FC3F7).withOpacity(0.5)
                      : heatmapColor(value),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatmapLegendBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          "Escala de fatiga (0–100)",
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              stops: [0.0, 0.04, 0.28, 0.52, 0.76, 0.95, 1.0],
              colors: [
                Colors.transparent, // 0–4
                Color(0xFF4FC3F7), // Celeste
                Color(0xFF1565C0), // Azul
                Color(0xFF7B1FA2), // Morado
                Color(0xFFFF8F00), // Naranjo
                Color(0xFFB71C1C), // Rojo intenso
                Color(0xFFB71C1C), // Rojo sólido 95–100
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("0", style: TextStyle(fontSize: 10)),
            Text("50", style: TextStyle(fontSize: 10)),
            Text("100", style: TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  // ======================================================
  // 👤 ENCABEZADO DE USUARIO
  // ======================================================

  // ======================================================
  // 📊 RESUMEN GENERAL
  // ======================================================
  Widget _summaryCard() {
    final avgFatigue = generalFatigueTopMuscles();

    final status =
        avgFatigue < 25
            ? "Recuperado, listo para entrenar"
            : avgFatigue < 55
            ? "Carga moderada, buen progreso"
            : "Alta carga, considera descansar";

    final color = heatmapColor(avgFatigue);
    final compact = context.isCompact;
    final stale = _isFatigueStale;

    final recalcButton = FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: calculatingFatigue ? null : _recalculateFatigue,
      icon:
          calculatingFatigue
              ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.refresh),
      label: Text(calculatingFatigue ? "Recalculando…" : "Recalcular fatiga"),
    );

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            stale
                ? BorderSide(color: Colors.amber.withOpacity(0.6))
                : BorderSide.none,
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment:
                  compact
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
              children: [
                ..._summaryContent(avgFatigue, status, color),
                if (!compact) ...[const SizedBox(width: 16), recalcButton],
                // Celular: botoncito en la esquina de la tarjeta (el botón
                // ancho ocupaba una fila entera).
                if (compact) ...[
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: "Recalcular fatiga",
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: calculatingFatigue ? null : _recalculateFatigue,
                    icon:
                        calculatingFatigue
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.refresh),
                  ),
                ],
              ],
            ),
            if (stale) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Hay entrenamientos posteriores al último cálculo. "
                      "Recalcula para ver la fatiga al día.",
                      style: TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Hay workouts guardados/editados después del último recálculo.
  bool get _isFatigueStale =>
      latestWorkoutAt != null &&
      (lastFatigueCalculation == null ||
          latestWorkoutAt!.isAfter(lastFatigueCalculation!));

  List<Widget> _summaryContent(double avgFatigue, String status, Color color) {
    return [
      SizedBox(
        height: 80,
        width: 80,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: avgFatigue / 100,
              backgroundColor: Colors.white12,
              color: color,
              strokeWidth: 8,
            ),
            Center(
              child: Text(
                "${avgFatigue.toInt()}%",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Estado general",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.9),
              ),
            ),
            if (lastFatigueCalculation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Último cálculo: "
                  "${lastFatigueCalculation!.day.toString().padLeft(2, '0')}/"
                  "${lastFatigueCalculation!.month.toString().padLeft(2, '0')} "
                  "${lastFatigueCalculation!.hour.toString().padLeft(2, '0')}:"
                  "${lastFatigueCalculation!.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  // ======================================================
  // 🧍 HEATMAPS
  // ======================================================

  Widget _bodyBlock(String title, bool showBack) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),

        AspectRatio(
          aspectRatio: 3 / 5,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: SizedBox.expand(
              // 🔥 CLAVE
              child: BodyHeatmap(
                key: ValueKey(_heatmapSignature(_getDisplayHeatmap())),
                heatmap: _getDisplayHeatmap(),
                showBack: showBack,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Map<Muscle, double> _getDisplayHeatmap() {
    if (fatigueViewMode == MuscleViewMode.muscle) {
      return heatmap;
    }

    final Map<Muscle, double> groupedHeatmap = {};

    final groups =
        fatigueViewMode == MuscleViewMode.anatomical
            ? anatomicalGroups
            : functionalGroups;

    for (final entry in groups.entries) {
      final muscles = entry.value;

      final values =
          muscles.map((m) => heatmap[m] ?? 0).where((v) => v >= 4).toList();

      if (values.isEmpty) continue;

      final avg = values.reduce((a, b) => a + b) / values.length;

      for (final m in muscles) {
        groupedHeatmap[m] = avg;
      }
    }

    return groupedHeatmap;
  }

  // ======================================================
  // ⚡ ACCIONES
  // ======================================================
  Widget _actions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Tu cuenta",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(
                  Icons.emoji_events_outlined,
                  color: Colors.orange,
                  size: 22,
                ),
                title: const Text("Mis Logros"),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AchievementsScreen(),
                      ),
                    ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(
                  Icons.history,
                  color: Colors.blue,
                  size: 22,
                ),
                title: const Text("Historial"),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => MyWorkoutsScreen(
                            initialAthleteId: selectedAthleteId,
                            initialAthleteName: selectedAthleteName,
                          ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Separado de la navegación y con confirmación: antes estaba entre
        // "Historial" y "Auditoría" y se tocaba por error.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.logout),
            label: const Text("Cerrar sesión"),
            onPressed: _confirmSignOut,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text("¿Cerrar sesión?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Cerrar sesión"),
              ),
            ],
          ),
    );
    if (ok != true) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _generatePdf() async {
    final currentUser = user;
    if (currentUser == null || !mounted) return;

    final now = DateTime.now();
    final initialStartMonth = now.month == 1 ? 1 : now.month - 1;
    final initialStartDay = now.day.clamp(
      1,
      DateUtils.getDaysInMonth(now.year, initialStartMonth),
    );
    final initialRange = DateTimeRange(
      start: DateTime(now.year, initialStartMonth, initialStartDay),
      end: now,
    );

    debugPrint(
      '[ProfileScreen][_generatePdf] Abriendo picker '
      'athleteId=${selectedAthleteId ?? currentUser.uid} '
      'athleteName=$selectedAthleteName '
      'initialStart=${initialRange.start.toIso8601String()} '
      'initialEnd=${initialRange.end.toIso8601String()}',
    );

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initialRange,
      helpText: 'Selecciona el período del informe',
      saveText: 'Generar PDF',
      locale: const Locale('es'),
      builder: (context, child) {
        if (child == null) {
          debugPrint(
            '[ProfileScreen][_generatePdf] showDateRangePicker builder recibió child=null',
          );
          return const SizedBox.shrink();
        }

        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppColors.accent),
          ),
          child: child,
        );
      },
    );

    debugPrint(
      '[ProfileScreen][_generatePdf] Picker cerrado '
      'rangeStart=${range?.start.toIso8601String()} '
      'rangeEnd=${range?.end.toIso8601String()}',
    );

    if (range == null || !mounted) return;

    await AthleteReportService.generate(
      context: context,
      athleteId: selectedAthleteId ?? currentUser.uid,
      athleteName: selectedAthleteName,
      heatmap: heatmap,
      range: range,
    );
  }

  void _showAudit(List<FatigueRecalculationStep> steps) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => FatigueAuditScreen(
              steps: steps,
              athleteName: selectedAthleteName,
            ),
      ),
    );
  }
}
