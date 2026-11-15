import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const databaseId = '(default)';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));

function b64(value) {
  return Buffer.from(value).toString('base64url');
}

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64(JSON.stringify({
    iss: credentials.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: credentials.token_uri,
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const assertion = `${unsigned}.${b64(signer.sign(credentials.private_key))}`;
  const response = await fetch(credentials.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
}

function value(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map((item) => valueOf(item)) } };
  if (typeof value === 'object') {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, valueOf(v)])) } };
  }
  throw new Error(`Unsupported Firestore value: ${typeof value}`);
}

const valueOf = value;

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)]));
}

function documentName(collection, id) {
  return `projects/${projectId}/databases/${databaseId}/documents/${collection}/${id}`;
}

// Día 4 (vie 25-09): semana ya cargó deltoides, dorsales, brazos (D1-D3) e isquios/glúteo (D2).
// Cuádriceps, aductores, gemelos y core bajo son los grupos con menor fatiga -> pierna anterior + core.
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const athleteName = 'Belén Trigo';
const blockId = 'belen_trigo_d4_musculacion_2026_09_25';
const plannedId = 'belen_trigo_d4_2026_09_25';
const now = new Date().toISOString();

const exercise = (data) => ({
  ...data,
  displayName: data.name,
  valueType: data.valueType ?? 'reps',
  trackRM: false,
  trackProgression: false,
});

const blockExercises = [
  exercise({
    // D1: 40x8 @RPE 4-5, 50x8 @RPE 8 -> 45 kg para RPE ~7.
    name: 'Sentadilla - Barra trasera', exerciseId: 'movement_sentadilla', movementId: 'movement_sentadilla',
    variantId: 'barbell_back', variantLabel: 'Barra trasera', techniqueId: 'barbell_back', resistanceType: 'free',
    equipment: 'Barra, Rack', series: 4, reps: 8, value: 8, weight: 45, perSide: false,
    notes: 'RPE 7. Si 45 kg se siente RPE 6 o menos, subir a 47,5-50 kg.',
  }),
  exercise({
    name: 'Sentadilla Bulgara - Mancuernas', exerciseId: 'movement_sentadilla_bulgara', movementId: 'movement_sentadilla_bulgara',
    variantId: 'mancuernas', variantLabel: 'Mancuernas', techniqueId: 'rear_foot_elevated', resistanceType: 'free',
    equipment: 'Mancuernas, Banco', series: 3, reps: 10, value: 10, weight: 7.5, perSide: true,
  }),
  exercise({
    name: 'Extension De Cuadriceps - Bilateral en máquina', exerciseId: 'movement_extension_de_cuadriceps', movementId: 'movement_extension_de_cuadriceps',
    variantId: 'bilateral_en_maquina', variantLabel: 'Bilateral en máquina', techniqueId: 'bilateral_en_maquina', resistanceType: 'guided',
    equipment: 'Máquina de extensión de cuádriceps', series: 3, reps: 12, value: 12, weight: 20, perSide: false,
  }),
  exercise({
    name: 'Aducción de cadera - Máquina de aductores', exerciseId: 'movement_aductor_maquina_copenhagen', movementId: 'movement_aductor_maquina_copenhagen',
    variantId: 'original', variantLabel: 'Máquina de aductores', techniqueId: 'original', resistanceType: 'guided',
    equipment: 'Máquina de aductores', series: 3, reps: 15, value: 15, weight: 30, perSide: false,
  }),
  exercise({
    name: 'Rueda abdominal', exerciseId: 'Hh6KExWwZiAxNxWqOScG', movementId: 'Hh6KExWwZiAxNxWqOScG',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', resistanceType: 'bodyweight',
    equipment: 'Peso corporal, Rueda abdominal', series: 3, reps: 8, value: 8, weight: 1, perSide: false,
    notes: 'Rango que permita mantener la zona lumbar neutra. Si cuesta, de rodillas y más corta.',
  }),
  exercise({
    name: 'Bicicleta', exerciseId: 'Rru4w2BMPy1EZQkFEp1p', movementId: 'Rru4w2BMPy1EZQkFEp1p',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', resistanceType: 'guided',
    equipment: 'Bicicleta estática', // Por tiempo: reps/value en SEGUNDOS (10 min = 600 s).
    series: 1, reps: 600, value: 600, valueType: 'time', durationMinutes: 10, weight: 1, perSide: false,
    notes: 'Suave. Hacerla al final, después del Tabata de planchas.',
  }),
];

const block = {
  isLibraryTemplate: true,
  title: 'MUSCULACION 4',
  athleteId,
  folder: 'BELEN',
  type: 'Series',
  description: 'Pierna (cuádriceps/aductores) + core. Sin empujes ni tracciones de tren superior: hombros, dorsales y brazos vienen cargados de D1-D3. El atleta registra el RPE durante la sesión.',
  exercises: blockExercises,
  createdAt: now,
  updatedAt: now,
  libraryOrder: Date.now(),
};

// Tabata: el timer recorre todos los ejercicios en cada ronda (trabajo/descanso por ejercicio).
// 20/10 x 3 rondas x 3 planchas = 9 intervalos, 4,5 min.
// Los nombres deben ser distintos: el RPE del Tabata se guarda por nombre.
// Laterales: ejercicios propios del catálogo (oblicuos 0.55); las variantes
// laterales de la familia "Plancha" no tienen pesos musculares propios.
const plank = ({ name, exerciseId, movementName, variantId, variantLabel, techniqueId, isUnilateral, notes }) => ({
  name, displayName: name, movementName, exerciseId, movementId: exerciseId,
  variantId, variantLabel, techniqueId, resistanceType: 'bodyweight', equipment: 'Peso corporal',
  isUnilateral, perSide: false, weight: 1, trackRM: false, trackProgression: false, notes,
});

const tabataBlockId = 'belen_trigo_d4_tabata_planchas_2026_09_25';
const tabataPlannedId = 'belen_trigo_d4_tabata_2026_09_25';
const sidePlankNote = 'Cadera alta, cuerpo en línea, codo bajo el hombro.';
const tabataExercises = [
  plank({
    name: 'Plancha - Con antebrazos', exerciseId: 'B9wLn9cgyDHRBnpUZ5cr', movementName: 'Plancha',
    variantId: 'antebrazos_bodyweight', variantLabel: 'Con antebrazos', techniqueId: 'forearm', isUnilateral: false,
    notes: 'Glúteos y abdomen apretados, sin hundir la cadera.',
  }),
  plank({
    name: 'Plancha lateral derecha', exerciseId: '4WKbR97YKrpItGyrDZ0r', movementName: 'Plancha lateral derecha',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', isUnilateral: true, notes: sidePlankNote,
  }),
  plank({
    name: 'Plancha lateral izquierda', exerciseId: 'ukEDKOBF2eXkCjWPkjZR', movementName: 'Plancha lateral izquierda',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', isUnilateral: true, notes: sidePlankNote,
  }),
];

const tabataBlock = {
  isLibraryTemplate: true,
  title: 'TABATA PLANCHAS',
  athleteId,
  folder: 'BELEN',
  type: 'Tabata',
  work: 20,
  rest: 10,
  rounds: 3,
  description: 'Frontal (antebrazos) → lateral derecha → lateral izquierda, 20" trabajo / 10" descanso, 3 rondas (cada plancha 3 veces, 4,5 min).',
  exercises: tabataExercises,
  createdAt: now,
  updatedAt: now,
  libraryOrder: Date.now() + 1,
};

const planned = {
  athleteId,
  athleteName,
  blockId,
  blockTitle: 'MUSCULACION 4',
  date: '2026-09-25T03:00:00Z',
  day: 4,
  week: 1,
  order: 0,
  status: 'planned',
  createdAt: now,
  blockUpdatedAt: now,
};

const tabataPlanned = {
  ...planned,
  blockId: tabataBlockId,
  blockTitle: 'TABATA PLANCHAS',
  order: 1,
};

const token = await accessToken();
const writes = [
  { update: { name: documentName('blocks', blockId), fields: fields(block) } },
  { update: { name: documentName('planned_workouts', plannedId), fields: fields(planned) } },
  { update: { name: documentName('blocks', tabataBlockId), fields: fields(tabataBlock) } },
  { update: { name: documentName('planned_workouts', tabataPlannedId), fields: fields(tabataPlanned) } },
];

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents:commit`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ athlete: athleteName, blockId, plannedId, date: planned.date, exercises: blockExercises.map((item) => ({ name: item.name, weight: item.weight, perSide: item.perSide, series: item.series, repsOrSeconds: item.reps })), tabata: { tabataBlockId, tabataPlannedId, work: tabataBlock.work, rest: tabataBlock.rest, rounds: tabataBlock.rounds, exercises: tabataExercises.map((item) => item.name) } }, null, 2));
