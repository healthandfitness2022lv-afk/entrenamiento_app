import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/achievement.dart';
import '../services/workout_volume_service.dart';
import '../services/workout_rm_service.dart';

class ReportService {
  static Future<void> generateWeeklyReport({
    required BuildContext context,
    required String athleteId,
    required DateTimeRange range,
  }) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdf = pw.Document();

      // 1. Fetch fonts for Unicode support
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      // 2. Fetch data
      final start = Timestamp.fromDate(
        DateTime(range.start.year, range.start.month, range.start.day),
      );
      final end = Timestamp.fromDate(
        DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59),
      );

      final athleteSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(athleteId)
              .get();
      final athleteName = athleteSnap.data()?['name'] ?? 'Atleta';

      final workoutsSnap =
          await FirebaseFirestore.instance
              .collection('workouts_logged')
              .where('userId', isEqualTo: athleteId)
              .where('date', isGreaterThanOrEqualTo: start)
              .where('date', isLessThanOrEqualTo: end)
              .get();

      final achievementsSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(athleteId)
              .collection('achievements')
              .where('unlockedAt', isGreaterThanOrEqualTo: start)
              .where('unlockedAt', isLessThanOrEqualTo: end)
              .get();

      final List<Map<String, dynamic>> workouts =
          workoutsSnap.docs.map((d) => d.data()).toList()..sort(
            (a, b) =>
                (a['date'] as Timestamp).compareTo(b['date'] as Timestamp),
          );

      final List<Achievement> unlockedThisWeek = [];
      for (final doc in achievementsSnap.docs) {
        try {
          final ach = achievementsCatalog.firstWhere((a) => a.id == doc.id);
          unlockedThisWeek.add(ach);
        } catch (_) {}
      }

      // 3. Calculate summary & best lists
      double totalVolume = 0;
      int totalSessions = workouts.length;
      double avgRpeSum = 0;
      int setsCount = 0;
      final Map<String, double> bestLifts = {};

      for (final w in workouts) {
        final performed = List<Map<String, dynamic>>.from(w['performed'] ?? []);
        totalVolume += WorkoutVolumeService.calculateWorkoutVolume(performed);

        // Best lifts of the week
        final candidates = WorkoutRMService.extractAllValidRMSetCandidates(
          performed,
        );
        for (final c in candidates) {
          final ex = c['exercise'] as String;
          final wgt = (c['weight'] as num).toDouble();
          if ((bestLifts[ex] ?? 0) < wgt) {
            bestLifts[ex] = wgt;
          }
          setsCount++;
        }

        // Calculate avg RPE for this workout
        double sessionRpeSum = 0;
        int sessionSets = 0;
        for (final block in performed) {
          if (block['type'] == 'Series' ||
              block['type'] == 'Series descendentes' ||
              block['type'] == 'Buscar RM') {
            for (final ex in (block['exercises'] as List)) {
              for (final set in (ex['sets'] as List)) {
                sessionRpeSum += (set['rpe'] as num).toDouble();
                sessionSets++;
              }
            }
          } else if (block['type'] == 'Circuito') {
            for (final round in (block['rounds'] as List)) {
              for (final ex in (round['exercises'] as List)) {
                sessionRpeSum += (ex['rpe'] as num).toDouble();
                sessionSets++;
              }
            }
          }
        }
        if (sessionSets > 0) {
          avgRpeSum += (sessionRpeSum / sessionSets);
        }
      }

      final double weeklyAvgRpe =
          totalSessions > 0 ? avgRpeSum / totalSessions : 0;

      // 4. Build Document
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          header: (context) => _buildHeader(athleteName, range),
          footer: (context) => _buildFooter(context),
          build:
              (context) => [
                pw.SizedBox(height: 20),
                _buildSummaryCards(
                  totalSessions,
                  totalVolume,
                  weeklyAvgRpe,
                  setsCount,
                ),
                pw.SizedBox(height: 30),
                _buildWorkoutsTable(workouts),
                if (bestLifts.isNotEmpty) ...[
                  pw.SizedBox(height: 30),
                  _buildBestLiftsSection(bestLifts),
                ],
                if (unlockedThisWeek.isNotEmpty) ...[
                  pw.SizedBox(height: 30),
                  _buildAchievementsSection(unlockedThisWeek),
                ],
              ],
        ),
      );

      // Dismiss loading
      if (context.mounted) Navigator.pop(context);

      // Preview & Share
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'Reporte_Semanal_${athleteName}_${DateFormat('yyyy-MM-dd').format(range.start)}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error al generar PDF: $e")));
      }
    }
  }

  static pw.Widget _buildHeader(String name, DateTimeRange range) {
    final fmt = DateFormat('dd/MM/yyyy');
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.blue, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'REPORTE SEMANAL DE RENDIMIENTO',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.Text(
                name.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Período: ${fmt.format(range.start)} al ${fmt.format(range.end)}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.Container(
            height: 40,
            width: 40,
            decoration: const pw.BoxDecoration(
              color: PdfColors.blue900,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                'A',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryCards(
    int sessions,
    double volume,
    double rpe,
    int sets,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _summaryCard('Sesiones', sessions.toString(), PdfColors.blue800),
        _summaryCard(
          'Volumen (kg)',
          NumberFormat('#,###').format(volume),
          PdfColors.green800,
        ),
        _summaryCard(
          'RPE Promedio',
          rpe.toStringAsFixed(1),
          PdfColors.orange800,
        ),
        _summaryCard('Sets Totales', sets.toString(), PdfColors.purple800),
      ],
    );
  }

  static pw.Widget _summaryCard(String title, String value, PdfColor color) {
    return pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(
          color: PdfColor(color.red, color.green, color.blue, 0.2),
          width: 1,
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildWorkoutsTable(List<Map<String, dynamic>> workouts) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'RESUMEN DE SESIONES',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.symmetric(
            inside: const pw.BorderSide(color: PdfColors.grey200, width: 0.5),
          ),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue50),
              children: [
                _tableHeader('Fecha'),
                _tableHeader('Nombre de la Sesión'),
                _tableHeader('Duración'),
                _tableHeader('Volumen (kg)'),
              ],
            ),
            ...workouts.map((w) {
              final date = (w['date'] as Timestamp).toDate();
              final vol = WorkoutVolumeService.calculateWorkoutVolume(
                List<Map<String, dynamic>>.from(w['performed'] ?? []),
              );
              return pw.TableRow(
                children: [
                  _tableCell(DateFormat('dd/MM').format(date)),
                  _tableCell(w['sessionName'] ?? 'Entrenamiento'),
                  _tableCell('${w['durationMinutes'] ?? 0} min'),
                  _tableCell(NumberFormat('#,###').format(vol)),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
          color: PdfColors.blue900,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey900),
      ),
    );
  }

  static pw.Widget _buildBestLiftsSection(Map<String, double> lifts) {
    final sortedLifts =
        lifts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final displayLifts = sortedLifts.take(8).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'MEJORES LEVANTAMIENTOS DE LA SEMANA',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 15,
          runSpacing: 10,
          children:
              displayLifts
                  .map(
                    (e) => pw.Container(
                      width: 150,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(8),
                        ),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Text(
                            '★',
                            style: pw.TextStyle(
                              color: PdfColors.orange400,
                              fontSize: 14,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                e.key,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                '${e.value.toStringAsFixed(1)} kg',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.blue700,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  static pw.Widget _buildAchievementsSection(List<Achievement> achievements) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'NUEVOS HITOS DESBLOQUEADOS',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 12,
          runSpacing: 10,
          children: achievements.map((ach) => _achievementCard(ach)).toList(),
        ),
      ],
    );
  }

  static pw.Widget _achievementCard(Achievement ach) {
    return pw.Container(
      width: 160,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.amber200, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: const pw.BoxDecoration(
              color: PdfColors.amber400,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              '★',
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  ach.title,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.amber900,
                  ),
                ),
                pw.Text(
                  ach.description,
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 20),
      child: pw.Text(
        'Página ${context.pageNumber} de ${context.pagesCount} - Generado por Entrenamiento App',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }
}
