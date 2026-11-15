import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/exercise_name_utils.dart';
import 'planned_load_service.dart';
import 'planned_routine_loader_service.dart';

/// Un ejercicio (dentro de un bloque planificado en el pasado) que quedó sin
/// completar: se ejecutaron menos series/rondas de las planificadas.
class PendingExercise {
  final String name;
  final double plannedVol;
  final double doneVol;
  final String blockId;
  final String blockTitle;
  final String blockType;
  final String plannedWorkoutId;
  final DateTime originalDate;
  final Map<String, dynamic> exerciseData;

  PendingExercise({
    required this.name,
    required this.plannedVol,
    required this.doneVol,
    required this.blockId,
    required this.blockTitle,
    required this.blockType,
    required this.plannedWorkoutId,
    required this.originalDate,
    required this.exerciseData,
  });

  double get missingVol => (plannedVol - doneVol).clamp(0, double.infinity);
}

/// Detecta trabajo planificado en el pasado que el atleta no llegó a
/// completar, para poder ofrecerlo como recuperación en otro día.
///
/// Reusa el mismo criterio que la revisión semanal de `planning_screen.dart`
/// (bolsa de volumen ejecutado por nombre de ejercicio, sin importar qué día
/// se hizo), pero sobre una ventana de días pasados en vez de una semana
/// cerrada, y devolviendo el detalle por ejercicio en vez de un resumen.
class PendingWorkService {
  static String _normKey(dynamic name) => normalizeExerciseKey(name);

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [lookbackDays] limita cuántos días hacia atrás se revisan (por defecto,
  /// las últimas 2 semanas) para no arrastrar pendientes indefinidamente.
  static Future<List<PendingExercise>> loadPendingExercises({
    required String athleteId,
    DateTime? asOf,
    int lookbackDays = 14,
  }) async {
    final today = _dayOnly(asOf ?? DateTime.now());
    final start = today.subtract(Duration(days: lookbackDays));

    // 1) Planificados en el rango pasado (excluye hoy: hoy todavía se puede
    // completar normalmente, no es "pendiente").
    final plannedSnap =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: athleteId)
            .get();

    final plannedDocs =
        plannedSnap.docs.where((doc) {
          final date = PlannedRoutineLoaderService.dateTimeValue(
            doc.data()['date'],
          );
          if (date == null) return false;
          final day = _dayOnly(date);
          return !day.isBefore(start) && day.isBefore(today);
        }).toList();

    if (plannedDocs.isEmpty) return [];

    // 2) Ejecutados en el mismo rango (para restar de la bolsa, sin importar
    // qué día puntual se ejecutaron).
    final performedSnap =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThan: Timestamp.fromDate(today))
            .get();

    final Map<String, double> doneByKey = {};
    void addDone(dynamic name, double vol) {
      final key = _normKey(name);
      if (key.isEmpty || vol <= 0) return;
      doneByKey[key] = (doneByKey[key] ?? 0) + vol;
    }

    for (final w in performedSnap.docs) {
      final performed = w.data()['performed'];
      if (performed is! List) continue;

      for (final raw in performed) {
        if (raw is! Map) continue;
        final e = Map<String, dynamic>.from(raw);
        final type = (e['type'] ?? '').toString();

        if (type == 'Series' ||
            type == 'Series descendentes' ||
            type == 'Buscar RM') {
          for (final exRaw in (e['exercises'] as List? ?? const [])) {
            if (exRaw is! Map) continue;
            final ex = Map<String, dynamic>.from(exRaw);
            final sets = (ex['sets'] as List? ?? const []);
            addDone(ex['exercise'], sets.length.toDouble());
          }
        }

        if (type == 'Circuito') {
          final Map<String, int> count = {};
          for (final roundRaw in (e['rounds'] as List? ?? const [])) {
            if (roundRaw is! Map) continue;
            for (final exRaw in (roundRaw['exercises'] as List? ?? const [])) {
              if (exRaw is! Map) continue;
              final key = _normKey(exRaw['exercise']);
              if (key.isEmpty) continue;
              count[key] = (count[key] ?? 0) + 1;
            }
          }
          count.forEach((k, v) => doneByKey[k] = (doneByKey[k] ?? 0) + v);
        }

        if (type == 'Tabata') {
          final rounds =
              (e['rounds'] is num) ? (e['rounds'] as num).toDouble() : 1.0;
          for (final exRaw in (e['exercises'] as List? ?? const [])) {
            if (exRaw is! Map) continue;
            addDone(exRaw['exercise'], rounds);
          }
        }
      }
    }

    // 3) Resolver bloques planificados y comparar contra la bolsa de
    // ejecutados, igual criterio que `_reviewWeekDetailedByDay`: se
    // descuenta de más antiguo a más reciente para que un pendiente viejo
    // se considere cubierto primero.
    plannedDocs.sort((a, b) {
      final da = PlannedRoutineLoaderService.dateTimeValue(a.data()['date']);
      final db = PlannedRoutineLoaderService.dateTimeValue(b.data()['date']);
      return (da ?? today).compareTo(db ?? today);
    });

    final remaining = Map<String, double>.from(doneByKey);
    final Map<String, Map<String, dynamic>> blockCache = {};
    final List<PendingExercise> pending = [];

    for (final doc in plannedDocs) {
      final data = doc.data();
      final date = PlannedRoutineLoaderService.dateTimeValue(data['date']);
      if (date == null) continue;

      final blockId =
          (data['blockId'] ?? data['sourceBlockId'])?.toString().trim();
      if (blockId == null || blockId.isEmpty) continue;

      Map<String, dynamic>? block = blockCache[blockId];
      if (block == null) {
        final blockDoc =
            await FirebaseFirestore.instance
                .collection('blocks')
                .doc(blockId)
                .get();
        if (!blockDoc.exists) continue;
        block = blockDoc.data()!;
        blockCache[blockId] = block;
      }

      final type = (block['type'] ?? '').toString();
      final title =
          (data['blockTitle'] ?? block['title'] ?? block['name'] ?? '')
              .toString();
      final exercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? const [],
      );

      for (final exRaw in exercises) {
        final ex = Map<String, dynamic>.from(exRaw);
        final name = coerceExerciseName(ex['name']);
        final key = _normKey(name);
        if (key.isEmpty) continue;

        double plannedVol;
        if (type == 'Series' ||
            type == 'Series descendentes' ||
            type == 'Buscar RM') {
          plannedVol =
              (ex['series'] is num) ? (ex['series'] as num).toDouble() : 0.0;
        } else if (type == 'Circuito' || type == 'Tabata' || type == 'EMOM') {
          plannedVol =
              (block['rounds'] is num)
                  ? (block['rounds'] as num).toDouble()
                  : 1.0;
        } else {
          continue;
        }
        if (plannedVol <= 0) continue;

        final avail = remaining[key] ?? 0.0;
        final covered = avail >= plannedVol ? plannedVol : avail;
        remaining[key] = (avail - covered).clamp(0, double.infinity);

        final missing = plannedVol - covered;
        if (missing > 0) {
          pending.add(
            PendingExercise(
              name: name,
              plannedVol: plannedVol,
              doneVol: covered,
              blockId: blockId,
              blockTitle: title.isNotEmpty ? title : type,
              blockType: type,
              plannedWorkoutId: doc.id,
              originalDate: date,
              exerciseData: ex,
            ),
          );
        }
      }
    }

    return pending;
  }

  /// Arma un único bloque "Series" con los ejercicios pendientes elegidos,
  /// recortados a la cantidad de sets/rondas que efectivamente falta, listo
  /// para inyectarse en la rutina del día como bloque extra de recuperación.
  /// Cada ejercicio conserva de dónde viene (`plannedWorkoutId`/`blockId`
  /// originales) para trazabilidad, aunque se ejecute otro día.
  static Map<String, dynamic> buildRecoveryBlock(
    List<PendingExercise> selected,
  ) {
    final exercises = <Map<String, dynamic>>[];

    for (final pending in selected) {
      final resolved = PlannedLoadService.resolveBlock(
        block: {
          'type': 'Series',
          'exercises': [pending.exerciseData],
        },
        planned: const {},
      );
      final ex = Map<String, dynamic>.from(
        (resolved['exercises'] as List).first as Map,
      );

      final allSets = List<Map<String, dynamic>>.from(ex['sets'] ?? const []);
      final missingCount = pending.missingVol.ceil().clamp(
        1,
        allSets.isEmpty ? 1 : allSets.length,
      );
      ex['sets'] = allSets.isEmpty ? allSets : allSets.sublist(0, missingCount);
      ex['series'] = missingCount;
      ex['plannedWorkoutId'] = pending.plannedWorkoutId;
      ex['blockId'] = pending.blockId;
      ex['recoveredFromDate'] = pending.originalDate.toIso8601String();

      exercises.add(ex);
    }

    return {
      'type': 'Series',
      'title': 'Recuperación',
      'isRecoveryBlock': true,
      'exercises': exercises,
    };
  }
}
