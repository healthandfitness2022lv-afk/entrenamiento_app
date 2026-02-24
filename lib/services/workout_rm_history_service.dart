import '../utils/rpe_factor.dart';

class RMPoint {
  final DateTime date;
  final double rm;

  RMPoint(this.date, this.rm);
}

class WorkoutRMHistoryService {
  static Map<String, List<RMPoint>> buildRMHistory(
    List<Map<String, dynamic>> workouts,
  ) {
    final Map<String, List<RMPoint>> history = {};

    for (final w in workouts) {
      final DateTime date = w['date'];
      final List performed = w['performed'];

      for (final block in performed) {
        if (block['type'] != 'Series') continue;

        final exercises =
            List<Map<String, dynamic>>.from(block['exercises'] ?? []);

        for (final ex in exercises) {

          final String exName = ex['exercise'];

          final sets =
              List<Map<String, dynamic>>.from(ex['sets'] ?? []);

          for (final s in sets) {
            if (s['done'] != true) continue;

            final double weight =
                (s['weight'] as num?)?.toDouble() ?? 0;

            final int reps =
                (s['reps'] as num?)?.toInt() ?? 0;

            final double rpe =
                (s['rpe'] as num?)?.toDouble() ?? 0;

            if (weight <= 0 || reps <= 0 || rpe <= 0) continue;

            final rm =
                weight * (1 + reps / (rpeFactor(rpe) * 30));

            history.putIfAbsent(exName, () => []);
            history[exName]!.add(RMPoint(date, rm));
          }
        }
      }
    }

    // ordenar por fecha
    for (final h in history.values) {
      h.sort((a, b) => a.date.compareTo(b.date));
    }

    return history;
  }
}