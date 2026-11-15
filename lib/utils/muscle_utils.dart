import '../models/muscle_catalog.dart';

/// Decodes a `muscleWeights` map stored inside an exercise data document
/// into a typed `Map<Muscle, double>`.
///
/// Handles the legacy alias `'traps'` → `'trapsUpper'`.
Map<Muscle, double> decodeMuscleWeights(Map<String, dynamic>? exData) {
  if (exData == null) return {};
  final raw = exData['muscleWeights'];
  if (raw is! Map) return {};

  final Map<Muscle, double> result = {};
  for (final entry in raw.entries) {
    final key =
        entry.key.toString() == 'traps' ? 'trapsUpper' : entry.key.toString();
    try {
      final muscle = Muscle.values.firstWhere((m) => m.name == key);
      result[muscle] = (entry.value as num).toDouble();
    } catch (_) {}
  }
  return result;
}
