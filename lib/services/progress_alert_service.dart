class ProgressAlert {
  final ProgressAlertType type;
  final String title;
  final String explanation;
  final Map<String, dynamic> evidence;

  ProgressAlert({
    required this.type,
    required this.title,
    required this.explanation,
    required this.evidence,
  });
}

enum ProgressAlertType {
  newPR,
  rpeWithoutProgress,
  stagnation,
  heaviestSet,
}

class ProgressAlertService {
  static List<ProgressAlert> analyze({
    required Map<String, List<Map<String, dynamic>>> rmHistory,
    required List<Map<String, dynamic>> weeklyVolume,
  }) {
    final List<ProgressAlert> alerts = [];

    // ======================================================
    // 🏆 PRs HISTÓRICOS + GRANDES PROGRESOS
    // ======================================================
    rmHistory.forEach((exercise, rawPoints) {
      if (rawPoints.length < 2) return;

      // ---------- 1 RM máximo por día ----------
      final Map<DateTime, Map<String, dynamic>> bestPerDay = {};

      for (final p in rawPoints) {
        final DateTime d = p['date'];
        final day = DateTime(d.year, d.month, d.day);
        final double? rm = p['rm'];

        if (rm == null) continue;

        if (!bestPerDay.containsKey(day) ||
            rm > (bestPerDay[day]!['rm'] as double)) {
          bestPerDay[day] = {
            'date': day,
            'rm': rm,
            'rpe': p['rpe'],
            'weight': p['weight'],
            'reps': p['reps'],
          };
        }
      }

      final points = bestPerDay.values.toList()
        ..sort((a, b) =>
            (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      double currentBest = 0;

      for (int i = 0; i < points.length; i++) {
        final p = points[i];

        final double rm = p['rm'];
        final DateTime date = p['date'];
        final num? weight = p['weight'];
        final num? reps = p['reps'];

        final tonelaje =
            (weight != null && reps != null) ? weight * reps : null;

        if (rm > currentBest) {
          final deltaPct =
              currentBest > 0 ? (rm - currentBest) / currentBest : null;

          // 🥇 GRAN PROGRESO
          if (deltaPct != null && deltaPct >= 0.20) {
            alerts.add(
              ProgressAlert(
                type: ProgressAlertType.newPR,
                title: "Gran progreso en $exercise",
                explanation:
                    "Serie: ${weight ?? '-'} kg × ${reps ?? '-'} reps\n"
                    "Tonelaje del set: ${tonelaje?.toStringAsFixed(0) ?? '-'} kg\n"
                    "RM estimada: ${rm.toStringAsFixed(1)} kg "
                    "(+${(deltaPct * 100).toStringAsFixed(0)}%).",
                evidence: {
                  'exercise': exercise,
                  'weight': weight,
                  'reps': reps,
                  'tonnage': tonelaje,
                  'currentRM': rm,
                  'previousRM': currentBest,
                  'deltaPct': deltaPct,
                  'date': date,
                },
              ),
            );
          }
          // 🏆 PR NORMAL
          else {
            alerts.add(
              ProgressAlert(
                type: ProgressAlertType.newPR,
                title: "Nuevo PR en $exercise",
                explanation:
                    "Serie: ${weight ?? '-'} kg × ${reps ?? '-'} reps\n"
                    "Tonelaje del set: ${tonelaje?.toStringAsFixed(0) ?? '-'} kg\n"
                    "RM estimada: ${rm.toStringAsFixed(1)} kg.",
                evidence: {
                  'exercise': exercise,
                  'weight': weight,
                  'reps': reps,
                  'tonnage': tonelaje,
                  'currentRM': rm,
                  'date': date,
                },
              ),
            );
          }

          currentBest = rm;
        }

        // ======================================================
        // ⚠️ RPE ↑ SIN RM ↑
        // ======================================================
        if (i > 0) {
          final prev = points[i - 1];
          final num? prevRpe = prev['rpe'];
          final num? currRpe = p['rpe'];
          final double prevRm = prev['rm'];

          if (prevRpe != null &&
              currRpe != null &&
              currRpe > prevRpe &&
              rm <= prevRm) {
            alerts.add(
              ProgressAlert(
                type: ProgressAlertType.rpeWithoutProgress,
                title: "Más esfuerzo sin mejora en $exercise",
                explanation:
                    "Serie: ${weight ?? '-'} kg × ${reps ?? '-'} reps\n"
                    "RPE subió de $prevRpe a $currRpe, "
                    "pero el RM se mantuvo (${prevRm.toStringAsFixed(1)} kg).",
                evidence: {
                  'exercise': exercise,
                  'weight': weight,
                  'reps': reps,
                  'previousRM': prevRm,
                  'currentRM': rm,
                  'previousRPE': prevRpe,
                  'currentRPE': currRpe,
                  'date': date,
                },
              ),
            );
          }
        }
      }

      // ======================================================
      // 🏋️ SERIE MÁS PESADA HISTÓRICA
      // ======================================================
      final heaviest = rawPoints
          .where((p) => p['weight'] != null && p['reps'] != null)
          .fold<Map<String, dynamic>?>(null, (best, p) {
        final w = p['weight'] as num?;
        if (w == null) return best;

        if (best == null || w > (best['weight'] as num)) {
          return p;
        }
        return best;
      });

      if (heaviest != null) {
        final ton = heaviest['weight'] * heaviest['reps'];

        alerts.add(
          ProgressAlert(
            type: ProgressAlertType.heaviestSet,
            title: "Serie más pesada en $exercise",
            explanation:
                "Serie: ${heaviest['weight']} kg × ${heaviest['reps']} reps\n"
                "Tonelaje del set: ${ton.toStringAsFixed(0)} kg\n"
                "RM estimada: ${(heaviest['rm'] as double).toStringAsFixed(1)} kg.",
            evidence: {
              'exercise': exercise,
              'weight': heaviest['weight'],
              'reps': heaviest['reps'],
              'tonnage': ton,
              'rm': heaviest['rm'],
              'date': heaviest['date'],
            },
          ),
        );
      }
    });

    // ======================================================
    // 📉 ESTANCAMIENTO DE VOLUMEN (3 SEMANAS)
    // ======================================================
    if (weeklyVolume.length >= 3) {
      weeklyVolume.sort((a, b) =>
          (a['week'] as DateTime).compareTo(b['week'] as DateTime));

      final last3 = weeklyVolume.sublist(weeklyVolume.length - 3);

      final volumes = last3
          .map((e) => e['volume'])
          .whereType<num>()
          .map((v) => v.toDouble())
          .toList();

      final maxV = volumes.reduce((a, b) => a > b ? a : b);
      final minV = volumes.reduce((a, b) => a < b ? a : b);

      if ((maxV - minV) < (maxV * 0.05)) {
        alerts.add(
          ProgressAlert(
            type: ProgressAlertType.stagnation,
            title: "Volumen estancado",
            explanation:
                "El volumen semanal se ha mantenido estable durante 3 semanas "
                "(${volumes.map((v) => v.toStringAsFixed(0)).join(" → ")} kg).",
            evidence: {
              'weeks': last3.map((e) => e['week']).toList(),
              'volumes': volumes,
            },
          ),
        );
      }
    }

    return alerts;
  }
}
