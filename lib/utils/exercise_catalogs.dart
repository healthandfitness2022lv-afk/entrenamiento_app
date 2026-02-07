const List<String> muscleCatalog = [
  "Cuádriceps",
  "Isquiotibiales",
  "Glúteos",
  "Pectorales",
  "Dorsales",
  "Bíceps",
  "Tríceps",
  "Hombros",
  "Abdominales",
  "Oblícuos",
  "Lumbares",
  "Manguito rotador",
  "Pantorrillas",
  "Antebrazos",
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
  "Cardio",
  "Metabólico",
  "Técnica",
  "Movilidad",
  "Pliometría",
  "Isometría",
  "Calistenia"
];

const Map<String, double> exerciseTypeFactor = {
  "Fuerza": 1.3,
  "weightlifting": 1.25,
  "Hipertrofia": 1.1,
  "Potencia": 0.95,
  "Pliometría": 0.7,
  "Metabólico": 1.0,
  "Cardio": 0.5,
  "Calistenia": 1.0,
  "Isometría": 0.6,
  "Técnica": 0.4,
  "Movilidad": 0.35,
};

double exerciseTypeFactorOf(String? type) {
  return exerciseTypeFactor[type] ?? 1.0;
}