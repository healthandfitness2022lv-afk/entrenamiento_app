import '../models/muscle_catalog.dart';

class ImbalanceAlert {
  final String title;
  final String explanation;
  final double ratio;
  final double dominantLoad;
  final double weakerLoad;
  final String dominantLabel;
  final String weakerLabel;

  const ImbalanceAlert({
    required this.title,
    required this.explanation,
    required this.ratio,
    required this.dominantLoad,
    required this.weakerLoad,
    required this.dominantLabel,
    required this.weakerLabel,
  });
}

class TrainingImbalanceService {
  static List<ImbalanceAlert> analyze({
    required Map<String, double> totalLoad,
  }) {
    final result = <ImbalanceAlert>[];

    void addIfImbalanced({
      required String title,
      required String leftLabel,
      required String rightLabel,
      required List<Muscle> leftMuscles,
      required List<Muscle> rightMuscles,
      double threshold = 1.35,
    }) {
      final left = _sum(totalLoad, leftMuscles);
      final right = _sum(totalLoad, rightMuscles);

      if (left <= 0 && right <= 0) return;

      final dominantIsLeft = left >= right;
      final dominant = dominantIsLeft ? left : right;
      final weaker = dominantIsLeft ? right : left;

      if (weaker <= 0) {
        result.add(
          ImbalanceAlert(
            title: title,
            explanation:
                "Toda la carga cayó en ${dominantIsLeft ? leftLabel : rightLabel}.",
            ratio: double.infinity,
            dominantLoad: dominant,
            weakerLoad: weaker,
            dominantLabel: dominantIsLeft ? leftLabel : rightLabel,
            weakerLabel: dominantIsLeft ? rightLabel : leftLabel,
          ),
        );
        return;
      }

      final ratio = dominant / weaker;
      if (ratio < threshold) return;

      result.add(
        ImbalanceAlert(
          title: title,
          explanation:
              "${dominantIsLeft ? leftLabel : rightLabel} acumula ${ratio.toStringAsFixed(2)}x la carga de ${dominantIsLeft ? rightLabel : leftLabel}.",
          ratio: ratio,
          dominantLoad: dominant,
          weakerLoad: weaker,
          dominantLabel: dominantIsLeft ? leftLabel : rightLabel,
          weakerLabel: dominantIsLeft ? rightLabel : leftLabel,
        ),
      );
    }

    addIfImbalanced(
      title: 'Empuje vs tirón',
      leftLabel: 'Empuje superior',
      rightLabel: 'Tirón superior',
      leftMuscles: functionalGroups[FunctionalGroup.upperPush]!,
      rightMuscles: functionalGroups[FunctionalGroup.upperPull]!,
    );

    addIfImbalanced(
      title: 'Cuádriceps vs isquios',
      leftLabel: 'Cuádriceps',
      rightLabel: 'Isquiotibiales',
      leftMuscles: const [Muscle.quads],
      rightMuscles: const [Muscle.hamstrings],
    );

    addIfImbalanced(
      title: 'Pecho vs espalda',
      leftLabel: 'Pecho',
      rightLabel: 'Espalda',
      leftMuscles: anatomicalGroups[AnatomicalGroup.pecho]!,
      rightMuscles: anatomicalGroups[AnatomicalGroup.espalda]!,
    );

    addIfImbalanced(
      title: 'Anterior vs posterior de hombro',
      leftLabel: 'Deltoide anterior',
      rightLabel: 'Deltoide posterior',
      leftMuscles: const [Muscle.frontDelts],
      rightMuscles: const [Muscle.rearDelts],
    );

    result.sort((a, b) => b.ratio.compareTo(a.ratio));
    return result;
  }

  static double _sum(Map<String, double> load, List<Muscle> muscles) {
    double total = 0;
    for (final muscle in muscles) {
      total += load[muscle.name] ?? 0;
    }
    return total;
  }
}
