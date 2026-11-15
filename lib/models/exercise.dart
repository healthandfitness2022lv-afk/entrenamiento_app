import 'muscle_catalog.dart';

class ExerciseVariant {
  final String id;
  final String label;
  final String group;
  final List<String> equipment;
  final String resistanceType;
  final bool trackRM;
  final String trainingDiscipline;
  final String movementIntent;

  /// Training category for this exact technique + implement combination.
  final String exerciseType;
  final String familyId;
  final String techniqueId;
  final String techniqueLabel;

  /// Include this exact movement + variant in the planned overload mesocycle.
  final bool trackProgression;
  final bool isUnilateral;

  /// Plano de movimiento dominante: `'sagittal'` (default, empuje/tracción/
  /// flexo-extensión clásicos), `'rotational'` (genera torque rotacional
  /// deliberado: leñador, landmine snatch/twist, lanzamientos laterales) o
  /// `'anti-rotational'` (exige resistir la rotación: Pallof, plancha
  /// lateral). Ambos casos rotacionales comparten la misma demanda de
  /// control de tronco en el plano transverso, clave en deportes de
  /// raqueta/lanzamiento/contacto — ver `attributeModifiers` en
  /// `training_identity_service.dart`.
  final String movementPlane;
  final Map<Muscle, double> muscleWeightOverrides;
  final bool needsReview;

  const ExerciseVariant({
    required this.id,
    required this.label,
    required this.group,
    required this.equipment,
    required this.resistanceType,
    required this.trackRM,
    this.trainingDiscipline = 'fuerza',
    this.movementIntent = 'full',
    this.exerciseType = '',
    this.familyId = '',
    this.techniqueId = '',
    this.techniqueLabel = '',
    this.trackProgression = false,
    required this.isUnilateral,
    this.movementPlane = 'sagittal',
    this.muscleWeightOverrides = const {},
    this.needsReview = false,
  });

  factory ExerciseVariant.fromMap(Map<String, dynamic> data) {
    final overrides = <Muscle, double>{};
    final raw = data['muscleWeightOverrides'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final matches = Muscle.values.where((m) => m.name == entry.key);
        if (matches.isNotEmpty && entry.value is num) {
          overrides[matches.first] = (entry.value as num).toDouble();
        }
      }
    }
    return ExerciseVariant(
      id: (data['id'] ?? '').toString(),
      label: (data['label'] ?? 'Original').toString(),
      group: (data['group'] ?? 'Peso libre').toString(),
      equipment: List<String>.from(data['equipment'] ?? const []),
      resistanceType: (data['resistanceType'] ?? 'free').toString(),
      trackRM: data['trackRM'] == true,
      trainingDiscipline: (data['trainingDiscipline'] ?? 'fuerza').toString(),
      movementIntent: (data['movementIntent'] ?? 'full').toString(),
      exerciseType: (data['exerciseType'] ?? '').toString(),
      familyId: (data['familyId'] ?? '').toString(),
      techniqueId: (data['techniqueId'] ?? '').toString(),
      techniqueLabel: (data['techniqueLabel'] ?? '').toString(),
      trackProgression: data['trackProgression'] == true,
      isUnilateral: data['isUnilateral'] == true,
      movementPlane: (data['movementPlane'] ?? 'sagittal').toString(),
      muscleWeightOverrides: overrides,
      needsReview: data['needsReview'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'group': group,
    'equipment': equipment,
    'resistanceType': resistanceType,
    'trackRM': trackRM,
    'trainingDiscipline': trainingDiscipline,
    'movementIntent': movementIntent,
    if (exerciseType.isNotEmpty) 'exerciseType': exerciseType,
    'familyId': familyId,
    'techniqueId': techniqueId,
    'techniqueLabel': techniqueLabel,
    'trackProgression': trackProgression,
    'isUnilateral': isUnilateral,
    if (movementPlane != 'sagittal') 'movementPlane': movementPlane,
    if (muscleWeightOverrides.isNotEmpty)
      'muscleWeightOverrides': {
        for (final entry in muscleWeightOverrides.entries)
          entry.key.name: entry.value,
      },
    if (needsReview) 'needsReview': true,
  };

  String displayName(
    String movementName, {
    bool hideSingleVariantLabel = false,
  }) =>
      hideSingleVariantLabel || label.toLowerCase() == 'original'
          ? movementName
          : '$movementName - $label';
}

class Exercise {
  // ======================================================
  // 🔑 IDENTIDAD FIRESTORE
  // ======================================================
  final String id;

  // ======================================================
  // 📌 DATOS PRINCIPALES
  // ======================================================
  final String name;
  final String instructions;

  final List<String> equipment;

  /// 🔒 YA NO NULLABLE
  final String exerciseType;

  final String? videoUrl;

  /// 🔥 PONDERACIÓN MUSCULAR REAL
  final Map<Muscle, double> muscleWeights;

  /// ⭐ NUEVO: ¿Este ejercicio cuenta para progreso (RM / PR / alertas)?
  final bool trackRM;
  final List<ExerciseVariant> variants;

  // ======================================================
  // 🧱 CONSTRUCTOR
  // ======================================================
  Exercise({
    required this.id,
    required this.name,
    required this.instructions,

    this.equipment = const [],
    required this.exerciseType,
    this.videoUrl,
    required this.muscleWeights,
    required this.trackRM,
    this.variants = const [],
  });

  // ======================================================
  // 🔁 FROM FIRESTORE (CON ID)
  // ======================================================
  factory Exercise.fromFirestore(
    Map<String, dynamic> data, {
    required String id,
  }) {
    // --------------------------------------------------
    // 🔁 Caso ejercicios antiguos SIN ponderación
    // --------------------------------------------------
    Map<Muscle, double> weights = {};

    if (data['muscleWeights'] != null &&
        data['muscleWeights'] is Map<String, dynamic>) {
      weights = {
        for (final e in (data['muscleWeights'] as Map<String, dynamic>).entries)
          Muscle.values.firstWhere(
                (m) => m.name == e.key,
                orElse: () => Muscle.quads,
              ):
              (e.value as num).toDouble(),
      };
    } else {
      // fallback seguro para legacy
      weights = {
        Muscle.values.firstWhere(
              (m) => m.name == _fallbackPrimary(data['primaryMuscle']),
              orElse: () => Muscle.quads,
            ):
            1.0,
      };
    }

    final rawVariants = data['variants'];
    final variants =
        rawVariants is List
            ? rawVariants
                .whereType<Map>()
                .map(
                  (v) => ExerciseVariant.fromMap(Map<String, dynamic>.from(v)),
                )
                .where((v) => v.id.isNotEmpty)
                .toList()
            : <ExerciseVariant>[];

    return Exercise(
      id: id, // 🔥 CLAVE ABSOLUTA
      name: (data['name'] ?? '').toString(),
      instructions: (data['instructions'] ?? '').toString(),
      equipment: List<String>.from(data['equipment'] ?? const []),

      /// 🔒 Nunca null
      exerciseType: (data['exerciseType'] ?? 'Otros').toString(),

      videoUrl: data['videoUrl'] as String?,
      muscleWeights: weights,

      /// ⭐ NUEVO
      /// default FALSE para no romper ejercicios antiguos
      trackRM: data['trackRM'] == true,
      variants:
          variants.isNotEmpty
              ? variants
              : [
                ExerciseVariant(
                  id: 'original',
                  label: 'Original',
                  group: _legacyGroup(data),
                  equipment: List<String>.from(data['equipment'] ?? const []),
                  resistanceType: (data['resistanceType'] ?? 'free').toString(),
                  trackRM: data['trackRM'] == true,
                  isUnilateral: data['isUnilateral'] == true,
                  movementPlane:
                      (data['movementPlane'] ?? 'sagittal').toString(),
                  needsReview: true,
                ),
              ],
    );
  }

  static String _legacyGroup(Map<String, dynamic> data) {
    final resistance = (data['resistanceType'] ?? '').toString();
    if (resistance == 'bodyweight') return 'Peso corporal';
    if (resistance == 'guided') return 'Máquina';
    final equipment = List<String>.from(data['equipment'] ?? const []);
    if (equipment.any((e) => e.toLowerCase().contains('polea'))) return 'Polea';
    if (equipment.any((e) => e.toLowerCase().contains('banda'))) return 'Banda';
    return 'Peso libre';
  }

  // ======================================================
  // 🔎 FALLBACK LEGACY
  // ======================================================
  static String _fallbackPrimary(String? name) {
    if (name == null) return 'quads';

    return name
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(' ', '');
  }
}
