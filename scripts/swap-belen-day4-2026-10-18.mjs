import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const now = new Date().toISOString();

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
const blockId = 'belen_trigo_d4_musculacion_2026_10_18';

// La prensa no existía en el catálogo: se crea con el formato de los movimientos unificados.
const prensaId = 'movement_prensa_de_piernas';
const prensaVariant = (id, label, equipment) => ({
  id, label, techniqueId: id, techniqueLabel: label, equipment, group: 'Máquina', resistanceType: 'guided', isUnilateral: false,
  familyId: 'leg_press', movementIntent: 'full', exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia', trackRM: true, trackProgression: true, needsReview: false,
});
const prensa = {
  name: 'Prensa De Piernas', familyId: 'leg_press', movementClass: 'compound', movementIntent: 'full', exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia',
  resistanceType: 'guided', equipment: ['Prensa de piernas', 'Prensa horizontal'], isUnilateral: false, trackRM: true, trackProgression: true,
  muscleWeights: { quads: 0.5, glutes: 0.25, adductors: 0.12, hamstrings: 0.08, calves: 0.05 },
  instructions: '1. Apoya espalda y glúteos en el respaldo y los pies al ancho de caderas en la plataforma.\n2. Libera los seguros y baja controlando hasta que la cadera empiece a despegarse del respaldo.\n3. Empuja con todo el pie hasta casi extender, sin bloquear las rodillas.',
  variants: [prensaVariant('maquina_inclinada', 'Máquina inclinada', ['Prensa de piernas']), prensaVariant('horizontal', 'Horizontal', ['Prensa horizontal'])],
  catalogStatus: 'reviewed_single', catalogReviewedBy: 'ai_initial_review_v1', videoUrl: '', createdAt: now, updatedAt: now,
};

const replacements = {
  'Sentadilla - Barra trasera': {
    name: 'Prensa De Piernas - Máquina inclinada', displayName: 'Prensa De Piernas - Máquina inclinada', exerciseId: prensaId, movementId: prensaId,
    variantId: 'maquina_inclinada', variantLabel: 'Máquina inclinada', techniqueId: 'maquina_inclinada', resistanceType: 'guided', equipment: 'Prensa de piernas',
    series: 4, reps: 10, value: 10, weight: 70, perSide: false, valueType: 'reps', trackRM: false, trackProgression: false,
    notes: 'Reemplaza a la sentadilla. Sin registro previo: 70 kg en discos (sin contar el carro) como referencia por su sentadilla de 45 × 8. Subir de a 10 kg hasta RPE 8 y registrar la carga real.',
  },
  'Aducción de cadera - Máquina de aductores': {
    name: 'Curl Femoral - Máquina tumbado', displayName: 'Curl Femoral - Máquina tumbado', exerciseId: 'movement_curl_femoral', movementId: 'movement_curl_femoral',
    variantId: 'maquina_tumbado', variantLabel: 'Máquina tumbado', techniqueId: 'maquina_tumbado', resistanceType: 'guided', equipment: 'Máquina de curl femoral tumbado',
    series: 3, reps: 12, value: 12, weight: 30, perSide: false, valueType: 'reps', trackRM: false, trackProgression: false,
    notes: 'Camilla femoral, reemplaza a la aducción. Sin registro previo tumbada: el miércoles hizo 50 kg × 10 sentada a RPE 7-8; tumbado rinde menos, partir en 30 kg y ajustar a RPE 8.',
  },
};

const token = await accessToken();
const blockResponse = await fetch(`https://firestore.googleapis.com/v1/${name('blocks', blockId)}`, { headers: { Authorization: `Bearer ${token}` } });
if (!blockResponse.ok) throw new Error(`blocks/${blockId} ${blockResponse.status}: ${await blockResponse.text()}`);
const block = Object.fromEntries(Object.entries((await blockResponse.json()).fields).map(([key, item]) => [key, decode(item)]));
const pending = new Set(Object.keys(replacements));
const exercises = block.exercises.map((exercise) => {
  const replacement = replacements[exercise.name];
  if (!replacement) return exercise;
  pending.delete(exercise.name);
  return replacement;
});
if (pending.size) throw new Error(`No se encontró en el bloque: ${[...pending].join(', ')}`);
const updated = {
  ...block, exercises, updatedAt: now,
  description: 'Dom 18-10. Semana 4, día 4, desde lo realizado el 11-10-2026. Sentadilla reemplazada por prensa y aducción por camilla femoral (cargas iniciales a ajustar a RPE 8). Descansos: 2 min en prensa, 90 s en búlgara, 60 s en accesorios.',
};

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ writes: [
    { update: { name: name('exercises', prensaId), fields: fields(prensa) }, currentDocument: { exists: false } },
    { update: { name: name('blocks', blockId), fields: fields(updated) } },
    { update: { name: name('planned_workouts', 'belen_trigo_d4_2026_10_18'), fields: fields({ blockUpdatedAt: now }) }, updateMask: { fieldPaths: ['blockUpdatedAt'] } },
  ] }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(exercises.map((e) => `${e.name}: ${e.series}×${e.reps} @ ${e.weight}`).join('\n'));
