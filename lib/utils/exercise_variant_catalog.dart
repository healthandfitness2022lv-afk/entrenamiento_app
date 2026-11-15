import '../models/exercise.dart';

const variantGroups = <String>[
  'Peso libre',
  'Máquina',
  'Polea',
  'Banda',
  'Peso corporal',
];

ExerciseVariant variantPreset(
  String id,
  String label,
  String group,
  List<String> equipment, {
  bool trackRM = true,
  bool unilateral = false,
  String trainingDiscipline = 'fuerza',
  String movementIntent = 'full',
  String familyId = '',
  String techniqueId = '',
  String techniqueLabel = '',
}) => ExerciseVariant(
  id: id,
  label: label,
  group: group,
  equipment: equipment,
  resistanceType: switch (group) {
    'Máquina' || 'Polea' => 'guided',
    'Peso corporal' => 'bodyweight',
    _ => 'free',
  },
  trackRM: trackRM,
  trainingDiscipline: trainingDiscipline,
  movementIntent: movementIntent,
  familyId: familyId,
  techniqueId: techniqueId,
  techniqueLabel: techniqueLabel,
  isUnilateral: unilateral,
);

final Map<String, List<ExerciseVariant>> commonMovementVariants = {
  'sentadilla': [
    variantPreset('barbell_back', 'Barra trasera', 'Peso libre', [
      'Barra',
      'Rack',
    ]),
    variantPreset('barbell_front', 'Barra frontal', 'Peso libre', [
      'Barra',
      'Rack',
    ]),
    variantPreset('safety_bar', 'Safety bar', 'Peso libre', [
      'Safety bar',
      'Rack',
    ]),
    variantPreset('goblet_dumbbell', 'Goblet con mancuerna', 'Peso libre', [
      'Mancuerna',
    ]),
    variantPreset('goblet_kettlebell', 'Goblet con kettlebell', 'Peso libre', [
      'Kettlebell',
    ]),
    variantPreset('smith', 'Máquina Smith', 'Máquina', ['Máquina Smith']),
    variantPreset('hack', 'Hack squat', 'Máquina', ['Hack squat']),
    variantPreset('pendulum', 'Sentadilla pendular', 'Máquina', [
      'Sentadilla pendular',
    ]),
    variantPreset('belt_squat', 'Belt squat', 'Máquina', ['Belt squat']),
    variantPreset('landmine', 'Landmine', 'Peso libre', ['Landmine', 'Barra']),
    variantPreset('bodyweight', 'Peso corporal', 'Peso corporal', [
      'Peso corporal',
    ], trackRM: false),
  ],
  'press de pecho': [
    variantPreset('barbell_flat', 'Barra en banco plano', 'Peso libre', [
      'Barra',
      'Banco',
    ]),
    variantPreset('dumbbell_flat', 'Mancuernas en banco plano', 'Peso libre', [
      'Mancuernas',
      'Banco',
    ]),
    variantPreset('smith_flat', 'Smith en banco plano', 'Máquina', [
      'Máquina Smith',
      'Banco',
    ]),
    variantPreset('selectorized', 'Máquina selectorizada', 'Máquina', [
      'Press de pecho selectorizado',
    ]),
    variantPreset('plate_loaded', 'Máquina con discos', 'Máquina', [
      'Press de pecho con discos',
    ]),
    variantPreset('cable', 'Poleas', 'Polea', ['Polea doble']),
  ],
  'remo': [
    variantPreset('barbell', 'Barra', 'Peso libre', ['Barra']),
    variantPreset('dumbbell', 'Mancuerna unilateral', 'Peso libre', [
      'Mancuerna',
    ], unilateral: true),
    variantPreset('chest_supported', 'Pecho apoyado', 'Máquina', [
      'Remo pecho apoyado',
    ]),
    variantPreset('seated_machine', 'Máquina sentada', 'Máquina', [
      'Remo sentado',
    ]),
    variantPreset('low_cable', 'Polea baja', 'Polea', ['Polea baja']),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
  ],
  'peso muerto': [
    variantPreset(
      'conventional_barbell',
      'Convencional con barra',
      'Peso libre',
      ['Barra'],
    ),
    variantPreset('romanian_barbell', 'Rumano con barra', 'Peso libre', [
      'Barra',
    ]),
    variantPreset('romanian_dumbbell', 'Rumano con mancuernas', 'Peso libre', [
      'Mancuernas',
    ]),
    variantPreset('trap_bar', 'Trap bar', 'Peso libre', ['Trap bar']),
    variantPreset('smith', 'Smith', 'Máquina', ['Máquina Smith']),
    variantPreset('cable', 'Polea baja', 'Polea', ['Polea baja']),
  ],
  'curl femoral': [
    variantPreset('lying', 'Máquina tumbado', 'Máquina', [
      'Curl femoral tumbado',
    ]),
    variantPreset('seated', 'Máquina sentado', 'Máquina', [
      'Curl femoral sentado',
    ]),
    variantPreset('standing', 'Máquina de pie', 'Máquina', [
      'Curl femoral de pie',
    ], unilateral: true),
    variantPreset('cable', 'Polea baja', 'Polea', [
      'Polea baja',
    ], unilateral: true),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
    variantPreset('slider', 'Deslizadores', 'Peso corporal', [
      'Deslizadores',
    ], trackRM: false),
  ],
  'press de hombro': [
    variantPreset('barbell', 'Barra', 'Peso libre', ['Barra']),
    variantPreset('dumbbell', 'Mancuernas', 'Peso libre', ['Mancuernas']),
    variantPreset('kettlebell', 'Kettlebells', 'Peso libre', ['Kettlebells']),
    variantPreset('smith', 'Smith', 'Máquina', ['Máquina Smith']),
    variantPreset('selectorized', 'Máquina selectorizada', 'Máquina', [
      'Press de hombro selectorizado',
    ]),
    variantPreset('landmine', 'Landmine unilateral', 'Peso libre', [
      'Landmine',
    ], unilateral: true),
  ],
  'jalon al pecho': [
    variantPreset('wide', 'Agarre ancho', 'Polea', ['Polea alta']),
    variantPreset('neutral', 'Agarre neutro', 'Polea', ['Polea alta']),
    variantPreset('single_arm', 'Unilateral', 'Polea', [
      'Polea alta',
    ], unilateral: true),
    variantPreset('plate_loaded', 'Máquina con discos', 'Máquina', [
      'Jalón con discos',
    ]),
  ],
  'extension de cuadriceps': [
    variantPreset('bilateral', 'Bilateral en máquina', 'Máquina', [
      'Extensión de cuádriceps',
    ]),
    variantPreset('unilateral', 'Unilateral en máquina', 'Máquina', [
      'Extensión de cuádriceps',
    ], unilateral: true),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
  ],
  'landmine press': [
    variantPreset('bilateral', 'Bilateral', 'Peso libre', [
      'Landmine',
      'Barra',
    ]),
    variantPreset('unilateral', 'Unilateral', 'Peso libre', [
      'Landmine',
      'Barra',
    ], unilateral: true),
    variantPreset('explosive', 'Explosivo', 'Peso libre', [
      'Landmine',
      'Barra',
    ], unilateral: true),
  ],
  'curl de biceps': [
    variantPreset('straight_bar', 'Barra recta', 'Peso libre', ['Barra']),
    variantPreset('ez_bar', 'Barra Z', 'Peso libre', ['Barra Z']),
    variantPreset('dumbbells', 'Mancuernas', 'Peso libre', ['Mancuernas']),
    variantPreset('preacher_machine', 'Máquina predicador', 'Máquina', [
      'Curl de bíceps selectorizado',
    ]),
    variantPreset('low_cable', 'Polea baja', 'Polea', ['Polea baja']),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
  ],
  'extension de triceps': [
    variantPreset('ez_bar_lying', 'Barra Z acostado', 'Peso libre', [
      'Barra Z',
      'Banco',
    ]),
    variantPreset('dumbbell_overhead', 'Mancuerna sobre cabeza', 'Peso libre', [
      'Mancuerna',
    ]),
    variantPreset('cable_rope', 'Cuerda en polea', 'Polea', [
      'Polea alta',
      'Cuerda',
    ]),
    variantPreset('cable_bar', 'Barra en polea', 'Polea', [
      'Polea alta',
      'Barra de polea',
    ]),
    variantPreset('machine', 'Máquina selectorizada', 'Máquina', [
      'Extensión de tríceps selectorizada',
    ]),
  ],
  'elevacion lateral': [
    variantPreset('dumbbells', 'Mancuernas', 'Peso libre', ['Mancuernas']),
    variantPreset('single_cable', 'Polea unilateral', 'Polea', [
      'Polea baja',
    ], unilateral: true),
    variantPreset('dual_cable', 'Polea bilateral', 'Polea', ['Polea doble']),
    variantPreset('machine', 'Máquina selectorizada', 'Máquina', [
      'Elevación lateral selectorizada',
    ]),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
  ],
  'estocada': [
    variantPreset(
      'bodyweight',
      'Peso corporal',
      'Peso corporal',
      ['Peso corporal'],
      trackRM: false,
      unilateral: true,
    ),
    variantPreset('dumbbells', 'Mancuernas', 'Peso libre', [
      'Mancuernas',
    ], unilateral: true),
    variantPreset('kettlebells', 'Kettlebells', 'Peso libre', [
      'Kettlebells',
    ], unilateral: true),
    variantPreset('barbell', 'Barra', 'Peso libre', [
      'Barra',
      'Rack',
    ], unilateral: true),
    variantPreset('smith', 'Máquina Smith', 'Máquina', [
      'Máquina Smith',
    ], unilateral: true),
    variantPreset('landmine', 'Landmine', 'Peso libre', [
      'Landmine',
      'Barra',
    ], unilateral: true),
    variantPreset('cable', 'Polea baja', 'Polea', [
      'Polea baja',
    ], unilateral: true),
  ],
  'hip thrust': [
    variantPreset('barbell', 'Barra', 'Peso libre', ['Barra', 'Banco']),
    variantPreset('dumbbell', 'Mancuerna', 'Peso libre', [
      'Mancuerna',
      'Banco',
    ]),
    variantPreset('smith', 'Máquina Smith', 'Máquina', [
      'Máquina Smith',
      'Banco',
    ]),
    variantPreset('plate_loaded', 'Máquina con discos', 'Máquina', [
      'Hip thrust con discos',
    ]),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
  ],
  'dominada': [
    variantPreset('pronated', 'Agarre prono', 'Peso corporal', [
      'Barra fija',
    ], trackRM: false),
    variantPreset('supinated', 'Agarre supino', 'Peso corporal', [
      'Barra fija',
    ], trackRM: false),
    variantPreset('neutral', 'Agarre neutro', 'Peso corporal', [
      'Barra fija',
    ], trackRM: false),
    variantPreset('assisted', 'Máquina asistida', 'Máquina', [
      'Máquina de dominadas asistidas',
    ]),
    variantPreset('weighted', 'Lastrada', 'Peso libre', [
      'Barra fija',
      'Cinturón de lastre',
    ]),
  ],
  'flexion de brazos': [
    variantPreset('standard', 'Estándar', 'Peso corporal', [
      'Peso corporal',
    ], trackRM: false),
    variantPreset('kneeling', 'Con rodillas apoyadas', 'Peso corporal', [
      'Peso corporal',
    ], trackRM: false),
    variantPreset('incline', 'Inclinada', 'Peso corporal', [
      'Banco',
    ], trackRM: false),
    variantPreset('decline', 'Declinada', 'Peso corporal', [
      'Banco',
    ], trackRM: false),
    variantPreset('band', 'Con banda', 'Banda', ['Banda elástica']),
    variantPreset('weighted', 'Lastrada', 'Peso libre', ['Disco']),
  ],
  'step up': [
    variantPreset(
      'bodyweight',
      'Peso corporal',
      'Peso corporal',
      ['Caja'],
      trackRM: false,
      unilateral: true,
    ),
    variantPreset('dumbbells', 'Mancuernas', 'Peso libre', [
      'Mancuernas',
      'Caja',
    ], unilateral: true),
    variantPreset('kettlebells', 'Kettlebells', 'Peso libre', [
      'Kettlebells',
      'Caja',
    ], unilateral: true),
    variantPreset('barbell', 'Barra', 'Peso libre', [
      'Barra',
      'Caja',
    ], unilateral: true),
    variantPreset('smith', 'Máquina Smith', 'Máquina', [
      'Máquina Smith',
      'Caja',
    ], unilateral: true),
  ],
  'press pallof': [
    variantPreset(
      'cable',
      'Polea',
      'Polea',
      ['Polea ajustable'],
      trackRM: false,
      unilateral: true,
      trainingDiscipline: 'correctivos',
      movementIntent: 'stability',
      familyId: 'anti_rotation',
      techniqueId: 'standing',
      techniqueLabel: 'Antirotación de pie',
    ),
    variantPreset(
      'band',
      'Banda elástica',
      'Banda',
      ['Banda elástica'],
      trackRM: false,
      unilateral: true,
      trainingDiscipline: 'correctivos',
      movementIntent: 'stability',
      familyId: 'anti_rotation',
      techniqueId: 'standing',
      techniqueLabel: 'Antirotación de pie',
    ),
    variantPreset(
      'cable_kneeling',
      'Polea de rodillas',
      'Polea',
      ['Polea ajustable'],
      trackRM: false,
      unilateral: true,
      trainingDiscipline: 'correctivos',
      movementIntent: 'stability',
      familyId: 'anti_rotation',
      techniqueId: 'kneeling',
      techniqueLabel: 'Antirotación de rodillas',
    ),
  ],
  'pullover': [
    variantPreset('dumbbell', 'Mancuerna', 'Peso libre', [
      'Mancuerna',
      'Banco',
    ]),
    variantPreset('ez_bar', 'Barra Z', 'Peso libre', ['Barra Z', 'Banco']),
    variantPreset('cable', 'Polea alta', 'Polea', ['Polea alta']),
    variantPreset('machine', 'Máquina selectorizada', 'Máquina', [
      'Pullover selectorizado',
    ]),
  ],
  'face pull': [
    variantPreset('rope', 'Cuerda en polea', 'Polea', ['Polea alta', 'Cuerda']),
    variantPreset('dual_handle', 'Doble maneral', 'Polea', ['Polea doble']),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
  ],
  'elevacion de pantorrillas': [
    variantPreset('standing_machine', 'Máquina de pie', 'Máquina', [
      'Pantorrilla de pie selectorizada',
    ]),
    variantPreset('seated_machine', 'Máquina sentado', 'Máquina', [
      'Pantorrilla sentada',
    ]),
    variantPreset('leg_press', 'En prensa', 'Máquina', ['Prensa de piernas']),
    variantPreset('smith', 'Máquina Smith', 'Máquina', ['Máquina Smith']),
    variantPreset('bodyweight', 'Peso corporal', 'Peso corporal', [
      'Step',
    ], trackRM: false),
  ],
  'sentadilla bulgara': [
    variantPreset(
      'bodyweight',
      'Peso corporal',
      'Peso corporal',
      ['Banco'],
      trackRM: false,
      unilateral: true,
    ),
    variantPreset('dumbbells', 'Mancuernas', 'Peso libre', [
      'Mancuernas',
      'Banco',
    ], unilateral: true),
    variantPreset('kettlebells', 'Kettlebells', 'Peso libre', [
      'Kettlebells',
      'Banco',
    ], unilateral: true),
    variantPreset('barbell', 'Barra', 'Peso libre', [
      'Barra',
      'Rack',
      'Banco',
    ], unilateral: true),
    variantPreset('smith', 'Máquina Smith', 'Máquina', [
      'Máquina Smith',
      'Banco',
    ], unilateral: true),
  ],
  'elevacion frontal': [
    variantPreset('dumbbells', 'Mancuernas', 'Peso libre', ['Mancuernas']),
    variantPreset('plate', 'Disco', 'Peso libre', ['Disco']),
    variantPreset('barbell', 'Barra', 'Peso libre', ['Barra']),
    variantPreset('cable', 'Polea baja', 'Polea', ['Polea baja']),
    variantPreset('band', 'Banda elástica', 'Banda', [
      'Banda elástica',
    ], trackRM: false),
  ],
  'russian twist': [
    variantPreset('bodyweight', 'Peso corporal', 'Peso corporal', [
      'Peso corporal',
    ], trackRM: false),
    variantPreset('medicine_ball', 'Balón medicinal', 'Peso libre', [
      'Balón medicinal',
    ]),
    variantPreset('plate', 'Disco', 'Peso libre', ['Disco']),
    variantPreset('dumbbell', 'Mancuerna', 'Peso libre', ['Mancuerna']),
    variantPreset('cable', 'Polea', 'Polea', ['Polea ajustable']),
  ],
  'thruster': [
    variantPreset('barbell', 'Barra', 'Peso libre', ['Barra']),
    variantPreset('dumbbells', 'Mancuernas', 'Peso libre', ['Mancuernas']),
    variantPreset('kettlebells', 'Kettlebells', 'Peso libre', ['Kettlebells']),
    variantPreset('landmine', 'Landmine', 'Peso libre', ['Landmine', 'Barra']),
  ],
};
