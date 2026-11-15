import 'exercise_name_utils.dart';

/// Encuentra la variante del catálogo a la que apunta una referencia guardada
/// (workout, bloque, planificación) aunque su id ya no exista.
///
/// Los scripts de consolidación renombran ids de variantes (p. ej. `landmine`
/// → `snatch_landmine`), y los documentos que guardaron el id viejo quedaban
/// "huérfanos": sin ponderación propia y sin poder editarse. Orden:
///   1. id exacto;
///   2. `variantAliases` del ejercicio (id viejo → id nuevo), que se escribe
///      al renombrar o al reasignar una variante desde la app;
///   3. mismo label (normalizado), que sobrevive a los cambios de id.
/// Devuelve `null` si nada coincide.
Map<String, dynamic>? resolveCatalogVariant(
  Map<String, dynamic> exercise, {
  String? variantId,
  String? variantLabel,
}) {
  final variants =
      (exercise['variants'] as List? ?? const [])
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
  if (variants.isEmpty) return null;

  Map<String, dynamic>? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final v in variants) {
      if ((v['id'] ?? '').toString() == id) return v;
    }
    return null;
  }

  final id = (variantId == null || variantId.isEmpty) ? null : variantId;

  final exact = byId(id);
  if (exact != null) return exact;

  final aliases = exercise['variantAliases'];
  if (id != null && aliases is Map) {
    final aliased = byId(aliases[id]?.toString());
    if (aliased != null) return aliased;
  }

  final label = variantLabel?.trim() ?? '';
  if (label.isNotEmpty) {
    final key = normalizeExerciseKey(label);
    for (final v in variants) {
      if (normalizeExerciseKey(v['label']) == key) return v;
    }
  }

  return null;
}
