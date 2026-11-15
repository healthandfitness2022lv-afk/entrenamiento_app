import 'dart:io';

import 'package:entrenamiento_app/services/planned_workout_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reporte mensual compacto se genera sin exceder 20 páginas', () async {
    await initializeDateFormatting('es');
    final start = DateTime(2026, 9, 21);
    final days = <DateTime, List<Map<String, dynamic>>>{};
    for (var index = 0; index < 20; index++) {
      final date = start.add(Duration(days: index));
      final week = (index ~/ 5) + 1;
      days[date] = List.generate(4, (blockIndex) {
        return {
          'planned': {
            'week': week,
            'order': blockIndex + 1,
            'blockTitle': 'Bloque ${blockIndex + 1}',
            'mesocycleId': 'fixture_mensual',
          },
          'block': {
            'title':
                blockIndex == 1 ? 'Fuerza principal' : 'Trabajo complementario',
            'type': 'Series',
            'exercises': [
              {
                'name': 'Press De Pecho - Barra en banco plano',
                'displayName': 'Press De Pecho - Barra en banco plano',
                'variantLabel': 'Barra en banco plano',
                'trackProgression': true,
                'series': 4,
                'reps': 6,
                'weight': 66.25,
                'sets': const [
                  {'reps': 6, 'weight': 60},
                  {'reps': 6, 'weight': 65},
                  {'reps': 6, 'weight': 70},
                  {'reps': 6, 'weight': 70},
                ],
              },
              {
                'name': 'Accesorio $blockIndex',
                'series': 3,
                'reps': 10,
                'weight': 20,
              },
            ],
          },
        };
      });
    }

    final bytes = await PlannedWorkoutPdfService.buildBytes(
      athleteName: 'Héctor Álvarez',
      range: DateTimeRange(
        start: start,
        end: start.add(const Duration(days: 27)),
      ),
      days: days,
      muscleDistribution: const {
        'quads': 900,
        'glutes': 780,
        'hamstrings': 650,
        'pecs': 540,
        'lats': 510,
        'frontDelts': 420,
        'triceps': 380,
        'biceps': 310,
      },
      dailyLoad: {for (final day in days.keys) day: 1200 + day.day * 10},
      summary: const {
        'days': 20,
        'blocks': 80,
        'exercises': 160,
        'sets': 560,
        'volume': 84200,
        'mesocycleId': 'fixture_mensual',
      },
    );

    final output = File('tmp/pdfs/monthly_plan_preview.pdf');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes);
    expect(bytes, isNotEmpty);
    expect(PlannedWorkoutPdfService.pageCountFor(days), 6);
  });
}
