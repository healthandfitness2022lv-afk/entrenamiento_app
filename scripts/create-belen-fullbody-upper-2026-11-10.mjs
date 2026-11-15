import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const dryRun = process.argv.includes('--dry-run');
const now = new Date().toISOString();
const date = '2026-11-10T03:00:00Z';
const blockId = 'belen_trigo_fullbody_torso_2026_11_10';
const plannedId = 'belen_trigo_fullbody_torso_2026_11_10';

const b64 = (value) => Buffer.from(value).toString('base64url');
async function accessToken() {
  const issuedAt = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({ iss: credentials.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: credentials.token_uri, iat: issuedAt, exp: issuedAt + 3600 }))}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(credentials.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(credentials.private_key))}` }) });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
}
function decode(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  throw new Error('Tipo Firestore no soportado');
}
function value(data) {
  if (data === null) return { nullValue: null };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data) ? { integerValue: String(data) } : { doubleValue: data };
  if (typeof data === 'string') return { stringValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)])) } };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)]));
const name = (collection, id) => `projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
async function getDoc(token, collection, id) {
  const response = await fetch(`${base}/${collection}/${id}`, { headers: { Authorization: `Bearer ${token}` } });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${collection}/${id} ${response.status}: ${await response.text()}`);
  return Object.fromEntries(Object.entries((await response.json()).fields ?? {}).map(([key, item]) => [key, decode(item)]));
}

const token = await accessToken();
const [existingBlock, existingPlanned, upperSource, hingeSource, lowerSource] = await Promise.all([
  getDoc(token, 'blocks', blockId),
  getDoc(token, 'planned_workouts', plannedId),
  getDoc(token, 'blocks', 'belen_trigo_d3_musculacion_2026_10_29'),
  getDoc(token, 'blocks', 'belen_trigo_d2_musculacion_2026_11_03'),
  getDoc(token, 'blocks', 'belen_trigo_d4_musculacion_2026_11_01'),
]);
if (existingBlock || existingPlanned) throw new Error(`Ya existe la planificación de Belén para ${date.slice(0, 10)}.`);
if (!upperSource || !hingeSource || !lowerSource) throw new Error('Falta un bloque fuente para crear la sesión.');

const sourceExercises = [...upperSource.exercises, ...hingeSource.exercises, ...lowerSource.exercises];
const plan = [
  ['Press Banca inclinado DB', 3, 10, 12.5, '12,5 kg por mano. Venía de 10-12 reps a RPE 8-9; hoy dejar 1-2 reps en reserva. Escápulas atrás y abajo.'],
  ['Remo - Barra', 4, 10, 30, '30 kg. El último 4×10 fue RPE 8: repetir limpio, pausa breve arriba y torso firme.'],
  ['Press De Hombro - Landmine half kneeling', 3, 8, 27.5, '27,5 kg por lado. Controlar el rango y mantener el glúteo de la rodilla apoyada firme; sin arco lumbar.'],
  ['Sentadilla Bulgara - Mancuernas', 3, 8, 7.5, '7,5 kg por mano, 8 reps por pierna. Pierna de apoyo estable y bajar con control.'],
  ['Peso Muerto - Rumano con barra', 3, 6, 55, '55 kg. El 57,5×8 fue RPE 8-9; hoy baja volumen para priorizar técnica: barra cerca y espalda neutra.'],
  ['Elevacion Lateral - Mancuernas', 3, 12, 5, '5 kg por mano. Sin impulso y con 2 s de bajada; detener si se encogen los hombros.'],
  ['Leñador', 3, 10, 12.5, '12,5 kg por lado. Cadera y tronco rotan controlados; brazos largos y sin compensar con la zona lumbar.'],
];
const exercises = plan.map(([exerciseName, series, reps, weight, notes]) => {
  const found = sourceExercises.find((exercise) => exercise.name === exerciseName);
  if (!found) throw new Error(`No encontré ${exerciseName} en los bloques fuente.`);
  const { instanceId, durationMinutes, ...rest } = found;
  return { ...rest, series, reps, value: reps, weight, notes };
});

const { createdAt, updatedAt, libraryOrder, ...sourceRest } = upperSource;
const block = {
  ...sourceRest,
  athleteId,
  folder: 'BELEN',
  isLibraryTemplate: true,
  title: 'FULL BODY · ÉNFASIS TORSO',
  description: 'Mar 10-11. Full body con predominio de empuje/tirón de tren superior y todo con peso libre. Descansos: 90 s en press, remo, búlgara y rumano; 45-60 s en laterales y leñador.',
  exercises,
  createdAt: now,
  updatedAt: now,
  libraryOrder: Date.now(),
};
const planned = {
  athleteId,
  athleteName: 'Belén Trigo',
  blockId,
  blockTitle: block.title,
  date,
  day: 1,
  week: 8,
  order: 0,
  status: 'planned',
  createdAt: now,
  blockUpdatedAt: now,
};

console.log(JSON.stringify({ dryRun, date: date.slice(0, 10), title: block.title, exercises: exercises.map((exercise) => ({ name: exercise.name, series: exercise.series, reps: exercise.reps, weight: exercise.weight })) }, null, 2));
if (dryRun) process.exit(0);

const response = await fetch(`${base}:commit`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes: [
  { update: { name: name('blocks', blockId), fields: fields(block) }, currentDocument: { exists: false } },
  { update: { name: name('planned_workouts', plannedId), fields: fields(planned) }, currentDocument: { exists: false } },
] }) });
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log('OK: entrenamiento cargado.');
