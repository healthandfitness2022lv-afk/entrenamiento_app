import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const now = new Date().toISOString();
const date = '2026-10-19T03:00:00Z';

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
const getDoc = async (token, collection, id) => {
  const response = await fetch(`${base}/${collection}/${id}`, { headers: { Authorization: `Bearer ${token}` } });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${collection}/${id} ${response.status}: ${await response.text()}`);
  return Object.fromEntries(Object.entries((await response.json()).fields ?? {}).map(([key, item]) => [key, decode(item)]));
};

// ── Ejercicio nuevo en el catálogo ─────────────────────────────────────────
const backExtensionId = 'movement_extension_de_espalda';
const backExtensionVariant = {
  id: 'banco_romano', label: 'Banco romano', techniqueId: 'banco_romano', techniqueLabel: 'Banco romano',
  group: 'Peso corporal', familyId: 'back_extension', exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia',
  movementIntent: 'full', resistanceType: 'bodyweight', equipment: ['Banco romano', 'Peso corporal'],
  isUnilateral: false, trackRM: false, trackProgression: false,
};
const backExtension = {
  name: 'Extensión de espalda',
  familyId: 'back_extension',
  exerciseType: 'Hipertrofia',
  trainingDiscipline: 'hipertrofia',
  movementIntent: 'full',
  movementClass: 'compound',
  resistanceType: 'bodyweight',
  equipment: ['Banco romano', 'Peso corporal'],
  isUnilateral: false,
  trackRM: false,
  trackProgression: false,
  muscleWeights: { lowerBack: 0.4, glutes: 0.3, hamstrings: 0.25, midBack: 0.05 },
  variants: [backExtensionVariant],
  instructions: '1. Cadera apoyada en el borde del banco romano, talones fijos.\n2. Baja el tronco con la espalda neutra, bisagra de cadera.\n3. Sube contrayendo glúteos e isquios hasta un poco antes de quedar en línea recta.\n4. No hiperextender la zona lumbar. Movimiento controlado, sin impulso.',
  videoUrl: '',
  catalogStatus: 'reviewed_single',
  createdAt: now,
  updatedAt: now,
};

// ── Sesión de hoy ──────────────────────────────────────────────────────────
// Lun 19-10: el domingo hizo pierna pesada; hoy torso y brazos. Cargas desde
// lo realizado (no lo planificado), mantenidas o levemente progresadas.
const sources = {
  'Press De Pecho - Barra en banco plano': 'belen_trigo_d1_musculacion_2026_10_13',
  'Press De Hombro - Landmine half kneeling': 'belen_trigo_d2_musculacion_2026_10_14',
  'Elevación frontal - Mancuernas': 'belen_trigo_d2_musculacion_2026_10_14',
  'Extension De Triceps - Cuerda en polea': 'belen_trigo_d1_musculacion_2026_10_13',
  'Curl De Biceps - Barra Z': 'belen_trigo_d1_musculacion_2026_10_13',
  'Rueda abdominal': 'belen_trigo_d4_musculacion_2026_10_18',
};
const plan = [
  { name: 'Press De Pecho - Barra en banco plano', series: 3, reps: 10, weight: 27.5, notes: '27,5 kg: el 13-10 hizo 25 kg × 12-12-15 a RPE 8-8-9. Progresión de 2,5 kg; objetivo RPE 8. Descanso 2 min.' },
  { name: 'Press De Hombro - Landmine half kneeling', series: 3, reps: 10, weight: 27.5, notes: '27,5 kg por lado: el 14-10 hizo 3×8 a RPE 8-8-9. Misma carga, progresión a 10 repeticiones. Descanso 90 s.' },
  { name: 'Elevación frontal - Mancuernas', series: 3, reps: 12, weight: 10, notes: '10 kg: el 14-10 hizo 3×12 a RPE 8-8-9. Se mantiene; sin balanceo de cadera. Descanso 60 s.' },
  { name: 'Extension De Triceps - Cuerda en polea', series: 3, reps: 12, weight: 15, notes: '15 kg: el 05-10 hizo 3×15 a RPE 9. Misma carga a 12 repeticiones para RPE 8. Descanso 60 s.' },
  { name: 'Curl De Biceps - Barra Z', series: 3, reps: 12, weight: 14, notes: '14 kg: el 13-10 hizo 3×10 a RPE 8. Misma carga, progresión a 12 repeticiones, ejecución estricta. Descanso 60 s.' },
  { name: 'Rueda abdominal', series: 3, reps: 10, weight: 1, notes: 'El 18-10 hizo 3×8 a RPE 7-8-7. Progresión a 10 repeticiones; zona lumbar neutra, si cuesta, rango más corto.' },
  { name: 'Extensión de espalda - Banco romano', series: 3, reps: 12, weight: 1, notes: 'Sin hiperextender la espalda: sube solo hasta un poco antes de quedar en línea recta con las piernas. Movimiento controlado, sin impulso. Descanso 60 s.' },
];

const blockId = 'belen_trigo_d1_torso_brazos_2026_10_19';
const plannedId = 'belen_trigo_d1_2026_10_19';
const title = 'TORSO Y BRAZOS';

const token = await accessToken();

// Salvaguardas: no duplicar lo de hoy ni pisar un ejercicio existente.
if (await getDoc(token, 'planned_workouts', plannedId)) throw new Error(`Ya existe planned_workouts/${plannedId}`);
if (await getDoc(token, 'blocks', blockId)) throw new Error(`Ya existe blocks/${blockId}`);
const existingExercise = await getDoc(token, 'exercises', backExtensionId);
if (existingExercise) throw new Error(`Ya existe exercises/${backExtensionId} (${existingExercise.name})`);
const plannedQuery = await fetch(`${base}:runQuery`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'planned_workouts' }], where: { fieldFilter: { field: { fieldPath: 'athleteId' }, op: 'EQUAL', value: { stringValue: athleteId } } } } }),
});
const sameDay = (await plannedQuery.json()).filter((r) => r.document).map((r) => decode({ mapValue: { fields: r.document.fields } })).filter((p) => String(p.date ?? '').startsWith('2026-10-19'));
if (sameDay.length) throw new Error(`Ya hay ${sameDay.length} planned_workouts para el 19-10: ${sameDay.map((p) => p.blockTitle).join(', ')}`);

const blockCache = {};
const exercises = [];
for (const item of plan) {
  let entry;
  if (item.name === 'Extensión de espalda - Banco romano') {
    entry = {
      name: item.name, displayName: item.name, exerciseId: backExtensionId, movementId: backExtensionId,
      movementName: 'Extensión de espalda', familyId: 'back_extension',
      variantId: 'banco_romano', variantLabel: 'Banco romano', techniqueId: 'banco_romano', techniqueLabel: 'Banco romano',
      exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia', movementIntent: 'full', resistanceType: 'bodyweight',
      equipment: 'Banco romano, Peso corporal', perSide: false, isUnilateral: false, valueType: 'reps', trackRM: false, trackProgression: false,
    };
  } else {
    const sourceId = sources[item.name];
    blockCache[sourceId] ??= await getDoc(token, 'blocks', sourceId);
    const source = blockCache[sourceId]?.exercises?.find((exercise) => exercise.name === item.name);
    if (!source) throw new Error(`No encontré ${item.name} en ${sourceId}`);
    const { instanceId, durationMinutes, ...rest } = source;
    entry = rest;
  }
  exercises.push({ ...entry, series: item.series, reps: item.reps, value: item.reps, weight: item.weight, notes: item.notes });
}

const block = {
  type: 'Series', folder: 'BELEN', athleteId, isLibraryTemplate: true, title,
  description: 'Lun 19-10. Semana 5, día 1. El domingo hizo pierna pesada, así que hoy va torso y brazos. Cargas mantenidas o levemente progresadas respecto de lo realizado. Descansos: 2 min en banca, 90 s en landmine, 60 s en el resto.',
  exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now(),
};
const planned = {
  athleteId, athleteName: 'Belén Trigo', blockId, blockTitle: title,
  date, day: 1, week: 5, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now,
};

const writes = [
  { update: { name: name('exercises', backExtensionId), fields: fields(backExtension) }, currentDocument: { exists: false } },
  { update: { name: name('blocks', blockId), fields: fields(block) }, currentDocument: { exists: false } },
  { update: { name: name('planned_workouts', plannedId), fields: fields(planned) }, currentDocument: { exists: false } },
];
const response = await fetch(`${base}:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({
  exercise: `exercises/${backExtensionId}`, block: blockId, planned: plannedId, date,
  exercises: exercises.map((e) => `${e.name}: ${e.series}×${e.reps} @ ${e.weight}`),
}, null, 2));
