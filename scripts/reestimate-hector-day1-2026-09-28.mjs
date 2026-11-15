import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const athleteId = '71DheGSwhtfDEfN4tk3TlI7Kzut1';
const now = new Date().toISOString();

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

async function getDocument(token, collection, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/${name(collection, id)}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`No se pudo leer ${collection}/${id}: ${response.status} ${await response.text()}`);
  return documentData(await response.json());
}

const configurations = [
  {
    sourceId: 'library_hector_d1_b1', plannedId: 'XtFTfSKOHxYpRgBIW7WM', cloneId: 'hector_alvarez_d1_2026_09_28_potencia_1',
    weights: {
      'Sentadilla - Salto con barra': 35,
      'Clean - Power Clean · Barra': 60,
      'Snatch - Hang Power Snatch · Barra': 42.5,
    },
    notes: {
      'Sentadilla - Salto con barra': '35 kg: 40 kg alcanzó RPE 8-9; se mantiene intención explosiva.',
      'Clean - Power Clean · Barra': '60 kg: 4×3 efectivas entre RPE 7 y 8 la semana pasada.',
      'Snatch - Hang Power Snatch · Barra': '42,5 kg: 40 kg × 5 se completó a RPE 7 en las tres series.',
    },
  },
  {
    sourceId: 'hector_padel_m1_d1_b2', plannedId: '2aaY36qOhkcf9EZUrQf0', cloneId: 'hector_alvarez_d1_2026_09_28_fuerza_1',
    weights: {
      'Sentadilla - Barra trasera': 82.5,
      'Peso Muerto - Convencional con trap bar': 105,
    },
    notes: {
      'Sentadilla - Barra trasera': '82,5 kg: 80 kg × 5 se completó en las cuatro series (RPE 8, 8, 7 y 6).',
      'Peso Muerto - Convencional con trap bar': '105 kg sin cambio: no se realizó la semana pasada.',
    },
  },
  {
    sourceId: 'hector_padel_m1_d1_b3', plannedId: 'CqbmCQTXwklTXJTmta9Q', cloneId: 'hector_alvarez_d1_2026_09_28_hipertrofia_1',
    weights: {
      'Sentadilla - Hack squat': 30,
      'Aducción de cadera - Máquina de aductores': 25,
    },
    notes: {
      'Sentadilla - Hack squat': '30 kg: 3×10 realizadas a RPE 8, 8 y 9; se conserva la carga.',
      'Aducción de cadera - Máquina de aductores': '25 kg: reestimación intermedia tras series efectivas a 20 y 30 kg, con respuesta irregular a 30 kg.',
    },
  },
  {
    sourceId: 'hector_padel_m1_d1_b4', plannedId: 'BURa1GCugrKRyK4LulQ4', cloneId: 'hector_alvarez_d1_2026_09_28_core_1',
    weights: {
      'Press Pallof - Polea': 25,
      'Lanzamiento de balón medicinal - Lateral a pared': 8,
      'Leñador - Original': 12.5,
    },
    notes: {
      'Press Pallof - Polea': '25 kg: 10 reps a RPE 7 en la última serie real.',
      'Lanzamiento de balón medicinal - Lateral a pared': '8 kg: 7 kg × 6 se completó a RPE 6 en las tres series.',
      'Leñador - Original': '12,5 kg: 2×10 a RPE 7; 15 kg redujo a 8 reps a RPE 8.',
    },
  },
];

const token = await accessToken();
const writes = [];
for (const configuration of configurations) {
  const [source, planned] = await Promise.all([
    getDocument(token, 'blocks', configuration.sourceId),
    getDocument(token, 'planned_workouts', configuration.plannedId),
  ]);
  const exercises = source.exercises.map((exercise) => ({
    ...exercise,
    weight: configuration.weights[exercise.name] ?? exercise.weight,
    notes: configuration.notes[exercise.name] ?? exercise.notes,
  }));
  const block = {
    ...source, athleteId, exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now() + writes.length,
    description: `${source.description ?? ''}${source.description ? ' ' : ''}Cargas reestimadas desde la sesión real del 21-09-2026; los ejercicios no realizados conservan la carga planificada.`,
  };
  const nextPlanned = { ...planned, athleteId, athleteName: 'Héctor Álvarez', blockId: configuration.cloneId, blockUpdatedAt: now };
  writes.push(
    { update: { name: name('blocks', configuration.cloneId), fields: fields(block) } },
    { update: { name: name('planned_workouts', configuration.plannedId), fields: fields(nextPlanned) } },
  );
}

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ plannedIds: configurations.map(({ plannedId }) => plannedId), blockIds: configurations.map(({ cloneId }) => cloneId) }, null, 2));
