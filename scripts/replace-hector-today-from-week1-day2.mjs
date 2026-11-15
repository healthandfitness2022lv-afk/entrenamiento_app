import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = '71DheGSwhtfDEfN4tk3TlI7Kzut1';
const athleteName = 'Héctor Álvarez';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const now = new Date().toISOString();
const today = '2026-10-02T03:00:00Z';
const replacedPlannedIds = ['ayoG5nszKlzs0FFIh3tT', 'S1yrPyp6gG3iHe9uf6zF', 'FWoPppuT8HpU14UIqaEd'];

const b64 = (value) => Buffer.from(value).toString('base64url');
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
function decode(data) {
  if ('stringValue' in data) return data.stringValue;
  if ('integerValue' in data) return Number(data.integerValue);
  if ('doubleValue' in data) return data.doubleValue;
  if ('booleanValue' in data) return data.booleanValue;
  if ('nullValue' in data) return null;
  if ('timestampValue' in data) return data.timestampValue;
  if ('arrayValue' in data) return (data.arrayValue.values ?? []).map(decode);
  if ('mapValue' in data) return Object.fromEntries(Object.entries(data.mapValue.fields ?? {}).map(([key, value]) => [key, decode(value)]));
  throw new Error('Tipo Firestore no soportado');
}
function documentData(document) { return Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decode(value)])); }
function value(data) {
  if (data === undefined) return undefined;
  if (data === null) return { nullValue: null };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data) ? { integerValue: String(data) } : { doubleValue: data };
  if (typeof data === 'string') return { stringValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return {
    mapValue: {
      fields: Object.fromEntries(
        Object.entries(data)
          .filter(([, item]) => item !== undefined)
          .map(([key, item]) => [key, value(item)]),
      ),
    },
  };
}
const fields = (data) => Object.fromEntries(
  Object.entries(data)
    .filter(([, item]) => item !== undefined)
    .map(([key, item]) => [key, value(item)]),
);
const name = (collection, id) => `projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
async function getDocument(token, collection, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/${name(collection, id)}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`No se pudo leer ${collection}/${id}: ${response.status} ${await response.text()}`);
  return documentData(await response.json());
}

// Día 2 planificado (22-09) recalculado desde lo realmente completado el 23-09.
const configurations = [
  {
    sourceId: 'hector_padel_m1_d2_b1', cloneId: 'hector_alvarez_d2_2026_10_02_potencia_2', plannedId: 'hector_alvarez_d2_potencia_2_2026_10_02', order: 0,
    weights: { 'Snatch - Snatch · Landmine': 32.5, 'Jerk - Landmine': 45 },
    notes: {
      'Snatch - Snatch · Landmine': '32,5 kg: 30 kg × 6 terminó en RPE 6, 7 y 8; mantener velocidad y detener si baja la calidad.',
      'Jerk - Landmine': '45 kg: última serie real a 45 kg × 6 fue RPE 8; objetivo RPE 8, sin grind.',
    },
  },
  {
    sourceId: 'hector_padel_m1_d2_b2', cloneId: 'hector_alvarez_d2_2026_10_02_fuerza_2', plannedId: 'hector_alvarez_d2_fuerza_2_2026_10_02', order: 1,
    weights: { 'Press De Hombro - Barra': 40, 'Press De Pecho - Barra en banco plano': 65 },
    notes: {
      'Press De Hombro - Barra': '40 kg: 40 kg × 10 fue RPE 8; 43 kg × 8 llegó a RPE 9. Priorizar series parejas.',
      'Press De Pecho - Barra en banco plano': '65 kg: se logró 8 y 9 reps a RPE 8-9; conservar carga y no exceder RPE 9.',
    },
  },
  {
    sourceId: 'Ul0LbSG3scOwCTUjMwdW', cloneId: 'hector_alvarez_d2_2026_10_02_biserie_1', plannedId: 'hector_alvarez_d2_biserie_1_2026_10_02', order: 2,
    weights: { 'Lanzamiento de balón medicinal - Sobre cabeza a piso': 8, 'Salto a cajón': 1, 'Clean & Jerk - Mancuernas': 25 },
    notes: {
      'Lanzamiento de balón medicinal - Sobre cabeza a piso': '8 kg: 7 kg × 8 fue RPE 6-7. Lanzar explosivo, no al fallo.',
      'Salto a cajón': 'Peso corporal: las 6 reps subieron de RPE 6 a 8; cortar la serie si la recepción pierde calidad.',
      'Clean & Jerk - Mancuernas': '25 kg: 3 rounds de 10 reps a RPE 7-8. Mantener carga y ritmo técnico.',
    },
  },
  {
    sourceId: 'hector_padel_m1_d2_b3', cloneId: 'hector_alvarez_d2_2026_10_02_calistenia_1', plannedId: 'hector_alvarez_d2_calistenia_1_2026_10_02', order: 3,
    weights: { 'Dominada - Agarre prono': 1, 'Fondos en paralelas - Original': 1 },
    notes: {
      'Dominada - Agarre prono': 'Peso corporal: 5/4/5/4 reps a RPE 5-8. Repetir el volumen previsto con 1-2 reps en reserva.',
      'Fondos en paralelas - Original': 'Peso corporal: 2 × 6 a RPE 5. Completar el volumen planificado sin lastre, controlando hombros.',
    },
  },
];

const token = await accessToken();
const writes = [];
for (const configuration of configurations) {
  const source = await getDocument(token, 'blocks', configuration.sourceId);
  const exercises = (source.exercises ?? []).map((exercise) => ({
    ...exercise,
    weight: configuration.weights[exercise.name] ?? exercise.weight,
    notes: configuration.notes[exercise.name] ?? exercise.notes,
  }));
  const block = {
    ...source, athleteId, exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now() + writes.length,
    description: `${source.description ?? ''}${source.description ? ' ' : ''}Sesión recalculada desde lo realizado el 23-09-2026; objetivo general RPE 7-9, sin fallo técnico.`,
  };
  const planned = {
    athleteId, athleteName, blockId: configuration.cloneId, blockTitle: source.title, date: today,
    day: 2, week: 2, order: configuration.order, status: 'planned', createdAt: now, blockUpdatedAt: now,
  };
  writes.push(
    { update: { name: name('blocks', configuration.cloneId), fields: fields(block) } },
    { update: { name: name('planned_workouts', configuration.plannedId), fields: fields(planned) } },
  );
}
for (const plannedId of replacedPlannedIds) writes.push({ delete: name('planned_workouts', plannedId) });

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ replacedPlannedIds, newPlannedIds: configurations.map(({ plannedId }) => plannedId), blocks: configurations.map(({ cloneId }) => cloneId) }, null, 2));
