import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const now = new Date().toISOString();

function b64(value) { return Buffer.from(value).toString('base64url'); }
async function accessToken() {
  const issuedAt = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({
    iss: credentials.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: credentials.token_uri,
    iat: issuedAt, exp: issuedAt + 3600,
  }))}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(credentials.token_uri, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(credentials.private_key))}` }),
  });
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
function decodeDocument(document) { return Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, item]) => [key, decode(item)])); }
function value(data) {
  if (data === null) return { nullValue: null };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data) ? { integerValue: String(data) } : { doubleValue: data };
  if (typeof data === 'string') return { stringValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)])) } };
}
function fields(data) { return Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)])); }
function name(collection, id) { return `projects/${projectId}/databases/(default)/documents/${collection}/${id}`; }
async function getBlock(token, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/${name('blocks', id)}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`No se pudo leer blocks/${id}: ${response.status} ${await response.text()}`);
  return decodeDocument(await response.json());
}

// Cargas reestimadas desde lo realizado los martes 22-09 y 29-09-2026.
const configurations = [
  {
    sourceId: 'belen_trigo_d2_musculacion_2026_09_29', cloneId: 'belen_trigo_d2_musculacion_2026_10_06', plannedId: 'belen_trigo_d2_2026_10_06', title: 'MUSCULACION 2', order: 0,
    overrides: {
      'Press De Hombro - Landmine half kneeling': { weight: 25, notes: '25 kg: 3×8 completas a RPE 8-9-9 el 29-09; se consolida la carga antes de subir.' },
      'Elevación frontal - Mancuernas': { weight: 10, notes: '10 kg: es la carga que usó ambos martes; 3×10 bajó de RPE 9 a RPE 8.' },
      'Leñador': { reps: 12, weight: 12, notes: '3×12 con 12 kg: ambos martes hizo 12 reps (12 kg a RPE 8-9 y 10 kg a RPE 8), no las 8 programadas.' },
      'Peso Muerto - Rumano con barra': { weight: 60, notes: '60 kg para 4×8: el 29-09 hizo 55-60-60-65 × 8 a RPE 8-9. Si la última serie queda en RPE ≤ 8, subir a 65.' },
      'Curl Femoral - Máquina sentado': { weight: 30, notes: '30 kg: 3×12 a RPE 7-8-8 el 29-09 (programado 25); se fija la carga real.' },
    },
  },
  {
    sourceId: 'belen_trigo_d2_metcon_2026_09_29', cloneId: 'belen_trigo_d2_metcon_2026_10_06', plannedId: 'belen_trigo_d2_metcon_2026_10_06', title: 'METCON 1', order: 1,
    overrides: {
      'Ketlebell swing americano': { weight: 16, notes: '16 kg: con 14 kg los 3 rounds de 12 bajaron de RPE 7-8-9 a RPE 7-8-7.' },
      'Step Up - Peso corporal': { reps: 6, weight: 1, notes: 'Peso corporal, 6 por lado: 5 por lado a RPE 7 en los 3 rounds.' },
      'Tuck Up': { reps: 12, weight: 1, notes: 'Peso corporal, 12 reps: 10 reps a RPE 7 estable ambos martes.' },
      'Dominada - Australiana': { weight: 1, notes: 'Peso corporal; se mantienen 6 reps: RPE 8-9-8 el 29-09.' },
    },
  },
];

const token = await accessToken();
const writes = [];
const summary = [];
for (const configuration of configurations) {
  const source = await getBlock(token, configuration.sourceId);
  const exercises = source.exercises.map((exercise) => {
    const override = configuration.overrides[exercise.name];
    if (!override) throw new Error(`Sin definición para ${exercise.name}`);
    const reps = override.reps ?? exercise.reps;
    return { ...exercise, reps, value: reps, weight: override.weight, notes: override.notes };
  });
  const block = {
    ...source, athleteId, title: configuration.title, exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now() + writes.length,
    description: 'Semana 3, día 2. Cargas reestimadas desde lo realizado los martes 22-09 y 29-09-2026.',
  };
  const planned = {
    athleteId, athleteName: 'Belén Trigo', blockId: configuration.cloneId, blockTitle: configuration.title,
    date: '2026-10-06T03:00:00Z', day: 2, week: 3, order: configuration.order, status: 'planned', createdAt: now, blockUpdatedAt: now,
  };
  writes.push(
    { update: { name: name('blocks', configuration.cloneId), fields: fields(block) } },
    { update: { name: name('planned_workouts', configuration.plannedId), fields: fields(planned) } },
  );
  summary.push({ block: configuration.cloneId, planned: configuration.plannedId, exercises: exercises.map((e) => `${e.name}: ${e.series ?? source.rounds}x${e.reps} @ ${e.weight}`) });
}
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify(summary, null, 2));
