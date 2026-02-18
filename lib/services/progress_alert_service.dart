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

  // 🔥 NUEVOS
  improvedEfficiency,
  sessionVolumePR,
  bestWeekEver,
}

class ProgressAlertService {


static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  
  static List<ProgressAlert> analyzeSessionImpact({
  required Map<String, List<Map<String, dynamic>>> rmHistory,
  required DateTime targetDate,
}) {
  final List<ProgressAlert> alerts = [];

  final DateTime todayKey =
      DateTime(targetDate.year, targetDate.month, targetDate.day);

  rmHistory.forEach((exercise, rawPoints) {
    if (rawPoints.isEmpty) return;

    final previousPoints = rawPoints.where((p) {
      final d = p['date'] as DateTime;
      final day = DateTime(d.year, d.month, d.day);
      return day.isBefore(todayKey);
    }).toList();

    final todayPoints = rawPoints.where((p) {
      final d = p['date'] as DateTime;
      final day = DateTime(d.year, d.month, d.day);
      return day == todayKey;
    }).toList();

    if (todayPoints.isEmpty) return;
    if (previousPoints.isEmpty) return;


    

    // ======================================================
// 1️⃣ NEW PR
// ======================================================

final double previousBestRM = previousPoints.isNotEmpty
    ? previousPoints
        .map((p) => _d(p['rm']))
        .reduce((a, b) => a > b ? a : b)
    : 0;

final double todayBestRM = todayPoints
    .map((p) => _d(p['rm']))
    .reduce((a, b) => a > b ? a : b);

if (todayBestRM > previousBestRM) {
  final previousBestPoint = previousPoints.isNotEmpty
      ? previousPoints.reduce((a, b) =>
          _d(a['rm']) > (b['rm'] as double) ? a : b)
      : null;

  final todayBestPoint = todayPoints.reduce((a, b) =>
      _d(a['rm']) > (b['rm'] as double) ? a : b);

  final deltaPct = previousBestRM > 0
      ? (todayBestRM - previousBestRM) / previousBestRM
      : null;

  alerts.add(
    ProgressAlert(
      type: ProgressAlertType.newPR,
      title: "Nuevo PR en $exercise",
      explanation: "",
      evidence: {
        'exercise': exercise,
        'previous': previousBestRM,
        'current': todayBestRM,
        'deltaPct': deltaPct,
        'previousSet': previousBestPoint,
        'currentSet': todayBestPoint,
      },
    ),
  );
}

    // ======================================================
    // 2️⃣ IMPROVED EFFICIENCY
    // ======================================================

    for (final todaySet in todayPoints) {
      final weight = _d(todaySet['weight']);
final rpe = _d(todaySet['rpe']);

      final sameWeightHistory = previousPoints
          .where((p) => p['weight'] == weight)
          .toList();

      if (sameWeightHistory.isEmpty) continue;

      final bestPreviousRPE = sameWeightHistory
          .map((p) => _d(p['rpe']))
          .reduce((a, b) => a < b ? a : b);

      if (rpe < bestPreviousRPE) {
        final deltaPct = bestPreviousRPE > 0
            ? (bestPreviousRPE - rpe) / bestPreviousRPE
            : null;

        alerts.add(
          ProgressAlert(
            type: ProgressAlertType.improvedEfficiency,
            title: "Mejor eficiencia en $exercise",
            explanation: "",
            evidence: {
              'exercise': exercise,
              'previous': bestPreviousRPE,
              'current': rpe,
              'deltaPct': deltaPct,
            },
          ),
        );
      }
    }

    // ======================================================
    // 3️⃣ HEAVIEST SET (por tonelaje)
    // ======================================================

    Map<String, dynamic>? previousBestSet;
double previousMaxTonnage = 0;

for (final p in previousPoints) {
  final w = _d(p['weight']);
final r = _d(p['reps']);

  final ton = w * r;
  if (ton > previousMaxTonnage) {
    previousMaxTonnage = ton;
    previousBestSet = p;
  }
}

Map<String, dynamic>? todayBestSet;
double todayMaxTonnage = 0;

for (final p in todayPoints) {
  final w = p['weight'];
  final r = p['reps'];
  if (w != null && r != null) {
    final ton = w * r;
    if (ton > todayMaxTonnage) {
      todayMaxTonnage = ton;
      todayBestSet = p;
    }
  }
}

if (todayMaxTonnage > previousMaxTonnage) {
  final deltaPct = previousMaxTonnage > 0
      ? (todayMaxTonnage - previousMaxTonnage) /
          previousMaxTonnage
      : null;

  alerts.add(
    ProgressAlert(
      type: ProgressAlertType.heaviestSet,
      title: "Serie más pesada histórica en $exercise",
      explanation: "",
      evidence: {
        'exercise': exercise,
        'previous': previousMaxTonnage,
        'current': todayMaxTonnage,
        'deltaPct': deltaPct,
        'previousSet': previousBestSet,
        'currentSet': todayBestSet,
      },
    ),
  );
}

    // ======================================================
    // 4️⃣ SESSION VOLUME PR
    // ======================================================

   final Map<DateTime, List<Map<String, dynamic>>> previousSetsPerDay = {};

for (final p in previousPoints) {
  final DateTime d = p['date'];
  final day = DateTime(d.year, d.month, d.day);

  final w = p['weight'];
  final r = p['reps'];

  if (w != null && r != null) {
    previousSetsPerDay.putIfAbsent(day, () => []);
    previousSetsPerDay[day]!.add(p);
  }
}

DateTime? previousBestDay;
double previousBestVolume = 0;

previousSetsPerDay.forEach((day, sets) {
  final volume = sets.fold<double>(
  0,
  (sum, s) => sum + (_d(s['weight']) * _d(s['reps'])),
)
;

  if (volume > previousBestVolume) {
    previousBestVolume = volume;
    previousBestDay = day;
  }
});

double todayVolume = 0;
final List<Map<String, dynamic>> todaySets = [];

for (final p in todayPoints) {
  final w = p['weight'];
  final r = p['reps'];
  if (w != null && r != null) {
    todayVolume += w * r;
    todaySets.add(p);
  }
}

if (todayVolume > previousBestVolume) {
  final deltaPct = previousBestVolume > 0
      ? (todayVolume - previousBestVolume) /
          previousBestVolume
      : null;

  alerts.add(
    ProgressAlert(
      type: ProgressAlertType.sessionVolumePR,
      title: "Récord de volumen en $exercise",
      explanation: "",
      evidence: {
        'exercise': exercise,
        'previous': previousBestVolume,
        'current': todayVolume,
        'deltaPct': deltaPct,
        'previousSets': previousBestDay != null
            ? previousSetsPerDay[previousBestDay]
            : [],
        'currentSets': todaySets,
      },
    ),
  );
}


  });

  return alerts;
}


  static List<ProgressAlert> analyzeHistorical({
  required Map<String, List<Map<String, dynamic>>> rmHistory,
}) {
  final List<ProgressAlert> alerts = [];

  rmHistory.forEach((exercise, rawPoints) {
    if (rawPoints.length < 2) return;

    rawPoints.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    double bestRM = 0;

    for (final p in rawPoints) {
      final rm = _d(p['rm']);
      if (rm > bestRM) {
        alerts.add(
          ProgressAlert(
            type: ProgressAlertType.newPR,
            title: "Nuevo PR histórico en $exercise",
            explanation:
                "RM estimada: ${rm.toStringAsFixed(1)} kg.",
            evidence: {
              'exercise': exercise,
              'date': p['date'],
            },
          ),
        );
        bestRM = rm;
      }
    }
  });

  return alerts;
}

}


