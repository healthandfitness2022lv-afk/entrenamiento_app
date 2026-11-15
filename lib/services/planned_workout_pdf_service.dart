import 'workout_rm_service.dart';
import 'dart:ui' as ui;

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/muscle_catalog.dart';
import '../utils/block_title_utils.dart';
import '../utils/exercise_name_utils.dart';
import '../utils/svg_utils.dart';
import 'planned_load_service.dart';

class PlannedWorkoutPdfService {
  static final PdfColor _nexusInk = PdfColor.fromHex('#0B1220');
  static final PdfColor _nexusBlue = PdfColor.fromHex('#2563EB');
  static final PdfColor _nexusPurple = PdfColor.fromHex('#7C3AED');
  static final PdfColor _nexusLime = PdfColor.fromHex('#8CFF24');
  static final PdfColor _nexusSurface = PdfColor.fromHex('#F6F8FC');

  static Future<void> exportBytes({
    required Uint8List bytes,
    required String athleteName,
    required DateTimeRange range,
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'Plan_${athleteName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}_${DateFormat('yyyyMMdd').format(range.start)}.pdf',
    );
  }

  static Future<void> generate({
    required String athleteName,
    required DateTimeRange range,
    required Map<DateTime, List<Map<String, dynamic>>> days,
    required Map<String, double> muscleDistribution,
    required Map<DateTime, double> dailyLoad,
    required Map<String, dynamic> summary,
  }) async {
    final bytes = await buildBytes(
      athleteName: athleteName,
      range: range,
      days: days,
      muscleDistribution: muscleDistribution,
      dailyLoad: dailyLoad,
      summary: summary,
    );
    await exportBytes(bytes: bytes, athleteName: athleteName, range: range);
  }

  static int pageCountFor(
    Map<DateTime, List<Map<String, dynamic>>> days, {
    Set<String> progressionVariants = const {},
  }) {
    final strengthExerciseCount =
        _strengthExerciseCards(days, progressionVariants).length;
    return 1 + ((strengthExerciseCount + 1) ~/ 2) + ((days.length + 4) ~/ 5);
  }

  static Future<Uint8List> buildBytes({
    required String athleteName,
    required DateTimeRange range,
    required Map<DateTime, List<Map<String, dynamic>>> days,
    required Map<String, double> muscleDistribution,
    required Map<DateTime, double> dailyLoad,
    required Map<String, dynamic> summary,
    Set<String> progressionVariants = const {},
  }) async {
    final pdf = pw.Document();
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Montserrat-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Montserrat-Bold.ttf'),
    );
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final dateFormat = DateFormat('EEEE dd/MM/yyyy', 'es');
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/logo/logo.png')).buffer.asUint8List(),
    );
    final heatmap = _muscleHeatmap(muscleDistribution);
    final frontBody = pw.MemoryImage(
      await _svgToBytes(
        buildColoredSvg(
          await rootBundle.loadString('assets/svg/body_front.svg'),
          heatmap,
        ),
      ),
    );
    final backBody = pw.MemoryImage(
      await _svgToBytes(
        buildColoredSvg(
          await rootBundle.loadString('assets/svg/body_back.svg'),
          heatmap,
        ),
      ),
    );

    final strengthCards = _strengthExerciseCards(days, progressionVariants);
    final dayEntries =
        days.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final projectedPages =
        1 + ((strengthCards.length + 1) ~/ 2) + ((dayEntries.length + 4) ~/ 5);
    if (projectedPages > 20) {
      throw StateError(
        'El reporte requiere $projectedPages páginas; el máximo permitido es 20.',
      );
    }
    // La rutina va primero y agrupa una semana laboral por página.
    for (var index = 0; index < dayEntries.length; index += 5) {
      final chunk = dayEntries.sublist(
        index,
        (index + 5).clamp(0, dayEntries.length),
      );
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: theme,
          margin: const pw.EdgeInsets.all(20),
          build:
              (context) => _pageFrame(
                context: context,
                athleteName: athleteName,
                section: 'Rutina diaria',
                logo: logo,
                child: _compactDayGrid(Map.fromEntries(chunk), dateFormat),
              ),
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(24),
        build:
            (context) => _pageFrame(
              context: context,
              athleteName: athleteName,
              section: 'Resumen mensual',
              logo: logo,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  _summarySection(summary),
                  pw.SizedBox(height: 10),
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Expanded(
                          flex: 11,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              _sectionCard(
                                title: 'Carga planificada',
                                subtitle: 'Volumen total estimado por día',
                                accent: _nexusBlue,
                                child: _dailyChart(dailyLoad),
                              ),
                              pw.SizedBox(height: 8),
                              pw.Expanded(
                                child: _sectionCard(
                                  title: 'Distribución muscular',
                                  subtitle:
                                      'Porcentaje del estímulo planificado',
                                  accent: _nexusPurple,
                                  child: _muscleChart(muscleDistribution),
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          flex: 9,
                          child: _bodyHeatmapPanel(
                            frontBody: frontBody,
                            backBody: backBody,
                            distribution: muscleDistribution,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );

    for (var index = 0; index < strengthCards.length; index += 2) {
      final chunk = strengthCards.sublist(
        index,
        (index + 2).clamp(0, strengthCards.length),
      );
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: theme,
          margin: const pw.EdgeInsets.all(24),
          build:
              (context) => _pageFrame(
                context: context,
                athleteName: athleteName,
                section: 'Mesociclo de fuerza',
                logo: logo,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Progresión por ejercicio',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        _infoChip('PM', 'peso medio'),
                        pw.SizedBox(width: 5),
                        _infoChip('1RM est.', 'máximo estimado'),
                        pw.SizedBox(width: 5),
                        _infoChip('IMR', 'PM ÷ 1RM estimada'),
                      ],
                    ),
                    pw.SizedBox(height: 7),
                    ...chunk.map(
                      (card) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 8),
                        child: card,
                      ),
                    ),
                  ],
                ),
              ),
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _pageFrame({
    required pw.Context context,
    required String athleteName,
    required String section,
    required pw.MemoryImage logo,
    required pw.Widget child,
  }) {
    return pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _nexusInk,
            borderRadius: pw.BorderRadius.circular(7),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Container(
                width: 34,
                height: 34,
                padding: const pw.EdgeInsets.all(2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.black,
                  borderRadius: pw.BorderRadius.circular(17),
                  border: pw.Border.all(color: _nexusLime, width: 1),
                ),
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 9),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NEXUS TRAINING',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      section.toUpperCase(),
                      style: pw.TextStyle(fontSize: 8, color: _nexusLime),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: _nexusBlue,
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
        ),
        pw.SizedBox(height: 10),
        pw.Expanded(child: child),
        pw.Container(
          padding: const pw.EdgeInsets.only(top: 5),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: .5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Planificación de entrenamiento',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Página ${context.pageNumber}',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _compactDayGrid(
    Map<DateTime, List<Map<String, dynamic>>> days,
    DateFormat dateFormat,
  ) {
    final entries =
        days.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) pw.SizedBox(width: 7),
          pw.Expanded(child: _compactDayCard(entries[index], dateFormat)),
        ],
      ],
    );
  }

  static pw.Widget _compactDayCard(
    MapEntry<DateTime, List<Map<String, dynamic>>> entry,
    DateFormat dateFormat,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: _nexusSurface,
        border: pw.Border.all(color: PdfColors.blueGrey100, width: .7),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _nexusInk,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              _capitalize(dateFormat.format(entry.key)),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          ...entry.value.map((item) {
            final planned = Map<String, dynamic>.from(item['planned'] as Map);
            final block = Map<String, dynamic>.from(
              item['block'] as Map? ?? const {},
            );
            final title = visibleBlockTitle(
              block['title'] ?? planned['blockTitle'] ?? block['type'],
            );
            final blockType = (block['type'] ?? 'Series').toString();
            final isCircuit = blockType == 'Circuito';
            final rounds = block['rounds'];
            final accent = _blockAccent(title);
            final exercises = (block['exercises'] as List? ?? const []).map(
              (raw) => Map<String, dynamic>.from(raw as Map),
            );
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(6, 5, 5, 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border(
                    left: pw.BorderSide(color: accent, width: 2.4),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    if (isCircuit)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: pw.Text(
                          'Circuito - ${rounds ?? '?'} rondas - completar en orden',
                          style: pw.TextStyle(
                            fontSize: 6.2,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.amber800,
                          ),
                        ),
                      ),
                    ...exercises.map((exercise) {
                      final name =
                          (exercise['displayName'] ??
                                  exercise['name'] ??
                                  exercise['exercise'] ??
                                  'Ejercicio')
                              .toString();
                      final plannedSets = _plannedSetsFor(exercise);
                      // Desglosado por grupos de series con el mismo peso y
                      // reps (ej. "2x3 @ 85kg / 1x3 @ 90kg") en vez de
                      // agrupar reps y pesos por separado, que ocultaba qué
                      // peso corresponde a qué serie cuando ambos variaban
                      // juntos.
                      final setsLabel = PlannedLoadService.formatSetGroups(
                        plannedSets,
                      );
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              name,
                              maxLines: 2,
                              style: pw.TextStyle(
                                fontSize: 7,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey800,
                              ),
                            ),
                            pw.Text(
                              [
                                if (isCircuit) 'Por ronda',
                                if (setsLabel.isNotEmpty) setsLabel,
                              ].join(' · '),
                              style: const pw.TextStyle(
                                fontSize: 6.4,
                                color: PdfColors.grey600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _summarySection(Map<String, dynamic> summary) {
    final values = [
      ['Días', _value(summary['days'])],
      ['Bloques', _value(summary['blocks'])],
      ['Ejercicios', _value(summary['exercises'])],
      ['Series', _value(summary['sets'])],
      ['Volumen', _number(summary['volume'])],
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Resumen del entrenamiento',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              values
                  .map(
                    (item) => pw.Container(
                      width: 92,
                      padding: const pw.EdgeInsets.fromLTRB(7, 5, 7, 7),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border(
                          top: pw.BorderSide(
                            color: _metricAccent(item[0]),
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            item[0],
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            item[1],
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: _nexusInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Mesociclo: ${summary['mesocycleId'] ?? 'Sin mesociclo'}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static List<pw.Widget> _strengthExerciseCards(
    Map<DateTime, List<Map<String, dynamic>>> days,
    Set<String> progressionVariants,
  ) {
    final exercises = <String, Map<int, List<Map<String, String>>>>{};
    for (final items in days.values) {
      for (final item in items) {
        final planned = Map<String, dynamic>.from(item['planned'] as Map);
        final block = Map<String, dynamic>.from(
          item['block'] as Map? ?? const {},
        );
        final week = (planned['week'] as num?)?.toInt() ?? 0;
        if (week <= 0) continue;
        final plannedProgression = List<Map<String, dynamic>>.from(
          planned['loadProgression'] ?? const [],
        );
        final blockExercises = block['exercises'] as List? ?? const [];
        for (
          var exerciseIndex = 0;
          exerciseIndex < blockExercises.length;
          exerciseIndex++
        ) {
          final raw = blockExercises[exerciseIndex];
          final exercise = Map<String, dynamic>.from(raw as Map);
          final name =
              (exercise['displayName'] ??
                      exercise['name'] ??
                      exercise['exercise'] ??
                      'Ejercicio')
                  .toString();
          final variant = (exercise['variantLabel'] ?? '').toString();
          final exerciseId =
              (exercise['exerciseId'] ?? exercise['movementId'])?.toString();
          final variantId = exercise['variantId']?.toString();
          final movementName = name.split(' - ').first.trim();
          final instanceKey =
              exercise['exerciseInstanceId']?.toString() ??
              PlannedLoadService.exerciseKey(exercise, exerciseIndex);
          final configuredInPlanning = plannedProgression.any((rule) {
            if (rule['exerciseInstanceId']?.toString() != instanceKey) {
              return false;
            }
            return rule['mode']?.toString() != 'manual';
          });
          final configuredFromCatalog =
              (exerciseId != null &&
                  variantId != null &&
                  progressionVariants.contains('$exerciseId::$variantId')) ||
              progressionVariants.contains(
                '${_catalogKey(movementName)}::${_catalogKey(variant)}',
              );
          if (!configuredInPlanning &&
              exercise['trackProgression'] != true &&
              !configuredFromCatalog) {
            continue;
          }
          final label =
              variant.isEmpty ||
                      name.toLowerCase().contains(variant.toLowerCase())
                  ? name
                  : '$name · $variant';
          final plannedSets = _plannedSetsFor(exercise);
          final volume = plannedSets.fold<double>(0, (total, set) {
            final series = (set['series'] as num?)?.toDouble() ?? 1;
            final reps = (set['reps'] as num?)?.toDouble() ?? 0;
            return total + series * reps;
          });
          final tonnage = plannedSets.fold<double>(0, (total, set) {
            final series = (set['series'] as num?)?.toDouble() ?? 1;
            final reps = (set['reps'] as num?)?.toDouble() ?? 0;
            final weight = (set['weight'] as num?)?.toDouble() ?? 0;
            return total + series * reps * weight;
          });
          final averageWeight =
              volume > 0 && tonnage > 0 ? tonnage / volume : null;
          final estimatedValues = plannedSets
              .map((set) {
                final weight = (set['weight'] as num?)?.toDouble() ?? 0;
                final reps = (set['reps'] as num?)?.toDouble() ?? 0;
                return weight > 0 && reps > 0
                    ? WorkoutRMService.estimate1RM(
                      weight: weight,
                      reps: reps.toInt(),
                    )
                    : 0.0;
              })
              .where((value) => value > 0);
          final estimated1Rm =
              estimatedValues.isEmpty
                  ? null
                  : estimatedValues.reduce((a, b) => a > b ? a : b);
          final imr =
              averageWeight == null || estimated1Rm == null || estimated1Rm <= 0
                  ? null
                  : averageWeight / estimated1Rm * 100;
          // Desglosado por grupos de series con el mismo peso y reps (ej.
          // "2x3 @ 85kg / 1x3 @ 90kg") en vez de listar reps y pesos por
          // separado, que no dejaba claro qué peso iba con qué serie.
          final setGroupsLabel = PlannedLoadService.formatSetGroups(
            plannedSets,
          );
          final rpe = exercise['rpe'] ?? block['rpe'] ?? planned['rpe'];
          final weekEntries = exercises
              .putIfAbsent(label, () => {})
              .putIfAbsent(week, () => []);
          final prescription = {
            'setsReps': setGroupsLabel.isNotEmpty ? setGroupsLabel : '-',
            'meanWeight':
                averageWeight == null ? '-' : _compactNumber(averageWeight),
            'volume': volume > 0 ? _compactNumber(volume) : '-',
            'tonnage': tonnage > 0 ? _compactNumber(tonnage) : '-',
            'oneRm': estimated1Rm == null ? '-' : _compactNumber(estimated1Rm),
            'imr': imr == null ? '-' : '${imr.toStringAsFixed(1)}%',
            'rpe': rpe?.toString() ?? '-',
          };
          final duplicate = weekEntries.any(
            (existing) => prescription.entries.every(
              (entry) => existing[entry.key] == entry.value,
            ),
          );
          if (!duplicate) weekEntries.add(prescription);
        }
      }
    }
    final sorted =
        exercises.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((entry) {
      final weeks = entry.value.keys.toList()..sort();
      return pw.Container(
        padding: const pw.EdgeInsets.all(7),
        decoration: pw.BoxDecoration(
          color: _nexusSurface,
          border: pw.Border.all(color: PdfColors.blueGrey100, width: .7),
          borderRadius: pw.BorderRadius.circular(7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              entry.key,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _nexusPurple,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.symmetric(
                inside: const pw.BorderSide(
                  color: PdfColors.grey200,
                  width: .4,
                ),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(.6),
                1: pw.FlexColumnWidth(2.3),
                2: pw.FlexColumnWidth(.7),
                3: pw.FlexColumnWidth(1),
                4: pw.FlexColumnWidth(.7),
                5: pw.FlexColumnWidth(.85),
                6: pw.FlexColumnWidth(.75),
                7: pw.FlexColumnWidth(.6),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.deepPurple50,
                  ),
                  children:
                      [
                        'Sem.',
                        'Series x reps @ kg',
                        'Vol.',
                        'Tonelaje',
                        'PM',
                        '1RM est.',
                        'IMR',
                        'RPE',
                      ].map((value) => _cell(value, true)).toList(),
                ),
                ...weeks.expand(
                  (week) => entry.value[week]!.map(
                    (data) => pw.TableRow(
                      children: [
                        _cell('$week'),
                        _cell(data['setsReps']!),
                        _cell(data['volume']!),
                        _cell(data['tonnage']!),
                        _cell(data['meanWeight']!),
                        _cell(data['oneRm']!),
                        _cell(data['imr']!),
                        _cell(data['rpe']!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  static String _catalogKey(String value) => normalizeExerciseKey(value);

  static pw.Widget _infoChip(String label, String description) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.deepPurple50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label  ',
              style: pw.TextStyle(
                fontSize: 6.5,
                fontWeight: pw.FontWeight.bold,
                color: _nexusPurple,
              ),
            ),
            pw.TextSpan(
              text: description,
              style: const pw.TextStyle(fontSize: 6.5),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _sectionCard({
    required String title,
    required String subtitle,
    required PdfColor accent,
    required pw.Widget child,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: _nexusSurface,
        border: pw.Border.all(color: PdfColors.blueGrey100, width: .6),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(width: 4, height: 22, color: accent),
              pw.SizedBox(width: 6),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _nexusInk,
                    ),
                  ),
                  pw.Text(
                    subtitle,
                    style: const pw.TextStyle(
                      fontSize: 6.5,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  static pw.Widget _bodyHeatmapPanel({
    required pw.MemoryImage frontBody,
    required pw.MemoryImage backBody,
    required Map<String, double> distribution,
  }) {
    final entries =
        distribution.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    final leaders = entries.take(4).toList();
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _nexusInk,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'MAPA DE ESTÍMULO',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _nexusLime,
            ),
          ),
          pw.Text(
            'Vista frontal y posterior',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 7),
          pw.Expanded(
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Expanded(child: _bodyFigure('FRONTAL', frontBody)),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _bodyFigure('POSTERIOR', backBody)),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#141F33'),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ZONAS PRINCIPALES',
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 4),
                ...leaders.map((entry) {
                  final percent = total <= 0 ? 0 : entry.value / total * 100;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          _muscleLabel(entry.key),
                          style: const pw.TextStyle(
                            fontSize: 6.5,
                            color: PdfColors.grey200,
                          ),
                        ),
                        pw.Text(
                          '${percent.toStringAsFixed(1)}%',
                          style: pw.TextStyle(
                            fontSize: 6.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _nexusLime,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _bodyFigure(String label, pw.MemoryImage image) {
    return pw.Column(
      children: [
        pw.Expanded(child: pw.Image(image, fit: pw.BoxFit.contain)),
        pw.SizedBox(height: 3),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey300),
        ),
      ],
    );
  }

  static Map<Muscle, double> _muscleHeatmap(Map<String, double> distribution) {
    final total = distribution.values
        .where((value) => value > 0)
        .fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return const {};
    return {
      for (final muscle in Muscle.values)
        muscle: (distribution[muscle.name] ?? 0) / total * 100,
    };
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

  static PdfColor _blockAccent(String title) {
    final normalized = _normalizedText(title);
    if (normalized.contains('fuerza')) return _nexusBlue;
    if (normalized.contains('potencia') || normalized.contains('velocidad')) {
      return PdfColors.orange700;
    }
    if (normalized.contains('hipertrofia') || normalized.contains('push')) {
      return _nexusPurple;
    }
    if (normalized.contains('core') || normalized.contains('estabilidad')) {
      return PdfColors.green700;
    }
    if (normalized.contains('movilidad') || normalized.contains('entrada')) {
      return PdfColors.teal600;
    }
    return PdfColors.blueGrey600;
  }

  static PdfColor _metricAccent(String label) {
    switch (label) {
      case 'Días':
        return _nexusBlue;
      case 'Bloques':
        return _nexusPurple;
      case 'Ejercicios':
        return PdfColors.teal600;
      case 'Series':
        return PdfColors.orange700;
      default:
        return PdfColors.green700;
    }
  }

  static pw.Widget _dailyChart(Map<DateTime, double> dailyLoad) {
    if (dailyLoad.isEmpty)
      return pw.Text(
        'Sin carga diaria calculable.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
      );
    final entries =
        dailyLoad.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxValue = entries
        .map((e) => e.value)
        .fold<double>(0, (max, value) => value > max ? value : max);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ...entries.map(
          (entry) => _barRow(
            DateFormat('dd/MM').format(entry.key),
            entry.value,
            maxValue,
            PdfColors.blue,
          ),
        ),
      ],
    );
  }

  static pw.Widget _muscleChart(Map<String, double> distribution) {
    final entries =
        distribution.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    final top =
        entries
            .take(12)
            .map((entry) => MapEntry(entry.key, entry.value / total * 100))
            .toList();
    if (top.isEmpty)
      return pw.Text(
        'No hay distribución muscular disponible.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
      );
    final maxValue = top.first.value;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ...top.map(
          (entry) => _barRow(
            _muscleLabel(entry.key),
            entry.value,
            maxValue,
            PdfColors.deepPurple,
            showPercent: true,
          ),
        ),
      ],
    );
  }

  static pw.Widget _barRow(
    String label,
    double value,
    double max,
    PdfColor color, {
    bool showPercent = false,
  }) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 68,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 7.2)),
          ),
          pw.Container(
            width: 105,
            height: 8,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Container(
                width: 105 * fraction,
                height: 8,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          pw.SizedBox(
            width: 34,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                showPercent
                    ? '${value.toStringAsFixed(1)}%'
                    : _compactNumber(value),
                style: const pw.TextStyle(fontSize: 7.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _plannedSetsFor(
    Map<String, dynamic> exercise,
  ) {
    if (exercise['sets'] is List) {
      final sets = List<Map<String, dynamic>>.from(exercise['sets'] as List);
      if (sets.isNotEmpty) return sets;
    }
    final count = (exercise['series'] as num?)?.toInt() ?? 1;
    final reps =
        exercise['reps'] ?? exercise['value'] ?? exercise['targetReps'] ?? 0;
    final weight =
        exercise['weight'] ??
        exercise['referenceWeight'] ??
        exercise['load'] ??
        0;
    return List.generate(
      count.clamp(1, 100),
      (_) => {'reps': reps, 'weight': weight},
    );
  }

  static String _normalizedText(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _compactNumber(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return _value(value);
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number
        .toStringAsFixed(1)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _number(dynamic value) => _compactNumber(value);

  static String _muscleLabel(String key) {
    const labels = {
      'quads': 'Cuádriceps',
      'hamstrings': 'Isquios',
      'glutes': 'Glúteos',
      'midGlutes': 'Glúteo medio',
      'calves': 'Pantorrillas',
      'abs': 'Abdominales',
      'lowerAbs': 'Abd. inferiores',
      'obliques': 'Oblicuos',
      'lowerBack': 'Lumbar',
      'lats': 'Dorsales',
      'midBack': 'Espalda media',
      'rombs': 'Romboides',
      'trapsUpper': 'Trapecio sup.',
      'frontDelts': 'Deltoides ant.',
      'midDelts': 'Deltoides med.',
      'rearDelts': 'Deltoides post.',
      'biceps': 'Bíceps',
      'triceps': 'Tríceps',
      'adductors': 'Aductores',
      'serratus': 'Serrato',
    };
    return labels[key] ?? key;
  }

  static pw.Widget _cell(String value, [bool header = false]) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  static String _value(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '-';
    return value.toString();
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
