import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const athleteId = '71DheGSwhtfDEfN4tk3TlI7Kzut1';
const now = new Date().toISOString();
const today = '2026-10-06T03:00:00Z';
const tomorrow = '2026-10-07T03:00:00Z';
// Día 2 que estaba planificado para hoy: se corre un día porque hoy se hace el día 1.
const shiftedPlannedIds = ['dWofEgk0jqBnpmplOjoY', 'cKwqFpdZDjz6I8BpCUFz', 'ZIIu5z3cAaFMz1G8mmXj'];

function b64(value) { return Buffer.from(value).toString('base64url'); }

async function accessToken() {
  const issuedAt = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({
    iss: credentials.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: credentials.token_uri,
    iat: issuedAt, exp: issuedAt + 3600,
  }))}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
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

function documentData(document) {
  return Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, item]) => [key, decode(item)]));
}

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

async function getRaw(token, collection, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/${name(collection, id)}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`No se pudo leer ${collection}/${id}: ${response.status} ${await response.text()}`);
  return response.json();
}
// Conserva el tipo (timestamp o string) con que la app guardó la fecha.
function dateValue(raw, iso) { return 'timestampValue' in (raw.fields?.date ?? {}) ? { timestampValue: iso } : { stringValue: iso }; }

// Día 1 (lunes) recalculado desde lo realizado los lunes 21-09 y 28-09-2026.
// plannedId = documentos del lunes 05-10 (no realizado), que se mueven a hoy.
const configurations = [
  {
    sourceId: 'hector_alvarez_d1_2026_09_28_potencia_1', plannedId: 'iPzsrIyGOViKwYUeYCiC', cloneId: 'hector_alvarez_d1_2026_10_06_potencia_1',
    weights: {
      'Sentadilla - Salto con barra': 40,
      'Clean - Power Clean · Barra': 62.5,
      'Snatch - Hang Power Snatch · Barra': 45,
    },
    notes: {
      'Sentadilla - Salto con barra': '40 kg: es la carga que usó ambos lunes; bajó de RPE 8-9 a RPE 8-8. Mantener intención explosiva.',
      'Clean - Power Clean · Barra': '62,5 kg: 4×3 con 60 kg a RPE 7 y una serie con 65 kg a RPE 8 el 28-09.',
      'Snatch - Hang Power Snatch · Barra': '45 kg: 3×5 a RPE 8-8-7 el 28-09 (programado 42,5); se consolida la carga real.',
    },
  },
  {
    sourceId: 'hector_alvarez_d1_2026_09_28_hipertrofia_1', plannedId: 'UCgtbuEMxWL7Ie1hJAf2', cloneId: 'hector_alvarez_d1_2026_10_06_hipertrofia_1',
    weights: {
      'Sentadilla - Hack squat': 30,
      'Aducción de cadera - Máquina de aductores': 25,
    },
    notes: {
      'Sentadilla - Hack squat': '30 kg sin cambio: no se realizó el 28-09; última referencia 3×10 a RPE 8-8-9 (21-09).',
      'Aducción de cadera - Máquina de aductores': '25 kg sin cambio: no se realizó el 28-09; el 21-09 usó 20 y 30 kg con respuesta irregular.',
    },
  },
  {
    sourceId: 'hector_alvarez_d1_2026_09_28_fuerza_1', plannedId: 'PRgXKMwBfpXRxyCY9ha2', cloneId: 'hector_alvarez_d1_2026_10_06_fuerza_1',
    weights: {
      'Sentadilla - Barra trasera': 82.5,
      'Peso Muerto - Convencional con trap bar': 105,
    },
    notes: {
      'Sentadilla - Barra trasera': '82,5 kg sin cambio: no se realizó el 28-09; última referencia 80 kg × 5 en 4 series a RPE 8-8-7-6 (21-09).',
      'Peso Muerto - Convencional con trap bar': '105 kg sin cambio: aún sin registro real en ninguno de los dos lunes.',
    },
  },
  {
    sourceId: 'hector_alvarez_d1_2026_09_28_core_1', plannedId: 'unLnBE4vnVW7hBNrj76R', cloneId: 'hector_alvarez_d1_2026_10_06_core_1',
    weights: {
      'Press Pallof - Polea': 25,
      'Lanzamiento de balón medicinal - Lateral a pared': 8,
      'Leñador - Original': 12,
    },
    notes: {
      'Press Pallof - Polea': '25 kg sin cambio: no se realizó el 28-09; 25 kg × 10 fue RPE 7 el 21-09.',
      'Lanzamiento de balón medicinal - Lateral a pared': '8 kg sin cambio: no se realizó el 28-09; 7 kg × 6 fue RPE 6 el 21-09.',
      'Leñador - Original': '12 kg: 3×10 a RPE 6-7-7 el 28-09. Si la última serie queda en RPE ≤ 7, probar 15 kg.',
    },
  },
];

const token = await accessToken();
const writes = [];
const summary = [];
for (const configuration of configurations) {
  const [sourceRaw, plannedRaw] = await Promise.all([
    getRaw(token, 'blocks', configuration.sourceId),
    getRaw(token, 'planned_workouts', configuration.plannedId),
  ]);
  const source = documentData(sourceRaw);
  const exercises = source.exercises.map((exercise) => {
    if (!(exercise.name in configuration.weights)) throw new Error(`Sin definición para ${exercise.name}`);
    return { ...exercise, weight: configuration.weights[exercise.name], notes: configuration.notes[exercise.name] };
  });
  const block = {
    ...source, athleteId, exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now() + writes.length,
    description: 'Día 1 recalculado desde lo realizado los lunes 21-09 y 28-09-2026; los ejercicios no realizados conservan la carga planificada.',
  };
  writes.push(
    { update: { name: name('blocks', configuration.cloneId), fields: fields(block) } },
    {
      update: { name: name('planned_workouts', configuration.plannedId), fields: { date: dateValue(plannedRaw, today), blockId: value(configuration.cloneId), blockUpdatedAt: value(now) } },
      updateMask: { fieldPaths: ['date', 'blockId', 'blockUpdatedAt'] },
    },
  );
  summary.push({ block: configuration.cloneId, planned: configuration.plannedId, exercises: exercises.map((e) => `${e.name}: ${e.series}x${e.reps} @ ${e.weight}`) });
}
for (const plannedId of shiftedPlannedIds) {
  const plannedRaw = await getRaw(token, 'planned_workouts', plannedId);
  writes.push({ update: { name: name('planned_workouts', plannedId), fields: { date: dateValue(plannedRaw, tomorrow) } }, updateMask: { fieldPaths: ['date'] } });
}

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ summary, shiftedToTomorrow: shiftedPlannedIds }, null, 2));
