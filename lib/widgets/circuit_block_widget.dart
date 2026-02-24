import 'package:flutter/material.dart';

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
final void Function(int blockIndex, String exercise, bool value)
    onPerSideChanged;

  final String Function(dynamic) normalizeExerciseName;
  final VoidCallback onStateChanged;

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
required this.onPerSideChanged,
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
          _roundCard(context, round, totalRounds),
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

  Widget _roundCard(BuildContext context, int round, int totalRounds) {
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
              _exerciseRow(context, round, ex),
          ],
        ),
      ),
    );
  }

  Widget _exerciseRow(
    BuildContext context,
    int round,
    Map<String, dynamic> ex,
  ) {
    final String name = normalizeExerciseName(ex['name']);

    circuitoReps[index]![round]!.putIfAbsent(
      name,
      () => TextEditingController(
        text: (ex['reps'] ?? 1).toString(),
      ),
    );

    circuitoWeight[index]![round]!.putIfAbsent(
      name,
      () => TextEditingController(
        text: (ex['weight'] ?? 0).toString(),
      ),
    );

    circuitoRpePorRonda[index]![round]!.putIfAbsent(name, () => 5);

    circuitoDone[index]![round]!.putIfAbsent(
      name,
      () => ValueNotifier(false),
    );

    circuitoPerSide.putIfAbsent(index, () => {});
circuitoPerSide[index]!.putIfAbsent(
  name,
  () => ex['perSide'] == true,
);

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

    SizedBox(
      width: 22,
      height: 22,
      child: Checkbox(
        value: circuitoPerSide[index]?[name] == true,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize:
            MaterialTapTargetSize.shrinkWrap,
        onChanged: (v) {
          onPerSideChanged(index, name, v == true);
        },
      ),
    ),

    const SizedBox(width: 4),

    const Text(
      "L",
      style: TextStyle(fontSize: 12),
    ),
  ],
),
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
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),

            DropdownButton<int>(
              value: circuitoRpePorRonda[index]![round]![name],
              items: List.generate(
                10,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text("RPE ${i + 1}"),
                ),
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
                    circuitoDone[index]![round]![name]!.value = v!;
                  },
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 12),
      ],
    );
  }
}
