import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const dryRun = process.argv.includes('--dry-run');
const now = new Date().toISOString();
const date = '2026-11-16T03:00:00Z';
const blockId = 'belen_trigo_fullbody_sentadilla_2026_11_16';
const plannedId = 'belen_trigo_fullbody_sentadilla_2026_11_16';

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
const [existingBlock, existingPlanned, d1Source, hingeSource, legSource, torsoSource, lungeMovement] = await Promise.all([
  getDoc(token, 'blocks', blockId),
  getDoc(token, 'planned_workouts', plannedId),
  getDoc(token, 'blocks', 'belen_trigo_d1_musculacion_2026_10_26'),
  getDoc(token, 'blocks', 'belen_trigo_d2_musculacion_2026_11_03'),
  getDoc(token, 'blocks', 'belen_trigo_d4_musculacion_2026_11_01'),
  getDoc(token, 'blocks', 'belen_trigo_fullbody_torso_2026_11_10'),
  getDoc(token, 'exercises', 'movement_estocada'),
]);
if (existingBlock || existingPlanned) throw new Error(`Ya existe la planificación de Belén para ${date.slice(0, 10)}.`);
if (!d1Source || !hingeSource || !legSource || !torsoSource || !lungeMovement) throw new Error('Falta un documento fuente para crear la sesión.');

// Estocada - Mancuernas: ejercicio nuevo para Belén. Se arma desde el catálogo
// usando la búlgara (unilateral con mancuernas) como molde de campos.
const lungeVariant = (lungeMovement.variants ?? []).find((variant) => variant.id === 'mancuernas');
const bulgarian = torsoSource.exercises.find((exercise) => exercise.name === 'Sentadilla Bulgara - Mancuernas');
if (!lungeVariant || !bulgarian) throw new Error('No encontré la variante de estocada con mancuernas o el molde de la búlgara.');
const lungeName = `${lungeMovement.name} - ${lungeVariant.label}`;
const lunge = {
  ...bulgarian,
  name: lungeName,
  displayName: lungeName,
  exerciseId: 'movement_estocada',
  movementId: 'movement_estocada',
  movementName: lungeMovement.name,
  variantId: lungeVariant.id,
  variantLabel: lungeVariant.label,
  techniqueId: lungeVariant.techniqueId ?? lungeVariant.id,
  techniqueLabel: lungeVariant.techniqueLabel ?? lungeVariant.label,
  familyId: lungeVariant.familyId ?? 'lunge',
  exerciseType: lungeVariant.exerciseType,
  trainingDiscipline: lungeVariant.trainingDiscipline,
  movementIntent: lungeVariant.movementIntent,
  resistanceType: lungeVariant.resistanceType,
  trackRM: lungeVariant.trackRM,
  trackProgression: lungeVariant.trackProgression,
  isUnilateral: true,
  perSide: true,
  equipment: Array.isArray(bulgarian.equipment) ? lungeVariant.equipment : lungeVariant.equipment.join(', '),
};

const sourceExercises = [...d1Source.exercises, ...hingeSource.exercises, ...legSource.exercises, lunge];
const plan = [
  ['Sentadilla - Barra trasera', 4, 6, 55, '55 kg. El último 4×6 con 52,5 fue RPE 7. Si la primera serie pasa de RPE 8, volver a 52,5 kg. Profundidad completa y rodillas siguiendo la punta del pie.'],
  [lungeName, 3, 10, 7.5, '7,5 kg por mano, 10 reps por pierna. Ejercicio nuevo: priorizar técnica, apuntar a RPE 7. Paso largo, torso erguido y empujar con el talón de adelante.'],
  ['Press De Pecho - Barra en banco plano', 3, 8, 30, '30 kg. Venía de 27,5×10 a RPE 7: sube carga y baja reps. Escápulas retraídas y bajada controlada.'],
  ['Jalon Al Pecho - Agarre ancho', 3, 12, 35, '35 kg. Misma carga que el último 3×10 (RPE 7), 2 reps más. Pecho arriba y codos hacia las costillas, sin balanceo.'],
  ['Curl Femoral - Máquina sentado', 3, 12, 50, '50 kg. Mantener: 1 s de pausa en la contracción y 2 s de vuelta.'],
  ['Rueda abdominal', 3, 10, 1, 'Rango controlado sin hundir la zona lumbar; acortar el recorrido si aparece la espalda baja.'],
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
  title: 'FULL BODY · SENTADILLA + ESTOCADAS',
  description: 'Lun 16-11. Full body con sentadilla con barra y estocadas como base, tras 6 días de descanso. Sin rumano ni hip thrust (glúteo ya cargado por sentadilla + estocadas). Descansos: 2 min en sentadilla; 90 s en estocadas, press y jalón; 60 s en el resto.',
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
  week: 9,
  order: 0,
  status: 'planned',
  createdAt: now,
  blockUpdatedAt: now,
};

console.log(JSON.stringify({ dryRun, date: date.slice(0, 10), title: block.title, exercises: exercises.map((exercise) => ({ name: exercise.name, series: exercise.series, reps: exercise.reps, weight: exercise.weight })) }, null, 2));
if (dryRun) {
  console.log('Estocada (objeto completo):', JSON.stringify(exercises[1], null, 1));
  console.log('Molde búlgara:', JSON.stringify(bulgarian, null, 1));
  process.exit(0);
}

const response = await fetch(`${base}:commit`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes: [
  { update: { name: name('blocks', blockId), fields: fields(block) }, currentDocument: { exists: false } },
  { update: { name: name('planned_workouts', plannedId), fields: fields(planned) }, currentDocument: { exists: false } },
] }) });
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log('OK: entrenamiento cargado.');
