import 'package:flutter/material.dart';
import '../services/tabata_timer_service.dart';

class TabataBlockWidget extends StatelessWidget {
  final int index;
  final Map<String, dynamic> block;
  final bool expanded;

  final TabataTimerService tabataTimer;

  final void Function(int blockIndex, Map<String, dynamic> block)
      onStartTabata;

  final VoidCallback onSkipTabata;

  const TabataBlockWidget({
    super.key,
    required this.index,
    required this.block,
    required this.expanded,
    required this.tabataTimer,
    required this.onStartTabata,
    required this.onSkipTabata,
  });

  @override
  Widget build(BuildContext context) {
    if (!expanded) return const SizedBox();

    final int work = block['work'];
    final int rest = block['rest'];
    final int rounds = block['rounds'];
    final List exercises = block['exercises'];

    final bool started = tabataTimer.isStarted(index);
    final bool completed = tabataTimer.isCompleted(index);
    final Map<String, int>? rpeResults =
        tabataTimer.getRpeResults(index);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tabata",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text("Trabajo: $work s · Descanso: $rest s · Rondas: $rounds"),

            const SizedBox(height: 12),

            if (completed && rpeResults != null) ...[
              const Text(
                "Resultados:",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              for (final ex in exercises)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(ex['name']),
                    Text(
                      "RPE ${rpeResults[ex['name']] ?? '-'}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
            ] else ...[
              ...exercises.map((e) => Text("• ${e['name']}")),
            ],

            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerRight,
              child: completed
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.replay),
                      label: const Text("Repetir Tabata"),
                      onPressed: () =>
                          onStartTabata(index, block),
                    )
                  : ElevatedButton(
                      onPressed: () =>
                          onStartTabata(index, block),
                      child: Text(
                        started
                            ? "Continuar Tabata"
                            : "Iniciar Tabata",
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}



class TabataOverlayWidget extends StatelessWidget {
  final TabataTimerService tabataTimer;
  final VoidCallback onSkip;

  const TabataOverlayWidget({
    super.key,
    required this.tabataTimer,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final bool isWork =
        tabataTimer.phase == TabataPhase.work;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.45),
        child: Center(
          child: Card(
            elevation: 16,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "TABATA",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  Text("Ronda ${tabataTimer.currentRound}"),
                  const SizedBox(height: 8),

                  Text(tabataTimer.currentExercise?['name'] ?? ''),
                  const SizedBox(height: 12),

                  Text(
                    isWork ? "TRABAJO" : "DESCANSO",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color:
                          isWork ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                      "${tabataTimer.elapsed} / ${tabataTimer.total} s"),

                  const SizedBox(height: 20),

                  TextButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text("Finalizar Tabata"),
                    onPressed: onSkip,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
