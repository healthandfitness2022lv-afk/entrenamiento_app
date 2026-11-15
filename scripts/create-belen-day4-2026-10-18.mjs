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
const getBlock = async (token, id) => {
  const response = await fetch(`https://firestore.googleapis.com/v1/${name('blocks', id)}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`blocks/${id} ${response.status}: ${await response.text()}`);
  return Object.fromEntries(Object.entries((await response.json()).fields).map(([key, item]) => [key, decode(item)]));
};

// Semana 4, día 4 (piernas). Referencia: día 4 realizado el domingo 11-10-2026.
const configurations = [
  {
    sourceId: 'belen_trigo_d4_musculacion_2026_09_25', cloneId: 'belen_trigo_d4_musculacion_2026_10_18', plannedId: 'belen_trigo_d4_2026_10_18', title: 'MUSCULACION 4', order: 0,
    description: 'Dom 18-10. Semana 4, día 4, desde lo realizado el 11-10-2026. Sentadilla y extensión quedaron en RPE 9: se consolida; progresión por repeticiones en búlgara y de carga en aductores. Descansos: 2 min en sentadilla, 90 s en búlgara, 60 s en accesorios.',
    overrides: {
      'Sentadilla - Barra trasera': { series: 4, reps: 8, weight: 45, notes: '45 kg: 4×8 quedó en RPE 8-9-9-9 el 11-10 (y el martes hizo 52,5 × 6 a RPE 8-9). Misma carga, objetivo RPE 8.' },
      'Sentadilla Bulgara - Mancuernas': { series: 3, reps: 12, weight: 7.5, notes: '7,5 kg c/mano: 3×10 a RPE 8 estable el 11-10. Sobrecarga por repeticiones, 3×12 por pierna.' },
      'Extension De Cuadriceps - Bilateral en máquina': { series: 3, reps: 12, weight: 45, notes: '45 kg: el 11-10 registró 50 kg × 12 a RPE 9-10-9 (plan 20). Se baja un escalón para RPE 8; si 50 no era real, ajustar a la carga usada.' },
      'Aducción de cadera - Máquina de aductores': { series: 3, reps: 12, weight: 20, notes: '20 kg: dos veces 15 kg × 15 a RPE 8. Sube carga y baja a 12 reps; si pasa de RPE 9, volver a 15 kg × 15.' },
      'Rueda abdominal': { series: 3, reps: 8, weight: 1, notes: '3×8 a RPE 8 el 11-10. Se mantiene; zona lumbar neutra, si cuesta, rango más corto.' },
      'Bicicleta': { series: 1, reps: 600, weight: 1, durationMinutes: 10, notes: '10 minutos suaves (RPE 7 el 11-10). Hacerla al final, después del Tabata de planchas.' },
    },
  },
  {
    sourceId: 'belen_trigo_d4_tabata_planchas_2026_09_25', cloneId: 'belen_trigo_d4_tabata_planchas_2026_10_18', plannedId: 'belen_trigo_d4_tabata_2026_10_18', title: 'TABATA PLANCHAS', order: 1,
    rounds: 4,
    description: 'Dom 18-10. 4 rondas de 20 s / 10 s: las dos veces anteriores las 3 rondas quedaron en RPE 7.',
  },
];

const token = await accessToken();
const writes = [];
const summary = [];
for (const configuration of configurations) {
  const source = await getBlock(token, configuration.sourceId);
  const exercises = configuration.overrides
    ? source.exercises.map((exercise) => {
      const override = configuration.overrides[exercise.name];
      if (!override) throw new Error(`Sin definición para ${exercise.name}`);
      return { ...exercise, ...override, value: override.reps };
    })
    : source.exercises;
  const block = {
    ...source, athleteId, title: configuration.title, exercises, description: configuration.description,
    ...(configuration.rounds ? { rounds: configuration.rounds } : {}),
    createdAt: now, updatedAt: now, libraryOrder: Date.now() + writes.length,
  };
  const planned = {
    athleteId, athleteName: 'Belén Trigo', blockId: configuration.cloneId, blockTitle: configuration.title,
    date: '2026-10-18T03:00:00Z', day: 4, week: 4, order: configuration.order, status: 'planned', createdAt: now, blockUpdatedAt: now,
  };
  writes.push(
    { update: { name: name('blocks', configuration.cloneId), fields: fields(block) } },
    { update: { name: name('planned_workouts', configuration.plannedId), fields: fields(planned) } },
  );
  summary.push({ block: configuration.cloneId, planned: configuration.plannedId, type: block.type, rounds: block.rounds, exercises: exercises.map((e) => `${e.name}: ${e.series ?? '-'}×${e.reps ?? '-'} @ ${e.weight}`) });
}
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify(summary, null, 2));
