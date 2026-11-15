import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/exercise.dart';
import '../utils/exercise_name_utils.dart';
import '../utils/exercise_variant_catalog.dart';

enum DuplicateExercisePolicy { skip, merge, review }

class ExerciseImportRow {
  final String movement;
  final String variant;
  final String group;
  final List<String> equipment;

  const ExerciseImportRow({
    required this.movement,
    required this.variant,
    required this.group,
    required this.equipment,
  });
}

class ExerciseImportResult {
  final int created;
  final int merged;
  final int skipped;
  final List<String> errors;

  const ExerciseImportResult({
    required this.created,
    required this.merged,
    required this.skipped,
    required this.errors,
  });
}

class ExerciseCatalogService {
  final FirebaseFirestore firestore;

  ExerciseCatalogService({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  static List<ExerciseImportRow> parseTabular(String input) {
    final rows = <ExerciseImportRow>[];
    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\t|\s*\|\s*'));
      if (parts.isEmpty || normalizeExerciseKey(parts.first) == 'movimiento') {
        continue;
      }
      final movement = parts.first.trim();
      final variant =
          parts.length > 1 && parts[1].trim().isNotEmpty
              ? parts[1].trim()
              : 'Original';
      final group =
          parts.length > 2 && parts[2].trim().isNotEmpty
              ? parts[2].trim()
              : 'Peso libre';
      final equipment =
          parts.length > 3
              ? parts[3]
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList()
              : <String>[];
      if (movement.isNotEmpty) {
        rows.add(
          ExerciseImportRow(
            movement: movement,
            variant: variant,
            group: group,
            equipment: equipment,
          ),
        );
      }
    }
    return rows;
  }

  Future<ExerciseImportResult> seedCommonVariants() async {
    final rows = <ExerciseImportRow>[];
    for (final entry in commonMovementVariants.entries) {
      final movement = entry.key
          .split(' ')
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
      for (final variant in entry.value) {
        rows.add(
          ExerciseImportRow(
            movement: movement,
            variant: variant.label,
            group: variant.group,
            equipment: variant.equipment,
          ),
        );
      }
    }
    return importRows(rows, duplicatePolicy: DuplicateExercisePolicy.merge);
  }

  Future<int> migrateLegacyExercises() async {
    final snapshot = await firestore.collection('exercises').get();
    var migrated = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final rawVariants = data['variants'];
      final key = canonicalExerciseKey(data['name']);
      final exactSuggested = commonMovementVariants[key];
      final current = _variantsFromData(data);
      final isLegacyOriginal =
          current.length == 1 &&
          normalizeExerciseKey(current.first.id) == 'original';
      if (rawVariants is List &&
          rawVariants.isNotEmpty &&
          !isLegacyOriginal &&
          exactSuggested == null) {
        continue;
      }

      final safeSingleton = exactSuggested == null && _isSafeSingleton(data);
      final variants =
          exactSuggested ??
          (safeSingleton ? current.map(_markReviewed).toList() : current);
      await doc.reference.update({
        'variants': variants.map((variant) => variant.toMap()).toList(),
        'catalogStatus':
            exactSuggested != null
                ? 'ready'
                : safeSingleton
                ? 'reviewed_single'
                : 'needs_review',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      migrated++;
    }
    return migrated;
  }

  static String variantIdFor(String label) =>
      normalizeExerciseKey(label).replaceAll(' ', '_');

  static bool _isSafeSingleton(Map<String, dynamic> data) {
    final equipment = List<String>.from(data['equipment'] ?? const []);
    if (equipment.isNotEmpty) return true;
    final type = normalizeExerciseKey(data['exerciseType']);
    return {
      'cardio',
      'movilidad',
      'pliometria',
      'calistenia',
      'core estabilidad',
      'weightlifting',
    }.contains(type);
  }

  static ExerciseVariant _markReviewed(ExerciseVariant variant) =>
      ExerciseVariant(
        id: variant.id,
        label: variant.label,
        group: variant.group,
        equipment: variant.equipment,
        resistanceType: variant.resistanceType,
        trackRM: variant.trackRM,
        trackProgression: variant.trackProgression,
        isUnilateral: variant.isUnilateral,
        muscleWeightOverrides: variant.muscleWeightOverrides,
        needsReview: false,
      );

  Future<ExerciseImportResult> importRows(
    List<ExerciseImportRow> rows, {
    required DuplicateExercisePolicy duplicatePolicy,
  }) async {
    final snapshot = await firestore.collection('exercises').get();
    final byKey = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final doc in snapshot.docs)
        canonicalExerciseKey(doc.data()['name']): doc,
    };
    var created = 0;
    var merged = 0;
    var skipped = 0;
    final errors = <String>[];

    final grouped = <String, List<ExerciseImportRow>>{};
    for (final row in rows) {
      grouped
          .putIfAbsent(canonicalExerciseKey(row.movement), () => [])
          .add(row);
    }

    for (final entry in grouped.entries) {
      final rowsForMovement = entry.value;
      final existing = byKey[entry.key];
      try {
        if (existing == null) {
          final variants = _dedupeVariants(
            rowsForMovement.map(_variantFromRow),
          );
          await firestore.collection('exercises').add({
            'name': rowsForMovement.first.movement,
            'instructions':
                'Configurar la técnica y el rango según la variante elegida.',
            'exerciseType': 'Otros',
            'equipment': variants.expand((v) => v.equipment).toSet().toList(),
            'muscleWeights': <String, double>{},
            'trackRM': variants.any((v) => v.trackRM),
            'variants': variants.map((v) => v.toMap()).toList(),
            'catalogStatus': 'needs_profile',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          created++;
          continue;
        }

        if (duplicatePolicy == DuplicateExercisePolicy.skip) {
          skipped++;
          continue;
        }

        final data = existing.data();
        final current = _variantsFromData(data);
        final incoming = rowsForMovement.map(_variantFromRow);
        final variants = _dedupeVariants([...current, ...incoming]);
        await existing.reference.update({
          'variants': variants.map((v) => v.toMap()).toList(),
          'equipment': variants.expand((v) => v.equipment).toSet().toList(),
          if (duplicatePolicy == DuplicateExercisePolicy.review)
            'catalogStatus': 'needs_review',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        merged++;
      } catch (error) {
        errors.add('${rowsForMovement.first.movement}: $error');
      }
    }

    return ExerciseImportResult(
      created: created,
      merged: merged,
      skipped: skipped,
      errors: errors,
    );
  }

  static List<ExerciseVariant> _variantsFromData(Map<String, dynamic> data) {
    final raw = data['variants'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => ExerciseVariant.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [
      ExerciseVariant(
        id: 'original',
        label: 'Original',
        group: 'Peso libre',
        equipment: List<String>.from(data['equipment'] ?? const []),
        resistanceType: (data['resistanceType'] ?? 'free').toString(),
        trackRM: data['trackRM'] == true,
        isUnilateral: data['isUnilateral'] == true,
        needsReview: true,
      ),
    ];
  }

  static ExerciseVariant _variantFromRow(ExerciseImportRow row) {
    final resistance = switch (normalizeExerciseKey(row.group)) {
      'maquina' || 'polea' => 'guided',
      'peso corporal' => 'bodyweight',
      _ => 'free',
    };
    return ExerciseVariant(
      id: variantIdFor(row.variant),
      label: row.variant,
      group: row.group,
      equipment: row.equipment,
      resistanceType: resistance,
      trackRM: resistance != 'bodyweight',
      isUnilateral: normalizeExerciseKey(row.variant).contains('unilateral'),
    );
  }

  static List<ExerciseVariant> _dedupeVariants(
    Iterable<ExerciseVariant> variants,
  ) {
    final byId = <String, ExerciseVariant>{};
    for (final variant in variants) {
      final key = variant.id.isEmpty ? variantIdFor(variant.label) : variant.id;
      byId[key] = variant;
    }
    return byId.values.toList()..sort((a, b) {
      final group = a.group.compareTo(b.group);
      return group != 0 ? group : a.label.compareTo(b.label);
    });
  }
}
