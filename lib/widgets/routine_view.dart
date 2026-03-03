import 'package:flutter/material.dart';

class RoutineView extends StatelessWidget {
  final Map<String, dynamic> routine;
  final bool compact;

  const RoutineView({
    super.key,
    required this.routine,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final blocks =
        List<Map<String, dynamic>>.from(routine['blocks'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks
          .map(
            (block) => Padding(
              padding: EdgeInsets.only(
                bottom: compact ? 16 : 24,
              ),
              child: RoutineBlockView(
                block: block,
                compact: compact,
              ),
            ),
          )
          .toList(),
    );
  }
}

class RoutineBlockView extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool compact;

  const RoutineBlockView({
    super.key,
    required this.block,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final exercises =
        List<Map<String, dynamic>>.from(block['exercises'] ?? []);

    final customTitle =
        (block['title'] ?? '').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ===========================
        // HEADER BLOQUE
        // ===========================
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _blockIcon(block['type']),
              size: compact ? 16 : 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // 🔥 TÍTULO PRINCIPAL
                  Text(
                    customTitle.isNotEmpty
                        ? customTitle
                        : _blockSubtitle(block),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 14 : 17,
                    ),
                  ),

                  // 🔥 SUBTÍTULO (solo si hay nombre personalizado)
                  if (customTitle.isNotEmpty)
                    Text(
                      _blockSubtitle(block),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: compact ? 8 : 12),

        // ===========================
        // CONTENEDOR EJERCICIOS
        // ===========================
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 1.2,
            ),
          ),
          child: Column(
            children: exercises
                .map((e) => RoutineExerciseRow(
                      exercise: e,
                      compact: compact,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class RoutineExerciseRow extends StatelessWidget {
  final Map<String, dynamic> exercise;
  final bool compact;

  const RoutineExerciseRow({
    super.key,
    required this.exercise,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool perSide = exercise['perSide'] == true;
    final num weight = (exercise['weight'] ?? 0);

    String mainValue = "";

    // 🔥 SERIES
    if (exercise['series'] != null &&
        exercise['reps'] != null) {
      mainValue =
          "${exercise['series']}×${exercise['reps']} reps";
    }

    // 🔥 TIEMPO / REPS dinámico
    else if (exercise['value'] != null &&
        exercise['valueType'] != null) {
      mainValue =
          exercise['valueType'] == "time"
              ? "${exercise['value']} s"
              : "${exercise['value']} reps";
    }

    // 🔥 SERIES DESCENDENTES (Muestra el arreglo de repeticiones de ser posible)
    else if (exercise['reps'] is List) {
      final repsList = exercise['reps'] as List;
      mainValue = "${repsList.join('-')} reps";
    }

    final String sideLabel =
        perSide ? " · por lado" : "";

    final String weightLabel =
        weight > 0 ? " · ${weight}kg" : "";

    final String rightText =
        [mainValue, sideLabel, weightLabel]
            .where((s) => s.isNotEmpty)
            .join("");

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 4 : 6,
      ),
      child: Row(
        children: [
          Icon(
            Icons.play_arrow,
            size: compact ? 14 : 16,
            color: Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              exercise['name'] ?? '',
              style: TextStyle(
                fontSize: compact ? 12 : 14,
              ),
            ),
          ),
          Text(
            rightText,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// 🔹 HELPERS
// =======================================================

String _blockSubtitle(Map<String, dynamic> block) {
  switch (block['type']) {
    case "Series":
      return "Series";

    case "Circuito":
      return "Circuito · ${block['rounds']} rondas";

    case "EMOM":
      return "EMOM · ${block['time']}s · ${block['rounds']} rondas";

    case "Tabata":
      return "Tabata ${block['work']}/${block['rest']} · ${block['rounds']} rondas";

    case "Series descendentes":
      return "Ladder Descendente";

    case "Buscar RM":
      final rm = block['rm'] ?? 5;
      return "Objetivo: ${rm}RM";

    default:
      return block['type'] ?? '';
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
    case "Series descendentes":
      return Icons.trending_down;
    case "Buscar RM":
      return Icons.track_changes;
    default:
      return Icons.category;
  }
}
