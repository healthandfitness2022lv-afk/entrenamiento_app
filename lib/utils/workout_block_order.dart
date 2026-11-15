/// Orden estable para bloques de entrenamientos guardados.
///
/// Algunos historiales antiguos conservaron un `blockIndex` distinto al
/// orden de la planificación. Los ids de bloques de mesociclo contienen la
/// posición canónica (`d1_b2`), que permite reparar la presentación sin
/// cambiar los datos históricos.
int comparePerformedBlocks(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aCanonical = _canonicalBlockOrder(a);
  final bCanonical = _canonicalBlockOrder(b);
  if (aCanonical != null && bCanonical != null && aCanonical != bCanonical) {
    return aCanonical.compareTo(bCanonical);
  }

  final aIndex = int.tryParse('${a['blockIndex'] ?? ''}');
  final bIndex = int.tryParse('${b['blockIndex'] ?? ''}');
  if (aIndex != null && bIndex != null && aIndex != bIndex) {
    return aIndex.compareTo(bIndex);
  }
  return (aIndex ?? 1 << 30).compareTo(bIndex ?? 1 << 30);
}

int? _canonicalBlockOrder(Map<String, dynamic> block) {
  final candidates = <String?>[
    block['blockId']?.toString(),
    block['sourceKey']?.toString(),
    block['plannedWorkoutId']?.toString(),
  ];

  for (final candidate in candidates) {
    if (candidate == null) continue;
    final match = RegExp(
      r'd(\d+)_b(\d+)',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (match == null) continue;
    final day = int.tryParse(match.group(1)!);
    final blockNumber = int.tryParse(match.group(2)!);
    if (day != null && blockNumber != null) {
      return day * 1000 + blockNumber;
    }
  }
  return null;
}
