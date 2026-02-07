import 'muscle_catalog.dart';

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
        for (final e
            in (data['muscleWeights'] as Map<String, dynamic>).entries)
          Muscle.values.firstWhere(
            (m) => m.name == e.key,
            orElse: () => Muscle.quads,
          ): (e.value as num).toDouble(),
      };
    } else {
      // fallback seguro para legacy
      weights = {
        Muscle.values.firstWhere(
          (m) => m.name == _fallbackPrimary(data['primaryMuscle']),
          orElse: () => Muscle.quads,
        ): 1.0,
      };
    }

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
    );
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
