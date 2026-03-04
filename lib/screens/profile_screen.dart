import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/svg_utils.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';
import 'my_workouts_screen.dart';
import 'fatigue_audit_screen.dart';
import '../services/fatigue_service.dart';


import '../services/fatigue_recalculation_service.dart';
import 'achievements_screen.dart';

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
  List<FatigueRecalculationStep>? lastAuditSteps;
  late Set<Muscle> pendingChartMuscles;
  bool hasPendingChanges = false;
  bool showGlobalFatigue = true;


  Set<Muscle> chartMuscles = {};

  DateTimeRange? chartRange;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  String _heatmapSignature(Map<Muscle, double> heatmap) {
    final entries = heatmap.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return entries
        .map((e) => '${e.key.name}:${e.value.toStringAsFixed(2)}')
        .join('|');
  }

  // ======================================================
  // 🔄 CARGA INICIAL (estado guardado + recuperación lazy)
  // ======================================================
  Future<void> _loadInitialState() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    

    // 🔥 2) leer auditoría persistida
    final auditSnap = await userRef
        .collection('fatigue_audit')
        .orderBy('workoutDate')
        .get();

    if (auditSnap.docs.isNotEmpty) {
      lastAuditSteps = auditSnap.docs
          .map((d) => FatigueRecalculationStep.fromJson(d.data()))
          .toList();
    }

    _rebuildHeatmapFromSteps();

    // 🔹 FECHA ÚLTIMO CÁLCULO
    final userDoc = await userRef.get();
    final userData = userDoc.data();
    if (userData?['lastFatigueCalculation'] != null) {
      lastFatigueCalculation =
          (userData!['lastFatigueCalculation'] as Timestamp).toDate();
    }

    if (!mounted) return;

    setState(() {
      pendingChartMuscles = {...chartMuscles};
      loading = false;
    });
  }

  

  Future<void> _recalculateFatigue() async {
    setState(() => calculatingFatigue = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;

    final result = await FatigueRecalculationService.recalculateAndPersist(
      uid: uid,
      forceRecalculateLoad: true,
    );

    if (!mounted) return;

    final now = DateTime.now(); // 👈 NUEVO

    setState(() {
  lastAuditSteps = result.steps;
_rebuildHeatmapFromSteps();

  // 🔥 ACTUALIZAR AUDITORÍA TAMBIÉN
  lastAuditSteps = result.steps;

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

 void _rebuildHeatmapFromSteps() {
  if (lastAuditSteps == null || lastAuditSteps!.isEmpty) {
    heatmap.clear();
    return;
  }

  final sorted = [...lastAuditSteps!]
    ..sort((a, b) => a.workoutDate.compareTo(b.workoutDate));

  final start = sorted.first.workoutDate;

  final Map<Muscle, double> fatigue = {
    for (final m in Muscle.values) m: 0.0,
  };

  final Map<Muscle, DateTime> lastUpdate = {
    for (final m in Muscle.values) m: start,
  };

  for (final step in sorted) {
    final t = step.workoutDate;

    for (final m in Muscle.values) {
      // recuperar hasta workout
      fatigue[m] = FatigueService.recoverToNow(
        muscle: m,
        fatigue: fatigue[m]!,
        lastUpdate: lastUpdate[m]!,
        now: t,
      );

      // aplicar carga
      final load = step.loadApplied[m] ?? 0;
      fatigue[m] = fatigue[m]! + load;

      lastUpdate[m] = t;
    }
  }

  // 🔥 recuperar hasta ahora SOLO UNA VEZ
  final now = DateTime.now();

  for (final m in Muscle.values) {
    fatigue[m] = FatigueService.recoverToNow(
      muscle: m,
      fatigue: fatigue[m]!,
      lastUpdate: lastUpdate[m]!,
      now: now,
    );
  }

  heatmap
    ..clear()
    ..addAll(fatigue);
}

  // ======================================================
  // 🖥 UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Perfil corporal"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: "Ver auditoría de fatiga",
            onPressed: lastAuditSteps == null
                ? null
                : () => _showAudit(lastAuditSteps!),
          ),
          IconButton(
            icon: calculatingFatigue
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: "Recalcular fatiga",
            onPressed: calculatingFatigue ? null : _recalculateFatigue,
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryCard(),
            const SizedBox(height: 32),
            _bodyAndMusclesSection(),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  double generalFatigueTopMuscles() {
    if (heatmap.isEmpty) return 0;

    // 🔹 tomamos solo músculos con carga real (evita ruido)
    final values = heatmap.values.where((v) => v >= 5).toList();

    if (values.isEmpty) return 0;

    // 🔥 orden descendente
    values.sort((a, b) => b.compareTo(a));

    // 🔥 TOP 5
    final top = values.take(5).toList();

    final avg = top.reduce((a, b) => a + b) / top.length;
    return avg.clamp(0, 100);
  }

  Widget _bodyAndMusclesSection() {
    if (heatmap.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        _buildViewModeTabs(),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // COLUMNA IZQUIERDA (Heatmaps y Cuenta en una caja)
            Expanded(
              flex: 10,
              child: Column(
                children: [
                  // Fila de Heatmaps
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _bodyBlock("Frontal", false)),
                      const SizedBox(width: 8),
                      Expanded(child: _bodyBlock("Posterior", true)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Debajo de Heatmaps pero lado izquierdo
                  _actions(),
                ],
              ),
            ),
            
            const SizedBox(width: 24),
            
            // COLUMNA DERECHA (Barras de músculos, más cortas)
            Expanded(
              flex: 11,
              child: _allMusclesList(),
            ),
          ],
        ),
      ],
    );
  }

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
            )
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
            onSelected: (_) => setState(() => fatigueViewMode = MuscleViewMode.muscle),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text("Grupo"),
            selected: fatigueViewMode == MuscleViewMode.anatomical,
            onSelected: (_) => setState(() => fatigueViewMode = MuscleViewMode.anatomical),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text("Funcional"),
            selected: fatigueViewMode == MuscleViewMode.functional,
            onSelected: (_) => setState(() => fatigueViewMode = MuscleViewMode.functional),
          ),
        ],
      ),
    );
  }

  Widget _allMusclesList() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (fatigueViewMode == MuscleViewMode.muscle)
        _buildMuscleView(),

      if (fatigueViewMode == MuscleViewMode.anatomical)
        _buildGroupView(
          anatomicalGroups,
          (g) => g.label,
        ),

      if (fatigueViewMode == MuscleViewMode.functional)
        _buildGroupView(
          functionalGroups,
          (g) => g.label,
        ),

      const SizedBox(height: 16),
      const Divider(),
      _heatmapLegendBar(),
    ],
  );
}

Widget _buildMuscleView() {
  final entries = heatmap.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return Column(
    children: entries.map((e) {
      return _fatigueRow(e.key.label, e.value);
    }).toList(),
  );
}


Widget _buildGroupView<T>(
  Map<T, List<Muscle>> groups,
  String Function(T) labelGetter,
)
 {
  final results = <MapEntry<String, double>>[];

for (final entry in groups.entries) {
  final muscles = entry.value;

  final values = muscles
      .map((m) => heatmap[m] ?? 0)
      .where((v) => v >= 4)
      .toList();

  if (values.isEmpty) continue;

  final avg = values.reduce((a, b) => a + b) / values.length;

  results.add(MapEntry(labelGetter(entry.key), avg));
}

results.sort((a, b) => b.value.compareTo(a.value));

return Column(
  children: results.map((e) {
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
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              "${value.toStringAsFixed(1)}",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isLowValue ? Colors.grey.shade600 : heatmapColor(value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            color: isLowValue ? const Color(0xFF4FC3F7).withOpacity(0.5) : heatmapColor(value),
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
    Colors.transparent,          // 0–4
    Color(0xFF4FC3F7),     // Celeste
    Color(0xFF1565C0),     // Azul
    Color(0xFF7B1FA2),     // Morado
    Color(0xFFFF8F00),     // Naranjo
    Color(0xFFB71C1C),     // Rojo intenso
    Color(0xFFB71C1C),     // Rojo sólido 95–100
  ],
)




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
      )
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

    final status = avgFatigue < 25
        ? "Recuperado, listo para entrenar"
        : avgFatigue < 55
        ? "Carga moderada, buen progreso"
        : "Alta carga, considera descansar";

    final color = heatmapColor(avgFatigue);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              height: 80,
              width: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: avgFatigue / 100,
                    backgroundColor: Colors.grey.shade200,
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  final groups = fatigueViewMode == MuscleViewMode.anatomical
      ? anatomicalGroups
      : functionalGroups;

  for (final entry in groups.entries) {
    final muscles = entry.value;

    final values = muscles
        .map((m) => heatmap[m] ?? 0)
        .where((v) => v >= 4)
        .toList();

    if (values.isEmpty) continue;

    final avg =
        values.reduce((a, b) => a + b) / values.length;

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
        const Text("Tu cuenta", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.emoji_events_outlined, color: Colors.orange, size: 22),
                title: const Text("Mis Logros"),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen())), 
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.history, color: Colors.blue, size: 22),
                title: const Text("Historial"),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyWorkoutsScreen()),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.analytics_outlined, color: Colors.purple, size: 22),
                title: const Text("Auditoría"),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: lastAuditSteps == null ? null : () => _showAudit(lastAuditSteps!),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.logout, color: Colors.red, size: 22),
                title: const Text("Salir", style: TextStyle(color: Colors.red)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
  void _showAudit(List<FatigueRecalculationStep> steps) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FatigueAuditScreen(steps: steps),
    ),
  );
}
}