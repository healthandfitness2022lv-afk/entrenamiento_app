import 'package:cloud_firestore/cloud_firestore.dart';

class SessionStats {
  final DateTime date;
  final String sessionName;
  final double volumeKg;
  final double avgRpe;
  final int totalSets;
  final int durationMinutes;

  const SessionStats({
    required this.date,
    required this.sessionName,
    required this.volumeKg,
    required this.avgRpe,
    required this.totalSets,
    required this.durationMinutes,
  });
}

class WorkoutStatsService {
  /// Trae las últimas [limit] sesiones del usuario [uid] y las convierte
  /// en [SessionStats] ordenadas de más antigua a más reciente.
  static Future<List<SessionStats>> fetch({
    required String uid,
    int limit = 200,
  }) async {
    final snap =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: uid)
            .orderBy('date', descending: true)
            .limit(limit)
            .get();

    final List<SessionStats> results = [];

    for (final doc in snap.docs) {
      final data = doc.data();
      final rawDate = data['date'];
      if (rawDate == null) continue;

      final date = (rawDate as Timestamp).toDate();
      final performed = List<Map<String, dynamic>>.from(
        data['performed'] ?? [],
      );
      final m = _metrics(performed);

      results.add(
        SessionStats(
          date: date,
          sessionName: (data['sessionName'] as String?) ?? 'Entrenamiento',
          volumeKg: m.volume,
          avgRpe: m.avgRpe,
          totalSets: m.sets,
          durationMinutes: (data['durationMinutes'] as int?) ?? 0,
        ),
      );
    }

    // Orden cronológico ascendente
    results.sort((a, b) => a.date.compareTo(b.date));
    return results;
  }

  // ─── métricas internas ────────────────────────────────────────────────────
  static _Metrics _metrics(List<Map<String, dynamic>> performed) {
    double vol = 0, rpeSum = 0;
    int sets = 0, rpeN = 0;

    for (final blk in performed) {
      final type = (blk['type'] as String?) ?? '';

      if (['Series', 'Series descendentes', 'Buscar RM'].contains(type)) {
        for (final ex in List<Map<String, dynamic>>.from(
          blk['exercises'] ?? [],
        )) {
          final ps = ex['perSide'] == true ? 2.0 : 1.0;
          for (final s in List<Map<String, dynamic>>.from(ex['sets'] ?? [])) {
            sets++;
            final rpe = (s['rpe'] as num?)?.toDouble();
            if (rpe != null) {
              rpeSum += rpe;
              rpeN++;
            }
            final w = ((s['weight'] as num?)?.toDouble() ?? 0) * ps;
            final r = (s['reps'] as num?)?.toInt() ?? 0;
            if (w > 0 && r > 0) vol += w * r;
          }
        }
      } else if (type == 'Circuito') {
        for (final rnd in List<Map<String, dynamic>>.from(
          blk['rounds'] ?? [],
        )) {
          for (final ex in List<Map<String, dynamic>>.from(
            rnd['exercises'] ?? [],
          )) {
            sets++;
            final rpe = (ex['rpe'] as num?)?.toDouble();
            if (rpe != null) {
              rpeSum += rpe;
              rpeN++;
            }
            final w =
                ((ex['weight'] as num?)?.toDouble() ?? 0) *
                (ex['perSide'] == true ? 2.0 : 1.0);
            final r = (ex['reps'] as num?)?.toInt() ?? 0;
            if (w > 0 && r > 0) vol += w * r;
          }
        }
      } else if (type == 'Tabata' || type == 'EMOM') {
        for (final ex in List<Map<String, dynamic>>.from(
          blk['exercises'] ?? [],
        )) {
          sets++;
          final rpe = (ex['rpe'] as num?)?.toDouble();
          if (rpe != null) {
            rpeSum += rpe;
            rpeN++;
          }
        }
      }
    }

    return _Metrics(
      volume: vol,
      avgRpe: rpeN > 0 ? rpeSum / rpeN : 0,
      sets: sets,
    );
  }
}

class _Metrics {
  final double volume;
  final double avgRpe;
  final int sets;
  const _Metrics({
    required this.volume,
    required this.avgRpe,
    required this.sets,
  });
}
