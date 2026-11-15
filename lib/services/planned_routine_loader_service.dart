import 'package:cloud_firestore/cloud_firestore.dart';
import 'planned_load_service.dart';

/// Carga rutinas planificadas (`planned_workouts` + `blocks`) para un atleta
/// y una fecha dadas. Centraliza la lógica que antes vivía duplicada en
/// distintas pantallas (Home, LogWorkout).
class PlannedRoutineLoaderService {
  /// Convierte `date` a `DateTime` sin importar el formato en que se haya
  /// guardado en Firestore (Timestamp, DateTime, String o num), ya que
  /// planes creados en distintos momentos pueden usar formatos distintos.
  static DateTime? dateTimeValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }
    return null;
  }

  /// Carga TODOS los bloques planificados para la fecha dada y los une en una
  /// sola estructura de "rutina" con múltiples bloques, compatible con el
  /// ViewModel de LogWorkout.
  static Future<Map<String, dynamic>?> loadRoutineForDate({
    required String athleteId,
    required DateTime date,
  }) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final snap =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: athleteId)
            .get();

    // El campo `date` puede venir como Timestamp, String, num o DateTime
    // según cuándo/cómo se creó el plan, así que filtramos el rango en Dart
    // en vez de con un filtro de rango de Firestore (que solo compara
    // Timestamps y descarta silenciosamente otros formatos).
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> plannedDocs =
        snap.docs.where((doc) {
          final docDate = dateTimeValue(doc.data()['date']);
          return docDate != null &&
              !docDate.isBefore(start) &&
              docDate.isBefore(end);
        }).toList();

    if (plannedDocs.isEmpty) return null;

    plannedDocs.sort((a, b) {
      final dataA = a.data();
      final dataB = b.data();
      final orderA = dataA['order'] as int? ?? 0;
      final orderB = dataB['order'] as int? ?? 0;
      return orderA.compareTo(orderB);
    });

    final List<Map<String, dynamic>> allBlocks = [];
    final List<String> blockTitles = [];

    for (final planned in plannedDocs) {
      final data = {...planned.data(), 'id': planned.id};

      final blockId =
          (data['blockId'] ?? data['sourceBlockId'])?.toString().trim();
      Map<String, dynamic>? blockData;
      if (blockId != null && blockId.isNotEmpty) {
        final blockDoc =
            await FirebaseFirestore.instance
                .collection('blocks')
                .doc(blockId)
                .get();
        if (blockDoc.exists) blockData = {...blockDoc.data()!};
      }

      // Compatibilidad con planificaciones antiguas que guardaban el bloque
      // embebido, o que todavía no tienen un documento válido en `blocks`.
      if (blockData == null && data['block'] is Map) {
        blockData = Map<String, dynamic>.from(data['block'] as Map);
      }
      if (blockData == null && data['exercises'] is List) {
        blockData = Map<String, dynamic>.from(data);
      }
      final sourceBlock = blockData;
      if (sourceBlock != null) {
        if ((sourceBlock['exercises'] as List? ?? const []).isEmpty &&
            data['exercises'] is List) {
          sourceBlock['exercises'] = data['exercises'];
        }
        final resolved = PlannedLoadService.resolveBlock(
          block: sourceBlock,
          planned: {...data, if (blockId != null) 'blockId': blockId},
        );
        allBlocks.add(resolved);
        blockTitles.add(data['blockTitle'] ?? sourceBlock['title'] ?? 'Bloque');
      }
    }

    if (allBlocks.isEmpty) return null;

    return {
      'id': null,
      'name':
          blockTitles.length == 1
              ? blockTitles.first
              : 'Sesión del día (${allBlocks.length} bloques)',
      'blocks': allBlocks,
    };
  }
}
