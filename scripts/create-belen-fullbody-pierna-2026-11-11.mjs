import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const dryRun = process.argv.includes('--dry-run');
const now = new Date().toISOString();
const date = '2026-11-11T03:00:00Z';
const blockId = 'belen_trigo_fullbody_pierna_2026_11_11';
const plannedId = 'belen_trigo_fullbody_pierna_2026_11_11';

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
const [existingBlock, existingPlanned, d1Source, legSource] = await Promise.all([
  getDoc(token, 'blocks', blockId),
  getDoc(token, 'planned_workouts', plannedId),
  getDoc(token, 'blocks', 'belen_trigo_d1_musculacion_2026_10_26'),
  getDoc(token, 'blocks', 'belen_trigo_d4_musculacion_2026_11_01'),
]);
if (existingBlock || existingPlanned) throw new Error(`Ya existe la planificación de Belén para ${date.slice(0, 10)}.`);
if (!d1Source || !legSource) throw new Error('Falta un bloque fuente para crear la sesión.');

const sourceExercises = [...legSource.exercises, ...d1Source.exercises];
const plan = [
  ['Prensa De Piernas - Máquina inclinada', 4, 10, 70, '70 kg. Venía de 4×10 a RPE 8-9; hoy dejar 2 reps en reserva. Pies a la altura de los hombros y sin despegar la pelvis abajo.'],
  ['Extension De Cuadriceps - Bilateral en máquina', 3, 12, 50, '50 kg. 1 s de pausa arriba y 2 s de bajada.'],
  ['Press De Pecho - Barra en banco plano', 3, 10, 27.5, '27,5 kg. El último 3×10 fue RPE 7: repetir limpio, escápulas retraídas y bajada controlada.'],
  ['Jalon Al Pecho - Agarre ancho', 3, 10, 35, '35 kg. Tirón vertical (ayer fue horizontal). Pecho arriba y codos hacia las costillas, sin balanceo.'],
  ['Curl De Biceps - Barra Z', 3, 12, 14, '14 kg. Codos quietos y sin impulso de cadera.'],
  ['Extension De Triceps - Cuerda en polea', 3, 12, 15, '15 kg. Codos pegados y abrir la cuerda abajo.'],
  ['Rueda abdominal', 3, 10, 1, 'Rango controlado sin hundir la zona lumbar; acortar el recorrido si la espalda baja aparece (viene cargada del rumano).'],
];
const exercises = plan.map(([exerciseName, series, reps, weight, notes]) => {
  const found = sourceExercises.find((exercise) => exercise.name === exerciseName);
  if (!found) throw new Error(`No encontré ${exerciseName} en los bloques fuente.`);
  const { instanceId, durationMinutes, ...rest } = found;
  return { ...rest, series, reps, value: reps, weight, notes };
});

const { createdAt, updatedAt, libraryOrder, ...sourceRest } = d1Source;
const block = {
  ...sourceRest,
  athleteId,
  folder: 'BELEN',
  isLibraryTemplate: true,
  title: 'FULL BODY · ÉNFASIS PIERNA',
  description: 'Mié 11-11. Full body con predominio de cuádriceps tras el énfasis de torso de ayer. Sin bisagra de cadera ni hombros (isquios, glúteos y deltoides cargados). Descansos: 90 s en prensa, press y jalón; 60 s en el resto.',
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
  day: 2,
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
