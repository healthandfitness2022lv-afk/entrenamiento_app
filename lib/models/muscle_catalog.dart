// lib/models/muscle_catalog.dart

// ======================================================
// 💪 ENUM DE MÚSCULOS (CLAVE TÉCNICA / SVG / FIRESTORE)
// ======================================================
enum Muscle {
  // Tren inferior
  quads,
  hamstrings,
  glutes,
  adductors,
  calves,

  // Pecho / hombro
  chest,
  frontDelts,
  midDelts, // ✅ NUEVO
  rearDelts,

  // Brazos
  biceps,
  triceps,
  forearms,

  // Espalda
  lats,
  midBack,
  traps,
  lowerBack,

  // Core
  abs,
  obliques,
  psoas,

  // Estabilizadores
  serratus,
}

// ======================================================
// 🏷️ LABELS EN ESPAÑOL (UI)
// ======================================================
extension MuscleLabel on Muscle {
  String get label {
    switch (this) {
      // Tren inferior
      case Muscle.quads:
        return "Cuádriceps";
      case Muscle.hamstrings:
        return "Isquiotibiales";
      case Muscle.glutes:
        return "Glúteos";
      case Muscle.adductors:
        return "Aductores";
      case Muscle.calves:
        return "Pantorrillas";

      // Pecho / hombro
      case Muscle.chest:
        return "Pectorales";
      case Muscle.frontDelts:
        return "Deltoides anterior";
      case Muscle.midDelts:
        return "Deltoides medial"; // ✅ NUEVO
      case Muscle.rearDelts:
        return "Deltoide posterior";

      // Brazos
      case Muscle.biceps:
        return "Bíceps";
      case Muscle.triceps:
        return "Tríceps";
      case Muscle.forearms:
        return "Antebrazos";

      // Espalda
      case Muscle.lats:
        return "Dorsales";
      case Muscle.midBack:
        return "Redondo";
      case Muscle.traps:
        return "Trapecios";
      case Muscle.lowerBack:
        return "Lumbares";

      // Core
      case Muscle.abs:
        return "Abdominales";
      case Muscle.obliques:
        return "Oblícuos";
      case Muscle.psoas:
        return "Flexores de cadera";

      // Estabilizadores
      case Muscle.serratus:
        return "Serrato anterior";
    }
  }
}

// ======================================================
// 🔤 NORMALIZADOR (acentos / mayúsculas / espacios)
// ======================================================
String normalizeKey(String input) {
  return input
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u');
}

// ======================================================
// 📋 CATÁLOGO VISIBLE (SELECTORES / AUTOCOMPLETE)
// ======================================================
final List<String> muscleCatalog =
    Muscle.values.map((m) => m.label).toList();

// ======================================================
// 🧠 CATÁLOGO → ENUM (PONDERACIÓN BASE)
// ======================================================
final Map<String, Map<Muscle, double>> muscleCatalogMap = {
  // Tren inferior
  "Cuádriceps": {Muscle.quads: 1.0},
  "Isquiotibiales": {Muscle.hamstrings: 1.0},
  "Glúteos": {Muscle.glutes: 1.0},
  "Aductores": {Muscle.adductors: 1.0},
  "Pantorrillas": {Muscle.calves: 1.0},

  // Pecho
  "Pectorales": {Muscle.chest: 1.0},

  // Espalda
  "Dorsales": {Muscle.lats: 1.0},
  "Redondo": {Muscle.midBack: 1.0},
  "Trapecios": {Muscle.traps: 1.0},
  "Lumbares": {Muscle.lowerBack: 1.0},

  // Hombros
  "Deltoides anterior": {Muscle.frontDelts: 1.0},
  "Deltoides medial": {Muscle.midDelts: 1.0}, // ✅ NUEVO
  "Deltoide posterior": {Muscle.rearDelts: 1.0},

  // Brazos
  "Bíceps": {Muscle.biceps: 1.0},
  "Tríceps": {Muscle.triceps: 1.0},
  "Antebrazos": {Muscle.forearms: 1.0},

  // Core
  "Abdominales": {Muscle.abs: 1.0},
  "Oblícuos": {Muscle.obliques: 1.0},
  "Flexores de cadera": {Muscle.psoas: 1.0},

  // Estabilizadores
  "Serrato anterior": {Muscle.serratus: 1.0},
};

// ======================================================
// 🔑 MAPA NORMALIZADO (USO INTERNO)
// ======================================================
final Map<String, Map<Muscle, double>> normalizedMuscleCatalogMap = {
  for (final entry in muscleCatalogMap.entries)
    normalizeKey(entry.key): entry.value,
};
