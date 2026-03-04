import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

class BuscarRmBlockWidget extends StatelessWidget {
  final int index;
  final Map<String, dynamic> block;
  final bool expanded;

  final Map<String, List<Map<String, dynamic>>> seriesData;
  final Map<String, List<TextEditingController>> seriesRepsCtrl;
  final Map<String, List<TextEditingController>> seriesWeightCtrl;

  final String Function(dynamic) normalizeExerciseName;
  final bool Function(Map<String, dynamic>) isPerSide;
  final void Function(Map<String, dynamic>) onInfoPressed;
  final VoidCallback onStateChanged;

  const BuscarRmBlockWidget({
    super.key,
    required this.index,
    required this.block,
    required this.expanded,
    required this.seriesData,
    required this.seriesRepsCtrl,
    required this.seriesWeightCtrl,
    required this.normalizeExerciseName,
    required this.isPerSide,
    required this.onInfoPressed,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!expanded) return const SizedBox();

    final exercises = block['exercises'] as List;
    final int rmTarget = block['rm'] ?? 5;

    return Column(
      children: exercises.map((ex) {
        final name = normalizeExerciseName(ex['name']);
        final key = "$index-$name";

        final sets = seriesData[key] ?? [];

        return Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Ejercicio
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => onInfoPressed(ex),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.track_changes, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      "Objetivo: Buscar ${rmTarget}RM", 
                      style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Lista de intentos
                Column(
                  children: List.generate(sets.length + 1, (i) {
                    // Extra fila vacia dinamica al final de la lista si la previa esta completada
                    if (i == sets.length) {
                      bool showNewSet = sets.isEmpty || sets.last['done'] == true;
                      if (!showNewSet) return const SizedBox();
                      
                      return TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text("A?adir intento"),
                        onPressed: () {
                          final int targetReps = ex['reps'] ?? rmTarget;
                          sets.add({
                            'valueType': 'reps',
                            'value': targetReps,
                            'reps': targetReps,
                            'weight': ex['weight'],
                            'rpe': 5,
                            'done': false,
                          });
                          seriesRepsCtrl[key]!.add(TextEditingController(text: targetReps.toString()));
                          seriesWeightCtrl[key]!.add(TextEditingController(text: ex['weight']?.toString() ?? ''));
                          onStateChanged();
                        },
                      );
                    }

                    final set = sets[i];
                    final done = set['done'] == true;
                    final repsCtrl = seriesRepsCtrl[key]?[i];
                    final weightCtrl = seriesWeightCtrl[key]?[i];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: done
                            ? Colors.green.withOpacity(0.15)
                            : Colors.grey.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: done
                              ? Colors.green
                              : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            alignment: Alignment.center,
                            child: Text(
                              "",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: repsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "reps",
                                isDense: true,
                              ),
                              onChanged: (_) => onStateChanged(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: weightCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: "kg",
                                isDense: true,
                              ),
                              onChanged: (_) => onStateChanged(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 52,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: set['rpe'] ?? 7,
                                isExpanded: true,
                                iconSize: 18,
                                items: List.generate(
                                  10,
                                  (r) => DropdownMenuItem(
                                    value: r + 1,
                                    child: Text("R${r + 1}", style: const TextStyle(fontSize: 13)),
                                  ),
                                ),
                                onChanged: (v) {
                                  set['rpe'] = v!;
                                  onStateChanged();
                                },
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (!done && i == sets.length - 1)
                             IconButton(
                               icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                               onPressed: () {
                                 sets.removeAt(i);
                                 seriesRepsCtrl[key]?.removeAt(i);
                                 seriesWeightCtrl[key]?.removeAt(i);
                                 onStateChanged();
                               }
                             ),
                          Checkbox(
                            value: done,
                            onChanged: (v) {
                              if (v == true) HapticFeedback.lightImpact();
                              set['done'] = v ?? false;
                              onStateChanged();
                            },
                          )
                          .animate(target: done ? 1 : 0)
                          .shimmer(duration: 400.ms, color: Colors.greenAccent)
                          .scaleXY(end: 1.2, duration: 150.ms)
                          .then()
                          .scaleXY(end: 1.0, duration: 150.ms),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
