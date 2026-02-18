import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/svg_utils.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';
import 'my_workouts_screen.dart';
import 'fatigue_audit_screen.dart';

import '../services/fatigue_recalculation_service.dart';

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

    // 🔥 1) leer estado latest (la “última tabla” persistida)
    final latestStateSnap = await userRef
        .collection('fatigue_state')
        .doc('latest')
        .get();

    heatmap.clear();

    if (latestStateSnap.exists) {
      final data = latestStateSnap.data()!;
      final fatigueMap = Map<String, dynamic>.from(data['fatigue'] ?? {});

      for (final e in fatigueMap.entries) {
        // ✅ decodificación estricta, sin abs fallback
        final matches = Muscle.values.where((m) => m.name == e.key);
        if (matches.isEmpty) continue;
        final muscle = matches.first;

        heatmap[muscle] = (e.value as num).toDouble();
      }
    }

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
      heatmap
        ..clear()
        ..addAll(result.finalFatigue);

      lastFatigueCalculation = now; // 👈 CLAVE
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
            const SizedBox(height: 24),
            _bodyAndMusclesSection(),
            _actions(),
            const SizedBox(height: 24),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          // 🖥️ 3 columnas
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _bodyBlock("Frontal", false)),
              const SizedBox(width: 16),
              Expanded(child: _bodyBlock("Posterior", true)),
              const SizedBox(width: 16),
              Expanded(child: _allMusclesList()),
            ],
          );
        }

        // 📱 Mobile: SVG arriba, lista abajo
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _bodyBlock("Frontal", false)),
                const SizedBox(width: 16),
                Expanded(child: _bodyBlock("Posterior", true)),
              ],
            ),
            const SizedBox(height: 24),
            _allMusclesList(),
          ],
        );
      },
    );
  }

  Widget _allMusclesList() {
  if (heatmap.isEmpty) {
    return const Text(
      "Sin datos de fatiga",
      style: TextStyle(color: Colors.grey),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Fatiga",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),

      const SizedBox(height: 12),

      /// 🔘 TABS
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChoiceChip(
            label: const Text("Músculo"),
            selected: fatigueViewMode == MuscleViewMode.muscle,
            onSelected: (_) {
              setState(() {
                fatigueViewMode = MuscleViewMode.muscle;
              });
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text("Grupo"),
            selected: fatigueViewMode == MuscleViewMode.anatomical,
            onSelected: (_) {
              setState(() {
                fatigueViewMode = MuscleViewMode.anatomical;
              });
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text("Funcional"),
            selected: fatigueViewMode == MuscleViewMode.functional,
            onSelected: (_) {
              setState(() {
                fatigueViewMode = MuscleViewMode.functional;
              });
            },
          ),
        ],
      ),

      const SizedBox(height: 16),

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
      .where((v) => v > 10)
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
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: heatmapColor(value),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),

        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
        ),

        Text(
          value.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
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
    const Color(0xFF4FC3F7),     // Celeste
    const Color(0xFF1565C0),     // Azul
    const Color(0xFF7B1FA2),     // Morado
    const Color(0xFFFF8F00),     // Naranjo
    const Color(0xFFB71C1C),     // Rojo intenso
    const Color(0xFFB71C1C),     // Rojo sólido 95–100
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
  // 📊 RESUMEN GENERAL
  // ======================================================
  Widget _summaryCard() {
    final avgFatigue = generalFatigueTopMuscles();

    final status = avgFatigue < 25
        ? "Recuperado"
        : avgFatigue < 55
        ? "Carga moderada"
        : "Alta carga";

    final color = heatmapColor(avgFatigue);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.accessibility_new, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Estado general",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${avgFatigue.toStringAsFixed(2)}% de fatiga",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 14,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                  if (lastFatigueCalculation != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
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
        .where((v) => v > 10)
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
        const Text("Acciones", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        ListTile(
          leading: const Icon(Icons.history),
          title: const Text("Ver entrenamientos"),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyWorkoutsScreen()),
            );
          },
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