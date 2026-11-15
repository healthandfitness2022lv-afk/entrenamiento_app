import 'dart:math';

import 'package:entrenamiento_app/services/progress_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/legacy_progress_alerts.dart';

/// Sesión sintética: puntos de RM por ejercicio en una fecha.
class _Session {
  final DateTime date;
  final Map<String, List<Map<String, dynamic>>> points;
  _Session(this.date, this.points);
}

List<_Session> _randomSessions(Random rng) {
  const exercises = ['Sentadilla', 'Press banca', 'Remo - Barra'];
  const weights = [40.0, 50.0, 60.0, 62.5, 70.0];
  final sessions = <_Session>[];
  var day = DateTime(2026, 1, 1, 9);
  for (var i = 0; i < 25; i++) {
    // 0–3 días después; a veces dos sesiones el mismo día.
    day = day.add(Duration(days: rng.nextInt(4), hours: rng.nextInt(3)));
    final points = <String, List<Map<String, dynamic>>>{};
    for (final ex in exercises) {
      if (rng.nextDouble() < 0.3) continue;
      final sets = 1 + rng.nextInt(4);
      points[ex] = [
        for (var s = 0; s < sets; s++)
          () {
            final w = weights[rng.nextInt(weights.length)];
            final r = 3 + rng.nextInt(10);
            return <String, dynamic>{
              'date': day,
              'rm': w * (1 + r / 30.0),
              'weight': w,
              'reps': r,
              'rpe': (6 + rng.nextInt(5)).toDouble(),
            };
          }(),
      ];
    }
    if (points.isNotEmpty) sessions.add(_Session(day, points));
  }
  return sessions;
}

/// Firma comparable de una alerta (sin los sets de evidencia, que pueden
/// diferir solo en empates exactos).
List<String> _signature(List<ProgressAlert> alerts) =>
    alerts
        .map(
          (a) =>
              '${a.type}|${a.title}|'
              '${(a.evidence['previous'] as num?)?.toStringAsFixed(6)}|'
              '${(a.evidence['current'] as num?)?.toStringAsFixed(6)}',
        )
        .toList()
      ..sort();

void main() {
  test(
    'resumen incremental == historial completo (implementación original)',
    () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        final sessions = _randomSessions(rng);
        final summaries = <String, ExerciseProgressSummary>{};

        for (var i = 0; i < sessions.length; i++) {
          final session = sessions[i];

          // Referencia: historial completo de las sesiones anteriores + la
          // actual, con la implementación original. Solo los ejercicios de la
          // sesión actual (así lo filtra el guardado): si no, una segunda
          // sesión el mismo día repetiría alertas de ejercicios que no hizo.
          final history = <String, List<Map<String, dynamic>>>{};
          for (final prev in sessions.take(i)) {
            prev.points.forEach((ex, pts) {
              if (!session.points.containsKey(ex)) return;
              history.putIfAbsent(ex, () => []).addAll(pts);
            });
          }
          session.points.forEach(
            (ex, pts) => history.putIfAbsent(ex, () => []).addAll(pts),
          );
          final expected = legacyAnalyzeSessionImpact(
            rmHistory: history,
            targetDate: session.date,
          );

          // Camino nuevo (1): mismo historial completo.
          final viaHistory = ProgressAlertService.analyzeSessionImpact(
            rmHistory: history,
            targetDate: session.date,
          );

          // Camino nuevo (2): resúmenes persistidos (con ida y vuelta JSON,
          // simulando Firestore) + solo la sesión actual.
          final persisted = {
            for (final e in summaries.entries)
              e.key: ExerciseProgressSummary.fromJson(e.value.toJson()),
          };
          final viaSummary = ProgressAlertService.analyzeWithSummaries(
            summaries: persisted,
            today: session.points,
            targetDate: session.date,
          );

          final reason = 'seed $seed, sesión $i (${session.date})';
          expect(_signature(viaHistory), _signature(expected), reason: reason);
          expect(viaSummary, isNotNull, reason: reason);
          expect(_signature(viaSummary!), _signature(expected), reason: reason);

          // Actualizar resúmenes como hace ProgressSummaryService.
          session.points.forEach((ex, pts) {
            final s = persisted[ex] ?? ExerciseProgressSummary();
            s.addDay(session.date, pts);
            summaries[ex] = s;
          });
        }
      }
    },
  );

  test('fromHistory == construcción incremental', () {
    final sessions = _randomSessions(Random(42));
    final all = <String, List<Map<String, dynamic>>>{};
    final incremental = <String, ExerciseProgressSummary>{};
    for (final s in sessions) {
      s.points.forEach((ex, pts) {
        all.putIfAbsent(ex, () => []).addAll(pts);
        incremental
            .putIfAbsent(ex, ExerciseProgressSummary.new)
            .addDay(s.date, pts);
      });
    }
    all.forEach((ex, pts) {
      final rebuilt = ExerciseProgressSummary.fromHistory(pts).toJson();
      final inc = incremental[ex]!.toJson();
      for (final key in [
        'bestTonnageValue',
        'bestDayVolume',
        'foldedPoints',
        'lastDay',
        'minRpeByWeight',
      ]) {
        expect(rebuilt[key], inc[key], reason: '$ex.$key');
      }
      expect(
        (rebuilt['bestRm'] as Map)['rm'],
        (inc['bestRm'] as Map)['rm'],
        reason: '$ex.bestRm',
      );
    });
  });

  test('sesión con fecha anterior al resumen → null (usa historial)', () {
    final summary =
        ExerciseProgressSummary()..addDay(DateTime(2026, 3, 10), [
          {
            'date': DateTime(2026, 3, 10),
            'rm': 80.0,
            'weight': 60.0,
            'reps': 10,
            'rpe': 8.0,
          },
        ]);
    final result = ProgressAlertService.analyzeWithSummaries(
      summaries: {'Sentadilla': summary},
      today: {
        'Sentadilla': [
          {
            'date': DateTime(2026, 3, 1),
            'rm': 90.0,
            'weight': 70.0,
            'reps': 8,
            'rpe': 8.0,
          },
        ],
      },
      targetDate: DateTime(2026, 3, 1),
    );
    expect(result, isNull);
  });
}
