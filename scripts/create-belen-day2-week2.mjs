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

const configurations = [
  {
    sourceId: 'DUs6HETAiWcEmCTr5Ces', cloneId: 'belen_trigo_d2_musculacion_2026_09_29', plannedId: 'belen_trigo_d2_2026_09_29', title: 'MUSCULACION 2', order: 0,
    weights: {
      'Press De Hombro - Landmine half kneeling': 25,
      'Elevación frontal - Mancuernas': 7.5,
      'Leñador': 12.5,
      'Peso Muerto - Rumano con barra': 55,
      'Curl Femoral - Máquina sentado': 25,
    },
    notes: {
      'Press De Hombro - Landmine half kneeling': '25 kg para 3×8: 23 kg × 12 alcanzó RPE 9 la semana pasada.',
      'Elevación frontal - Mancuernas': '7,5 kg: 10 kg × 10 llegó a RPE 9 en las tres series; se prioriza técnica a 10 reps.',
      'Leñador': '12,5 kg para 3×8: 12 kg × 12 se realizó a RPE 8-9.',
      'Peso Muerto - Rumano con barra': '55 kg para 4×8: 60 kg sólo cerró 8 reps en la última serie a RPE 8.',
      'Curl Femoral - Máquina sentado': '25 kg: 3×12 efectivas a RPE 7-9; se conserva la carga.',
    },
  },
  {
    sourceId: 'ZrlKIPSh7BgMuKhqmdCI', cloneId: 'belen_trigo_d2_metcon_2026_09_29', plannedId: 'belen_trigo_d2_metcon_2026_09_29', title: 'METCON 1', order: 1,
    weights: {
      'Ketlebell swing americano': 14,
      'Step Up - Peso corporal': 1,
      'Tuck Up': 1,
      'Dominada - Australiana': 1,
    },
    notes: {
      'Ketlebell swing americano': '14 kg: completó los 3 rounds de 12 reps a RPE 7, 8 y 9.',
      'Step Up - Peso corporal': 'Peso corporal, como se ejecutó realmente la semana pasada.',
      'Tuck Up': 'Peso corporal; 3×10 realizados a RPE 6-7.',
      'Dominada - Australiana': 'Peso corporal; se mantienen las 6 reps programadas tras haber realizado 12 reps la semana pasada.',
    },
  },
];

const token = await accessToken();
const writes = [];
for (const configuration of configurations) {
  const source = await getBlock(token, configuration.sourceId);
  const exercises = source.exercises.map((exercise) => ({
    ...exercise,
    weight: configuration.weights[exercise.name] ?? exercise.weight,
    notes: configuration.notes[exercise.name] ?? exercise.notes,
  }));
  const block = {
    ...source, athleteId, title: configuration.title, exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now() + writes.length,
    description: `${source.description ?? ''}${source.description ? ' ' : ''}Mismo volumen programado que el día equivalente; cargas reestimadas desde lo realizado el 22-09-2026.`,
  };
  const planned = {
    athleteId, athleteName: 'Belén Trigo', blockId: configuration.cloneId, blockTitle: configuration.title,
    date: '2026-09-29T03:00:00Z', day: 2, week: 2, order: configuration.order, status: 'planned', createdAt: now, blockUpdatedAt: now,
  };
  writes.push(
    { update: { name: name('blocks', configuration.cloneId), fields: fields(block) } },
    { update: { name: name('planned_workouts', configuration.plannedId), fields: fields(planned) } },
  );
}
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ plannedIds: configurations.map(({ plannedId }) => plannedId), blockIds: configurations.map(({ cloneId }) => cloneId) }, null, 2));
