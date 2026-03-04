// lib/models/muscle_catalog.dart
// ======================================================
// 💪 ENUM DE MÚSCULOS (CLAVE TÉCNICA / SVG / FIRESTORE)
// ======================================================
enum Muscle {
  // Tren inferior
  quads,
  hamstrings,
  glutes,
  midGlutes,
  adductors,
  calves,

  // Pecho
  chest,
  upperChest, // 🔥 NUEVO

  // Hombros
  frontDelts,
  midDelts,
  rearDelts,

  // Brazos
  biceps,
  triceps,
  forearms,

  // Espalda
  lats,
  rombs,
  midBack,
  trapsUpper, // 🔥 reemplaza traps
  lowerTraps, // 🔥 NUEVO
  lowerBack,

  // Core
  abs,
  lowerAbs,
  obliques,
  psoas,
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
        return "Glúteos mayores";
      case Muscle.midGlutes:
        return "Glúteos medios";
      case Muscle.adductors:
        return "Aductores";
      case Muscle.calves:
        return "Pantorrillas";

      // Pecho / hombro
      case Muscle.chest:
        return "Pectorales";
      case Muscle.upperChest:
        return "Pectoral superior";
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
      case Muscle.rombs:
        return "Romboides";
      case Muscle.midBack:
        return "Redondo";
      case Muscle.trapsUpper:
        return "Trapecio superior";
      case Muscle.lowerTraps:
        return "Trapecio inferior";
      case Muscle.lowerBack:
        return "Lumbares";

      // Core
      case Muscle.abs:
        return "Abdominales";
      case Muscle.lowerAbs:
        return "Abdominales inferiores";
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
  "Glúteos medios": {Muscle.midGlutes: 1.0},
  "Aductores": {Muscle.adductors: 1.0},
  "Pantorrillas": {Muscle.calves: 1.0},

  // Pecho
  "Pectorales": {Muscle.chest: 1.0},
  "Pectoral superior": {Muscle.upperChest: 1.0},


  // Espalda
"Dorsales": {Muscle.lats: 1.0},
"Redondo": {Muscle.midBack: 1.0},
"Trapecio superior": {Muscle.trapsUpper: 1.0},
"Trapecio inferior": {Muscle.lowerTraps: 1.0},
"Lumbares": {Muscle.lowerBack: 1.0},
"Romboides": {Muscle.rombs: 1.0},

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
  "Abdominales inferiores": {Muscle.lowerAbs: 1.0},
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

// ======================================================
// 🧩 GRUPOS ANATÓMICOS
// ======================================================

enum AnatomicalGroup {
  hombros,
  pecho,
  espalda,
  piernas,
  core,
  brazos,
}

const Map<AnatomicalGroup, List<Muscle>> anatomicalGroups = {
  AnatomicalGroup.hombros: [
    Muscle.frontDelts,
    Muscle.midDelts,
    Muscle.rearDelts,
  ],
  AnatomicalGroup.pecho: [
    Muscle.chest,
    Muscle.upperChest,
  ],
  AnatomicalGroup.espalda: [
    Muscle.lats,
    Muscle.rombs,
    Muscle.midBack,
    Muscle.trapsUpper,
    Muscle.lowerTraps,
    
  ],
  AnatomicalGroup.piernas: [
    Muscle.quads,
    Muscle.hamstrings,
    Muscle.adductors,
    Muscle.calves,
    Muscle.glutes,
    Muscle.midGlutes,
  ],
  AnatomicalGroup.core: [
    Muscle.abs,
    Muscle.lowerAbs,
    Muscle.obliques,
    Muscle.psoas,
    Muscle.lowerBack,
    Muscle.serratus,
  ],
  AnatomicalGroup.brazos: [
    Muscle.biceps,
    Muscle.triceps,
    Muscle.forearms,
    
  ],
};

// ======================================================
// 🔄 GRUPOS FUNCIONALES
// ======================================================

enum FunctionalGroup {
  upperPush,
  upperPull,
  lowerBody,
  coreStability,
}

const Map<FunctionalGroup, List<Muscle>> functionalGroups = {
  FunctionalGroup.upperPush: [
    Muscle.chest,
    Muscle.upperChest,
    Muscle.frontDelts,
    Muscle.midDelts,
    Muscle.triceps,
  ],
  FunctionalGroup.upperPull: [
    Muscle.lats,
    Muscle.rombs,
    Muscle.midBack,
    Muscle.trapsUpper,
    Muscle.lowerTraps,
    Muscle.rearDelts,
    Muscle.biceps,
    Muscle.forearms,

  ],

  FunctionalGroup.lowerBody: [
    Muscle.quads,
    Muscle.hamstrings,
    Muscle.glutes,
    Muscle.midGlutes,
    Muscle.calves,
    Muscle.adductors
  ],
  FunctionalGroup.coreStability: [
    Muscle.abs,
    Muscle.lowerAbs,
    Muscle.obliques,
    Muscle.psoas,
    Muscle.lowerBack,
      Muscle.serratus,
  ],
};


extension AnatomicalGroupLabel on AnatomicalGroup {
  String get label {
    switch (this) {
      case AnatomicalGroup.hombros:
        return "Hombros";
      case AnatomicalGroup.pecho:
        return "Pecho";
      case AnatomicalGroup.espalda:
        return "Espalda";
      case AnatomicalGroup.piernas:
        return "Piernas";
      case AnatomicalGroup.core:
        return "Core";
      case AnatomicalGroup.brazos:
        return "Brazos";
    }
  }
}

extension FunctionalGroupLabel on FunctionalGroup {
  String get label {
    switch (this) {
      case FunctionalGroup.upperPush:
        return "Empuje superior";
      case FunctionalGroup.upperPull:
        return "Tirones superior";
      case FunctionalGroup.lowerBody:
        return "Piernas";
      case FunctionalGroup.coreStability:
        return "Core / Estabilidad";
    }
  }
}

// ======================================================
// ⏳ FACTORES DE RECUPERACIÓN POR MÚSCULO
// ======================================================
extension MuscleRecovery on Muscle {
  double get recoveryFactor {
    switch (this) {
      // 1. Muy rápido (0.55)
      case Muscle.calves:
      case Muscle.forearms:
      case Muscle.abs:
      case Muscle.lowerAbs:
      case Muscle.obliques:
      case Muscle.midDelts:
      case Muscle.rearDelts:
      case Muscle.biceps:
        return 0.6;

      // 2. Rápido (0.65)
      case Muscle.triceps:
      case Muscle.frontDelts:
      case Muscle.trapsUpper:
      case Muscle.lowerTraps:
      case Muscle.serratus:
      case Muscle.psoas:
        return 0.65;

      // 3. Estándar torso (0.72)
      case Muscle.upperChest:
      case Muscle.lats:
      case Muscle.midBack:
      case Muscle.rombs:
      case Muscle.lowerBack:
        return 0.7;

      // 4. Lento sistémico piernas/lumbares (0.80)
      case Muscle.quads:
      case Muscle.chest:
      case Muscle.hamstrings:
      case Muscle.glutes:
      case Muscle.midGlutes:
      case Muscle.adductors:
        return 0.75;
    }
  }
}
