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
  "weightlifting": 1.2,
  "Hipertrofia": 1.05,
  "Potencia": 0.95,
  "Pliometría": 0.75,
  "Metabólico": 0.9,
  "Calistenia": 1.0,
  "Isometría": 0.7,
  "Movilidad": 0.35,
  "Cardio": 0.4,
};

double exerciseTypeFactorOf(String? type) {
  return exerciseTypeFactor[type] ?? 1.0;
}