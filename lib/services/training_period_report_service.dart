import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/muscle_catalog.dart';
import '../utils/svg_utils.dart';
import 'fatigue_recalculation_service.dart';
import 'training_identity_service.dart';
import 'training_review_service.dart';

/// Fila de la tabla diaria: un ejercicio planificado (con lo logrado) o uno
/// realizado sin planificar.
class _ExerciseRow {
  final String block;
  final String name;
  final double plannedSets;
  final double doneSets;
  final double plannedKg;
  final double doneKg;
  final double? avgRpe;
  final String note;
  final bool planned;

  _ExerciseRow({
    required this.block,
    required this.name,
    required this.plannedSets,
    required this.doneSets,
    required this.plannedKg,
    required this.doneKg,
    required this.avgRpe,
    required this.note,
    required this.planned,
  });
}

class _DayReport {
  final DateTime date;
  final List<_ExerciseRow> rows;
  final double plannedSets;
  final double doneSets;
  final double plannedKg;
  final double doneKg;
  final double? avgRpe;
  final TrainingIdentityResult? plannedIdentity;
  final TrainingIdentityResult? loggedIdentity;
  final Map<String, double> plannedMuscles;
  final Map<String, double> loggedMuscles;
  final double? fatigueBefore;
  final double? fatigueAfter;
  final List<MapEntry<Muscle, double>> topFatigued;
  final List<Map<String, dynamic>> sessions;
  final bool isFuture;

  _DayReport({
    required this.date,
    required this.rows,
    required this.plannedSets,
    required this.doneSets,
    required this.plannedKg,
    required this.doneKg,
    required this.avgRpe,
    required this.plannedIdentity,
    required this.loggedIdentity,
    required this.plannedMuscles,
    required this.loggedMuscles,
    required this.fatigueBefore,
    required this.fatigueAfter,
    required this.topFatigued,
    required this.sessions,
    required this.isFuture,
  });

  bool get hasPlan => plannedSets > 0;
  bool get trained => sessions.isNotEmpty || doneSets > 0;
  double get seriesPct => plannedSets > 0 ? doneSets / plannedSets : 0;

  String get status {
    if (!hasPlan) return trained ? 'No planificado' : 'Descanso';
    if (isFuture && doneSets == 0) return 'Pendiente';
    if (doneSets == 0) return 'No realizado';
    if (seriesPct >= 0.9) return 'Completo';
    return 'Parcial';
  }

  /// `durationMinutes` es inicio→"finalizar": una sesión que quedó abierta
  /// horas/días da duraciones absurdas. Solo se cuentan las de 1–240 min.
  static const maxValidMinutes = 240;

  static int? validMinutes(Map<String, dynamic> session) {
    final m = (session['durationMinutes'] as num?)?.toInt();
    if (m == null || m <= 0 || m > maxValidMinutes) return null;
    return m;
  }

  int get totalMinutes =>
      sessions.fold<int>(0, (acc, s) => acc + (validMinutes(s) ?? 0));

  int get invalidDurationSessions =>
      sessions.where((s) => validMinutes(s) == null).length;
}

/// Informe retrospectivo de un período (por defecto 4 semanas): lo
/// planificado vs. lo entrenado día por día, perfil de entrenamiento,
/// músculos trabajados, cumplimiento (series y kg) y fatiga.
///
/// El cálculo de cumplimiento/perfil/carga es el mismo de la revisión
/// semanal ([TrainingReviewCalculator]); la fatiga sale del recálculo del
/// histórico ([FatigueRecalculationService.recalculate]) sin persistir nada.
class TrainingPeriodReportService {
  static final PdfColor _ink = PdfColor.fromHex('#0B1220');
  static final PdfColor _blue = PdfColor.fromHex('#2563EB');
  static final PdfColor _purple = PdfColor.fromHex('#7C3AED');
  static final PdfColor _lime = PdfColor.fromHex('#8CFF24');
  static final PdfColor _surface = PdfColor.fromHex('#F6F8FC');
  static final PdfColor _green = PdfColor.fromHex('#16A34A');
  static final PdfColor _amber = PdfColor.fromHex('#D97706');
  static final PdfColor _red = PdfColor.fromHex('#DC2626');
  static final PdfColor _grey = PdfColor.fromHex('#64748B');

  static const _fatigueTopK = 6;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Montserrat no trae emojis: se quitan de textos libres (nombres, notas).
  static final RegExp _emoji = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
    unicode: true,
  );
  static String _clean(String s) => s.replaceAll(_emoji, '').trim();

  static String _norm(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Arma el PDF y lo muestra en una vista previa con opción de compartir /
  /// imprimir. Maneja su propio diálogo de carga y los errores.
  static Future<void> generateAndPreview({
    required BuildContext context,
    required String athleteId,
    required String athleteName,
    required DateTimeRange range,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    var loadingOpen = true;
    try {
      final bytes = await buildBytes(
        athleteId: athleteId,
        athleteName: athleteName,
        range: range,
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      loadingOpen = false;
      final fileName =
          'Informe_${athleteName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}_'
          '${DateFormat('yyyyMMdd').format(range.start)}-'
          '${DateFormat('yyyyMMdd').format(range.end)}.pdf';
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => Scaffold(
                appBar: AppBar(title: const Text('Informe de entrenamiento')),
                body: PdfPreview(
                  build: (_) async => bytes,
                  pdfFileName: fileName,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                ),
              ),
        ),
      );
    } catch (error, stack) {
      debugPrint('[TrainingPeriodReport] ERROR: $error');
      debugPrintStack(stackTrace: stack);
      if (!context.mounted) return;
      if (loadingOpen) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el informe: $error')),
      );
    }
  }

  static Future<Uint8List> buildBytes({
    required String athleteId,
    required String athleteName,
    required DateTimeRange range,
  }) async {
    final start = _day(range.start);
    final endExclusive = _day(range.end).add(const Duration(days: 1));
    final today = _day(DateTime.now());

    // ── Datos ────────────────────────────────────────────────────────────
    final calc = TrainingReviewCalculator(
      athleteId: athleteId,
      rangeStart: start,
      rangeEnd: endExclusive,
    );
    await calc.run();

    final fatigue = await FatigueRecalculationService.recalculate(
      uid: athleteId,
    );
    final steps =
        fatigue.steps
            .where(
              (s) =>
                  !s.isRecoveryOnly &&
                  !s.workoutDate.isBefore(start) &&
                  s.workoutDate.isBefore(endExclusive),
            )
            .toList()
          ..sort((a, b) => a.workoutDate.compareTo(b.workoutDate));

    final workoutsSnap =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThan: Timestamp.fromDate(endExclusive))
            .get();
    final sessionsByDay = <String, List<Map<String, dynamic>>>{};
    for (final doc in workoutsSnap.docs) {
      final data = doc.data();
      final date = (data['date'] as Timestamp?)?.toDate();
      if (date == null) continue;
      sessionsByDay
          .putIfAbsent(TrainingReviewCalculator.dayKey(date), () => [])
          .add(data);
    }

    // ── Días ─────────────────────────────────────────────────────────────
    final contribByDay = <String, List<TrainingIdentityExerciseContribution>>{};
    for (final c in calc.identityExercises) {
      contribByDay
          .putIfAbsent(TrainingReviewCalculator.dayKey(c.date), () => [])
          .add(c);
    }

    final dayKeys =
        {
            ...calc.reviewByDay.keys,
            ...sessionsByDay.keys,
            ...contribByDay.keys,
          }.toList()
          ..sort();

    final days = <_DayReport>[];
    for (final key in dayKeys) {
      final date = DateTime.parse(key);
      final results = calc.reviewByDay[key] ?? const <DayResultItem>[];
      final contribs = contribByDay[key] ?? const [];
      final plannedContribs = contribs.where((c) => c.source == 'planned');
      final loggedContribs =
          contribs.where((c) => c.source == 'logged').toList();
      final compliance =
          calc.exerciseLoadComplianceByDay[key] ??
          const <ExerciseLoadCompliance>[];
      final complianceByName = {for (final c in compliance) _norm(c.name): c};

      double? rpeOf(ExerciseLoadCompliance? c) {
        final values =
            (c?.achievedSets ?? const <AchievedSetDetail>[])
                .map((s) => s.rpe)
                .whereType<double>()
                .where((v) => v > 0)
                .toList();
        if (values.isEmpty) return null;
        return values.reduce((a, b) => a + b) / values.length;
      }

      final rows = <_ExerciseRow>[];
      final coveredNames = <String>{};
      for (final r in results) {
        final c = complianceByName[_norm(r.planned.name)];
        coveredNames.add(_norm(r.planned.name));
        if (r.substitutedBy != null) coveredNames.add(_norm(r.substitutedBy!));
        rows.add(
          _ExerciseRow(
            block: r.planned.blockLabel,
            name: r.planned.name,
            plannedSets: r.planned.plannedVol,
            doneSets: r.achieved,
            plannedKg: c?.plannedKg ?? 0,
            doneKg: c?.achievedKg ?? 0,
            avgRpe: rpeOf(c),
            note:
                r.substitutedBy != null
                    ? 'Sustituido por ${r.substitutedBy}'
                    : (r.missing > 0 && r.achieved > 0
                        ? 'Faltaron ${_num(r.missing)}'
                        : ''),
            planned: true,
          ),
        );
      }

      // Ejercicios hechos sin planificar (cada contribución 'logged' es una
      // serie/ronda registrada).
      final extraSets = <String, double>{};
      final extraBlock = <String, String>{};
      final extraName = <String, String>{};
      for (final c in loggedContribs) {
        final n = _norm(c.name);
        if (coveredNames.contains(n)) continue;
        extraSets[n] = (extraSets[n] ?? 0) + 1;
        extraBlock.putIfAbsent(n, () => c.blockTitle);
        extraName.putIfAbsent(n, () => c.name);
      }
      for (final n in extraSets.keys) {
        final c = complianceByName[n];
        rows.add(
          _ExerciseRow(
            block: extraBlock[n] ?? '',
            name: extraName[n] ?? n,
            plannedSets: 0,
            doneSets: extraSets[n]!,
            plannedKg: 0,
            doneKg: c?.achievedKg ?? 0,
            avgRpe: rpeOf(c),
            note: 'No planificado',
            planned: false,
          ),
        );
      }
      for (final extra in calc.extrasByDay[key] ?? const []) {
        rows.add(
          _ExerciseRow(
            block: 'Extra',
            name: (extra['name'] ?? 'Extra').toString(),
            plannedSets: 0,
            doneSets: (extra['volume'] as num?)?.toDouble() ?? 0,
            plannedKg: 0,
            doneKg: 0,
            avgRpe: null,
            note: 'Ejercicio extra',
            planned: false,
          ),
        );
      }

      final allRpe =
          compliance
              .expand((c) => c.achievedSets)
              .map((s) => s.rpe)
              .whereType<double>()
              .where((v) => v > 0)
              .toList();

      final daySteps =
          steps
              .where(
                (s) => TrainingReviewCalculator.dayKey(s.workoutDate) == key,
              )
              .toList();
      double? before;
      double? after;
      var topFatigued = <MapEntry<Muscle, double>>[];
      if (daySteps.isNotEmpty) {
        before = FatigueRecalculationService.calculateGlobalFatigue(
          daySteps.first.fatigueBefore,
          topK: _fatigueTopK,
        );
        after = FatigueRecalculationService.calculateGlobalFatigue(
          daySteps.last.fatigueAfter,
          topK: _fatigueTopK,
        );
        topFatigued =
            daySteps.last.fatigueAfter.entries
                .where((e) => e.value >= 5)
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
        topFatigued = topFatigued.take(4).toList();
      }

      days.add(
        _DayReport(
          date: date,
          rows: rows,
          plannedSets: results.fold(0.0, (a, r) => a + r.planned.plannedVol),
          doneSets: results.fold(0.0, (a, r) => a + r.achieved),
          plannedKg: compliance.fold(0.0, (a, c) => a + c.plannedKg),
          doneKg: compliance.fold(0.0, (a, c) => a + c.achievedKg),
          avgRpe:
              allRpe.isEmpty
                  ? null
                  : allRpe.reduce((a, b) => a + b) / allRpe.length,
          plannedIdentity: calc.identityFor(plannedContribs),
          loggedIdentity: calc.identityFor(loggedContribs),
          plannedMuscles: _muscleSum(plannedContribs),
          loggedMuscles: _muscleSum(loggedContribs),
          fatigueBefore: before,
          fatigueAfter: after,
          topFatigued: topFatigued,
          sessions: sessionsByDay[key] ?? const [],
          isFuture: date.isAfter(today),
        ),
      );
    }

    // ── Agregados del período ────────────────────────────────────────────
    final pastDays = days.where((d) => !d.isFuture).toList();
    final plannedSetsToDate = pastDays.fold(0.0, (a, d) => a + d.plannedSets);
    final doneSetsToDate = pastDays.fold(0.0, (a, d) => a + d.doneSets);
    final plannedMusclesTotal = _muscleSum(
      calc.identityExercises.where((c) => c.source == 'planned'),
    );
    final loggedMusclesTotal = _muscleSum(
      calc.identityExercises.where((c) => c.source == 'logged'),
    );
    final sessionsCount = workoutsSnap.docs.length;
    final totalMinutes = days.fold<int>(0, (a, d) => a + d.totalMinutes);
    final invalidDurations = days.fold<int>(
      0,
      (a, d) => a + d.invalidDurationSessions,
    );

    // Fatiga al cierre del período: si el rango llega a hoy se usa la fatiga
    // actual (ya recuperada hasta ahora); si es un período pasado, la que
    // quedó tras la última sesión del rango.
    final Map<Muscle, double> closingFatigue =
        endExclusive.isAfter(DateTime.now())
            ? fatigue.finalFatigue
            : (steps.isNotEmpty ? steps.last.fatigueAfter : const {});

    final weeks = _weeklyRows(days, steps);
    final observations = _observations(
      days: days,
      steps: steps,
      plannedMuscles: plannedMusclesTotal,
      loggedMuscles: loggedMusclesTotal,
      plannedIdentity: calc.plannedTrainingIdentity,
      loggedIdentity: calc.loggedTrainingIdentity,
    );

    // ── Recursos ─────────────────────────────────────────────────────────
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Montserrat-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Montserrat-Bold.ttf'),
    );
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/logo/logo.png')).buffer.asUint8List(),
    );
    final frontSvg = await rootBundle.loadString('assets/svg/body_front.svg');
    final backSvg = await rootBundle.loadString('assets/svg/body_back.svg');
    final loadHeat = _relativeHeat(loggedMusclesTotal);
    final loadFront = pw.MemoryImage(
      await _svgToBytes(buildColoredSvg(frontSvg, loadHeat)),
    );
    final loadBack = pw.MemoryImage(
      await _svgToBytes(buildColoredSvg(backSvg, loadHeat)),
    );
    final fatigueFront = pw.MemoryImage(
      await _svgToBytes(buildColoredSvg(frontSvg, closingFatigue)),
    );
    final fatigueBack = pw.MemoryImage(
      await _svgToBytes(buildColoredSvg(backSvg, closingFatigue)),
    );

    final fmt = DateFormat('dd/MM/yyyy');
    final rangeLabel = '${fmt.format(start)} – ${fmt.format(_day(range.end))}';

    // ── PDF ──────────────────────────────────────────────────────────────
    final pdf = pw.Document(
      title: 'Informe de entrenamiento $athleteName',
      author: 'Nexus Training',
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 120,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
        header: (ctx) => _header(logo, athleteName, rangeLabel),
        footer: _footer,
        build:
            (ctx) => [
              _title('Resumen del período'),
              _kpiGrid([
                _Kpi(
                  'Días planificados',
                  '${days.where((d) => d.hasPlan).length}',
                  _blue,
                ),
                _Kpi(
                  'Días entrenados',
                  '${days.where((d) => d.trained).length}',
                  _purple,
                ),
                _Kpi('Sesiones', '$sessionsCount', _ink),
                _Kpi(
                  invalidDurations > 0
                      ? 'Tiempo total ($invalidDurations sin duración válida)'
                      : 'Tiempo total',
                  totalMinutes > 0 ? _hours(totalMinutes) : '-',
                  _grey,
                ),
                _Kpi(
                  'Cumplimiento series',
                  _pct(
                    plannedSetsToDate > 0
                        ? doneSetsToDate / plannedSetsToDate
                        : null,
                  ),
                  _pctColor(
                    plannedSetsToDate > 0
                        ? doneSetsToDate / plannedSetsToDate
                        : null,
                  ),
                ),
                _Kpi(
                  'Cumplimiento kg',
                  _pct(
                    calc.weeklyPlannedKg > 0
                        ? calc.weeklyAchievedKg / calc.weeklyPlannedKg
                        : null,
                  ),
                  _pctColor(
                    calc.weeklyPlannedKg > 0
                        ? calc.weeklyAchievedKg / calc.weeklyPlannedKg
                        : null,
                  ),
                ),
                _Kpi(
                  'Volumen levantado',
                  '${_compact(calc.weeklyAchievedKg)} kg',
                  _blue,
                ),
                _Kpi(
                  'RPE medio',
                  calc.weeklyAvgRpe > 0
                      ? calc.weeklyAvgRpe.toStringAsFixed(1)
                      : '-',
                  _amber,
                ),
              ]),
              pw.SizedBox(height: 12),
              _title('Tendencia semanal'),
              _weeklyTable(weeks),
              pw.SizedBox(height: 12),
              _title('Perfil de entrenamiento del período'),
              _profileComparison(
                calc.plannedTrainingIdentity,
                calc.loggedTrainingIdentity,
              ),
              pw.SizedBox(height: 12),
              _title('Músculos trabajados'),
              _muscleComparison(plannedMusclesTotal, loggedMusclesTotal),
              pw.SizedBox(height: 10),
              _bodyMaps(
                loadFront: loadFront,
                loadBack: loadBack,
                fatigueFront: fatigueFront,
                fatigueBack: fatigueBack,
                closingFatigue: closingFatigue,
              ),
              pw.SizedBox(height: 12),
              _title('Observaciones'),
              _observationList(observations),
              pw.NewPage(),
              _title('Detalle diario'),
              if (days.isEmpty)
                pw.Text(
                  'No hay planificación ni entrenamientos registrados en el período.',
                  style: pw.TextStyle(fontSize: 9, color: _grey),
                ),
              for (final d in days) ..._dayBlock(d),
            ],
      ),
    );

    return pdf.save();
  }

  // ════════════════════════════════════════════════════════════════════════
  // Cálculos auxiliares
  // ════════════════════════════════════════════════════════════════════════

  static Map<String, double> _muscleSum(
    Iterable<TrainingIdentityExerciseContribution> contribs,
  ) {
    final out = <String, double>{};
    for (final c in contribs) {
      c.muscleLoads.forEach((m, v) => out[m] = (out[m] ?? 0) + v);
    }
    return out;
  }

  static Map<Muscle, double> _relativeHeat(Map<String, double> loads) {
    final max = loads.values.fold<double>(0, (a, v) => v > a ? v : a);
    if (max <= 0) return const {};
    return {
      for (final m in Muscle.values)
        if ((loads[m.name] ?? 0) > 0) m: (loads[m.name]! / max) * 100,
    };
  }

  static List<Map<String, dynamic>> _weeklyRows(
    List<_DayReport> days,
    List<FatigueRecalculationStep> steps,
  ) {
    final byWeek = <DateTime, List<_DayReport>>{};
    for (final d in days) {
      final monday = d.date.subtract(Duration(days: d.date.weekday - 1));
      byWeek.putIfAbsent(_day(monday), () => []).add(d);
    }
    final weeks = byWeek.keys.toList()..sort();
    return [
      for (final w in weeks)
        () {
          final list = byWeek[w]!;
          final past = list.where((d) => !d.isFuture);
          final pSets = past.fold(0.0, (a, d) => a + d.plannedSets);
          final dSets = past.fold(0.0, (a, d) => a + d.doneSets);
          final pKg = past.fold(0.0, (a, d) => a + d.plannedKg);
          final dKg = list.fold(0.0, (a, d) => a + d.doneKg);
          final rpes = list.map((d) => d.avgRpe).whereType<double>().toList();
          final weekEnd = w.add(const Duration(days: 7));
          final fatigueValues =
              steps
                  .where(
                    (s) =>
                        !s.workoutDate.isBefore(w) &&
                        s.workoutDate.isBefore(weekEnd),
                  )
                  .map(
                    (s) => FatigueRecalculationService.calculateGlobalFatigue(
                      s.fatigueAfter,
                      topK: _fatigueTopK,
                    ),
                  )
                  .toList();
          return <String, dynamic>{
            'week': w,
            'plannedDays': list.where((d) => d.hasPlan).length,
            'trainedDays': list.where((d) => d.trained).length,
            'seriesPct': pSets > 0 ? dSets / pSets : null,
            'kgPct': pKg > 0 ? dKg / pKg : null,
            'kg': dKg,
            'rpe':
                rpes.isEmpty
                    ? null
                    : rpes.reduce((a, b) => a + b) / rpes.length,
            'fatigueAvg':
                fatigueValues.isEmpty
                    ? null
                    : fatigueValues.reduce((a, b) => a + b) /
                        fatigueValues.length,
            'fatigueMax':
                fatigueValues.isEmpty
                    ? null
                    : fatigueValues.reduce((a, b) => a > b ? a : b),
          };
        }(),
    ];
  }

  static List<String> _observations({
    required List<_DayReport> days,
    required List<FatigueRecalculationStep> steps,
    required Map<String, double> plannedMuscles,
    required Map<String, double> loggedMuscles,
    required TrainingIdentityResult? plannedIdentity,
    required TrainingIdentityResult? loggedIdentity,
  }) {
    final out = <String>[];
    final dm = DateFormat('EEE dd/MM', 'es');

    final missed = days.where((d) => d.status == 'No realizado').toList();
    if (missed.isNotEmpty) {
      out.add(
        'Días planificados sin entrenar (${missed.length}): '
        '${missed.map((d) => dm.format(d.date)).join(', ')}.',
      );
    }
    final partial = days.where((d) => d.status == 'Parcial').toList();
    if (partial.isNotEmpty) {
      out.add(
        'Sesiones parciales (${partial.length}): '
        '${partial.map((d) => '${dm.format(d.date)} (${_pct(d.seriesPct)})').join(', ')}.',
      );
    }
    final unplanned = days.where((d) => d.status == 'No planificado').length;
    if (unplanned > 0) {
      out.add('Se entrenó $unplanned día(s) sin sesión planificada.');
    }

    // Ejercicios con cumplimiento bajo (<60% de las series) en 2+ días.
    final lowCount = <String, int>{};
    final lowName = <String, String>{};
    for (final d in days.where((d) => !d.isFuture)) {
      for (final r in d.rows.where((r) => r.planned && r.plannedSets > 0)) {
        if (r.doneSets / r.plannedSets < 0.6 && !r.note.startsWith('Sustit')) {
          final k = _norm(r.name);
          lowCount[k] = (lowCount[k] ?? 0) + 1;
          lowName[k] = r.name;
        }
      }
    }
    final repeatedLow =
        lowCount.entries.where((e) => e.value >= 2).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (repeatedLow.isNotEmpty) {
      out.add(
        'Ejercicios que se quedan cortos con frecuencia: '
        '${repeatedLow.take(6).map((e) => '${lowName[e.key]} (${e.value} días)').join(', ')}.',
      );
    }

    // Músculos planificados con poca carga real (<60% de lo planificado).
    final plannedTotal = plannedMuscles.values.fold(0.0, (a, v) => a + v);
    final underworked = <String>[];
    if (plannedTotal > 0) {
      final ranked =
          plannedMuscles.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in ranked.take(10)) {
        if (e.value / plannedTotal < 0.03) continue;
        final real = loggedMuscles[e.key] ?? 0;
        if (real / e.value < 0.6) underworked.add(_muscleLabel(e.key));
      }
    }
    if (underworked.isNotEmpty) {
      out.add(
        'Músculos con menos estímulo real del planificado (<60%): '
        '${underworked.join(', ')}.',
      );
    }

    // Picos de fatiga global.
    final peaks =
        steps
            .map(
              (s) => MapEntry(
                s.workoutDate,
                FatigueRecalculationService.calculateGlobalFatigue(
                  s.fatigueAfter,
                  topK: _fatigueTopK,
                ),
              ),
            )
            .where((e) => e.value >= 70)
            .toList();
    if (peaks.isNotEmpty) {
      out.add(
        'Fatiga global alta (70% o más) tras: '
        '${peaks.map((e) => '${dm.format(e.key)} (${e.value.toStringAsFixed(0)}%)').join(', ')}.',
      );
    }

    if (plannedIdentity != null &&
        loggedIdentity != null &&
        plannedIdentity.primaryProfile != loggedIdentity.primaryProfile) {
      out.add(
        'El perfil real (${loggedIdentity.primaryProfile.label}) difiere del '
        'planificado (${plannedIdentity.primaryProfile.label}).',
      );
    }

    if (out.isEmpty) {
      out.add('Sin desviaciones relevantes respecto a lo planificado.');
    }
    return out;
  }

  // ════════════════════════════════════════════════════════════════════════
  // Widgets
  // ════════════════════════════════════════════════════════════════════════

  static pw.Widget _header(
    pw.MemoryImage logo,
    String athleteName,
    String rangeLabel,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _ink,
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 30,
            height: 30,
            padding: const pw.EdgeInsets.all(2),
            decoration: pw.BoxDecoration(
              color: PdfColors.black,
              borderRadius: pw.BorderRadius.circular(15),
              border: pw.Border.all(color: _lime, width: 1),
            ),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'INFORME DE ENTRENAMIENTO',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  rangeLabel,
                  style: pw.TextStyle(fontSize: 8, color: _lime),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _blue,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Text(
              athleteName,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: .5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generado ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _title(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.Container(width: 4, height: 14, color: _blue),
          pw.SizedBox(width: 6),
          pw.Text(
            text.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _kpiGrid(List<_Kpi> kpis) {
    pw.Widget card(_Kpi k) => pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.all(3),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: pw.BoxDecoration(
          color: _surface,
          border: pw.Border(left: pw.BorderSide(color: k.color, width: 3)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              k.value,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: k.color,
              ),
            ),
            pw.Text(k.label, style: pw.TextStyle(fontSize: 7, color: _grey)),
          ],
        ),
      ),
    );
    final rows = <pw.Widget>[];
    for (var i = 0; i < kpis.length; i += 4) {
      rows.add(
        pw.Row(
          children:
              kpis.sublist(i, (i + 4).clamp(0, kpis.length)).map(card).toList(),
        ),
      );
    }
    return pw.Column(children: rows);
  }

  static pw.Widget _weeklyTable(List<Map<String, dynamic>> weeks) {
    if (weeks.isEmpty) {
      return pw.Text(
        'Sin datos.',
        style: pw.TextStyle(fontSize: 8, color: _grey),
      );
    }
    final dm = DateFormat('dd/MM');
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.3),
        3: pw.FlexColumnWidth(1.3),
        4: pw.FlexColumnWidth(1.5),
        5: pw.FlexColumnWidth(1),
        6: pw.FlexColumnWidth(1.8),
      },
      children: [
        _headerRow([
          'Semana',
          'Días ent./plan.',
          '% series',
          '% kg',
          'Kg totales',
          'RPE',
          'Fatiga media / máx',
        ]),
        for (final w in weeks)
          pw.TableRow(
            children: [
              _cell(
                '${dm.format(w['week'] as DateTime)} – '
                '${dm.format((w['week'] as DateTime).add(const Duration(days: 6)))}',
              ),
              _cell('${w['trainedDays']} / ${w['plannedDays']}'),
              _cell(
                _pct(w['seriesPct'] as double?),
                color: _pctColor(w['seriesPct'] as double?),
                bold: true,
              ),
              _cell(
                _pct(w['kgPct'] as double?),
                color: _pctColor(w['kgPct'] as double?),
                bold: true,
              ),
              _cell(_compact(w['kg'] as double)),
              _cell(
                w['rpe'] == null
                    ? '-'
                    : (w['rpe'] as double).toStringAsFixed(1),
              ),
              _cell(
                w['fatigueAvg'] == null
                    ? '-'
                    : '${(w['fatigueAvg'] as double).toStringAsFixed(0)}% / '
                        '${(w['fatigueMax'] as double).toStringAsFixed(0)}%',
                color: _fatigueColor(w['fatigueMax'] as double?),
              ),
            ],
          ),
      ],
    );
  }

  static Map<TrainingProfile, double> _profilePct(TrainingIdentityResult? r) {
    if (r == null) return const {};
    final total = r.scores.values.fold<double>(0, (a, v) => a + v);
    if (total <= 0) return const {};
    return {for (final e in r.scores.entries) e.key: e.value / total * 100};
  }

  static final Map<TrainingProfile, PdfColor> _profileColors = {
    TrainingProfile.powerlifting: PdfColor.fromHex('#2563EB'),
    TrainingProfile.athlete: PdfColor.fromHex('#D95926'),
    TrainingProfile.hypertrophy: PdfColor.fromHex('#199E70'),
    TrainingProfile.conditioning: PdfColor.fromHex('#C98500'),
    TrainingProfile.bodyweight: PdfColor.fromHex('#D55181'),
    TrainingProfile.hybrid: PdfColor.fromHex('#64748B'),
  };

  static pw.Widget _profileComparison(
    TrainingIdentityResult? planned,
    TrainingIdentityResult? logged,
  ) {
    final p = _profilePct(planned);
    final l = _profilePct(logged);
    final profiles =
        TrainingProfile.values
            .where((t) => (p[t] ?? 0) > 0.5 || (l[t] ?? 0) > 0.5)
            .toList();
    if (profiles.isEmpty) {
      return pw.Text(
        'Sin datos suficientes para calcular el perfil.',
        style: pw.TextStyle(fontSize: 8, color: _grey),
      );
    }

    pw.Widget bar(double value, PdfColor color) => pw.Row(
      children: [
        pw.Container(
          width: 150,
          height: 7,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              width: 150 * (value / 100).clamp(0.0, 1.0),
              height: 7,
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: pw.BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        pw.SizedBox(width: 4),
        pw.Text(
          '${value.toStringAsFixed(0)}%',
          style: const pw.TextStyle(fontSize: 7),
        ),
      ],
    );

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              _pill(
                'Planificado: ${planned?.primaryProfile.label ?? '-'}',
                _blue,
              ),
              pw.SizedBox(width: 6),
              _pill('Real: ${logged?.primaryProfile.label ?? '-'}', _green),
              if (logged != null) ...[
                pw.SizedBox(width: 6),
                _pill('Secundario: ${logged.secondaryProfile.label}', _grey),
              ],
            ],
          ),
          pw.SizedBox(height: 7),
          for (final t in profiles)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(
                      t.label,
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _profileColors[t],
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.SizedBox(
                              width: 32,
                              child: pw.Text(
                                'Plan',
                                style: pw.TextStyle(
                                  fontSize: 6.5,
                                  color: _grey,
                                ),
                              ),
                            ),
                            bar(p[t] ?? 0, PdfColors.blueGrey300),
                          ],
                        ),
                        pw.SizedBox(height: 1.5),
                        pw.Row(
                          children: [
                            pw.SizedBox(
                              width: 32,
                              child: pw.Text(
                                'Real',
                                style: pw.TextStyle(
                                  fontSize: 6.5,
                                  color: _grey,
                                ),
                              ),
                            ),
                            bar(l[t] ?? 0, _profileColors[t] ?? _blue),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (logged != null && logged.biases.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                'Sesgos: ${logged.biases.take(4).join(' · ')}',
                style: pw.TextStyle(fontSize: 7, color: _grey),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _muscleComparison(
    Map<String, double> planned,
    Map<String, double> logged,
  ) {
    final pTotal = planned.values.fold(0.0, (a, v) => a + v);
    final lTotal = logged.values.fold(0.0, (a, v) => a + v);
    final keys =
        {...planned.keys, ...logged.keys}.toList()..sort(
          (a, b) => (logged[b] ?? planned[b] ?? 0).compareTo(
            logged[a] ?? planned[a] ?? 0,
          ),
        );
    if (keys.isEmpty) {
      return pw.Text(
        'Sin carga muscular registrada.',
        style: pw.TextStyle(fontSize: 8, color: _grey),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.6),
      },
      children: [
        _headerRow([
          'Músculo',
          '% carga plan.',
          '% carga real',
          'Real / plan.',
        ]),
        for (final k in keys.take(14))
          () {
            final p = planned[k] ?? 0;
            final l = logged[k] ?? 0;
            final ratio = p > 0 ? l / p : null;
            return pw.TableRow(
              children: [
                _cell(_muscleLabel(k), bold: true),
                _cell(pTotal > 0 ? _pct(p / pTotal) : '-'),
                _cell(lTotal > 0 ? _pct(l / lTotal) : '-'),
                _cell(
                  ratio == null ? 'Sin plan' : _pct(ratio),
                  color: _pctColor(ratio),
                  bold: true,
                ),
              ],
            );
          }(),
      ],
    );
  }

  static pw.Widget _bodyMaps({
    required pw.MemoryImage loadFront,
    required pw.MemoryImage loadBack,
    required pw.MemoryImage fatigueFront,
    required pw.MemoryImage fatigueBack,
    required Map<Muscle, double> closingFatigue,
  }) {
    final topFatigue =
        closingFatigue.entries.where((e) => e.value >= 5).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final global = FatigueRecalculationService.calculateGlobalFatigue(
      closingFatigue,
      topK: _fatigueTopK,
    );

    pw.Widget panel(
      String title,
      String subtitle,
      pw.MemoryImage front,
      pw.MemoryImage back,
      pw.Widget? footer,
    ) => pw.Expanded(
      child: pw.Container(
        height: 230,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: _ink,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _lime,
              ),
            ),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.grey300,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Expanded(
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.Image(front, fit: pw.BoxFit.contain)),
                  pw.Expanded(child: pw.Image(back, fit: pw.BoxFit.contain)),
                ],
              ),
            ),
            if (footer != null) footer,
          ],
        ),
      ),
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        panel(
          'CARGA REAL ACUMULADA',
          'Relativa al músculo más trabajado del período',
          loadFront,
          loadBack,
          null,
        ),
        pw.SizedBox(width: 8),
        panel(
          'FATIGA AL CIERRE · ${global.toStringAsFixed(0)}%',
          'Modelo de fatiga por músculo (entrenamiento + descanso)',
          fatigueFront,
          fatigueBack,
          topFatigue.isEmpty
              ? null
              : pw.Text(
                topFatigue
                    .take(4)
                    .map((e) => '${e.key.label} ${e.value.toStringAsFixed(0)}%')
                    .join(' · '),
                style: const pw.TextStyle(
                  fontSize: 6.5,
                  color: PdfColors.white,
                ),
              ),
        ),
      ],
    );
  }

  static pw.Widget _observationList(List<String> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final item in items)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 4,
                  height: 4,
                  margin: const pw.EdgeInsets.only(top: 3, right: 6),
                  decoration: pw.BoxDecoration(
                    color: _blue,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(item, style: const pw.TextStyle(fontSize: 8)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static PdfColor _statusColor(String status) {
    switch (status) {
      case 'Completo':
        return _green;
      case 'Parcial':
        return _amber;
      case 'No realizado':
        return _red;
      case 'No planificado':
        return _purple;
      default:
        return _grey;
    }
  }

  static List<pw.Widget> _dayBlock(_DayReport d) {
    final title = toBeginningOfSentenceCase(
      DateFormat("EEEE d 'de' MMMM", 'es').format(d.date),
    );
    final statusColor = _statusColor(d.status);
    final sessionNames = d.sessions
        .map((s) => (s['sessionName'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .join(' · ');
    final notes =
        d.sessions
            .map((s) => (s['notes'] ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();

    final widgets = <pw.Widget>[
      pw.SizedBox(height: 8),
      // Cabecera del día
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: _surface,
          border: pw.Border(left: pw.BorderSide(color: statusColor, width: 4)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  if (sessionNames.isNotEmpty)
                    pw.Text(
                      _clean(sessionNames),
                      style: pw.TextStyle(fontSize: 7, color: _grey),
                    ),
                ],
              ),
            ),
            _pill(d.status, statusColor),
            if (d.hasPlan) ...[
              pw.SizedBox(width: 4),
              _pill('Series ${_pct(d.seriesPct)}', _pctColor(d.seriesPct)),
            ],
            if (d.plannedKg > 0) ...[
              pw.SizedBox(width: 4),
              _pill(
                'Kg ${_pct(d.doneKg / d.plannedKg)}',
                _pctColor(d.doneKg / d.plannedKg),
              ),
            ],
            if (d.totalMinutes > 0) ...[
              pw.SizedBox(width: 4),
              _pill('${d.totalMinutes} min', _grey),
            ],
            if (d.avgRpe != null) ...[
              pw.SizedBox(width: 4),
              _pill('RPE ${d.avgRpe!.toStringAsFixed(1)}', _amber),
            ],
          ],
        ),
      ),
    ];

    // Perfil del día (plan vs real)
    final pp = _profilePct(d.plannedIdentity);
    final lp = _profilePct(d.loggedIdentity);
    String profileLine(Map<TrainingProfile, double> m) {
      final entries =
          m.entries.where((e) => e.value >= 5).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      return entries.isEmpty
          ? '-'
          : entries
              .map((e) => '${e.key.label} ${e.value.toStringAsFixed(0)}%')
              .join(' · ');
    }

    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, left: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _infoLine('Perfil planificado', profileLine(pp)),
            _infoLine('Perfil real', profileLine(lp)),
          ],
        ),
      ),
    );

    // Tabla de ejercicios
    if (d.rows.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FlexColumnWidth(3.2),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.9),
            4: pw.FlexColumnWidth(0.9),
            5: pw.FlexColumnWidth(2.3),
          },
          children: [
            _headerRow([
              'Bloque',
              'Ejercicio',
              'Series p/h',
              'Kg plan / hecho',
              'RPE',
              'Nota',
            ]),
            for (final r in d.rows)
              pw.TableRow(
                decoration:
                    r.planned
                        ? null
                        : pw.BoxDecoration(color: PdfColor.fromHex('#F3EEFF')),
                children: [
                  _cell(r.block, size: 6.5, color: _grey),
                  _cell(r.name, bold: true),
                  _cell(
                    r.planned
                        ? '${_num(r.plannedSets)} / ${_num(r.doneSets)}'
                        : '– / ${_num(r.doneSets)}',
                    color:
                        r.planned
                            ? _pctColor(
                              r.plannedSets > 0
                                  ? r.doneSets / r.plannedSets
                                  : null,
                            )
                            : _purple,
                    bold: true,
                  ),
                  _cell(
                    (r.plannedKg <= 0 && r.doneKg <= 0)
                        ? '-'
                        : '${r.plannedKg > 0 ? _compact(r.plannedKg) : '–'} / '
                            '${_compact(r.doneKg)}',
                  ),
                  _cell(r.avgRpe == null ? '-' : r.avgRpe!.toStringAsFixed(1)),
                  _cell(r.note, size: 6.5, color: _grey),
                ],
              ),
          ],
        ),
      );
    }

    // Músculos y fatiga
    final muscles =
        d.loggedMuscles.isNotEmpty ? d.loggedMuscles : d.plannedMuscles;
    final mTotal = muscles.values.fold(0.0, (a, v) => a + v);
    final topMuscles =
        muscles.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final muscleLine =
        mTotal <= 0
            ? '-'
            : topMuscles
                .take(5)
                .map(
                  (e) =>
                      '${_muscleLabel(e.key)} ${(e.value / mTotal * 100).toStringAsFixed(0)}%',
                )
                .join(' · ');
    widgets.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, left: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _infoLine(
              d.loggedMuscles.isNotEmpty
                  ? 'Músculos trabajados'
                  : 'Músculos planificados',
              muscleLine,
            ),
            if (d.fatigueAfter != null)
              _infoLine(
                'Fatiga global',
                'de ${d.fatigueBefore!.toStringAsFixed(0)}% a '
                    '${d.fatigueAfter!.toStringAsFixed(0)}%'
                    '${d.topFatigued.isEmpty ? '' : '   (más cargados: ${d.topFatigued.map((e) => '${e.key.label} ${e.value.toStringAsFixed(0)}%').join(', ')})'}',
                valueColor: _fatigueColor(d.fatigueAfter),
              ),
            if (notes.isNotEmpty) _infoLine('Notas', notes.join(' / ')),
          ],
        ),
      ),
    );

    return widgets;
  }

  static pw.Widget _infoLine(
    String label,
    String value, {
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.TextSpan(
              text: _clean(value),
              style: pw.TextStyle(fontSize: 7.5, color: valueColor ?? _ink),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pill(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.TableRow _headerRow(List<String> labels) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: _ink),
      children: [
        for (final l in labels)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Text(
              l,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _cell(
    String value, {
    bool bold = false,
    PdfColor? color,
    double size = 7.5,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        _clean(value),
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? _ink,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Formato
  // ════════════════════════════════════════════════════════════════════════

  static String _pct(double? v) =>
      v == null ? '-' : '${(v * 100).toStringAsFixed(0)}%';

  static PdfColor _pctColor(double? v) {
    if (v == null) return _grey;
    if (v >= 0.9) return _green;
    if (v >= 0.6) return _amber;
    return _red;
  }

  static PdfColor _fatigueColor(double? v) {
    if (v == null) return _grey;
    if (v >= 70) return _red;
    if (v >= 45) return _amber;
    return _green;
  }

  static String _hours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  static String _num(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  static String _compact(double v) {
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    return NumberFormat.decimalPattern('es').format(v.round());
  }

  static String _muscleLabel(String key) {
    for (final m in Muscle.values) {
      if (m.name == key) return m.label;
    }
    return key;
  }

  static Future<Uint8List> _svgToBytes(
    String svgData, {
    int width = 240,
    int height = 420,
  }) async {
    final pictureInfo = await vg.loadPicture(SvgStringLoader(svgData), null);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final svgWidth = pictureInfo.size.width;
    final svgHeight = pictureInfo.size.height;
    if (svgWidth > 0 && svgHeight > 0) {
      canvas.scale(width / svgWidth, height / svgHeight);
    }
    canvas.drawPicture(pictureInfo.picture);
    pictureInfo.picture.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}

class _Kpi {
  final String label;
  final String value;
  final PdfColor color;
  _Kpi(this.label, this.value, this.color);
}
