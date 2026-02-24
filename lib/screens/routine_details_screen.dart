import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_routine_screen.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';
import '../widgets/routine_view.dart';

class RoutineDetailsScreen extends StatefulWidget {
  final DocumentSnapshot routine;


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
                RoutineView(
  routine: routineData!,
  compact: false,
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

}