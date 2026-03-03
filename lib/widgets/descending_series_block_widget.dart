import 'package:flutter/material.dart';

class DescendingSeriesBlockWidget extends StatelessWidget {
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

  const DescendingSeriesBlockWidget({
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
    if (exercises.isEmpty) return const SizedBox();

    final schema = List<int>.from(block['schema'] ?? []);
    final firstName = normalizeExerciseName(exercises.first['name']);
    final int roundCount = seriesData["$index-$firstName"]?.length ?? schema.length;

    return Column(
      children: List.generate(roundCount, (i) {
        final roundReps = schema.length > i 
            ? schema[i] 
            : (seriesData["$index-$firstName"] != null && i < seriesData["$index-$firstName"]!.length 
                ? seriesData["$index-$firstName"]![i]['reps'] 
                : 0);

        return Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 🛑 Header de Peldaño (ej: 21 Repeticiones)
                Text(
                  "$roundReps reps",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // 🏋️ Lista de ejercicios de este escalón
                ...exercises.map((ex) {
                  final name = normalizeExerciseName(ex['name']);
                  final key = "$index-$name";
                  final sets = seriesData[key];

                  if (sets == null || i >= sets.length) return const SizedBox();

                  final set = sets[i];
                  final done = set['done'] == true;
                  final wList = seriesWeightCtrl[key];
                  final weightCtrl = (wList != null && i < wList.length) ? wList[i] : null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                        // Nombre y info
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                icon: const Icon(Icons.info_outline, color: Colors.blueGrey),
                                onPressed: () => onInfoPressed(ex),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Peso (kg)
                        SizedBox(
                          width: 70,
                          child: TextField(
                            controller: weightCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: "kg",
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            ),
                            onChanged: (_) => onStateChanged(),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Checkbox
                        Checkbox(
                          value: done,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) {
                            set['done'] = v ?? false;
                            onStateChanged();
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      }),
    );
  }
}