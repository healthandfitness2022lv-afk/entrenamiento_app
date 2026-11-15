import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const now = new Date().toISOString();

function b64(value) {
  return Buffer.from(value).toString('base64url');
}

async function accessToken() {
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64(JSON.stringify({
    iss: credentials.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: credentials.token_uri,
    iat: issuedAt,
    exp: issuedAt + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const assertion = `${unsigned}.${b64(signer.sign(credentials.private_key))}`;
  const response = await fetch(credentials.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
}

function value(data) {
  if (data === null) return { nullValue: null };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data) ? { integerValue: String(data) } : { doubleValue: data };
  if (typeof data === 'string') return { stringValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)])) } };
}

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)]));
}

function documentName(collection, id) {
  return `projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
}

const withDefaults = (exercise) => ({
  ...exercise,
  displayName: exercise.name,
  value: exercise.reps,
  valueType: 'reps',
});

// Conserva exactamente el volumen de MUSCULACION 1 (series y repeticiones).
// Las cargas salen de las series realmente realizadas la semana pasada:
// 50x8 RPE 8 en sentadilla; 40x12 RPE 8 en hip thrust; 30x12 RPE 8 en jalón;
// 16x10 RPE 9 en curl; 15x12 RPE 8 en tríceps en polea.
const exercises = [
  withDefaults({
    name: 'Sentadilla - Barra trasera', exerciseId: 'movement_sentadilla', movementId: 'movement_sentadilla', movementName: 'Sentadilla',
    familyId: 'squat', variantId: 'barbell_back', variantLabel: 'Barra trasera', techniqueId: 'barbell_back', techniqueLabel: 'Barra trasera',
    exerciseType: 'Fuerza', trainingDiscipline: 'fuerza', movementIntent: 'full', resistanceType: 'free', equipment: 'Barra, Rack',
    series: 4, reps: 8, weight: 50, perSide: false, isUnilateral: false, trackRM: true, trackProgression: true,
    notes: '50 kg: carga confirmada a 8 reps y RPE 8 en las dos últimas series de la semana pasada.',
  }),
  withDefaults({
    name: 'Hip Thrust - Máquina con discos', exerciseId: 'movement_hip_thrust', movementId: 'movement_hip_thrust', movementName: 'Hip Thrust',
    familyId: 'hip_thrust', variantId: 'maquina_con_discos', variantLabel: 'Máquina con discos', techniqueId: 'maquina_con_discos', techniqueLabel: 'Máquina con discos',
    exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia', movementIntent: 'full', resistanceType: 'guided', equipment: 'Hip thrust con discos',
    series: 3, reps: 12, weight: 40, perSide: false, isUnilateral: false, trackRM: true, trackProgression: false,
    notes: '40 kg: 2×12 a RPE 8 la semana pasada. No usar 50 kg: se alcanzó RPE 10 a 8 reps.',
  }),
  withDefaults({
    name: 'Press De Pecho - Barra en banco plano', exerciseId: 'movement_press_de_pecho', movementId: 'movement_press_de_pecho', movementName: 'Press De Pecho',
    familyId: 'chest_press', variantId: 'barra_en_banco_plano', variantLabel: 'Barra en banco plano', techniqueId: 'barra_en_banco_plano', techniqueLabel: 'Barra en banco plano',
    exerciseType: 'Fuerza', trainingDiscipline: 'fuerza', movementIntent: 'full', resistanceType: 'free', equipment: 'Barra, Banco, Banco plano',
    series: 3, reps: 8, weight: 22.5, perSide: false, isUnilateral: false, trackRM: true, trackProgression: false,
    notes: '22,5 kg: progresión desde 20 kg × 12 a RPE 7; 23 kg × 10 llegó a RPE 9.',
  }),
  withDefaults({
    name: 'Jalon Al Pecho - Agarre ancho', exerciseId: 'movement_jalon_al_pecho', movementId: 'movement_jalon_al_pecho', movementName: 'Jalon Al Pecho',
    familyId: 'jalon_al_pecho', variantId: 'agarre_ancho', variantLabel: 'Agarre ancho', techniqueId: 'agarre_ancho', techniqueLabel: 'Agarre ancho',
    exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia', movementIntent: 'full', resistanceType: 'guided', equipment: 'Polea alta',
    series: 3, reps: 12, weight: 30, perSide: false, isUnilateral: false, trackRM: true, trackProgression: false,
    notes: '30 kg: 2×12 a RPE 8 la semana pasada.',
  }),
  withDefaults({
    name: 'Curl De Biceps - Barra Z', exerciseId: 'movement_curl_de_biceps', movementId: 'movement_curl_de_biceps', movementName: 'Curl De Biceps',
    familyId: 'biceps_curl', variantId: 'barra_z', variantLabel: 'Barra Z', techniqueId: 'barra_z', techniqueLabel: 'Barra Z',
    exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', resistanceType: 'free', equipment: 'Barra Z',
    series: 3, reps: 12, weight: 14, perSide: false, isUnilateral: false, trackRM: true, trackProgression: false,
    notes: '14 kg: ajuste para mantener 12 reps, tras 16 kg × 10 a RPE 8-9 la semana pasada.',
  }),
  withDefaults({
    name: 'Extension De Triceps - Cuerda en polea', exerciseId: 'movement_extension_de_triceps', movementId: 'movement_extension_de_triceps', movementName: 'Extension De Triceps',
    familyId: 'triceps_extension', variantId: 'cuerda_en_polea', variantLabel: 'Cuerda en polea', techniqueId: 'cuerda_en_polea', techniqueLabel: 'Cuerda en polea',
    exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', resistanceType: 'guided', equipment: 'Polea alta, Cuerda',
    series: 3, reps: 15, weight: 12.5, perSide: false, isUnilateral: false, trackRM: true, trackProgression: false,
    notes: '12,5 kg: ajuste para 15 reps, usando como referencia 15 kg × 12 a RPE 8 de la semana pasada.',
  }),
];

const blockId = 'belen_trigo_d1_musculacion_2026_09_28';
const plannedId = 'belen_trigo_d1_2026_09_28';
const block = {
  athleteId, folder: 'BELEN', isLibraryTemplate: true, title: 'MUSCULACION 1', type: 'Series',
  description: 'Mismo número de series y repeticiones que la sesión equivalente de la semana pasada. Cargas ajustadas con las series efectivamente realizadas y su RPE.',
  exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now(),
};
const planned = {
  athleteId, athleteName: 'Belén Trigo', blockId, blockTitle: 'MUSCULACION 1',
  date: '2026-09-28T03:00:00Z', day: 1, week: 2, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now,
};

const token = await accessToken();
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ writes: [
    { update: { name: documentName('blocks', blockId), fields: fields(block) } },
    { update: { name: documentName('planned_workouts', plannedId), fields: fields(planned) } },
  ] }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ blockId, plannedId, date: planned.date, loads: exercises.map(({ name, series, reps, weight }) => ({ name, series, reps, weight })) }, null, 2));
