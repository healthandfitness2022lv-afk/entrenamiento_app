import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/muscle_catalog.dart';
import '../screens/add_exercise_screen.dart';
import '../widgets/body_heatmap.dart';
import '../utils/svg_utils.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
  });

  @override
  State<ExerciseDetailScreen> createState() =>
      _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  Map<Muscle, double> _getHeatmapForTab() {
  final currentIndex = _tabController.index;

  // =========================
  // 0 → MUSCULAR (original)
  // =========================
  if (currentIndex == 0) {
    return widget.exercise.muscleWeights
        .map((m, v) => MapEntry(m, v * 100));
  }

  // =========================
  // 1 → GRUPO
  // =========================
  if (currentIndex == 1) {
    final groupTotals = <AnatomicalGroup, double>{};

    widget.exercise.muscleWeights.forEach((muscle, value) {
      for (final entry in anatomicalGroups.entries) {
        if (entry.value.contains(muscle)) {
          groupTotals.update(
            entry.key,
            (v) => v + value,
            ifAbsent: () => value,
          );
        }
      }
    });

    final result = <Muscle, double>{};

    for (final entry in anatomicalGroups.entries) {
      final groupValue = groupTotals[entry.key] ?? 0;
      for (final muscle in entry.value) {
        result[muscle] = groupValue * 100;
      }
    }

    return result;
  }

  // =========================
  // 2 → FUNCIONAL
  // =========================
  if (currentIndex == 2) {
    final functionalTotals = <FunctionalGroup, double>{};

    widget.exercise.muscleWeights.forEach((muscle, value) {
      for (final entry in functionalGroups.entries) {
        if (entry.value.contains(muscle)) {
          functionalTotals.update(
            entry.key,
            (v) => v + value,
            ifAbsent: () => value,
          );
        }
      }
    });

    final result = <Muscle, double>{};

    for (final entry in functionalGroups.entries) {
      final groupValue = functionalTotals[entry.key] ?? 0;
      for (final muscle in entry.value) {
        result[muscle] = groupValue * 100;
      }
    }

    return result;
  }

  return {};
}


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
  setState(() {});
});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ======================================================
              // 🔝 HEADER
              // ======================================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.exercise.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(widget.exercise.instructions),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddExerciseScreen(
                            exerciseToEdit: widget.exercise,
                            exerciseId: widget.exercise.id,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ======================================================
              // 🧠 MAPA + PONDERADORES
              // ======================================================
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ======================
                      // 🧍 FRONTAL
                      // ======================
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            const Text(
                              "Frontal",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            AspectRatio(
                              aspectRatio: 3 / 5,
                              child: BodyHeatmap(
  heatmap: _getHeatmapForTab(),

                                showBack: false,
                                percentageScale: false,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // ======================
                      // 🧍 POSTERIOR
                      // ======================
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            const Text(
                              "Posterior",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            AspectRatio(
                              aspectRatio: 3 / 5,
                              child: BodyHeatmap(
  heatmap: _getHeatmapForTab(),

                                showBack: true,
                                percentageScale: false,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      // ======================
                      // 📊 PONDERADORES CON TABS
                      // ======================
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [

                            TabBar(
                              controller: _tabController,
                              labelColor:
                                  Theme.of(context).colorScheme.primary,
                              unselectedLabelColor: Colors.grey,
                              labelStyle:
                                  const TextStyle(fontSize: 11),
                              tabs: const [
                                Tab(text: "Músculo"),
                                Tab(text: "Grupo"),
                                Tab(text: "Función"),
                              ],
                            ),

                            const SizedBox(height: 8),

                            SizedBox(
                              height: 300,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildMuscleWeights(),
                                  _buildGroupWeights(),
                                  _buildFunctionalWeights(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ======================================================
              // 🧰 EQUIPAMIENTO
              // ======================================================
              if (widget.exercise.equipment.isNotEmpty) ...[
                _sectionTitle("Equipamiento"),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.exercise.equipment
                      .map((e) => Chip(label: Text(e)))
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatPercent(double value) {
  final percent = value * 100;

  if (percent % 1 == 0) {
    return percent.toInt().toString();
  }

  return percent.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}


  // ======================================================
  // 🔵 MUSCULAR
  // ======================================================
  Widget _buildMuscleWeights() {
    final sorted = widget.exercise.muscleWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      children: sorted.map((e) {
        final percent = _formatPercent(e.value);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_muscleLabel(e.key))),
                  Text("$percent%"),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
  value: e.value,
  minHeight: 6,
  backgroundColor: Colors.grey.shade300,
  color: heatmapColor(e.value * 100).withOpacity(0.9),
),

            ],
          ),
        );
      }).toList(),
    );
  }

  // ======================================================
  // 🟢 GRUPO
  // ======================================================
  Widget _buildGroupWeights() {
    final groupTotals = <AnatomicalGroup, double>{};

    widget.exercise.muscleWeights.forEach((muscle, value) {
      for (final entry in anatomicalGroups.entries) {
        if (entry.value.contains(muscle)) {
          groupTotals.update(
            entry.key,
            (v) => v + value,
            ifAbsent: () => value,
          );
        }
      }
    });

    final sorted = groupTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      children: sorted.map((e) {
        final percent = (e.value * 100).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${e.key.name} $percent%"),
              const SizedBox(height: 4),
              LinearProgressIndicator(
  value: e.value,
  minHeight: 6,
  backgroundColor: Colors.grey.shade300,
  color: heatmapColor(e.value * 100).withOpacity(0.9),
),

            ],
          ),
        );
      }).toList(),
    );
  }

  // ======================================================
  // 🟣 FUNCIONAL
  // ======================================================
  Widget _buildFunctionalWeights() {
    final functionalTotals = <FunctionalGroup, double>{};

    widget.exercise.muscleWeights.forEach((muscle, value) {
      for (final entry in functionalGroups.entries) {
        if (entry.value.contains(muscle)) {
          functionalTotals.update(
            entry.key,
            (v) => v + value,
            ifAbsent: () => value,
          );
        }
      }
    });

    final sorted = functionalTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      children: sorted.map((e) {
        final percent = (e.value * 100).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${e.key.name} $percent%"),
              const SizedBox(height: 4),
              LinearProgressIndicator(
  value: e.value,
  minHeight: 6,
  backgroundColor: Colors.grey.shade300,
  color: heatmapColor(e.value * 100).withOpacity(0.9),
),

            ],
          ),
        );
      }).toList(),
    );
  }

  String _muscleLabel(Muscle m) {
    return muscleCatalogMap.entries
        .firstWhere((e) => e.value.keys.first == m)
        .key;
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
