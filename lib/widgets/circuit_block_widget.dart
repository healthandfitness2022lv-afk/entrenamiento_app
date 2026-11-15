import 'package:flutter/material.dart';
import 'exercise_note.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

class CircuitBlockWidget extends StatelessWidget {
  final int index;
  final Map<String, dynamic> block;
  final bool expanded;

  final Map<int, int> circuitoRound;
  final Map<int, Map<int, Map<String, TextEditingController>>> circuitoReps;
  final Map<int, Map<int, Map<String, TextEditingController>>> circuitoWeight;
  final Map<int, Map<int, Map<String, int>>> circuitoRpePorRonda;
  final Map<int, Map<int, Map<String, ValueNotifier<bool>>>> circuitoDone;
  final Map<int, Map<String, bool>> circuitoPerSide;

  final String Function(dynamic) normalizeExerciseName;
  final VoidCallback onStateChanged;

  /// Cambia la variante ejecutada de un ejercicio del circuito (ej. "el
  /// equipo planificado está ocupado"). Solo se ofrece en la ronda 1, antes
  /// de avanzar de ronda: como el mismo ejercicio se repite por ronda,
  /// cambiarlo más tarde dejaría rondas ya completadas con el nombre viejo
  /// mezcladas con las nuevas bajo el nombre nuevo, lo que confunde al
  /// atleta aunque el estado en sí migre correctamente.
  final void Function(int blockIndex, Map<String, dynamic> exercise)?
  onChangeVariant;

  const CircuitBlockWidget({
    super.key,
    required this.index,
    required this.block,
    required this.expanded,
    required this.circuitoRound,
    required this.circuitoReps,
    required this.circuitoWeight,
    required this.circuitoRpePorRonda,
    required this.circuitoDone,
    required this.normalizeExerciseName,
    required this.onStateChanged,
    required this.circuitoPerSide,
    this.onChangeVariant,
  });

  @override
  Widget build(BuildContext context) {
    if (!expanded) return const SizedBox();

    final int totalRounds = block['rounds'] ?? 1;
    final int currentRound = circuitoRound[index] ?? 1;

    circuitoWeight.putIfAbsent(index, () => {});
    circuitoReps.putIfAbsent(index, () => {});
    circuitoRpePorRonda.putIfAbsent(index, () => {});
    circuitoDone.putIfAbsent(index, () => {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int round = 1; round <= currentRound; round++) ...[
          _roundCard(context, round, totalRounds, currentRound),
          const SizedBox(height: 16),
        ],

        if (currentRound < totalRounds)
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.forward),
              label: Text("Completar ronda ${currentRound + 1}"),
              onPressed: () {
                circuitoRound[index] = currentRound + 1;
                onStateChanged();
              },
            ),
          ),
      ],
    );
  }

  Widget _roundCard(
    BuildContext context,
    int round,
    int totalRounds,
    int currentRound,
  ) {
    circuitoWeight[index]!.putIfAbsent(round, () => {});
    circuitoReps[index]!.putIfAbsent(round, () => {});
    circuitoRpePorRonda[index]!.putIfAbsent(round, () => {});
    circuitoDone[index]!.putIfAbsent(round, () => {});

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Ronda $round / $totalRounds",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            for (final ex in block['exercises'])
              _exerciseRow(
                context,
                round,
                ex,
                canChangeVariant: round == 1 && currentRound == 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _exerciseRow(
    BuildContext context,
    int round,
    Map<String, dynamic> ex, {
    required bool canChangeVariant,
  }) {
    final String name = normalizeExerciseName(ex['name']);

    circuitoReps[index]![round]!.putIfAbsent(
      name,
      () => TextEditingController(text: (ex['reps'] ?? 1).toString()),
    );

    circuitoWeight[index]![round]!.putIfAbsent(
      name,
      () => TextEditingController(text: (ex['weight'] ?? 0).toString()),
    );

    circuitoRpePorRonda[index]![round]!.putIfAbsent(name, () => 5);

    circuitoDone[index]![round]!.putIfAbsent(name, () => ValueNotifier(false));

    circuitoPerSide.putIfAbsent(index, () => {});
    circuitoPerSide[index]!.putIfAbsent(name, () => ex['perSide'] == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (circuitoPerSide[index]?[name] == true)
              const Text(
                " (L)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.info,
                ),
              ),
            if (canChangeVariant && onChangeVariant != null)
              IconButton(
                icon: const Icon(Icons.swap_horiz, size: 20),
                tooltip: "Cambiar variante (equipo ocupado)",
                onPressed: () => onChangeVariant!(index, ex),
              ),
          ],
        ),
        if (round == 1) ExerciseNote(ex['notes'], padding: EdgeInsets.zero),
        const SizedBox(height: 6),

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: circuitoReps[index]![round]![name],
                decoration: const InputDecoration(labelText: "Reps"),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),

            Expanded(
              child: TextField(
                controller: circuitoWeight[index]![round]![name],
                decoration: const InputDecoration(labelText: "Peso"),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ),
            const SizedBox(width: 8),

            DropdownButton<int>(
              value: circuitoRpePorRonda[index]![round]![name],
              items: List.generate(
                10,
                (i) =>
                    DropdownMenuItem(value: i + 1, child: Text("RPE ${i + 1}")),
              ),
              onChanged: (v) {
                circuitoRpePorRonda[index]![round]![name] = v!;
                onStateChanged();
              },
            ),

            ValueListenableBuilder<bool>(
              valueListenable: circuitoDone[index]![round]![name]!,
              builder: (_, checked, __) {
                return Checkbox(
                      value: checked,
                      fillColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).colorScheme.primary;
                        }
                        return Colors.transparent;
                      }),
                      checkColor: Colors.black,
                      side: const BorderSide(color: Colors.grey),
                      onChanged: (v) {
                        if (v == true) HapticFeedback.lightImpact();
                        circuitoDone[index]![round]![name]!.value = v!;
                      },
                    )
                    .animate(target: checked ? 1 : 0)
                    .shimmer(duration: 400.ms, color: Colors.greenAccent)
                    .scaleXY(end: 1.2, duration: 150.ms)
                    .then()
                    .scaleXY(end: 1.0, duration: 150.ms);
              },
            ),
          ],
        ),

        const SizedBox(height: 12),
      ],
    );
  }
}
