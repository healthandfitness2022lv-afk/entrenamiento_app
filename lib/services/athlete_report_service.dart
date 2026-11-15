import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
// vector_graphics singleton 'vg' is re-exported by flutter_svg
import '../models/achievement.dart';
import '../models/muscle_catalog.dart';
import '../services/training_identity_service.dart';
import '../services/workout_load_service.dart';
import '../services/workout_rm_service.dart';
import '../services/planned_load_service.dart';
import '../services/workout_stats_service.dart';
import '../utils/svg_utils.dart';

// â”€â”€â”€ color palette â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kPrimary = PdfColor(0.082, 0.396, 0.753); // #1565C0 deep blue
const _kAccent = PdfColor(0.404, 0.227, 0.718); // purple
const _kGreen = PdfColor(0.18, 0.49, 0.196);
const _kOrange = PdfColor(1.0, 0.56, 0.0);
const _kRed = PdfColor(0.72, 0.11, 0.11);
const _kBg = PdfColor(0.97, 0.97, 0.98);
const _kCardBg = PdfColors.white;

PdfColor _heatColor(double v) {
  if (v < 4) return PdfColors.grey200;
  if (v < 20) return const PdfColor(0.31, 0.76, 0.97);
  if (v < 45) return _kPrimary;
  if (v < 68) return _kAccent;
  if (v < 85) return _kOrange;
  return _kRed;
}

class AthleteReportService {
  static Future<void> generate({
    required BuildContext context,
    required String athleteId,
    required String? athleteName,
    required Map<Muscle, double> heatmap,
    required DateTimeRange range,
  }) async {
    debugPrint(
      '[AthleteReportService] generate start '
      'athleteId=$athleteId '
      'athleteName=$athleteName '
      'rangeStart=${range.start.toIso8601String()} '
      'rangeEnd=${range.end.toIso8601String()} '
      'heatmapSize=${heatmap.length}',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final startTs = Timestamp.fromDate(
      DateTime(range.start.year, range.start.month, range.start.day),
    );
    final endTs = Timestamp.fromDate(
      DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59),
    );

    try {
      // â”€â”€ fonts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      debugPrint('[AthleteReportService] loading embedded PDF fonts');
      final regularFontData = await rootBundle.load(
        'assets/fonts/Montserrat-Regular.ttf',
      );
      final boldFontData = await rootBundle.load(
        'assets/fonts/Montserrat-Bold.ttf',
      );
      final font = pw.Font.ttf(regularFontData);
      final boldFont = pw.Font.ttf(boldFontData);
      final itaFont = font;
      final theme = pw.ThemeData.withFont(
        base: font,
        bold: boldFont,
        italic: itaFont,
      );

      // fetch data sequentially to avoid mixed-type Future.wait issues
      debugPrint('[AthleteReportService] fetching workout stats');
      final allSessions = await WorkoutStatsService.fetch(
        uid: athleteId,
        limit: 300,
      );

      debugPrint(
        '[AthleteReportService] querying workouts_logged in selected range',
      );
      final wSnap =
          await FirebaseFirestore.instance
              .collection('workouts_logged')
              .where('userId', isEqualTo: athleteId)
              .where('date', isGreaterThanOrEqualTo: startTs)
              .where('date', isLessThanOrEqualTo: endTs)
              .orderBy('date')
              .get();

      final achSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(athleteId)
              .collection('achievements')
              .where('unlockedAt', isGreaterThanOrEqualTo: startTs)
              .where('unlockedAt', isLessThanOrEqualTo: endTs)
              .get();

      final userSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(athleteId)
              .get();

      final previousWorkoutSnap =
          await FirebaseFirestore.instance
              .collection('workouts_logged')
              .where('userId', isEqualTo: athleteId)
              .where('date', isLessThan: startTs)
              .orderBy('date', descending: true)
              .limit(200)
              .get();

      debugPrint(
        '[AthleteReportService] fetched '
        'allSessions=${allSessions.length} '
        'workoutDocs=${wSnap.docs.length} '
        'achievementDocs=${achSnap.docs.length} '
        'previousWorkoutDocs=${previousWorkoutSnap.docs.length} '
        'userExists=${userSnap.exists}',
      );

      // filter sessions by selected range
      final rangeEnd = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
      final sessions =
          allSessions
              .where(
                (s) =>
                    !s.date.isBefore(range.start) && !s.date.isAfter(rangeEnd),
              )
              .toList();

      // only include workouts with a valid date field
      final workouts =
          wSnap.docs
              .map((d) => d.data())
              .where((d) => d['date'] != null)
              .toList();

      debugPrint(
        '[AthleteReportService] filtered '
        'sessions=${sessions.length} '
        'workoutsWithDate=${workouts.length}',
      );

      final userData = userSnap.data() ?? {};
      final name = athleteName ?? (userData['name'] as String?) ?? 'Atleta';

      // â”€â”€ achievements â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final unlocked =
          achSnap.docs
              .map((d) {
                final data = d.data();
                final achievement = achievementsCatalog.where(
                  (a) => a.id == d.id,
                );
                if (achievement.isEmpty) return null;
                final unlockedAt = data['unlockedAt'];
                return _AchievementUnlock(
                  achievement.first,
                  unlockedAt is Timestamp ? unlockedAt.toDate() : null,
                );
              })
              .whereType<_AchievementUnlock>()
              .toList()
            ..sort((a, b) {
              final ad = a.unlockedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bd = b.unlockedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bd.compareTo(ad);
            });

      // â”€â”€ KPIs within selected range â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final totalSessions = sessions.length;
      final totalVolume = sessions.fold<double>(0, (s, e) => s + e.volumeKg);
      final avgRpe =
          totalSessions > 0
              ? sessions.fold<double>(0, (s, e) => s + e.avgRpe) / totalSessions
              : 0.0;
      final avgVolume = totalSessions > 0 ? totalVolume / totalSessions : 0.0;

      // â”€â”€ RM progression â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final Map<String, List<_RMPoint>> rmMap = {};
      final Map<String, List<_RMPoint>> previousRmMap = {};
      for (final w in workouts) {
        final rawDate = w['date'];
        if (rawDate == null) continue;
        final date = (rawDate as Timestamp).toDate();
        final performed = List<Map<String, dynamic>>.from(w['performed'] ?? []);
        for (final c in WorkoutRMService.extractAllValidRMSetCandidates(
          performed,
        )) {
          final exercise = c['exercise'] as String? ?? '';
          if (exercise.isEmpty) continue;
          final key = WorkoutRMService.normalizeExerciseName(exercise);
          final weight = (c['weight'] as num?)?.toDouble() ?? 0;
          final reps = (c['reps'] as num?)?.toInt() ?? 0;
          if (weight <= 1 || reps <= 0) continue;
          final rm = WorkoutRMService.estimate1RM(weight: weight, reps: reps);
          rmMap
              .putIfAbsent(key, () => [])
              .add(
                _RMPoint(
                  label: exercise,
                  date: date,
                  rm: rm,
                  weight: weight,
                  reps: reps,
                  rpe: 0,
                ),
              );
        }
      }

      for (final w in previousWorkoutSnap.docs.map((d) => d.data())) {
        final rawDate = w['date'];
        if (rawDate == null) continue;
        final date = (rawDate as Timestamp).toDate();
        final performed = List<Map<String, dynamic>>.from(w['performed'] ?? []);
        for (final c in WorkoutRMService.extractAllValidRMSetCandidates(
          performed,
        )) {
          final exercise = c['exercise'] as String? ?? '';
          if (exercise.isEmpty) continue;
          final key = WorkoutRMService.normalizeExerciseName(exercise);
          final weight = (c['weight'] as num?)?.toDouble() ?? 0;
          final reps = (c['reps'] as num?)?.toInt() ?? 0;
          if (weight <= 1 || reps <= 0) continue;

          previousRmMap
              .putIfAbsent(key, () => [])
              .add(
                _RMPoint(
                  label: exercise,
                  date: date,
                  rm: WorkoutRMService.estimate1RM(weight: weight, reps: reps),
                  weight: weight,
                  reps: reps,
                  rpe: 0,
                ),
              );
        }
      }

      // best current 1RM per exercise (max across all time)
      final Map<String, double> bestRM = {};
      for (final e in rmMap.entries) {
        final best = e.value.map((p) => p.rm).reduce(max);
        final lastName = e.value.last.label;
        bestRM[lastName] = best;
      }
      final topLifts =
          (bestRM.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .take(6)
              .toList();

      // improvements: best 1RM before range vs best 1RM inside range
      final improvements = <Map<String, dynamic>>[];
      for (final e in rmMap.entries) {
        final currentPoints = [...e.value]
          ..sort((a, b) => a.rm.compareTo(b.rm));
        final previousPoints = previousRmMap[e.key];
        if (previousPoints == null || previousPoints.isEmpty) continue;

        final currentBest = currentPoints.last;
        final previousBest =
            ([...previousPoints]..sort((a, b) => a.rm.compareTo(b.rm))).last;
        if (previousBest.rm <= 0) continue;

        final deltaKg = currentBest.rm - previousBest.rm;
        final deltaPercent = (deltaKg / previousBest.rm) * 100;
        if (deltaPercent > 0.1) {
          improvements.add({
            'exercise': currentBest.label,
            'baseline': previousBest,
            'latest': currentBest,
            'deltaKg': deltaKg,
            'deltaPercent': deltaPercent,
          });
        }
      }
      improvements.sort(
        (a, b) => (b['deltaPercent'] as double).compareTo(
          a['deltaPercent'] as double,
        ),
      );
      final topImprovements = improvements.take(5).toList();

      final Map<Muscle, double> accumulatedMuscleLoad = {};
      for (final workout in workouts) {
        final perWorkoutLoad =
            await WorkoutLoadService.calculateLoadFromWorkout(workout);
        for (final entry in perWorkoutLoad.entries) {
          accumulatedMuscleLoad[entry.key] =
              (accumulatedMuscleLoad[entry.key] ?? 0) + entry.value;
        }
      }
      final topAccumulatedMuscles =
          Muscle.values
              .map(
                (muscle) =>
                    MapEntry(muscle, accumulatedMuscleLoad[muscle] ?? 0),
              )
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      final groupLoads = _groupLoadsFromAccumulated(accumulatedMuscleLoad);
      final exerciseTypeDistribution =
          await _computeExerciseTypeDistributionFromLogged(workouts);

      final trainingIdentity = await _buildWeeklyTrainingIdentity(
        athleteId: athleteId,
        range: range,
      );

      // â”€â”€ chart data (last 20 sessions) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final chartSessions =
          sessions.length > 20
              ? sessions.sublist(sessions.length - 20)
              : sessions;

      // â”€â”€ sorted heatmap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // â”€â”€ recent workout detail (last 8 sessions for page 3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final recentWorkouts =
          workouts.length > 18
              ? workouts.sublist(workouts.length - 18)
              : workouts;

      // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // BUILD PDF
      // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // ── render body SVGs to PNG bytes ──────────────────────────────────────
      debugPrint('[AthleteReportService] rendering body SVG heatmaps');
      final frontSvgRaw = await rootBundle.loadString(
        'assets/svg/body_front.svg',
      );
      final backSvgRaw = await rootBundle.loadString(
        'assets/svg/body_back.svg',
      );
      final frontBytes = await _svgToBytes(
        buildColoredSvg(frontSvgRaw, heatmap),
      );
      final backBytes = await _svgToBytes(buildColoredSvg(backSvgRaw, heatmap));

      final pdf = pw.Document();
      final fmt = DateFormat('dd/MM/yyyy');
      final rangeLabel =
          '${fmt.format(range.start)} - ${fmt.format(range.end)}';

      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      // PAGE 1 â€“ Overview / Profile
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          theme: theme,
          build:
              (ctx) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // â”€â”€ cover header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _coverHeader(name, rangeLabel),
                  pw.SizedBox(height: 12),

                  // â”€â”€ KPI row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _kpiCard('Sesiones', totalSessions.toString(), _kPrimary),
                      _kpiCard(
                        'Volumen Total',
                        '${_fmtNum(totalVolume, decimals: 2)} kg',
                        _kGreen,
                      ),
                      _kpiCard(
                        'Vol. Promedio',
                        '${_fmtNum(avgVolume, decimals: 2)} kg',
                        _kOrange,
                      ),
                      _kpiCard(
                        'RPE Promedio',
                        _fmtNum(avgRpe, decimals: 2),
                        _kAccent,
                      ),
                      _kpiCard(
                        'Logros',
                        '${unlocked.length}',
                        const PdfColor(0.72, 0.53, 0.04),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),

                  // â”€â”€ two-column content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // LEFT: top lifts + improvements
                      pw.Expanded(
                        flex: 6,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('MEJORES RM ESTIMADOS'),
                            pw.SizedBox(height: 6),
                            pw.Table(
                              columnWidths: {
                                0: const pw.FlexColumnWidth(5),
                                1: const pw.FlexColumnWidth(2),
                              },
                              border: pw.TableBorder.symmetric(
                                inside: const pw.BorderSide(
                                  color: PdfColors.grey200,
                                  width: 0.5,
                                ),
                              ),
                              children: [
                                pw.TableRow(
                                  decoration: const pw.BoxDecoration(
                                    color: PdfColor(0.082, 0.396, 0.753),
                                  ),
                                  children: [
                                    _th('Ejercicio', PdfColors.white),
                                    _th('1RM est.', PdfColors.white),
                                  ],
                                ),
                                ...topLifts.map(
                                  (e) => pw.TableRow(
                                    decoration: const pw.BoxDecoration(
                                      color: _kBg,
                                    ),
                                    children: [
                                      _td(e.key),
                                      _td(
                                        '${_fmtNum(e.value, decimals: 2)} kg',
                                        bold: true,
                                        color: _kPrimary,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            if (topImprovements.isNotEmpty) ...[
                              pw.SizedBox(height: 16),
                              _sectionTitle('PROGRESIÓN EN FUERZA'),
                              pw.SizedBox(height: 6),
                              pw.Table(
                                columnWidths: {
                                  0: const pw.FlexColumnWidth(4),
                                  1: const pw.FlexColumnWidth(2),
                                  2: const pw.FlexColumnWidth(2),
                                  3: const pw.FlexColumnWidth(2),
                                },
                                border: pw.TableBorder.symmetric(
                                  inside: const pw.BorderSide(
                                    color: PdfColors.grey200,
                                    width: 0.5,
                                  ),
                                ),
                                children: [
                                  pw.TableRow(
                                    decoration: const pw.BoxDecoration(
                                      color: _kBg,
                                    ),
                                    children: [
                                      _th('Ejercicio'),
                                      _th('1RM previo'),
                                      _th('1RM actual'),
                                      _th('Mejora %'),
                                    ],
                                  ),
                                  ...topImprovements.map(
                                    (e) => pw.TableRow(
                                      children: [
                                        _td(e['exercise'] as String),
                                        _rmCell(e['baseline'] as _RMPoint),
                                        _rmCell(
                                          e['latest'] as _RMPoint,
                                          highlight: true,
                                        ),
                                        _td(
                                          '+${_fmtNum((e['deltaPercent'] as double), decimals: 2)}%',
                                          bold: true,
                                          color: _kGreen,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      pw.SizedBox(width: 16),

                      // RIGHT: achievements
                      pw.Expanded(
                        flex: 5,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('PERFIL DE ENTRENAMIENTO SEMANAL'),
                            pw.SizedBox(height: 6),
                            _trainingIdentityCard(trainingIdentity),
                            pw.SizedBox(height: 8),
                            _sectionTitle(
                              'LOGROS CONSEGUIDOS EN EL RANGO (${unlocked.length})',
                            ),
                            pw.SizedBox(height: 6),
                            if (unlocked.isEmpty)
                              pw.Text(
                                'Sin logros en este periodo.',
                                style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey600,
                                ),
                              )
                            else
                              ...unlocked
                                  .take(6)
                                  .map((a) => _achievementRow(a)),
                            pw.SizedBox(height: 8),
                            _sectionTitle('CARGA POR MUSCULO'),
                            pw.SizedBox(height: 5),
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  child: pw.Image(
                                    pw.MemoryImage(frontBytes),
                                    fit: pw.BoxFit.contain,
                                  ),
                                ),
                                pw.SizedBox(width: 4),
                                pw.Expanded(
                                  child: pw.Image(
                                    pw.MemoryImage(backBytes),
                                    fit: pw.BoxFit.contain,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  _footer(ctx),
                ],
              ),
        ),
      );

      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      // PAGE 2 â€“ Charts
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      final maxVol =
          chartSessions.isEmpty
              ? 1.0
              : chartSessions.map((s) => s.volumeKg).reduce(max);
      final maxRpe = 10.0;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          theme: theme,
          build:
              (ctx) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pageHeader('ANÁLISIS DE RENDIMIENTO', name),
                  pw.SizedBox(height: 16),

                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('TONELAJE POR SESIÓN'),
                            pw.SizedBox(height: 6),
                            _barChart(
                              items: chartSessions,
                              valueOf: (s) => s.volumeKg,
                              maxValue: maxVol,
                              barColor: _kPrimary,
                              height: 68,
                              labelOf:
                                  (s) => DateFormat('dd/MM').format(s.date),
                              valueDecimals: 2,
                            ),
                            pw.SizedBox(height: 4),
                            _chartYLegend('kg', maxVol, decimals: 2),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('RPE PROMEDIO POR SESIÓN'),
                            pw.SizedBox(height: 6),
                            _barChart(
                              items: chartSessions,
                              valueOf: (s) => s.avgRpe,
                              maxValue: maxRpe,
                              barColor: _kAccent,
                              height: 68,
                              labelOf:
                                  (s) => DateFormat('dd/MM').format(s.date),
                              valueDecimals: 2,
                              zones: const [
                                _Zone(5, PdfColors.green200),
                                _Zone(7, PdfColors.yellow200),
                                _Zone(9, PdfColors.orange200),
                                _Zone(10, PdfColors.red200),
                              ],
                            ),
                            pw.SizedBox(height: 4),
                            _rpeZoneLegend(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: _distributionCard(
                          'GRUPOS ANATOMICOS',
                          groupLoads,
                          accent: _kPrimary,
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: _distributionCard(
                          'TIPOS DE EJERCICIO',
                          exerciseTypeDistribution,
                          accent: _kAccent,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 18),

                  // â”€â”€ muscle fatigue â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _sectionTitle('CARGA ACUMULADA POR MUSCULO'),
                  pw.SizedBox(height: 8),
                  if (topAccumulatedMuscles.isEmpty)
                    pw.Text(
                      'Sin carga acumulada en el periodo.',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey500,
                      ),
                    )
                  else
                    ..._buildMuscleLoadColumns(topAccumulatedMuscles),

                  pw.Spacer(),
                  _footer(ctx),
                ],
              ),
        ),
      );

      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      // PAGE 3 â€“ Workout Log Detail
      // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          theme: theme,
          header:
              (ctx) =>
                  ctx.pageNumber == 1
                      ? _sessionRibbonHeader(name, rangeLabel, unlocked.length)
                      : _minHeader(name),
          footer: (ctx) => _footer(ctx),
          build:
              (ctx) => [
                pw.SizedBox(height: 18),
                ..._buildWorkoutGrid(recentWorkouts),
                pw.SizedBox(height: 6),
                _currentFatigueHeatmapCard(
                  heatmap,
                  frontBytes: frontBytes,
                  backBytes: backBytes,
                ),
              ],
        ),
      );

      final bytes = await pdf.save();
      final fileName =
          'Informe_${name.replaceAll(' ', '_')}_'
          '${DateFormat('yyyy-MM-dd').format(range.start)}_'
          '${DateFormat('yyyy-MM-dd').format(range.end)}.pdf';

      debugPrint(
        '[AthleteReportService] pdf built bytes=${bytes.length} fileName=$fileName',
      );

      if (context.mounted) {
        Navigator.of(context).pop(); // cerrar loading
      }

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => _ReportPreviewScreen(
                  bytes: bytes,
                  fileName: fileName,
                  title: 'Informe | $rangeLabel',
                ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[AthleteReportService] ERROR: $e');
      debugPrintStack(label: '[AthleteReportService] STACK', stackTrace: st);

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e')));
      }
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // LAYOUT HELPERS
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  static pw.Widget _coverHeader(String name, String date) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(
        color: _kPrimary,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _pdfAscii('INFORME DE RENDIMIENTO'),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _pdfAscii(name.toUpperCase()),
                    style: pw.TextStyle(
                      fontSize: 13,
                      color: PdfColor(0.8, 0.9, 1.0),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    _pdfAscii('Periodo: $date'),
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColor(1, 1, 1, 0.7),
                    ),
                  ),
                ],
              ),
              pw.Container(
                width: 52,
                height: 52,
                decoration: const pw.BoxDecoration(
                  color: PdfColor(1, 1, 1, 0.24),
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Center(
                  child: pw.Text(
                    _pdfAscii(name.isNotEmpty ? name[0].toUpperCase() : 'A'),
                    style: pw.TextStyle(
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pageHeader(String title, String name) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        _pdfAscii(title),
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          color: _kPrimary,
        ),
      ),
    );
  }

  static pw.Widget _sessionRibbonHeader(
    String name,
    String date,
    int achievementCount,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _pdfAscii('REGISTRO DE SESIONES'),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _kPrimary,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            _pdfAscii('$date | $achievementCount logros'),
            style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _minHeader(String name) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(
        _pdfAscii('REGISTRO DE SESIONES'),
        style: pw.TextStyle(
          fontSize: 9.2,
          fontWeight: pw.FontWeight.bold,
          color: _kPrimary,
        ),
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _pdfAscii('Nexus Training App'),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
          ),
          pw.Text(
            _pdfAscii('Pagina ${ctx.pageNumber} de ${ctx.pagesCount}'),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
          ),
        ],
      ),
    );
  }

  static pw.Widget _kpiCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3),
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: _kCardBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(
            color: PdfColor(color.red, color.green, color.blue, 0.3),
          ),
          boxShadow: [
            pw.BoxShadow(
              color: PdfColors.grey300,
              blurRadius: 2,
              offset: const PdfPoint(0, 1),
            ),
          ],
        ),
        child: pw.Column(
          children: [
            pw.Text(
              _pdfAscii(value),
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              _pdfAscii(label),
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Row(
      children: [
        pw.Container(width: 3, height: 14, color: _kPrimary),
        pw.SizedBox(width: 6),
        pw.Text(
          _pdfAscii(text),
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _kPrimary,
          ),
        ),
      ],
    );
  }

  static pw.Widget _achievementRow(_AchievementUnlock unlocked) {
    final a = unlocked.achievement;
    final catColor = _achColor(a.category);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 2),
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 5),
      decoration: pw.BoxDecoration(
        color: PdfColor(catColor.red, catColor.green, catColor.blue, 0.07),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(
          color: PdfColor(catColor.red, catColor.green, catColor.blue, 0.25),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 8,
            height: 8,
            decoration: pw.BoxDecoration(
              color: catColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfAscii(a.title),
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _pdfAscii(a.description),
                  style: const pw.TextStyle(
                    fontSize: 6.5,
                    color: PdfColors.grey700,
                  ),
                ),
                if (unlocked.unlockedAt != null)
                  pw.Text(
                    'Desbloqueado ${DateFormat('dd/MM/yyyy').format(unlocked.unlockedAt!)}',
                    style: const pw.TextStyle(
                      fontSize: 6.5,
                      color: PdfColors.grey500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static PdfColor _achColor(AchievementCategory cat) {
    switch (cat) {
      case AchievementCategory.constancy:
        return _kGreen;
      case AchievementCategory.volume:
        return _kPrimary;
      case AchievementCategory.strength:
        return _kOrange;
      case AchievementCategory.intelligence:
        return _kAccent;
    }
  }

  // â”€â”€ bar chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _barChart({
    required List<SessionStats> items,
    required double Function(SessionStats) valueOf,
    required double maxValue,
    required PdfColor barColor,
    required double height,
    required String Function(SessionStats) labelOf,
    int valueDecimals = 0,
    List<_Zone> zones = const [],
  }) {
    if (items.isEmpty) {
      return pw.SizedBox(
        height: height,
        child: pw.Center(
          child: pw.Text(
            'Sin datos',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
        ),
      );
    }

    return pw.Container(
      height: height + 20,
      child: pw.Column(
        children: [
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children:
                  items.map((s) {
                    final v = valueOf(s).clamp(0.0, maxValue);
                    final ratio = maxValue > 0 ? v / maxValue : 0.0;
                    final barH = height * ratio;
                    final color = _zonedColor(v, zones, barColor);
                    return pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            if (items.length <= 12)
                              pw.Text(
                                v >= 1000 && valueDecimals == 0
                                    ? '${_fmtNum(v / 1000, decimals: 1)}k'
                                    : _fmtNum(v, decimals: valueDecimals),
                                style: const pw.TextStyle(
                                  fontSize: 5.5,
                                  color: PdfColors.grey600,
                                ),
                              ),
                            pw.SizedBox(height: 2),
                            pw.Container(
                              height: barH.clamp(2.0, height),
                              decoration: pw.BoxDecoration(
                                color: color,
                                borderRadius: const pw.BorderRadius.only(
                                  topLeft: pw.Radius.circular(2),
                                  topRight: pw.Radius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children:
                items
                    .map(
                      (s) => pw.Expanded(
                        child: pw.Text(
                          labelOf(s),
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(
                            fontSize: 5,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  static PdfColor _zonedColor(double v, List<_Zone> zones, PdfColor fallback) {
    for (final z in zones) {
      if (v <= z.max) return z.color;
    }
    return fallback;
  }

  static pw.Widget _chartYLegend(
    String unit,
    double maxValue, {
    int decimals = 0,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '0 $unit',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
        pw.Text(
          '${_fmtNum(maxValue / 2, decimals: decimals)} $unit',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
        pw.Text(
          '${_fmtNum(maxValue, decimals: decimals)} $unit',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
      ],
    );
  }

  static pw.Widget _rpeZoneLegend() {
    const items = [
      ('<=5 Suave', PdfColors.green400),
      ('6-7 Moderado', PdfColors.yellow600),
      ('8 Alto', PdfColors.orange400),
      ('9-10 Maximo', PdfColors.red400),
    ];
    return pw.Row(
      children:
          items
              .map(
                (t) => pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 12),
                  child: pw.Row(
                    children: [
                      pw.Container(width: 8, height: 8, color: t.$2),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        t.$1,
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }

  static pw.Widget _muscleBar(String label, double value, {double max = 100}) {
    final color = _heatColor(value);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(_pdfAscii(label), style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                _fmtNum(value, decimals: 2),
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Stack(
            children: [
              pw.Container(
                height: 6,
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(3),
                  ),
                ),
              ),
              pw.Container(
                height: 6,
                width: 200 * (value / max).clamp(0.0, 1.0),
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Kept for the alternate compact report layout.
  // ignore: unused_element
  static pw.Widget _heatmapLegend() {
    return pw.Row(
      children: [
        pw.Text(
          'Escala: ',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
        ...const [
          (PdfColor(0.31, 0.76, 0.97), '1-20'),
          (_kPrimary, '20-45'),
          (_kAccent, '45-68'),
          (_kOrange, '68-85'),
          (_kRed, '85+'),
        ].map(
          (t) => pw.Padding(
            padding: const pw.EdgeInsets.only(right: 10),
            child: pw.Row(
              children: [
                pw.Container(width: 8, height: 8, color: t.$1),
                pw.SizedBox(width: 3),
                pw.Text(
                  t.$2,
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Renders a colored SVG string to PNG bytes for embedding in PDF.
  static Future<Uint8List> _svgToBytes(
    String svgData, {
    int width = 180,
    int height = 300,
  }) async {
    final pictureInfo = await vg.loadPicture(SvgStringLoader(svgData), null);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final svgW = pictureInfo.size.width;
    final svgH = pictureInfo.size.height;
    if (svgW > 0 && svgH > 0) {
      canvas.scale(width / svgW, height / svgH);
    }
    canvas.drawPicture(pictureInfo.picture);
    pictureInfo.picture.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData!.buffer.asUint8List();
  }

  // Kept for the alternate compact report layout.
  // ignore: unused_element
  static pw.Widget _compactMuscleHeatmap(Map<Muscle, double> heatmap) {
    final entries =
        heatmap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final visible = entries.where((e) => e.value > 0).take(8).toList();

    if (visible.isEmpty) {
      return pw.Text(
        'Sin datos de carga.',
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
      );
    }

    final maxVal = visible.first.value;

    pw.Widget muscleRow(MapEntry<Muscle, double> e) {
      final color = _heatColor(e.value);
      final ratio = maxVal > 0 ? (e.value / maxVal).clamp(0.0, 1.0) : 0.0;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _pdfAscii(e.key.label),
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
                pw.Text(
                  _fmtNum(e.value, decimals: 1),
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Stack(
              children: [
                pw.Container(
                  height: 5,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(2),
                    ),
                  ),
                ),
                pw.Container(
                  height: 5,
                  width: 95 * ratio,
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final mid = (visible.length / 2).ceil();
    final left = visible.take(mid).toList();
    final right = visible.skip(mid).toList();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: left.map(muscleRow).toList(),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: right.map(muscleRow).toList(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _currentFatigueHeatmapCard(
    Map<Muscle, double> heatmap, {
    required Uint8List frontBytes,
    required Uint8List backBytes,
  }) {
    final entries =
        heatmap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final visible = entries.where((e) => e.value > 0).take(5).toList();

    return pw.Container(
      height: 118,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _kCardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Image(pw.MemoryImage(frontBytes), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Image(pw.MemoryImage(backBytes), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 6),
          pw.SizedBox(
            width: 92,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: _heatmapLegendCompact(),
                ),
                pw.SizedBox(height: 6),
                if (visible.isEmpty)
                  pw.Text(
                    'Sin fatiga.',
                    style: const pw.TextStyle(
                      fontSize: 7.2,
                      color: PdfColors.grey600,
                    ),
                  )
                else
                  ...visible.map(
                    (entry) => _fatigueHeatChip(entry.key, entry.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _fatigueHeatChip(Muscle muscle, double value) {
    final color = _heatColor(value);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red, color.green, color.blue, 0.12),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(
          color: PdfColor(color.red, color.green, color.blue, 0.35),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 7,
            height: 7,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Text(
              _pdfAscii(muscle.label),
              style: const pw.TextStyle(fontSize: 5.7),
              maxLines: 1,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Text(
            _fmtNum(value, decimals: 2),
            style: pw.TextStyle(
              fontSize: 5.7,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _heatmapLegendCompact() {
    const items = [
      (PdfColor(0.31, 0.76, 0.97), '1-20'),
      (_kPrimary, '20-45'),
      (_kAccent, '45-68'),
      (_kOrange, '68-85'),
      (_kRed, '85+'),
    ];

    return pw.Wrap(
      alignment: pw.WrapAlignment.end,
      spacing: 4,
      runSpacing: 3,
      children:
          items
              .map(
                (t) => pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(width: 6, height: 6, color: t.$1),
                    pw.SizedBox(width: 2),
                    pw.Text(
                      t.$2,
                      style: const pw.TextStyle(
                        fontSize: 5.8,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
    );
  }

  // â”€â”€ workout detail block â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Kept for the alternate detailed report layout.
  // ignore: unused_element
  static pw.Widget _workoutDetailBlock(Map<String, dynamic> w) {
    final date = (w['date'] as Timestamp).toDate();
    final sName = (w['sessionName'] as String?) ?? 'Entrenamiento';
    final durMin = (w['durationMinutes'] as int?) ?? 0;
    final performed = List<Map<String, dynamic>>.from(w['performed'] ?? []);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _kCardBg,
        border: pw.Border.all(color: PdfColors.grey200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // session header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _pdfAscii('${DateFormat('dd/MM/yyyy').format(date)} | $sName'),
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _kPrimary,
                ),
              ),
              pw.Text(
                '$durMin min',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          // blocks
          ...performed.map((block) => _blockDetail(block)),
        ],
      ),
    );
  }

  static pw.Widget _blockDetail(Map<String, dynamic> block) {
    final type = (block['type'] as String?) ?? '';

    if (type == 'Series' ||
        type == 'Series descendentes' ||
        type == 'Buscar RM') {
      final exercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? [],
      );
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _blockTag(type, _kPrimary),
          pw.SizedBox(height: 4),
          ...exercises.map((ex) {
            final exName = (ex['name'] ?? ex['exercise'] ?? '') as String;
            final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6, left: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _pdfAscii(exName),
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  _setsTable(sets),
                ],
              ),
            );
          }),
        ],
      );
    }

    if (type == 'Circuito') {
      final rounds = List<Map<String, dynamic>>.from(block['rounds'] ?? []);
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _blockTag('Circuito', _kOrange),
          pw.SizedBox(height: 4),
          ...rounds.asMap().entries.map((roundEntry) {
            final round = roundEntry.value;
            final exercises = List<Map<String, dynamic>>.from(
              round['exercises'] ?? [],
            );
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4, left: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Ronda ${roundEntry.key + 1}',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _kOrange,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  ...exercises.map((ex) {
                    final exName = (ex['exercise'] ?? '') as String;
                    final reps = (ex['reps'] as num?)?.toInt() ?? 0;
                    final weight = (ex['weight'] as num?)?.toDouble() ?? 0;
                    final rpe = (ex['rpe'] as num?)?.toDouble() ?? 0;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                      child: pw.Text(
                        _pdfAscii(
                          '$exName - ${weight > 0 ? '${_fmtNum(weight, decimals: 2)}kg x ' : ''}$reps reps | RPE ${_fmtNum(rpe, decimals: 2)}',
                        ),
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey800,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      );
    }

    if (type == 'Tabata' || type == 'EMOM') {
      final exercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? [],
      );
      final work = (block['work'] as num?)?.toInt();
      final rest = (block['rest'] as num?)?.toInt();
      final rounds = (block['rounds'] as num?)?.toInt();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _blockTag(type, _kRed),
          pw.SizedBox(height: 4),
          if (type == 'Tabata')
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 8, bottom: 4),
              child: pw.Text(
                'Trabajo ${work ?? 0}s | Descanso ${rest ?? 0}s | Rondas ${rounds ?? 0}',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8),
            child: pw.Wrap(
              spacing: 8,
              runSpacing: 4,
              children:
                  exercises.map((ex) {
                    final exName =
                        (ex['exercise'] ?? ex['name'] ?? '') as String;
                    return pw.Text(
                      _pdfAscii(exName),
                      style: const pw.TextStyle(fontSize: 7.5),
                    );
                  }).toList(),
            ),
          ),
        ],
      );
    }

    return pw.SizedBox.shrink();
  }

  static pw.Widget _blockTag(String label, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 6),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red, color.green, color.blue, 0.12),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(
          color: PdfColor(color.red, color.green, color.blue, 0.4),
        ),
      ),
      child: pw.Text(
        _pdfAscii(label),
        style: pw.TextStyle(
          fontSize: 7.5,
          color: color,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _setsTable(List<Map<String, dynamic>> sets) {
    if (sets.isEmpty) return pw.SizedBox.shrink();
    return pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(20),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(1.5),
      },
      border: pw.TableBorder.symmetric(
        inside: const pw.BorderSide(color: PdfColors.grey100, width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor(0.082, 0.396, 0.753, 0.08),
          ),
          children: [_th('#'), _th('Peso'), _th('Reps'), _th('RPE')],
        ),
        ...sets.asMap().entries.map((e) {
          final i = e.key + 1;
          final s = e.value;
          final weight = (s['weight'] as num?)?.toDouble() ?? 0;
          final reps = (s['reps'] as num?)?.toInt() ?? 0;
          final rpe = (s['rpe'] as num?)?.toDouble() ?? 0;
          return pw.TableRow(
            children: [
              _td('$i', color: PdfColors.grey500),
              _td('${weight > 0 ? _fmtNum(weight, decimals: 2) : '-'} kg'),
              _td('$reps'),
              _td(
                rpe > 0 ? _fmtNum(rpe, decimals: 2) : '-',
                bold: rpe >= 9,
                color: rpe >= 9 ? _kRed : null,
              ),
            ],
          );
        }),
      ],
    );
  }

  // â”€â”€ table helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static pw.Widget _th(String text, [PdfColor? color]) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        _pdfAscii(text),
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: color ?? PdfColors.grey700,
        ),
      ),
    );
  }

  static pw.Widget _td(String text, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(
        _pdfAscii(text),
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : null,
          color: color ?? PdfColors.grey900,
        ),
      ),
    );
  }

  static pw.Widget _rmCell(_RMPoint point, {bool highlight = false}) {
    final mainColor = highlight ? _kPrimary : PdfColors.grey900;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${_fmtNum(point.rm, decimals: 2)} kg',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: mainColor,
            ),
          ),
          pw.Text(
            _pdfAscii(DateFormat('dd/MM/yyyy').format(point.date)),
            style: const pw.TextStyle(fontSize: 6.2, color: PdfColors.grey600),
          ),
          pw.Text(
            _pdfAscii(
              '${_fmtNum(point.weight, decimals: 2)} kg x ${point.reps} reps',
            ),
            style: const pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static String _fmtNum(double v, {int decimals = 0}) {
    if (decimals <= 0) {
      return NumberFormat('#,###').format(v.round());
    }
    final pattern = '#,##0.${'#' * decimals}';
    return NumberFormat(pattern).format(v);
  }

  static pw.Widget _trainingIdentityCard(TrainingIdentityResult? result) {
    if (result == null) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _kCardBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Text(
          'No hubo suficientes datos semanales para calcular el perfil.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      );
    }

    final orderedScores =
        result.scores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final totalScore = orderedScores.fold<double>(
      0,
      (total, entry) => total + entry.value,
    );

    String relPct(double v) {
      final p = totalScore > 0 ? (v / totalScore) * 100 : 0.0;
      return '${_fmtNum(p, decimals: 0)}%';
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _kCardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Principal
          pw.Text(
            _pdfAscii(
              'Perfil principal: ${result.primaryProfile.label} (${relPct(result.scores[result.primaryProfile] ?? 0)})',
            ),
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _kPrimary,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _pdfAscii(
              'Secundario: ${result.secondaryProfile.label} (${relPct(result.scores[result.secondaryProfile] ?? 0)})',
            ),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          // Barras de todos los perfiles
          ...orderedScores.map((entry) {
            final percent =
                totalScore > 0 ? (entry.value / totalScore) * 100 : 0.0;
            final ratio = (percent / 100).clamp(0.0, 1.0);
            final isPrimary = entry.key == result.primaryProfile;
            final barColor =
                isPrimary ? const PdfColor(0.0, 0.6, 0.6) : _kPrimary;
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        _pdfAscii(entry.key.label),
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: isPrimary ? pw.FontWeight.bold : null,
                        ),
                      ),
                      pw.Text(
                        '${_fmtNum(percent, decimals: 0)}%',
                        style: pw.TextStyle(fontSize: 7, color: barColor),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 1),
                  pw.Stack(
                    children: [
                      pw.Container(
                        height: 4,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(2),
                          ),
                        ),
                      ),
                      pw.Container(
                        height: 4,
                        width: 160 * ratio,
                        decoration: pw.BoxDecoration(
                          color: barColor,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          // Biases
          if (result.biases.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Wrap(
              spacing: 4,
              runSpacing: 3,
              children:
                  result.biases
                      .take(4)
                      .map(
                        (b) => pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: pw.BoxDecoration(
                            color: PdfColor(
                              _kAccent.red,
                              _kAccent.green,
                              _kAccent.blue,
                              0.10,
                            ),
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                            border: pw.Border.all(
                              color: PdfColor(
                                _kAccent.red,
                                _kAccent.green,
                                _kAccent.blue,
                                0.3,
                              ),
                            ),
                          ),
                          child: pw.Text(
                            _pdfAscii(b),
                            style: const pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.grey800,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
          // Evidencia
          if (result.evidence.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            ...result.evidence
                .take(3)
                .map(
                  (item) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Text(
                      _pdfAscii('- $item'),
                      style: const pw.TextStyle(
                        fontSize: 6,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  static List<pw.Widget> _buildMuscleLoadColumns(
    List<MapEntry<Muscle, double>> entries,
  ) {
    final left = <MapEntry<Muscle, double>>[];
    final right = <MapEntry<Muscle, double>>[];

    final mid = (entries.length / 2).ceil();
    for (var i = 0; i < entries.length; i++) {
      if (i < mid) {
        left.add(entries[i]);
      } else {
        right.add(entries[i]);
      }
    }

    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children:
                  left.map((e) => _muscleBar(e.key.label, e.value)).toList(),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children:
                  right.map((e) => _muscleBar(e.key.label, e.value)).toList(),
            ),
          ),
        ],
      ),
    ];
  }

  static Map<String, double> _groupLoadsFromAccumulated(
    Map<Muscle, double> accumulatedMuscleLoad,
  ) {
    final result = <String, double>{};
    for (final entry in anatomicalGroups.entries) {
      final total = entry.value.fold<double>(
        0,
        (total, muscle) => total + (accumulatedMuscleLoad[muscle] ?? 0),
      );
      if (total > 0) {
        result[_pdfAscii(entry.key.name.toUpperCase())] = total;
      }
    }
    return result;
  }

  static Future<Map<String, double>> _computeExerciseTypeDistributionFromLogged(
    List<Map<String, dynamic>> workouts,
  ) async {
    final names = <String>{};
    for (final workout in workouts) {
      final performed = List<Map<String, dynamic>>.from(
        workout['performed'] ?? const [],
      );
      for (final block in performed) {
        for (final exercise in _extractLoggedExercises(block)) {
          final name = (exercise['name'] ?? '').toString().trim();
          if (name.isNotEmpty) names.add(name);
        }
      }
    }

    if (names.isEmpty) return {};

    final exerciseMap = <String, Map<String, dynamic>>{};
    final namesList = names.toList();
    for (var i = 0; i < namesList.length; i += 10) {
      final chunk = namesList.skip(i).take(10).toList();
      final snap =
          await FirebaseFirestore.instance
              .collection('exercises')
              .where('name', whereIn: chunk)
              .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          exerciseMap[name] = data;
        }
      }
    }

    final distribution = <String, double>{};
    for (final workout in workouts) {
      final performed = List<Map<String, dynamic>>.from(
        workout['performed'] ?? const [],
      );
      for (final block in performed) {
        for (final exercise in _extractLoggedExercises(block)) {
          final name = (exercise['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final exerciseData = exerciseMap[name];
          if (exerciseData == null) continue;
          final type = (exerciseData['exerciseType'] ?? 'Otro').toString();
          final baseSets = (exercise['baseSets'] as num?)?.toDouble() ?? 1.0;
          final targetReps =
              (exercise['repsEquivalent'] as num?)?.toDouble() ??
              (exercise['targetReps'] as num?)?.toDouble() ??
              1.0;
          final perSideMultiplier = exercise['perSide'] == true ? 2.0 : 1.0;
          final referenceWeight =
              (exercise['referenceWeight'] as num?)?.toDouble() ?? 0.0;
          final load =
              (referenceWeight > 0 ? referenceWeight : 1.0) *
              (targetReps > 0 ? targetReps : 1.0) *
              baseSets *
              perSideMultiplier;
          distribution[type] = (distribution[type] ?? 0) + load;
        }
      }
    }

    return distribution;
  }

  static pw.Widget _distributionCard(
    String title,
    Map<String, double> data, {
    required PdfColor accent,
  }) {
    final sorted =
        data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<double>(
      0,
      (accumulated, entry) => accumulated + entry.value,
    );
    final items = sorted.take(6).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _kCardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(
          color: PdfColor(accent.red, accent.green, accent.blue, 0.25),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _pdfAscii(title),
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
          pw.SizedBox(height: 8),
          if (items.isEmpty)
            pw.Text(
              'Sin datos',
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey600,
              ),
            )
          else
            ...items.map((entry) {
              final percent = total > 0 ? (entry.value / total) * 100 : 0.0;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            _pdfAscii(entry.key),
                            style: const pw.TextStyle(fontSize: 7),
                            maxLines: 1,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Text(
                          '${_fmtNum(percent, decimals: 2)}%',
                          style: const pw.TextStyle(
                            fontSize: 7,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Container(
                      height: 5,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey200,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(3),
                        ),
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          width: 120 * (percent / 100).clamp(0.0, 1.0),
                          decoration: pw.BoxDecoration(
                            color: accent,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // Kept for the alternate report header.
  // ignore: unused_element
  static pw.Widget _metricPill(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red, color.green, color.blue, 0.10),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
        border: pw.Border.all(
          color: PdfColor(color.red, color.green, color.blue, 0.20),
        ),
      ),
      child: pw.Text(
        _pdfAscii(text),
        style: pw.TextStyle(
          fontSize: 6.1,
          color: color,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static List<pw.Widget> _buildWorkoutGrid(
    List<Map<String, dynamic>> workouts,
  ) {
    return [
      pw.Wrap(
        spacing: 6,
        runSpacing: 6,
        children:
            workouts
                .map(
                  (workout) => pw.SizedBox(
                    width: 171,
                    child: _workoutCompactCard(workout),
                  ),
                )
                .toList(),
      ),
    ];
  }

  static pw.Widget _workoutCompactCard(Map<String, dynamic> w) {
    final date = (w['date'] as Timestamp).toDate();
    final sessionName =
        (w['sessionName'] ?? w['routineName'] ?? 'Entrenamiento') as String;
    final performed = List<Map<String, dynamic>>.from(w['performed'] ?? []);
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _kCardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: PdfColors.grey300),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColor(0, 0, 0, 0.04),
            blurRadius: 2,
            offset: const PdfPoint(0, 1),
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: PdfColor(0.082, 0.396, 0.753, 0.08),
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(12),
                topRight: pw.Radius.circular(12),
              ),
            ),
            child: pw.Text(
              _pdfAscii(sessionName),
              style: pw.TextStyle(
                fontSize: 6.8,
                fontWeight: pw.FontWeight.bold,
                color: _kPrimary,
              ),
              maxLines: 2,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfAscii(DateFormat('dd/MM/yyyy').format(date)),
                  style: const pw.TextStyle(
                    fontSize: 5.6,
                    color: PdfColors.grey600,
                  ),
                ),
                if (performed.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  ..._performedWorkoutPdfView(performed),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Kept for the alternate session-summary layout.
  // ignore: unused_element
  static (double, double) _sessionMetrics(
    List<Map<String, dynamic>> performed,
  ) {
    double volume = 0;
    double rpeSum = 0;
    int rpeCount = 0;

    for (final block in performed) {
      final type = (block['type'] as String?) ?? '';

      if (type == 'Series' ||
          type == 'Series descendentes' ||
          type == 'Buscar RM') {
        for (final ex in List<Map<String, dynamic>>.from(
          block['exercises'] ?? [],
        )) {
          final perSideFactor = ex['perSide'] == true ? 2.0 : 1.0;
          for (final set in List<Map<String, dynamic>>.from(ex['sets'] ?? [])) {
            final reps = (set['reps'] as num?)?.toInt() ?? 0;
            final weight =
                ((set['weight'] as num?)?.toDouble() ?? 0) *
                ((set['perSide'] == true) ? 2.0 : perSideFactor);
            final rpe = (set['rpe'] as num?)?.toDouble();
            volume += reps * weight;
            if (rpe != null && rpe > 0) {
              rpeSum += rpe;
              rpeCount++;
            }
          }
        }
      } else if (type == 'Circuito') {
        for (final round in List<Map<String, dynamic>>.from(
          block['rounds'] ?? [],
        )) {
          for (final ex in List<Map<String, dynamic>>.from(
            round['exercises'] ?? [],
          )) {
            final reps = (ex['reps'] as num?)?.toInt() ?? 0;
            final weight =
                ((ex['weight'] as num?)?.toDouble() ?? 0) *
                (ex['perSide'] == true ? 2.0 : 1.0);
            final rpe = (ex['rpe'] as num?)?.toDouble();
            volume += reps * weight;
            if (rpe != null && rpe > 0) {
              rpeSum += rpe;
              rpeCount++;
            }
          }
        }
      }
    }

    return (volume, rpeCount > 0 ? rpeSum / rpeCount : 0.0);
  }

  static List<pw.Widget> _performedWorkoutPdfView(
    List<Map<String, dynamic>> performed,
  ) {
    final children = <pw.Widget>[];

    for (final p in performed) {
      final type = (p['type'] ?? 'Series').toString();
      var blockTitle = (p['blockTitle']?.toString() ?? '').trim();

      if (blockTitle.isEmpty ||
          blockTitle == 'Series' ||
          blockTitle == 'Circuito' ||
          blockTitle == 'Tabata') {
        blockTitle = type;
      }

      if (type == 'Circuito') {
        final rounds = List<Map<String, dynamic>>.from(p['rounds'] ?? []);
        blockTitle = '$blockTitle | ${rounds.length} rondas';
      } else if (type == 'Tabata') {
        blockTitle =
            '$blockTitle | ${p['work'] ?? 0}/${p['rest'] ?? 0} | ${p['rounds'] ?? 0} rondas';
      }

      children.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: 3, top: children.isEmpty ? 0 : 4),
          child: pw.Text(
            _pdfAscii(blockTitle.toUpperCase()),
            style: pw.TextStyle(
              fontSize: 6.1,
              fontWeight: pw.FontWeight.bold,
              color: _kPrimary,
            ),
          ),
        ),
      );

      if (type == 'Circuito') {
        children.add(_circuitBlockPdfView(p));
      } else if (type == 'Tabata') {
        children.add(_tabataBlockPdfView(p));
      } else if (type == 'Series descendentes') {
        children.add(_descendingSeriesBlockPdfView(p));
      } else if (type == 'Series' || type == 'Buscar RM') {
        final exercises = List<Map<String, dynamic>>.from(p['exercises'] ?? []);
        for (final ex in exercises) {
          children.add(_seriesExercisePdfRow(ex, type));
        }
      }
    }

    return children;
  }

  static pw.Widget _seriesExercisePdfRow(
    Map<String, dynamic> p,
    String blockType,
  ) {
    final name = (p['exercise'] ?? p['name'] ?? 'Ejercicio').toString();
    final sets = List<Map<String, dynamic>>.from(p['sets'] ?? []);
    if (sets.isEmpty) return pw.SizedBox.shrink();

    final perSide =
        (p['perSide'] == true) || sets.any((s) => s['perSide'] == true);
    final sideMultiplier = perSide ? 2 : 1;

    double totalWeight = 0;
    for (final s in sets) {
      final reps = (s['reps'] as num?)?.toInt() ?? 0;
      final weight = (s['weight'] as num?)?.toDouble() ?? 0;
      totalWeight += reps * weight * sideMultiplier;
    }

    final sideLabel = perSide ? ' | por lado x2' : '';
    var headerText = '$name$sideLabel | ${totalWeight.toStringAsFixed(0)} kg';
    if (blockType == 'Series descendentes') {
      headerText =
          '$name (Descendentes)$sideLabel | ${totalWeight.toStringAsFixed(0)} kg';
    } else if (blockType == 'Buscar RM') {
      headerText =
          '$name (RM)$sideLabel | ${totalWeight.toStringAsFixed(0)} kg';
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _pdfAscii(headerText),
            style: pw.TextStyle(fontSize: 6.1, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 0.5),
          ...List.generate(sets.length, (i) {
            final s = sets[i];
            final reps = s['reps'] ?? '-';
            final weight = s['weight'] ?? 0;
            final rpe = s['rpe'] ?? '-';
            var lineText = '| ${i + 1}: $reps reps | $weight kg | RPE $rpe';
            if (blockType == 'Series descendentes') {
              lineText =
                  '| Escalon ${i + 1}: $reps reps | $weight kg | RPE $rpe';
            } else if (blockType == 'Buscar RM') {
              lineText =
                  '| Intento ${i + 1}: $reps reps | $weight kg | RPE $rpe';
            }
            return pw.Text(
              _pdfAscii(lineText),
              style: const pw.TextStyle(
                fontSize: 5.6,
                color: PdfColors.grey700,
              ),
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _circuitBlockPdfView(Map<String, dynamic> p) {
    final rounds = List<Map<String, dynamic>>.from(p['rounds'] ?? []);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children:
          rounds.map((round) {
            final exercises = List<Map<String, dynamic>>.from(
              round['exercises'] ?? [],
            );
            double roundTotal = 0;

            for (final e in exercises) {
              final reps = (e['reps'] as num?)?.toInt() ?? 0;
              final weight = (e['weight'] as num?)?.toDouble() ?? 0;
              roundTotal += reps * weight * (e['perSide'] == true ? 2 : 1);
            }

            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _pdfAscii(
                      'Ronda ${round['round'] ?? ''} | ${roundTotal.toStringAsFixed(0)} kg',
                    ),
                    style: pw.TextStyle(
                      fontSize: 5.9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  ...exercises.map((e) {
                    final name = (e['exercise'] ?? '').toString();
                    final sideText = e['perSide'] == true ? ' | por lado' : '';
                    return pw.Text(
                      _pdfAscii(
                        '| $name$sideText | ${e['reps'] ?? '-'} reps | ${e['weight'] ?? 0} kg | RPE ${e['rpe'] ?? '-'}',
                      ),
                      style: const pw.TextStyle(
                        fontSize: 5.6,
                        color: PdfColors.grey700,
                      ),
                    );
                  }),
                ],
              ),
            );
          }).toList(),
    );
  }

  static pw.Widget _tabataBlockPdfView(Map<String, dynamic> p) {
    final exercises = List<Map<String, dynamic>>.from(p['exercises'] ?? []);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _pdfAscii(
            'Trabajo ${p['work'] ?? 0}s | Descanso ${p['rest'] ?? 0}s | ${p['rounds'] ?? 0} rondas',
          ),
          style: const pw.TextStyle(fontSize: 5.6, color: PdfColors.grey700),
        ),
        ...exercises.map(
          (e) => pw.Text(
            _pdfAscii('| ${(e['exercise'] ?? e['name'] ?? '').toString()}'),
            style: const pw.TextStyle(fontSize: 5.6, color: PdfColors.grey700),
          ),
        ),
      ],
    );
  }

  static pw.Widget _descendingSeriesBlockPdfView(Map<String, dynamic> p) {
    final exercises = List<Map<String, dynamic>>.from(p['exercises'] ?? []);
    if (exercises.isEmpty) return pw.SizedBox.shrink();

    var maxSets = 0;
    for (final ex in exercises) {
      final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
      if (sets.length > maxSets) maxSets = sets.length;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: List.generate(maxSets, (i) {
        int? roundReps;
        for (final ex in exercises) {
          final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
          if (i < sets.length) {
            roundReps = (sets[i]['reps'] as num?)?.toInt();
            if ((roundReps ?? 0) > 0) break;
          }
        }

        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _pdfAscii('${roundReps ?? '-'} reps'),
                style: pw.TextStyle(
                  fontSize: 5.9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              ...exercises.map((ex) {
                final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
                if (i >= sets.length) return pw.SizedBox.shrink();
                final s = sets[i];
                final name = (ex['exercise'] ?? 'Ejercicio').toString();
                final perSide = ex['perSide'] == true || s['perSide'] == true;
                final sideLabel = perSide ? ' | por lado' : '';
                return pw.Text(
                  _pdfAscii(
                    '| $name$sideLabel | ${s['weight'] ?? 0} kg | RPE ${s['rpe'] ?? '-'}',
                  ),
                  style: const pw.TextStyle(
                    fontSize: 5.6,
                    color: PdfColors.grey700,
                  ),
                );
              }),
            ],
          ),
        );
      }),
    );
  }

  static Future<TrainingIdentityResult?> _buildWeeklyTrainingIdentity({
    required String athleteId,
    required DateTimeRange range,
  }) async {
    DateTime startOfWeek(DateTime date) {
      final day = DateTime(date.year, date.month, date.day);
      return day.subtract(Duration(days: day.weekday - 1));
    }

    String normalizeExerciseName(dynamic raw) {
      if (raw == null) return '';
      if (raw is String) return raw.trim();
      if (raw is List && raw.isNotEmpty) return raw.first.toString().trim();
      return raw.toString().trim();
    }

    bool shouldUseHistorical1RM(String exerciseType) {
      final normalized = _normalizeIdentityText(exerciseType);
      return normalized.contains('fuerza') ||
          normalized.contains('hipertrofia') ||
          normalized.contains('weightlifting') ||
          normalized.contains('potencia');
    }

    double? computePercent1RM({
      required double? referenceWeight,
      required double? historical1RM,
    }) {
      if (referenceWeight == null ||
          historical1RM == null ||
          referenceWeight <= 0 ||
          historical1RM <= 0) {
        return null;
      }
      return referenceWeight / historical1RM;
    }

    String percent1RMBucket(double? percent1RM) {
      if (percent1RM == null || percent1RM <= 0) return 'unknown';
      if (percent1RM < 0.55) return '<55%';
      if (percent1RM < 0.60) return '55-60%';
      if (percent1RM < 0.65) return '60-65%';
      if (percent1RM < 0.70) return '65-70%';
      if (percent1RM < 0.75) return '70-75%';
      if (percent1RM < 0.80) return '75-80%';
      if (percent1RM < 0.85) return '80-85%';
      if (percent1RM < 0.90) return '85-90%';
      return '90%+';
    }

    double resolveIdentityBaseSets({
      required String rawType,
      required int rounds,
      required Map<String, dynamic> block,
      required Map<String, dynamic> exercise,
    }) {
      if (rawType == 'circuito' || rawType == 'tabata' || rawType == 'emom') {
        return rounds.toDouble();
      }
      if (rawType == 'series descendentes' && block['schema'] is List) {
        return (block['schema'] as List).length.toDouble();
      }
      return (exercise['series'] as num?)?.toDouble() ?? 1.0;
    }

    double resolveIdentityTargetReps({
      required String rawType,
      required Map<String, dynamic> block,
      required Map<String, dynamic> exercise,
      required TrainingIntentFamily family,
    }) {
      final valueType =
          (exercise['valueType'] ?? '').toString().toLowerCase().trim();
      final reps = (exercise['reps'] as num?)?.toDouble();
      final value = (exercise['value'] as num?)?.toDouble();

      if (rawType == 'series descendentes' && block['schema'] is List) {
        final schemaValues =
            (block['schema'] as List)
                .whereType<num>()
                .map((item) => item.toDouble())
                .where((item) => item > 0)
                .toList();
        if (schemaValues.isNotEmpty) {
          return schemaValues.reduce((a, b) => a + b) / schemaValues.length;
        }
      }

      if (reps != null && reps > 0) return reps;
      if (valueType == 'reps' && value != null && value > 0) return value;
      if (valueType == 'time' && value != null && value > 0) return value;

      final work = (block['work'] as num?)?.toDouble();
      if (rawType == 'tabata' && work != null && work > 0) return work;

      switch (family) {
        case TrainingIntentFamily.athleticPower:
          return 3;
        case TrainingIntentFamily.strength:
          return 5;
        case TrainingIntentFamily.hypertrophy:
        case TrainingIntentFamily.isolatedHypertrophy:
        case TrainingIntentFamily.accessory:
          return 10;
        case TrainingIntentFamily.bodyweight:
          return 8;
        case TrainingIntentFamily.stability:
          return 12;
        case TrainingIntentFamily.conditioning:
          return 20;
        case TrainingIntentFamily.unknown:
          return 8;
      }
    }

    double resolveIdentityRepsEquivalent({
      required String rawType,
      required Map<String, dynamic> block,
      required Map<String, dynamic> exercise,
      required double targetReps,
      required TrainingIntentFamily family,
    }) {
      final valueType =
          (exercise['valueType'] ?? '').toString().toLowerCase().trim();

      if (valueType == 'time') {
        return TrainingIdentityService.timeRepsEquivalent(targetReps, family);
      }
      if (rawType == 'tabata') {
        final work = (block['work'] as num?)?.toDouble() ?? targetReps;
        return (work / 5).clamp(1.0, 30.0);
      }
      if (targetReps > 0) return targetReps;

      switch (family) {
        case TrainingIntentFamily.athleticPower:
          return 3;
        case TrainingIntentFamily.strength:
          return 5;
        case TrainingIntentFamily.hypertrophy:
        case TrainingIntentFamily.isolatedHypertrophy:
        case TrainingIntentFamily.accessory:
          return 10;
        case TrainingIntentFamily.bodyweight:
          return 8;
        case TrainingIntentFamily.stability:
          return 12;
        case TrainingIntentFamily.conditioning:
          return 20;
        case TrainingIntentFamily.unknown:
          return 8;
      }
    }

    double? extractPlannedReferenceWeight(Map<String, dynamic> exercise) {
      final sets = List<Map<String, dynamic>>.from(
        exercise['sets'] ?? const [],
      );
      for (final set in sets) {
        final weight = (set['weight'] as num?)?.toDouble();
        if ((weight ?? 0) > 0) return weight;
      }
      return (exercise['weight'] as num?)?.toDouble();
    }

    List<Map<String, dynamic>> buildPlannedIdentitySets({
      required String rawType,
      required int rounds,
      required Map<String, dynamic> block,
      required Map<String, dynamic> exercise,
      required double fallbackTargetReps,
      required double fallbackRepsEquivalent,
    }) {
      final out = <Map<String, dynamic>>[];
      final sets = List<Map<String, dynamic>>.from(
        exercise['sets'] ?? const [],
      );

      if (sets.isNotEmpty) {
        // En circuito/tabata/EMOM las series resueltas describen UNA ronda: se
        // repiten por cada ronda del bloque (antes un circuito de 3 rondas
        // contaba 1 serie planificada contra 3 realizadas).
        final isRoundBased =
            rawType == 'circuito' || rawType == 'tabata' || rawType == 'emom';
        final count =
            isRoundBased && rounds > sets.length ? rounds : sets.length;
        // Por tiempo: `reps` son segundos; se usa la equivalencia seg/5 ya
        // calculada en el fallback (igual que lo realizado).
        final isTime = exercise['valueType']?.toString() == 'time';
        for (int i = 0; i < count; i++) {
          final set = sets[i < sets.length ? i : sets.length - 1];
          final reps = (set['reps'] as num?)?.toDouble() ?? fallbackTargetReps;
          final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
          final perSide = set['perSide'] == true || exercise['perSide'] == true;
          out.add({
            'targetReps': reps,
            'repsEquivalent':
                isTime
                    ? fallbackRepsEquivalent
                    : (reps > 0 ? reps : fallbackRepsEquivalent),
            'referenceWeight': weight,
            'perSide': perSide,
            'setLabel': isRoundBased ? 'Ronda ${i + 1}' : 'Serie ${i + 1}',
          });
        }
        return out;
      }

      final totalSets = resolveIdentityBaseSets(
        rawType: rawType,
        rounds: rounds,
        block: block,
        exercise: exercise,
      ).round().clamp(1, 100);
      final directWeight = extractPlannedReferenceWeight(exercise) ?? 0.0;
      final perSide = exercise['perSide'] == true;
      String prefix = 'Serie';
      if (rawType == 'tabata') {
        prefix = 'Tabata';
      } else if (rawType == 'circuito' || rawType == 'emom') {
        prefix = 'Ronda';
      }

      for (int i = 0; i < totalSets; i++) {
        out.add({
          'targetReps': fallbackTargetReps,
          'repsEquivalent': fallbackRepsEquivalent,
          'referenceWeight': directWeight,
          'perSide': perSide,
          'setLabel': '$prefix ${i + 1}',
        });
      }
      return out;
    }

    Map<String, double> buildHistorical1RMByExercise(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) {
      final out = <String, double>{};
      for (final doc in docs) {
        final performed = List<Map<String, dynamic>>.from(
          doc.data()['performed'] ?? const [],
        );
        for (final candidate in WorkoutRMService.extractAllValidRMSetCandidates(
          performed,
        )) {
          final exercise = (candidate['exercise'] as String?) ?? '';
          final weight = (candidate['weight'] as num?)?.toDouble() ?? 0.0;
          final reps = (candidate['reps'] as num?)?.toInt() ?? 0;
          if (exercise.isEmpty || weight <= 1 || reps <= 0) continue;
          final key = WorkoutRMService.normalizeExerciseName(exercise);
          final rm = WorkoutRMService.estimate1RM(weight: weight, reps: reps);
          if (rm > (out[key] ?? 0)) {
            out[key] = rm;
          }
        }
      }
      return out;
    }

    final totalLoad = <String, double>{};
    final exerciseTypeLoad = <String, double>{};
    final blockTypeLoad = <String, double>{};
    final intentFamilyLoad = <TrainingIntentFamily, double>{};
    final repRangeLoad = <String, double>{};
    double trackedRmLoad = 0;
    double bilateralLoad = 0;
    double unilateralLoad = 0;
    double freeLoad = 0;
    double guidedLoad = 0;
    double bodyweightLoad = 0;
    double compoundLoad = 0;
    double isolationLoad = 0;
    final identityExercises = <TrainingIdentityExerciseContribution>[];

    void addIdentityExercise({
      required DateTime date,
      required String source,
      required String setLabel,
      required String name,
      required String blockTitle,
      required String exerciseType,
      required String structureType,
      required Map<Muscle, double> weights,
      required double baseSets,
      required double targetReps,
      required double repsEquivalent,
      required double perSideMultiplier,
      required double factor,
      required double structFactor,
      required TrainingIntentFamily family,
      required String repBucket,
      required double? referenceWeight,
      required double? historical1RM,
      required double? percent1RM,
      required String percent1RMBucketValue,
      required bool trackRm,
      required bool unilateral,
      required bool freeWeight,
      required bool guided,
      required bool bodyweight,
      required bool compound,
      required bool isolation,
      String equipmentDescriptor = '',
      String trainingDiscipline = '',
      String movementIntent = '',
    }) {
      final normalizedRepFactor =
          (repsEquivalent <= 0 ? 1.0 : repsEquivalent / 10.0);
      final volumeUnits = baseSets * normalizedRepFactor * perSideMultiplier;
      double exerciseAccumulatedLoad = 0;
      final muscleLoads = <String, double>{};

      for (final entry in weights.entries) {
        final load = volumeUnits * entry.value * factor * structFactor;
        exerciseAccumulatedLoad += load;
        muscleLoads[entry.key.name] = load;
        totalLoad[entry.key.name] = (totalLoad[entry.key.name] ?? 0) + load;
      }

      if (exerciseAccumulatedLoad <= 0) return;

      exerciseTypeLoad[exerciseType] =
          (exerciseTypeLoad[exerciseType] ?? 0) + exerciseAccumulatedLoad;
      intentFamilyLoad[family] =
          (intentFamilyLoad[family] ?? 0) + exerciseAccumulatedLoad;
      repRangeLoad[repBucket] =
          (repRangeLoad[repBucket] ?? 0) + exerciseAccumulatedLoad;
      if (trackRm) trackedRmLoad += exerciseAccumulatedLoad;
      if (compound) compoundLoad += exerciseAccumulatedLoad;
      if (isolation) isolationLoad += exerciseAccumulatedLoad;
      if (freeWeight) freeLoad += exerciseAccumulatedLoad;
      if (guided) guidedLoad += exerciseAccumulatedLoad;
      if (bodyweight) bodyweightLoad += exerciseAccumulatedLoad;
      if (unilateral) {
        unilateralLoad += exerciseAccumulatedLoad;
      } else {
        bilateralLoad += exerciseAccumulatedLoad;
      }

      identityExercises.add(
        TrainingIdentityExerciseContribution(
          source: source,
          setLabel: setLabel,
          date: date,
          name: name,
          blockTitle: blockTitle,
          exerciseType: exerciseType,
          blockType: structureType,
          load: exerciseAccumulatedLoad,
          baseSets: baseSets,
          targetReps: targetReps,
          repsEquivalent: repsEquivalent,
          volumeUnits: volumeUnits,
          perSideMultiplier: perSideMultiplier,
          exerciseFactor: factor,
          structureFactor: structFactor,
          referenceWeight: referenceWeight,
          historical1RM: historical1RM,
          percent1RM: percent1RM,
          percent1RMBucket: percent1RMBucketValue,
          trackRm: trackRm,
          unilateral: unilateral,
          freeWeight: freeWeight,
          guided: guided,
          bodyweight: bodyweight,
          equipmentDescriptor: equipmentDescriptor,
          compound: compound,
          isolation: isolation,
          family: family,
          repBucket: repBucket,
          muscleLoads: muscleLoads,
          trainingDiscipline: trainingDiscipline,
          movementIntent: movementIntent,
        ),
      );
    }

    final weekStart = startOfWeek(range.start);
    final weekEndExclusive = weekStart.add(const Duration(days: 7));

    final dynamicFactors = await WorkoutLoadService.fetchExerciseFolders();

    final exercisesSnapshot =
        await FirebaseFirestore.instance.collection('exercises').get();
    final exerciseMap = <String, Map<String, dynamic>>{};
    for (final doc in exercisesSnapshot.docs) {
      final data = doc.data();
      final movementName = (data['name'] ?? '').toString().trim();
      if (movementName.isEmpty) continue;
      final baseData = <String, dynamic>{
        ...data,
        'hasIsUnilateralField': data.containsKey('isUnilateral'),
      };
      exerciseMap[WorkoutRMService.normalizeExerciseName(movementName)] =
          baseData;

      final rawVariants = data['variants'];
      if (rawVariants is! List) continue;
      for (final rawVariant in rawVariants.whereType<Map>()) {
        final variant = Map<String, dynamic>.from(rawVariant);
        final label = (variant['label'] ?? 'Original').toString().trim();
        final displayName =
            label.toLowerCase() == 'original'
                ? movementName
                : '$movementName - $label';
        final overrides = Map<String, dynamic>.from(
          variant['muscleWeightOverrides'] ?? const {},
        );
        exerciseMap[WorkoutRMService.normalizeExerciseName(displayName)] = {
          ...baseData,
          if (overrides.isNotEmpty) 'muscleWeights': overrides,
          'trackRM': variant['trackRM'] == true,
          'equipment': List<String>.from(
            variant['equipment'] ?? data['equipment'] ?? const [],
          ),
          'resistanceType':
              (variant['resistanceType'] ?? data['resistanceType'] ?? '')
                  .toString(),
          'isUnilateral': variant['isUnilateral'] == true,
          'hasIsUnilateralField': variant.containsKey('isUnilateral'),
        };
      }
    }

    final plannedSnapshot =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: athleteId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(weekEndExclusive))
            .get();

    final loggedSnapshot =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart),
            )
            .where('date', isLessThan: Timestamp.fromDate(weekEndExclusive))
            .get();

    final allLoggedSnapshot =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: athleteId)
            .get();

    final historical1RMByExercise = buildHistorical1RMByExercise(
      allLoggedSnapshot.docs,
    );

    final completedDates =
        loggedSnapshot.docs
            .map((doc) => (doc.data()['date'] as Timestamp?)?.toDate())
            .whereType<DateTime>()
            .map((date) => DateTime(date.year, date.month, date.day))
            .toSet();

    final blockIds =
        plannedSnapshot.docs
            .map((doc) => doc.data()['blockId'] as String?)
            .whereType<String>()
            .toSet()
            .toList();

    final blocksCache = <String, Map<String, dynamic>>{};
    if (blockIds.isNotEmpty) {
      final blockDocs = await Future.wait(
        blockIds.map(
          (id) => FirebaseFirestore.instance.collection('blocks').doc(id).get(),
        ),
      );
      for (var i = 0; i < blockIds.length; i++) {
        if (blockDocs[i].exists) {
          blocksCache[blockIds[i]] = blockDocs[i].data()!;
        }
      }
    }

    for (final doc in plannedSnapshot.docs) {
      final data = {...doc.data(), 'id': doc.id};
      final blockId = data['blockId'] as String?;
      if (blockId == null) continue;

      final workoutDate = (data['date'] as Timestamp?)?.toDate();
      if (workoutDate == null) continue;
      final normalizedDate = DateTime(
        workoutDate.year,
        workoutDate.month,
        workoutDate.day,
      );
      if (completedDates.contains(normalizedDate)) continue;

      final baseBlock = blocksCache[blockId];
      if (baseBlock == null) continue;
      final block = PlannedLoadService.resolveBlock(
        block: baseBlock,
        planned: data,
      );

      final rawType = _normalizeIdentityText(
        (block['type'] ?? 'normal').toString(),
      );
      final rounds =
          (rawType == 'circuito' || rawType == 'tabata' || rawType == 'emom')
              ? (block['rounds'] as num?)?.toInt() ?? 1
              : 1;
      final structureType = _normalizeBlockType(
        (block['type'] ?? '').toString(),
      );
      double blockLoad = 0;

      final exercises = List<Map<String, dynamic>>.from(
        block['exercises'] ?? const [],
      );
      for (final exercise in exercises) {
        final name = normalizeExerciseName(
          exercise['exercise'] ?? exercise['name'],
        );
        if (name.isEmpty) continue;
        final exerciseData =
            exerciseMap[WorkoutRMService.normalizeExerciseName(name)];
        if (exerciseData == null) continue;

        final weights = _resolveIdentityMuscleLoads(exerciseData);
        final exerciseType =
            (exerciseData['exerciseType'] ?? 'Otro').toString();
        final family = TrainingIdentityService.mapExerciseTypeToIntentFamily(
          exerciseType,
        );
        final resistanceType = _normalizeIdentityText(
          (exerciseData['resistanceType'] ?? '').toString(),
        );
        final movementClass = _normalizeIdentityText(
          (exerciseData['movementClass'] ?? '').toString(),
        );
        final hasExplicitResistance = resistanceType.isNotEmpty;
        final hasExplicitMovementClass = movementClass.isNotEmpty;
        final hasExplicitUnilateral =
            exerciseData['hasIsUnilateralField'] == true;
        final explicitCatalogUnilateral = exerciseData['isUnilateral'] == true;
        // El bloque planificado guarda un snapshot propio de la variante
        // elegida (equipment/trainingDiscipline/movementIntent), distinto
        // del documento base del catálogo — ej. "Clean & Jerk" con
        // variante "Mancuernas" trae equipment: "Mancuernas" y
        // trainingDiscipline: "balistico" en el propio ejercicio del
        // bloque, aunque el catálogo base diga "halterofilia". Ese
        // snapshot tiene prioridad; si falta, se cae al catálogo.
        final snapshotEquipment =
            (exercise['equipment'] ?? '').toString().trim();
        final equipmentDescriptor =
            '$name $exerciseType $snapshotEquipment ${(exerciseData['equipment'] as List? ?? const []).join(' ')}';
        final snapshotTrainingDiscipline =
            (exercise['trainingDiscipline'] ?? '').toString().trim();
        final snapshotMovementIntent =
            (exercise['movementIntent'] ?? '').toString().trim();
        final explicitPerSide = exercise['perSide'] == true;
        final inferredCatalogUnilateral =
            TrainingIdentityService.isUnilateralExercise(
              name: name,
              type: exerciseType,
            );
        final inferredUnilateral =
            hasExplicitUnilateral
                ? explicitCatalogUnilateral
                : explicitPerSide ||
                    explicitCatalogUnilateral ||
                    inferredCatalogUnilateral;
        final inferredBodyweight =
            hasExplicitResistance
                ? (resistanceType == 'bodyweight' ||
                    resistanceType == 'peso corporal')
                : TrainingIdentityService.isBodyweightType(equipmentDescriptor);
        final inferredGuided =
            hasExplicitResistance
                ? (resistanceType == 'guided' || resistanceType == 'guiado')
                : TrainingIdentityService.isGuidedType(equipmentDescriptor);
        final inferredFree =
            hasExplicitResistance
                ? (resistanceType == 'free' || resistanceType == 'libre')
                : !inferredBodyweight &&
                    TrainingIdentityService.isFreeType(equipmentDescriptor);
        final inferredCompound =
            hasExplicitMovementClass
                ? (movementClass == 'compound' || movementClass == 'compuesto')
                : TrainingIdentityService.isCompoundExercise(
                  family: family,
                  muscleCount: weights.length,
                  type: exerciseType,
                );
        final inferredIsolation =
            hasExplicitMovementClass
                ? (movementClass == 'isolation' || movementClass == 'aislado')
                : !inferredCompound &&
                    TrainingIdentityService.isIsolationExercise(
                      family: family,
                      muscleCount: weights.length,
                      type: exerciseType,
                    );

        final targetReps = resolveIdentityTargetReps(
          rawType: rawType,
          block: block,
          exercise: exercise,
          family: family,
        );
        final repsEquivalent = resolveIdentityRepsEquivalent(
          rawType: rawType,
          block: block,
          exercise: exercise,
          targetReps: targetReps,
          family: family,
        );
        final plannedSets = buildPlannedIdentitySets(
          rawType: rawType,
          rounds: rounds,
          block: block,
          exercise: exercise,
          fallbackTargetReps: targetReps,
          fallbackRepsEquivalent: repsEquivalent,
        );
        final historical1RM =
            shouldUseHistorical1RM(exerciseType)
                ? historical1RMByExercise[WorkoutRMService.normalizeExerciseName(
                  name,
                )]
                : null;

        for (final plannedSet in plannedSets) {
          final setTargetReps =
              (plannedSet['targetReps'] as num?)?.toDouble() ?? targetReps;
          final setRepsEquivalent =
              (plannedSet['repsEquivalent'] as num?)?.toDouble() ??
              repsEquivalent;
          final setPerSide = plannedSet['perSide'] == true;
          final perSideMultiplier = setPerSide ? 2.0 : 1.0;
          final referenceWeight =
              (plannedSet['referenceWeight'] as num?)?.toDouble();
          final percent1RM = computePercent1RM(
            referenceWeight: referenceWeight,
            historical1RM: historical1RM,
          );
          final repBucket = TrainingIdentityService.repBucketFor(
            blockType: structureType,
            targetReps: setTargetReps,
            family: family,
          );

          final before = identityExercises.length;
          addIdentityExercise(
            date: normalizedDate,
            source: 'planned',
            setLabel: (plannedSet['setLabel'] ?? 'Serie').toString(),
            name: name,
            blockTitle:
                (block['title'] ?? block['type'] ?? 'Bloque').toString(),
            exerciseType: exerciseType,
            structureType: structureType,
            weights: weights,
            baseSets: 1.0,
            targetReps: setTargetReps,
            repsEquivalent: setRepsEquivalent,
            perSideMultiplier: perSideMultiplier,
            factor: dynamicFactors[exerciseType] ?? 1.0,
            structFactor: WorkoutLoadService.structureFactor(structureType),
            family: family,
            repBucket: repBucket,
            referenceWeight: referenceWeight,
            historical1RM: historical1RM,
            percent1RM: percent1RM,
            percent1RMBucketValue: percent1RMBucket(percent1RM),
            trackRm: exerciseData['trackRM'] == true,
            unilateral: inferredUnilateral,
            freeWeight: inferredFree,
            guided: inferredGuided,
            bodyweight: inferredBodyweight,
            equipmentDescriptor: equipmentDescriptor,
            compound: inferredCompound,
            isolation: inferredIsolation,
            trainingDiscipline: snapshotTrainingDiscipline,
            movementIntent: snapshotMovementIntent,
          );
          if (identityExercises.length > before) {
            blockLoad += identityExercises.last.load;
          }
        }
      }

      blockTypeLoad[structureType] =
          (blockTypeLoad[structureType] ?? 0) + blockLoad;
    }

    for (final doc in loggedSnapshot.docs) {
      final workout = doc.data();
      final workoutDate = (workout['date'] as Timestamp?)?.toDate();
      if (workoutDate == null) continue;
      final normalizedDate = DateTime(
        workoutDate.year,
        workoutDate.month,
        workoutDate.day,
      );
      final performed = List<Map<String, dynamic>>.from(
        workout['performed'] ?? const [],
      );

      for (final rawBlock in performed) {
        final block = Map<String, dynamic>.from(rawBlock);
        final structureType = _normalizeBlockType(
          (block['type'] ?? '').toString(),
        );
        double blockLoad = 0;

        for (final exercise in _extractLoggedExercises(block)) {
          final name = normalizeExerciseName(exercise['name']);
          if (name.isEmpty) continue;
          final exerciseData =
              exerciseMap[WorkoutRMService.normalizeExerciseName(name)];
          if (exerciseData == null) continue;

          final weights = _resolveIdentityMuscleLoads(exerciseData);
          final exerciseType =
              (exerciseData['exerciseType'] ?? 'Otro').toString();
          final family = TrainingIdentityService.mapExerciseTypeToIntentFamily(
            exerciseType,
          );
          final resistanceType = _normalizeIdentityText(
            (exerciseData['resistanceType'] ?? '').toString(),
          );
          final movementClass = _normalizeIdentityText(
            (exerciseData['movementClass'] ?? '').toString(),
          );
          final hasExplicitResistance = resistanceType.isNotEmpty;
          final hasExplicitMovementClass = movementClass.isNotEmpty;
          final hasExplicitUnilateral =
              exerciseData['hasIsUnilateralField'] == true;
          final explicitCatalogUnilateral =
              exerciseData['isUnilateral'] == true;
          // Ídem que en el bloque "planned": el ejercicio logueado trae su
          // propio snapshot de variante (equipment/trainingDiscipline)
          // distinto del catálogo base — tiene prioridad para clasificar.
          final snapshotEquipment =
              (exercise['equipment'] ?? '').toString().trim();
          final equipmentDescriptor =
              '$name $exerciseType $snapshotEquipment ${(exerciseData['equipment'] as List? ?? const []).join(' ')}';
          final snapshotTrainingDiscipline =
              (exercise['trainingDiscipline'] ?? '').toString().trim();
          final snapshotMovementIntent =
              (exercise['movementIntent'] ?? '').toString().trim();
          final explicitPerSide = exercise['perSide'] == true;
          final inferredCatalogUnilateral =
              TrainingIdentityService.isUnilateralExercise(
                name: name,
                type: exerciseType,
              );
          final inferredUnilateral =
              hasExplicitUnilateral
                  ? explicitCatalogUnilateral
                  : explicitPerSide ||
                      explicitCatalogUnilateral ||
                      inferredCatalogUnilateral;
          final inferredBodyweight =
              hasExplicitResistance
                  ? (resistanceType == 'bodyweight' ||
                      resistanceType == 'peso corporal')
                  : TrainingIdentityService.isBodyweightType(
                    equipmentDescriptor,
                  );
          final inferredGuided =
              hasExplicitResistance
                  ? (resistanceType == 'guided' || resistanceType == 'guiado')
                  : TrainingIdentityService.isGuidedType(equipmentDescriptor);
          final inferredFree =
              hasExplicitResistance
                  ? (resistanceType == 'free' || resistanceType == 'libre')
                  : !inferredBodyweight &&
                      TrainingIdentityService.isFreeType(equipmentDescriptor);
          final inferredCompound =
              hasExplicitMovementClass
                  ? (movementClass == 'compound' ||
                      movementClass == 'compuesto')
                  : TrainingIdentityService.isCompoundExercise(
                    family: family,
                    muscleCount: weights.length,
                    type: exerciseType,
                  );
          final inferredIsolation =
              hasExplicitMovementClass
                  ? (movementClass == 'isolation' || movementClass == 'aislado')
                  : !inferredCompound &&
                      TrainingIdentityService.isIsolationExercise(
                        family: family,
                        muscleCount: weights.length,
                        type: exerciseType,
                      );

          final targetReps =
              (exercise['targetReps'] as num?)?.toDouble() ?? 0.0;
          final repsEquivalent =
              exercise['valueType']?.toString() == 'time'
                  ? TrainingIdentityService.timeRepsEquivalent(
                    targetReps,
                    family,
                  )
                  : (exercise['repsEquivalent'] as num?)?.toDouble() ??
                      targetReps;
          final perSideMultiplier = explicitPerSide ? 2.0 : 1.0;
          final referenceWeight =
              (exercise['referenceWeight'] as num?)?.toDouble();
          final historical1RM =
              shouldUseHistorical1RM(exerciseType)
                  ? historical1RMByExercise[WorkoutRMService.normalizeExerciseName(
                    name,
                  )]
                  : null;
          final percent1RM = computePercent1RM(
            referenceWeight: referenceWeight,
            historical1RM: historical1RM,
          );
          final repBucket = TrainingIdentityService.repBucketFor(
            blockType: structureType,
            targetReps: targetReps,
            family: family,
          );

          final before = identityExercises.length;
          addIdentityExercise(
            date: normalizedDate,
            source: 'logged',
            setLabel: (exercise['setLabel'] ?? 'Serie').toString(),
            name: name,
            blockTitle:
                (block['title'] ?? block['type'] ?? 'Entrenamiento realizado')
                    .toString(),
            exerciseType: exerciseType,
            structureType: structureType,
            weights: weights,
            baseSets: (exercise['baseSets'] as num?)?.toDouble() ?? 1.0,
            targetReps: targetReps,
            repsEquivalent: repsEquivalent,
            perSideMultiplier: perSideMultiplier,
            factor: dynamicFactors[exerciseType] ?? 1.0,
            structFactor: WorkoutLoadService.structureFactor(structureType),
            family: family,
            repBucket: repBucket,
            referenceWeight: referenceWeight,
            historical1RM: historical1RM,
            percent1RM: percent1RM,
            percent1RMBucketValue: percent1RMBucket(percent1RM),
            trackRm: exerciseData['trackRM'] == true,
            unilateral: inferredUnilateral,
            freeWeight: inferredFree,
            guided: inferredGuided,
            bodyweight: inferredBodyweight,
            equipmentDescriptor: equipmentDescriptor,
            compound: inferredCompound,
            isolation: inferredIsolation,
            trainingDiscipline: snapshotTrainingDiscipline,
            movementIntent: snapshotMovementIntent,
          );
          if (identityExercises.length > before) {
            blockLoad += identityExercises.last.load;
          }
        }

        blockTypeLoad[structureType] =
            (blockTypeLoad[structureType] ?? 0) + blockLoad;
      }
    }

    if (identityExercises.isEmpty) return null;

    return TrainingIdentityService.analyze(
      TrainingIdentityInput(
        totalLoad: totalLoad,
        exerciseTypeLoad: exerciseTypeLoad,
        blockTypeLoad: blockTypeLoad,
        intentFamilyLoad: intentFamilyLoad,
        repRangeLoad: repRangeLoad,
        trackedRmLoad: trackedRmLoad,
        bilateralLoad: bilateralLoad,
        unilateralLoad: unilateralLoad,
        freeLoad: freeLoad,
        guidedLoad: guidedLoad,
        bodyweightLoad: bodyweightLoad,
        compoundLoad: compoundLoad,
        isolationLoad: isolationLoad,
        exercises: identityExercises,
      ),
    );
  }

  // Kept for reports generated from an already loaded workout collection.
  // ignore: unused_element
  static Future<TrainingIdentityResult?> _buildTrainingIdentity({
    required String athleteId,
    required List<Map<String, dynamic>> workouts,
  }) async {
    if (workouts.isEmpty) return null;

    final exerciseNames = <String>{};
    for (final workout in workouts) {
      final performed = List<Map<String, dynamic>>.from(
        workout['performed'] ?? const [],
      );
      for (final block in performed) {
        for (final exercise in _extractLoggedExercises(block)) {
          final name = (exercise['name'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            exerciseNames.add(name);
          }
        }
      }
    }

    if (exerciseNames.isEmpty) return null;

    final exerciseMap = <String, Map<String, dynamic>>{};
    final names = exerciseNames.toList();
    for (var i = 0; i < names.length; i += 10) {
      final chunk = names.skip(i).take(10).toList();
      final snap =
          await FirebaseFirestore.instance
              .collection('exercises')
              .where('name', whereIn: chunk)
              .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          exerciseMap[name] = data;
        }
      }
    }

    if (exerciseMap.isEmpty) return null;

    final totalLoad = <String, double>{};
    final exerciseTypeLoad = <String, double>{};
    final blockTypeLoad = <String, double>{};
    final intentFamilyLoad = <TrainingIntentFamily, double>{};
    final repRangeLoad = <String, double>{};
    double trackedRmLoad = 0;
    double bilateralLoad = 0;
    double unilateralLoad = 0;
    double freeLoad = 0;
    double guidedLoad = 0;
    double bodyweightLoad = 0;
    double compoundLoad = 0;
    double isolationLoad = 0;
    final identityExercises = <TrainingIdentityExerciseContribution>[];

    for (final workout in workouts) {
      final dateValue = workout['date'];
      final date = dateValue is Timestamp ? dateValue.toDate() : DateTime.now();
      final performed = List<Map<String, dynamic>>.from(
        workout['performed'] ?? const [],
      );

      for (final rawBlock in performed) {
        final block = Map<String, dynamic>.from(rawBlock);
        final blockType = _normalizeBlockType((block['type'] ?? '').toString());
        double blockLoad = 0;

        for (final exercise in _extractLoggedExercises(block)) {
          final name = (exercise['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final exerciseData = exerciseMap[name];
          if (exerciseData == null) continue;

          final weights = _resolveIdentityMuscleLoads(exerciseData);
          final exerciseType =
              (exerciseData['exerciseType'] ?? 'Otro').toString();
          // El snapshot logueado (equipment/trainingDiscipline de la
          // variante real ejecutada) tiene prioridad sobre el catálogo
          // base, que solo conoce el movimiento genérico.
          final snapshotEquipment =
              (exercise['equipment'] ?? '').toString().trim();
          final snapshotTrainingDiscipline =
              (exercise['trainingDiscipline'] ?? '').toString().trim();
          final snapshotMovementIntent =
              (exercise['movementIntent'] ?? '').toString().trim();
          final equipment = <String>[
            if (snapshotEquipment.isNotEmpty) snapshotEquipment,
            ...List<String>.from(exerciseData['equipment'] ?? const []),
          ];
          final family = TrainingIdentityService.mapExerciseTypeToIntentFamily(
            exerciseType,
          );
          final targetReps =
              (exercise['targetReps'] as num?)?.toDouble() ?? 0.0;
          final repsEquivalent =
              exercise['valueType']?.toString() == 'time'
                  ? TrainingIdentityService.timeRepsEquivalent(
                    targetReps,
                    family,
                  )
                  : (exercise['repsEquivalent'] as num?)?.toDouble() ??
                      targetReps;
          final baseSets = (exercise['baseSets'] as num?)?.toDouble() ?? 1.0;
          final perSide = exercise['perSide'] == true;
          final perSideMultiplier = perSide ? 2.0 : 1.0;
          final referenceWeight =
              (exercise['referenceWeight'] as num?)?.toDouble() ?? 0.0;
          final load =
              (referenceWeight > 0 ? referenceWeight : 1.0) *
              (repsEquivalent > 0 ? repsEquivalent : 1.0) *
              baseSets *
              perSideMultiplier;
          if (load <= 0) continue;

          final repBucket = TrainingIdentityService.repBucketFor(
            blockType: blockType,
            targetReps: targetReps,
            family: family,
          );
          final freeWeight = equipment.any(TrainingIdentityService.isFreeType);
          final guided = equipment.any(TrainingIdentityService.isGuidedType);
          final bodyweight = equipment.any((item) {
            final normalized = _normalizeIdentityText(item);
            return normalized.contains('peso corporal') ||
                normalized.contains('bodyweight');
          });
          final unilateral =
              perSide ||
              TrainingIdentityService.isUnilateralExercise(
                name: name,
                type: exerciseType,
              );
          final compound = TrainingIdentityService.isCompoundExercise(
            family: family,
            muscleCount: weights.length,
            type: exerciseType,
          );
          final isolation = TrainingIdentityService.isIsolationExercise(
            family: family,
            muscleCount: weights.length,
            type: exerciseType,
          );

          exerciseTypeLoad[exerciseType] =
              (exerciseTypeLoad[exerciseType] ?? 0) + load;
          intentFamilyLoad[family] = (intentFamilyLoad[family] ?? 0) + load;
          repRangeLoad[repBucket] = (repRangeLoad[repBucket] ?? 0) + load;
          blockLoad += load;

          if (exerciseData['trackRM'] == true) trackedRmLoad += load;
          if (unilateral) {
            unilateralLoad += load;
          } else {
            bilateralLoad += load;
          }
          if (freeWeight) freeLoad += load;
          if (guided) guidedLoad += load;
          if (bodyweight) bodyweightLoad += load;
          if (compound) compoundLoad += load;
          if (isolation) isolationLoad += load;

          final muscleLoads = <String, double>{};
          for (final entry in weights.entries) {
            final muscleLoad = load * entry.value;
            muscleLoads[entry.key.name] = muscleLoad;
            totalLoad[entry.key.name] =
                (totalLoad[entry.key.name] ?? 0) + muscleLoad;
          }

          identityExercises.add(
            TrainingIdentityExerciseContribution(
              source: 'logged',
              setLabel: (exercise['setLabel'] ?? 'Serie').toString(),
              date: date,
              name: name,
              blockTitle:
                  (block['title'] ?? block['type'] ?? 'Entrenamiento')
                      .toString(),
              exerciseType: exerciseType,
              blockType: blockType,
              load: load,
              baseSets: baseSets,
              targetReps: targetReps,
              repsEquivalent: repsEquivalent,
              volumeUnits:
                  baseSets *
                  (repsEquivalent > 0 ? repsEquivalent : 1.0) *
                  perSideMultiplier,
              perSideMultiplier: perSideMultiplier,
              exerciseFactor: 1.0,
              structureFactor: 1.0,
              referenceWeight: referenceWeight,
              historical1RM: null,
              percent1RM: null,
              percent1RMBucket: 'unknown',
              trackRm: exerciseData['trackRM'] == true,
              unilateral: unilateral,
              freeWeight: freeWeight,
              guided: guided,
              bodyweight: bodyweight,
              equipmentDescriptor: equipment.join(' '),
              compound: compound,
              isolation: isolation,
              trainingDiscipline: snapshotTrainingDiscipline,
              movementIntent: snapshotMovementIntent,
              family: family,
              repBucket: repBucket,
              muscleLoads: muscleLoads,
            ),
          );
        }

        blockTypeLoad[blockType] = (blockTypeLoad[blockType] ?? 0) + blockLoad;
      }
    }

    if (identityExercises.isEmpty) return null;

    return TrainingIdentityService.analyze(
      TrainingIdentityInput(
        totalLoad: totalLoad,
        exerciseTypeLoad: exerciseTypeLoad,
        blockTypeLoad: blockTypeLoad,
        intentFamilyLoad: intentFamilyLoad,
        repRangeLoad: repRangeLoad,
        trackedRmLoad: trackedRmLoad,
        bilateralLoad: bilateralLoad,
        unilateralLoad: unilateralLoad,
        freeLoad: freeLoad,
        guidedLoad: guidedLoad,
        bodyweightLoad: bodyweightLoad,
        compoundLoad: compoundLoad,
        isolationLoad: isolationLoad,
        exercises: identityExercises,
      ),
    );
  }

  static List<Map<String, dynamic>> _extractLoggedExercises(
    Map<String, dynamic> block,
  ) {
    final type = _normalizeIdentityText((block['type'] ?? '').toString());

    if (type == 'series' ||
        type == 'series descendentes' ||
        type == 'buscar rm') {
      final out = <Map<String, dynamic>>[];
      for (final rawExercise in List<Map<String, dynamic>>.from(
        block['exercises'] ?? const [],
      )) {
        final name = rawExercise['exercise'] ?? rawExercise['name'];
        final sets = List<Map<String, dynamic>>.from(rawExercise['sets'] ?? []);

        if (sets.isEmpty) {
          final reps = (rawExercise['reps'] as num?)?.toDouble() ?? 0.0;
          out.add({
            'name': name,
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent': reps,
            'referenceWeight':
                (rawExercise['weight'] as num?)?.toDouble() ?? 0.0,
            'perSide': rawExercise['perSide'] == true,
            'setLabel': 'Serie 1',
            'equipment': rawExercise['equipment'],
            'trainingDiscipline': rawExercise['trainingDiscipline'],
            'movementIntent': rawExercise['movementIntent'],
          });
          continue;
        }

        // Por tiempo: `reps` son segundos (misma equivalencia que la
        // revisión semanal: seg/5, tope 30).
        final isTime = rawExercise['valueType']?.toString() == 'time';
        for (var i = 0; i < sets.length; i++) {
          final set = sets[i];
          final reps = (set['reps'] as num?)?.toDouble() ?? 0.0;
          out.add({
            'name': name,
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent': isTime ? (reps / 5).clamp(1.0, 30.0) : reps,
            if (isTime) 'valueType': 'time',
            'referenceWeight': (set['weight'] as num?)?.toDouble() ?? 0.0,
            'perSide': set['perSide'] == true || rawExercise['perSide'] == true,
            'setLabel': 'Serie ${i + 1}',
            'equipment': rawExercise['equipment'],
            'trainingDiscipline': rawExercise['trainingDiscipline'],
            'movementIntent': rawExercise['movementIntent'],
          });
        }
      }
      return out;
    }

    if (type == 'circuito' || type == 'emom') {
      final out = <Map<String, dynamic>>[];
      var roundIndex = 0;
      for (final round in List<Map<String, dynamic>>.from(
        block['rounds'] ?? const [],
      )) {
        roundIndex += 1;
        for (final rawExercise in List<Map<String, dynamic>>.from(
          round['exercises'] ?? const [],
        )) {
          final reps = (rawExercise['reps'] as num?)?.toDouble() ?? 0.0;
          out.add({
            'name': rawExercise['exercise'] ?? rawExercise['name'],
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent':
                rawExercise['valueType']?.toString() == 'time'
                    ? (reps / 5).clamp(1.0, 30.0)
                    : (reps <= 0 ? 10.0 : reps),
            'referenceWeight':
                (rawExercise['weight'] as num?)?.toDouble() ?? 0.0,
            'perSide': rawExercise['perSide'] == true,
            'setLabel': 'Ronda $roundIndex',
            'equipment': rawExercise['equipment'],
            'trainingDiscipline': rawExercise['trainingDiscipline'],
            'movementIntent': rawExercise['movementIntent'],
          });
        }
      }
      return out;
    }

    if (type == 'tabata') {
      final rounds = (block['rounds'] as num?)?.toInt() ?? 1;
      final work = (block['work'] as num?)?.toDouble() ?? 20.0;
      final out = <Map<String, dynamic>>[];
      for (final rawExercise in List<Map<String, dynamic>>.from(
        block['exercises'] ?? const [],
      )) {
        final reps = (rawExercise['reps'] as num?)?.toDouble() ?? 0.0;
        for (var i = 0; i < rounds; i++) {
          out.add({
            'name': rawExercise['exercise'] ?? rawExercise['name'],
            'baseSets': 1.0,
            'targetReps': reps,
            'repsEquivalent': reps > 0 ? reps : (work / 5).clamp(1.0, 30.0),
            'referenceWeight':
                (rawExercise['weight'] as num?)?.toDouble() ?? 0.0,
            'perSide': rawExercise['perSide'] == true,
            'setLabel': 'Tabata ${i + 1}',
            'equipment': rawExercise['equipment'],
            'trainingDiscipline': rawExercise['trainingDiscipline'],
            'movementIntent': rawExercise['movementIntent'],
          });
        }
      }
      return out;
    }

    return const [];
  }

  static Map<Muscle, double> _resolveIdentityMuscleLoads(
    Map<String, dynamic> exerciseData,
  ) {
    final result = <Muscle, double>{};
    final raw = exerciseData['muscleWeights'];

    if (raw is Map && raw.isNotEmpty) {
      raw.forEach((key, value) {
        final normalizedKey =
            key.toString() == 'traps' ? 'trapsUpper' : key.toString();
        final matches = Muscle.values.where(
          (muscle) => muscle.name == normalizedKey,
        );
        final numericValue = (value as num?)?.toDouble() ?? 0.0;
        if (matches.isNotEmpty && numericValue > 0) {
          result[matches.first] = numericValue;
        }
      });
      if (result.isNotEmpty) return result;
    }

    final muscleNames = <String>[
      (exerciseData['primaryMuscle'] ?? '').toString(),
      ...List<String>.from(exerciseData['secondaryMuscles'] ?? const []),
    ];

    for (final name in muscleNames) {
      final mapping = normalizedMuscleCatalogMap[normalizeKey(name)];
      if (mapping == null) continue;
      for (final entry in mapping.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
    }

    return result;
  }

  static String _normalizeBlockType(String raw) {
    final normalized = _normalizeIdentityText(raw);
    if (normalized == 'series' ||
        normalized == 'series descendentes' ||
        normalized == 'buscar rm') {
      return raw.trim().isEmpty ? 'Series' : raw.trim();
    }
    if (normalized == 'circuito') return 'Circuito';
    if (normalized == 'tabata') return 'Tabata';
    if (normalized == 'emom') return 'EMOM';
    return raw.trim().isEmpty ? 'Series' : raw.trim();
  }

  static String _normalizeIdentityText(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('Ã¡', 'a')
        .replaceAll('Ã©', 'e')
        .replaceAll('Ã­', 'i')
        .replaceAll('Ã³', 'o')
        .replaceAll('Ãº', 'u')
        .replaceAll('Ã¼', 'u')
        .replaceAll('Ã±', 'n');
  }

  static String _pdfAscii(String text) {
    return text
        .replaceAll("â€“", "-")
        .replaceAll("â€”", "-")
        .replaceAll("â‰¤", "<=")
        .replaceAll("Ã—", "x")
        .replaceAll("Â·", "|")
        .replaceAll("Ã¡", "a")
        .replaceAll("Ã©", "e")
        .replaceAll("Ã­", "i")
        .replaceAll("Ã³", "o")
        .replaceAll("Ãº", "u")
        .replaceAll("Ã", "A")
        .replaceAll("Ã‰", "E")
        .replaceAll("Ã", "I")
        .replaceAll("Ã“", "O")
        .replaceAll("Ãš", "U")
        .replaceAll("Ã±", "n")
        .replaceAll("Ã‘", "N")
        .replaceAll("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“", "-")
        .replaceAll("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â", "-")
        .replaceAll("ÃƒÂ¢Ã¢â‚¬Â°Ã‚Â¤", "<=")
        .replaceAll("ÃƒÆ’Ã¢â‚¬â€", "x")
        .replaceAll("Ãƒâ€šÃ‚Â·", "|")
        .replaceAll("ÃƒÆ’Ã‚Â¡", "a")
        .replaceAll("ÃƒÆ’Ã‚Â©", "e")
        .replaceAll("ÃƒÆ’Ã‚Â­", "i")
        .replaceAll("ÃƒÆ’Ã‚Â³", "o")
        .replaceAll("ÃƒÆ’Ã‚Âº", "u")
        .replaceAll("ÃƒÆ’Ã‚Â", "A")
        .replaceAll("ÃƒÆ’Ã¢â‚¬Â°", "E")
        .replaceAll("ÃƒÆ’Ã‚Â", "I")
        .replaceAll("ÃƒÆ’Ã¢â‚¬Å“", "O")
        .replaceAll("ÃƒÆ’Ã…Â¡", "U")
        .replaceAll("ÃƒÆ’Ã‚Â±", "n")
        .replaceAll("ÃƒÆ’Ã¢â‚¬Ëœ", "N")
        .replaceAll("Ã¢â‚¬â€œ", "-")
        .replaceAll("Ã¢â‚¬â€", "-")
        .replaceAll("Ã¢â€°Â¤", "<=")
        .replaceAll("Ãƒâ€”", "x")
        .replaceAll("Ã‚Â·", "|")
        .replaceAll("ÃƒÂ¡", "a")
        .replaceAll("ÃƒÂ©", "e")
        .replaceAll("ÃƒÂ­", "i")
        .replaceAll("ÃƒÂ³", "o")
        .replaceAll("ÃƒÂº", "u")
        .replaceAll("ÃƒÂ", "A")
        .replaceAll("Ãƒâ€°", "E")
        .replaceAll("ÃƒÂ", "I")
        .replaceAll("Ãƒâ€œ", "O")
        .replaceAll("ÃƒÅ¡", "U")
        .replaceAll("ÃƒÂ±", "n")
        .replaceAll("Ãƒâ€˜", "N")
        .replaceAll("Ã¡", "a")
        .replaceAll("Ã©", "e")
        .replaceAll("Ã­", "i")
        .replaceAll("Ã³", "o")
        .replaceAll("Ãº", "u")
        .replaceAll("Ã", "A")
        .replaceAll("Ã‰", "E")
        .replaceAll("Ã", "I")
        .replaceAll("Ã“", "O")
        .replaceAll("Ãš", "U")
        .replaceAll("Ã±", "n")
        .replaceAll("Ã‘", "N");
  }
}

// â”€â”€â”€ preview screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ReportPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;
  final String title;

  const _ReportPreviewScreen({
    required this.bytes,
    required this.fileName,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Compartir / Enviar',
            onPressed:
                () => Printing.sharePdf(bytes: bytes, filename: fileName),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Descargar',
            onPressed: () => _saveToDisk(context),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        allowPrinting: false,
        allowSharing: false,
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: fileName,
        scrollViewDecoration: BoxDecoration(color: Colors.grey.shade200),
        previewPageMargin: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 20,
        ),
      ),
    );
  }

  Future<void> _saveToDisk(BuildContext context) async {
    try {
      Directory dir;
      if (Platform.isAndroid || Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        dir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Guardado en: ${file.path}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }
}

// â”€â”€â”€ helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _RMPoint {
  final String label;
  final DateTime date;
  final double rm;
  final double weight;
  final int reps;
  final double rpe;
  const _RMPoint({
    required this.label,
    required this.date,
    required this.rm,
    required this.weight,
    required this.reps,
    required this.rpe,
  });
}

class _AchievementUnlock {
  final Achievement achievement;
  final DateTime? unlockedAt;

  const _AchievementUnlock(this.achievement, this.unlockedAt);
}

class _Zone {
  final double max;
  final PdfColor color;
  const _Zone(this.max, this.color);
}
