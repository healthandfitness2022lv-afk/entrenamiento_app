import 'package:cloud_firestore/cloud_firestore.dart';

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
    final todayKey = _dayKey(targetDate);

    rmHistory.forEach((exercise, rawPoints) {
      if (rawPoints.isEmpty) return;

      final previousPoints =
          rawPoints
              .where((p) => _dayKey(p['date'] as DateTime).isBefore(todayKey))
              .toList();
      final todayPoints =
          rawPoints
              .where((p) => _dayKey(p['date'] as DateTime) == todayKey)
              .toList();

      if (todayPoints.isEmpty) return;
      if (previousPoints.isEmpty) return;

      alerts.addAll(
        _analyzeExercise(
          exercise,
          ExerciseProgressSummary.fromPoints(previousPoints),
          todayPoints,
        ),
      );
    });

    return alerts;
  }

  /// Igual que [analyzeSessionImpact] pero partiendo de resúmenes ya
  /// persistidos, sin releer todo el historial. [today] son los puntos de la
  /// sesión recién registrada. Devuelve null si algún resumen tiene datos
  /// posteriores a [targetDate] (p. ej. sesión con fecha pasada): en ese
  /// caso hay que usar el historial completo.
  static List<ProgressAlert>? analyzeWithSummaries({
    required Map<String, ExerciseProgressSummary> summaries,
    required Map<String, List<Map<String, dynamic>>> today,
    required DateTime targetDate,
  }) {
    final List<ProgressAlert> alerts = [];

    for (final entry in today.entries) {
      final summary = summaries[entry.key];
      if (summary == null) continue; // ejercicio sin historial previo
      final split = summary.splitAt(targetDate);
      if (split == null) return null;
      final todayPoints = [...split.sameDay, ...entry.value];
      if (todayPoints.isEmpty || split.previous.isEmpty) continue;
      alerts.addAll(_analyzeExercise(entry.key, split.previous, todayPoints));
    }
    return alerts;
  }

  static DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<ProgressAlert> _analyzeExercise(
    String exercise,
    ExerciseProgressSummary previous,
    List<Map<String, dynamic>> todayPoints,
  ) {
    final List<ProgressAlert> alerts = [];

    // ======================================================
    // 1️⃣ NEW PR
    // ======================================================
    final previousBestPoint = previous.bestRm;
    final double previousBestRM =
        previousBestPoint == null ? 0 : _d(previousBestPoint['rm']);
    final todayBestPoint = todayPoints.reduce(
      (a, b) => _d(a['rm']) > _d(b['rm']) ? a : b,
    );
    final double todayBestRM = _d(todayBestPoint['rm']);

    if (todayBestRM > previousBestRM) {
      alerts.add(
        ProgressAlert(
          type: ProgressAlertType.newPR,
          title: "Nuevo PR en $exercise",
          explanation: "",
          evidence: {
            'exercise': exercise,
            'previous': previousBestRM,
            'current': todayBestRM,
            'deltaPct':
                previousBestRM > 0
                    ? (todayBestRM - previousBestRM) / previousBestRM
                    : null,
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
      final bestPreviousRPE = previous.minRpeByWeight[weight];
      if (bestPreviousRPE == null) continue;

      if (rpe < bestPreviousRPE) {
        alerts.add(
          ProgressAlert(
            type: ProgressAlertType.improvedEfficiency,
            title: "Mejor eficiencia en $exercise",
            explanation: "",
            evidence: {
              'exercise': exercise,
              'previous': bestPreviousRPE,
              'current': rpe,
              'deltaPct':
                  bestPreviousRPE > 0
                      ? (bestPreviousRPE - rpe) / bestPreviousRPE
                      : null,
            },
          ),
        );
      }
    }

    // ======================================================
    // 3️⃣ HEAVIEST SET (por tonelaje)
    // ======================================================
    final previousMaxTonnage = previous.bestTonnageValue;
    Map<String, dynamic>? todayBestSet;
    double todayMaxTonnage = 0;
    for (final p in todayPoints) {
      final ton = _d(p['weight']) * _d(p['reps']);
      if (ton > todayMaxTonnage) {
        todayMaxTonnage = ton;
        todayBestSet = p;
      }
    }

    if (todayMaxTonnage > previousMaxTonnage) {
      alerts.add(
        ProgressAlert(
          type: ProgressAlertType.heaviestSet,
          title: "Serie más pesada histórica en $exercise",
          explanation: "",
          evidence: {
            'exercise': exercise,
            'previous': previousMaxTonnage,
            'current': todayMaxTonnage,
            'deltaPct':
                previousMaxTonnage > 0
                    ? (todayMaxTonnage - previousMaxTonnage) /
                        previousMaxTonnage
                    : null,
            'previousSet': previous.bestTonnage,
            'currentSet': todayBestSet,
          },
        ),
      );
    }

    // ======================================================
    // 4️⃣ SESSION VOLUME PR
    // ======================================================
    final previousBestVolume = previous.bestDayVolume;
    final todayVolume = todayPoints.fold<double>(
      0,
      (sum, p) => sum + _d(p['weight']) * _d(p['reps']),
    );

    if (todayVolume > previousBestVolume) {
      alerts.add(
        ProgressAlert(
          type: ProgressAlertType.sessionVolumePR,
          title: "Récord de volumen en $exercise",
          explanation: "",
          evidence: {
            'exercise': exercise,
            'previous': previousBestVolume,
            'current': todayVolume,
            'deltaPct':
                previousBestVolume > 0
                    ? (todayVolume - previousBestVolume) / previousBestVolume
                    : null,
            'previousSets': previous.bestDaySets,
            'currentSets': todayPoints,
          },
        ),
      );
    }

    return alerts;
  }

  static List<ProgressAlert> analyzeHistorical({
    required Map<String, List<Map<String, dynamic>>> rmHistory,
  }) {
    final List<ProgressAlert> alerts = [];

    rmHistory.forEach((exercise, rawPoints) {
      if (rawPoints.length < 2) return;

      rawPoints.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
      );

      double bestRM = 0;

      for (final p in rawPoints) {
        final rm = _d(p['rm']);
        if (rm > bestRM) {
          alerts.add(
            ProgressAlert(
              type: ProgressAlertType.newPR,
              title: "Nuevo PR histórico en $exercise",
              explanation: "RM estimada: ${rm.toStringAsFixed(1)} kg.",
              evidence: {'exercise': exercise, 'date': p['date']},
            ),
          );
          bestRM = rm;
        }
      }
    });

    return alerts;
  }
}

/// Resumen acumulado del historial de un ejercicio: lo mínimo necesario
/// para evaluar las alertas de progreso sin releer todos los workouts.
///
/// Los días ya "cerrados" están agregados (mejor RM, mejor serie por
/// tonelaje, día de más volumen, RPE mínimo por peso). Los puntos del último
/// día registrado se guardan aparte en [lastDayPoints]: si llega otra sesión
/// ese mismo día, cuentan como "hoy" (igual que con el historial completo).
class ExerciseProgressSummary {
  Map<String, dynamic>? bestRm;
  Map<String, dynamic>? bestTonnage;
  double bestTonnageValue = 0;
  double bestDayVolume = 0;
  List<Map<String, dynamic>> bestDaySets = [];
  final Map<double, double> minRpeByWeight = {};
  int foldedPoints = 0;
  DateTime? lastDay;
  List<Map<String, dynamic>> lastDayPoints = [];

  ExerciseProgressSummary();

  bool get isEmpty => foldedPoints == 0;

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static Map<DateTime, List<Map<String, dynamic>>> _groupByDay(
    List<Map<String, dynamic>> points,
  ) {
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final p in points) {
      byDay.putIfAbsent(_day(p['date'] as DateTime), () => []).add(p);
    }
    return byDay;
  }

  /// Resumen de puntos arbitrarios (todos agregados, sin "último día").
  factory ExerciseProgressSummary.fromPoints(
    List<Map<String, dynamic>> points,
  ) {
    final summary = ExerciseProgressSummary();
    _groupByDay(points).forEach((_, dayPoints) => summary._foldDay(dayPoints));
    return summary;
  }

  /// Resumen persistible: agrega todos los días salvo el último, que queda
  /// pendiente en [lastDayPoints].
  factory ExerciseProgressSummary.fromHistory(
    List<Map<String, dynamic>> points,
  ) {
    final summary = ExerciseProgressSummary();
    final byDay = _groupByDay(points);
    final days = byDay.keys.toList()..sort();
    for (final day in days) {
      summary.addDay(day, byDay[day]!);
    }
    return summary;
  }

  void _foldDay(List<Map<String, dynamic>> dayPoints) {
    double dayVolume = 0;
    for (final p in dayPoints) {
      foldedPoints++;
      if (bestRm == null || _d(p['rm']) >= _d(bestRm!['rm'])) bestRm = p;
      final ton = _d(p['weight']) * _d(p['reps']);
      if (ton > bestTonnageValue) {
        bestTonnageValue = ton;
        bestTonnage = p;
      }
      final weight = _d(p['weight']);
      final rpe = _d(p['rpe']);
      final current = minRpeByWeight[weight];
      if (current == null || rpe < current) minRpeByWeight[weight] = rpe;
      dayVolume += ton;
    }
    if (dayVolume > bestDayVolume) {
      bestDayVolume = dayVolume;
      bestDaySets = List.of(dayPoints);
    }
  }

  /// Registra los puntos de un día.
  void addDay(DateTime day, List<Map<String, dynamic>> points) {
    final key = _day(day);
    if (lastDay == null || key.isAfter(lastDay!)) {
      if (lastDayPoints.isNotEmpty) _foldDay(lastDayPoints);
      lastDay = key;
      lastDayPoints = List.of(points);
    } else if (key == lastDay) {
      lastDayPoints = [...lastDayPoints, ...points];
    } else {
      // Día anterior al último registrado: se agrega directo.
      _foldDay(points);
    }
  }

  /// Separa lo "previo" a [day] de los puntos de ese mismo día. Null si el
  /// resumen tiene datos posteriores a [day] (no se puede evaluar así).
  ({ExerciseProgressSummary previous, List<Map<String, dynamic>> sameDay})?
  splitAt(DateTime day) {
    final key = _day(day);
    if (lastDay == null) return (previous: this, sameDay: const []);
    if (lastDay!.isAfter(key)) return null;
    if (lastDay == key) return (previous: this, sameDay: lastDayPoints);
    final copy = ExerciseProgressSummary.fromJson(toJson());
    copy._foldDay(copy.lastDayPoints);
    copy.lastDayPoints = [];
    copy.lastDay = null;
    return (previous: copy, sameDay: const []);
  }

  static Map<String, dynamic> _pointToJson(Map<String, dynamic> p) => {
    'date': Timestamp.fromDate(p['date'] as DateTime),
    'rm': _d(p['rm']),
    'weight': _d(p['weight']),
    'reps': (p['reps'] as num?)?.toInt() ?? 0,
    'rpe': _d(p['rpe']),
  };

  static Map<String, dynamic> _pointFromJson(Map raw) => {
    'date': (raw['date'] as Timestamp).toDate(),
    'rm': _d(raw['rm']),
    'weight': _d(raw['weight']),
    'reps': (raw['reps'] as num?)?.toInt() ?? 0,
    'rpe': _d(raw['rpe']),
  };

  Map<String, dynamic> toJson() => {
    'bestRm': bestRm == null ? null : _pointToJson(bestRm!),
    'bestTonnage': bestTonnage == null ? null : _pointToJson(bestTonnage!),
    'bestTonnageValue': bestTonnageValue,
    'bestDayVolume': bestDayVolume,
    'bestDaySets': bestDaySets.map(_pointToJson).toList(),
    // Lista de pares: un peso como "62.5" no sirve de clave de mapa.
    'minRpeByWeight': [
      for (final e in minRpeByWeight.entries) {'w': e.key, 'rpe': e.value},
    ],
    'foldedPoints': foldedPoints,
    'lastDay': lastDay == null ? null : Timestamp.fromDate(lastDay!),
    'lastDayPoints': lastDayPoints.map(_pointToJson).toList(),
  };

  factory ExerciseProgressSummary.fromJson(Map raw) {
    final s = ExerciseProgressSummary();
    final bestRm = raw['bestRm'];
    if (bestRm is Map) s.bestRm = _pointFromJson(bestRm);
    final bestTon = raw['bestTonnage'];
    if (bestTon is Map) s.bestTonnage = _pointFromJson(bestTon);
    s.bestTonnageValue = _d(raw['bestTonnageValue']);
    s.bestDayVolume = _d(raw['bestDayVolume']);
    s.bestDaySets = [
      for (final p in (raw['bestDaySets'] as List? ?? const []))
        if (p is Map) _pointFromJson(p),
    ];
    for (final e in (raw['minRpeByWeight'] as List? ?? const [])) {
      if (e is Map) s.minRpeByWeight[_d(e['w'])] = _d(e['rpe']);
    }
    s.foldedPoints = (raw['foldedPoints'] as num?)?.toInt() ?? 0;
    final lastDay = raw['lastDay'];
    if (lastDay is Timestamp) s.lastDay = lastDay.toDate();
    s.lastDayPoints = [
      for (final p in (raw['lastDayPoints'] as List? ?? const []))
        if (p is Map) _pointFromJson(p),
    ];
    return s;
  }
}
