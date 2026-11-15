/// Coerces a raw exercise name (String or List) to a plain String.
/// Returns 'Ejercicio' if the value cannot be interpreted.
String coerceExerciseName(dynamic raw) {
  if (raw is String) return raw;
  if (raw is List && raw.isNotEmpty) return raw.first.toString();
  return 'Ejercicio';
}

/// Stable comparison key used for catalog de-duplication and legacy aliases.
String normalizeExerciseKey(dynamic raw) {
  var value = coerceExerciseName(raw).trim().toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  replacements.forEach((from, to) => value = value.replaceAll(from, to));
  return value
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

const _exerciseAliases = <String, String>{
  'bulgarian squat': 'sentadilla bulgara',
  'thrusther': 'thruster',
};

/// Canonical key for preventing duplicates that differ only by a known alias.
String canonicalExerciseKey(dynamic raw) {
  final normalized = normalizeExerciseKey(raw);
  return _exerciseAliases[normalized] ?? normalized;
}

String exerciseIdentityKey({
  required String exerciseName,
  String? exerciseId,
  String? variantId,
}) {
  if (exerciseId != null && exerciseId.isNotEmpty) {
    return variantId == null || variantId.isEmpty
        ? exerciseId
        : '$exerciseId::$variantId';
  }
  final base = normalizeExerciseKey(exerciseName);
  return variantId == null || variantId.isEmpty ? base : '$base::$variantId';
}
