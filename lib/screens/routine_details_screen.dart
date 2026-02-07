import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_routine_screen.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';

class RoutineDetailsScreen extends StatefulWidget {
  final QueryDocumentSnapshot routine;

  const RoutineDetailsScreen({
    super.key,
    required this.routine,
  });

  @override
  State<RoutineDetailsScreen> createState() =>
      _RoutineDetailsScreenState();
}

class _RoutineDetailsScreenState extends State<RoutineDetailsScreen> {
  late DocumentReference routineRef;
  Map<String, dynamic>? routineData;

  @override
  void initState() {
    super.initState();
    routineRef = widget.routine.reference;
    _loadRoutine();
  }

  Future<void> _loadRoutine() async {
    final snap = await routineRef.get();
    if (!mounted) return;

    setState(() {
      routineData = snap.data() as Map<String, dynamic>;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (routineData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final blocks =
        List<Map<String, dynamic>>.from(routineData!['blocks']);
    final rawHeatmap = _buildRawMuscleHeatmap(blocks);
    final muscleHeatmap = _convertToMuscleHeatmap(rawHeatmap);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // =============================
            // CONTENIDO
            // =============================
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
              children: [
                if (muscleHeatmap.isNotEmpty) ...[
                  _muscleImpactSection(context, muscleHeatmap),
                  const SizedBox(height: 32),
                ],
                ...blocks.asMap().entries.map(
                      (e) => _blockCard(
                        context,
                        e.value,
                        e.key,
                      ),
                    ),
              ],
            ),

            // =============================
            // HEADER COMPACTO
            // =============================
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _topHeader(context),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // HEADER
  // =====================================================

  Widget _topHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _iconButton(
            icon: Icons.arrow_back,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              routineData!['name'],
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          _iconButton(
            icon: Icons.edit,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddRoutineScreen(
                    routineId: routineRef.id,
                    initialData: routineData,
                  ),
                ),
              );

              // 🔄 RECARGA TRAS EDITAR
              await _loadRoutine();
            },
          ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20),
      ),
    );
  }

  // =====================================================
  // MUSCLE IMPACT
  // =====================================================

  Widget _muscleImpactSection(
    BuildContext context,
    Map<Muscle, double> heatmap,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _greenBorderContainer(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Impacto muscular", Icons.accessibility_new),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: BodyHeatmap(
              heatmap: heatmap,
              showBack: false,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // BLOQUES
  // =====================================================

  Widget _blockCard(
    BuildContext context,
    Map<String, dynamic> block,
    int index,
  ) {
    final type = block['type'];
    final exercises =
        List<Map<String, dynamic>>.from(block['exercises']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _blockIcon(type),
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _blockTitle(block),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: _exerciseContainer(context),
            child: Column(
              children:
                  exercises.map((e) => _exerciseRow(e)).toList(),
            ),
          ),
        ],
      ),
    );
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
        return block['type'];
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

  Widget _exerciseRow(Map<String, dynamic> e) {
  final bool perSide = e['perSide'] == true;
  final num weight = (e['weight'] ?? 0);

  String mainValue = "";

  // 🔥 SOLO PARA SERIES
  if (e['series'] != null && e['reps'] != null) {
    mainValue = "${e['series']}×${e['reps']} reps";
  }

  // 🔥 CIRCUITOS / EMOM / TABATA
  else if (e['value'] != null && e['valueType'] != null) {
    mainValue = e['valueType'] == "time"
        ? "${e['value']} s"
        : "${e['value']} reps";
  }

  final String sideLabel = perSide ? " · por lado" : "";
  final String weightLabel = " · ${weight}kg";

  final String rightText =
      [mainValue, sideLabel, weightLabel]
          .where((s) => s.isNotEmpty)
          .join("");

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const Icon(Icons.play_arrow, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            e['name'],
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


  // =====================================================
  // HEATMAP UTILS
  // =====================================================

  Map<String, double> _buildRawMuscleHeatmap(
    List<Map<String, dynamic>> blocks,
  ) {
    final Map<String, double> heatmap = {};
    for (final block in blocks) {
      for (final e in block['exercises']) {
        final muscles = e['muscles'];
        if (muscles is! Map) continue;
        muscles.forEach((k, v) {
          heatmap[k] = (heatmap[k] ?? 0) + (v as num).toDouble();
        });
      }
    }
    return heatmap;
  }

  Map<Muscle, double> _convertToMuscleHeatmap(
    Map<String, double> raw,
  ) {
    final Map<Muscle, double> result = {};
    for (final entry in raw.entries) {
      try {
        final muscle =
            Muscle.values.firstWhere((m) => m.name == entry.key);
        result[muscle] = entry.value;
      } catch (_) {}
    }
    return result;
  }

  

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF39FF14)),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  BoxDecoration _greenBorderContainer(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary,
        width: 1.2,
      ),
    );
  }

  BoxDecoration _exerciseContainer(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: primary, width: 1.3),
      boxShadow: [
        BoxShadow(
          color: primary.withOpacity(0.18),
          blurRadius: 14,
          spreadRadius: 1,
        ),
      ],
    );
  }
}
