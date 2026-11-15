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

const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const athleteName = 'Belén Trigo';
const blockId = 'belen_trigo_d3_musculacion_2026_09_23';
const plannedId = 'belen_trigo_d3_2026_09_23';
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
    name: 'Press Banca inclinado DB', exerciseId: 'xVUHkvMloZM5TMQQ5UrA', movementId: 'xVUHkvMloZM5TMQQ5UrA',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', resistanceType: 'free',
    equipment: 'Mancuernas', series: 3, reps: 10, value: 10, weight: 7.5, perSide: true,
  }),
  exercise({
    name: 'Remo - Pecho apoyado', exerciseId: 'movement_remo', movementId: 'movement_remo',
    variantId: 'pecho_apoyado', variantLabel: 'Pecho apoyado', techniqueId: 'pecho_apoyado', resistanceType: 'free',
    equipment: 'Remo pecho apoyado, Mancuernas, Banco inclinado', series: 4, reps: 10, value: 10, weight: 10, perSide: true,
  }),
  exercise({
    name: 'Jalon Al Pecho - Polea baja, agarre cerrado', exerciseId: 'movement_jalon_al_pecho', movementId: 'movement_jalon_al_pecho',
    variantId: 'polea_baja_agarre_cerrado', variantLabel: 'Polea baja, agarre cerrado', techniqueId: 'polea_baja_agarre_cerrado', resistanceType: 'guided',
    equipment: 'Polea baja', series: 3, reps: 10, value: 10, weight: 25, perSide: false,
  }),
  exercise({
    name: 'Elevacion Lateral - Mancuernas', exerciseId: 'movement_elevacion_lateral', movementId: 'movement_elevacion_lateral',
    variantId: 'mancuernas', variantLabel: 'Mancuernas', techniqueId: 'mancuernas', resistanceType: 'free',
    equipment: 'Mancuernas', series: 3, reps: 15, value: 15, weight: 5, perSide: true,
  }),
  exercise({
    name: 'Face Pull - Cuerda en polea', exerciseId: 'movement_face_pull_cuerda_en_polea', movementId: 'movement_face_pull_cuerda_en_polea',
    variantId: 'original', variantLabel: 'Face pull con cuerda', techniqueId: 'original', resistanceType: 'guided',
    equipment: 'Polea alta, Cuerda', series: 3, reps: 15, value: 15, weight: 15, perSide: false,
  }),
  exercise({
    name: 'Press Pallof - Polea', exerciseId: 'NhKDOyUbYVtdr2AD5jLe', movementId: 'NhKDOyUbYVtdr2AD5jLe',
    variantId: 'cable', variantLabel: 'Polea', techniqueId: 'standing', resistanceType: 'guided',
    equipment: 'Polea ajustable', series: 3, reps: 10, value: 10, weight: 10, perSide: true,
  }),
  exercise({
    name: 'Trote - Caminadora', exerciseId: 'movement_trote', movementId: 'movement_trote',
    variantId: 'caminadora', variantLabel: 'Caminadora', techniqueId: 'caminadora', resistanceType: 'bodyweight',
    equipment: 'Caminadora', // Por tiempo: reps/value en SEGUNDOS (10 min = 600 s).
    series: 1, reps: 600, value: 600, valueType: 'time', durationMinutes: 10, weight: 1, perSide: false,
  }),
];

const block = {
  isLibraryTemplate: true,
  title: 'MUSCULACION 3',
  athleteId,
  folder: 'BELEN',
  type: 'Series',
  description: 'Trote en caminadora: 10 minutos al finalizar. El atleta registra el RPE durante la sesión.',
  exercises: blockExercises,
  createdAt: now,
  updatedAt: now,
  libraryOrder: Date.now(),
};

const cardioExercise = {
  name: 'Trote',
  movementName: 'Trote',
  exerciseId: 'movement_trote',
  movementId: 'movement_trote',
  variantId: 'caminadora',
  variantLabel: 'Caminadora',
  techniqueId: 'caminadora',
  resistanceType: 'bodyweight',
  exerciseType: 'Cardio',
  trainingDiscipline: 'acondicionamiento',
  group: 'Cardio',
  equipment: ['Caminadora'],
  trackRM: false,
  trackProgression: false,
  variants: [{
    id: 'caminadora', label: 'Caminadora', techniqueLabel: 'Caminadora', techniqueId: 'caminadora',
    resistanceType: 'bodyweight', equipment: ['Caminadora'], isUnilateral: false, trackRM: false, trackProgression: false,
  }],
  instructions: 'Trote continuo en caminadora durante 10 minutos a intensidad suave o moderada.',
};

const planned = {
  athleteId,
  athleteName,
  blockId,
  blockTitle: 'MUSCULACION 3',
  date: '2026-09-23T03:00:00Z',
  day: 3,
  week: 1,
  order: 0,
  status: 'planned',
  createdAt: now,
  blockUpdatedAt: now,
};

const token = await accessToken();
const writes = [
  { update: { name: documentName('exercises', 'movement_trote'), fields: fields(cardioExercise) } },
  { update: { name: documentName('blocks', blockId), fields: fields(block) } },
  { update: { name: documentName('planned_workouts', plannedId), fields: fields(planned) } },
];

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents:commit`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ athlete: athleteName, blockId, plannedId, date: planned.date, exercises: blockExercises.map((item) => ({ name: item.name, variant: item.variantLabel, weight: item.weight, perSide: item.perSide, series: item.series, repsOrMinutes: item.reps })) }, null, 2));
