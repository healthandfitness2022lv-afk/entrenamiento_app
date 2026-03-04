const List<String> muscleCatalog = [
  // Tren inferior
  "Cuádriceps",
  "Isquiotibiales",
  "Glúteos",
  "Aductores",
  "Pantorrillas",

  // Pecho
  "Pectorales",
  "Pectoral superior",

  // Hombros
  "Deltoides anterior",
  "Deltoides medial",
  "Deltoide posterior",

  // Brazos
  "Bíceps",
  "Tríceps",
  "Antebrazos",

  // Espalda
  "Dorsales",
  "Redondo",
  "Romboides",
  "Trapecio superior",
  "Trapecio inferior",
  "Lumbares",

  // Core
  "Abdominales",
  "Oblícuos",
  "Flexores de cadera",

  // Estabilizadores
  "Serrato anterior",
];


const List<String> equipmentCatalog = [
  "Peso corporal",
  "Barra",
  "Mancuernas",
  "Kettlebell",
  "Caja",
  "Banda elástica",
  "Polea alta",
  "Polea baja",
  "Cuerda",
  "Balón medicinal",
  "Steps",
  "Barra fija",
  "Barra Z",
  "Paralelas",
];

const List<String> exerciseTypeCatalog = [
  "Fuerza",
  "Hipertrofia",
  "Potencia",
  "weightlifting",
  "Metabólico",
  "Cardio",
  "Movilidad",
  "Pliometría",
  "Isometría",
  "Calistenia"
];

const Map<String, double> exerciseTypeFactor = {
  "Fuerza": 1.3,
  "weightlifting": 1.45, // Subido por demanda técnica
  "Hipertrofia": 1.0,
  "Potencia": 1.15,
  "Pliometría": 0.85,
  "Metabólico": 0.9,
  "Calistenia": 1.25, // Subido según estimación (control corporal/tensión)
  "Isometría": 0.75,
  "Movilidad": 0.4,
  "Cardio": 0.35,
};

const Map<String, double> equipmentFactor = {
  "Barra": 1.2,        // Mayor demanda estabilizadora y neural
  "Mancuernas": 1.1,
  "Kettlebell": 1.1,
  "Paralelas": 1.1,
  "Barra fija": 1.1,
  "Polea alta": 0.9,   // Guía de movimiento reduce carga estabilizadora
  "Polea baja": 0.9,
  "Polea": 0.9,
  "Cuerda": 0.85,
  "Máquina": 0.8,
  "Peso corporal": 1.0,
};

double equipmentFactorOf(dynamic equipment) {
  if (equipment == null) return 1.0;
  
  if (equipment is List) {
    if (equipment.isEmpty) return 1.0;
    // Si viene como lista, tomamos el factor del equipo principal (el primero)
    final firstEq = equipment.first.toString();
    return equipmentFactor[firstEq] ?? 1.0;
  }
  
  return equipmentFactor[equipment.toString()] ?? 1.0;
}

double exerciseTypeFactorOf(String? type) {
  return exerciseTypeFactor[type] ?? 1.0;
}