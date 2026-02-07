import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/muscle_catalog.dart';
import '../screens/add_exercise_screen.dart';
import '../widgets/body_heatmap.dart';

class ExerciseDetailScreen extends StatelessWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
  });

  @override
  Widget build(BuildContext context) {
    final sortedWeights = exercise.muscleWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ======================================================
              // 🔝 HEADER MODERNO (sin AppBar)
              // ======================================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⬅ BACK
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.pop(context),
                  ),

                  const SizedBox(width: 8),

                  // 🏷 TÍTULO
                  Expanded(
                    child: Text(
                      exercise.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),

                  // ℹ INFO
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: 'Instrucciones',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Instrucciones",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(exercise.instructions),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // ✏ EDIT
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar ejercicio',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddExerciseScreen(
                            exerciseToEdit: exercise,
                            exerciseId: exercise.id,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ======================================================
              // 🧠 MAPA DE ACTIVACIÓN + PONDERACIÓN
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
                                heatmap: exercise.muscleWeights,
                                showBack: false,
                                percentageScale: true,
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
                                heatmap: exercise.muscleWeights,
                                showBack: true,
                                percentageScale: true,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      // ======================
                      // 📊 PONDERACIÓN
                      // ======================
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: sortedWeights.map((e) {
                            final percent = (e.value * 100).round();

                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _muscleLabel(e.key),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        "$percent%",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: e.value,
                                    minHeight: 6,
                                    backgroundColor:
                                        Colors.grey.shade300,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
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
              if (exercise.equipment.isNotEmpty) ...[
                _sectionTitle("Equipamiento"),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: exercise.equipment
                      .map((e) => Chip(label: Text(e)))
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],

              // ======================================================
              // 🎥 VIDEO / IMAGEN
              // ======================================================
              Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    exercise.videoUrl != null &&
                            exercise.videoUrl!.isNotEmpty
                        ? "Video: ${exercise.videoUrl}"
                        : "Aquí irá el video / imagen",
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ======================================================
  // 🔤 HELPERS
  // ======================================================
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
