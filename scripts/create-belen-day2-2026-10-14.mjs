import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const now = new Date().toISOString();
const date = '2026-10-14T03:00:00Z';
const b64 = (value) => Buffer.from(value).toString('base64url');
async function accessToken() {
  const issuedAt = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({ iss: credentials.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: credentials.token_uri, iat: issuedAt, exp: issuedAt + 3600 }))}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(credentials.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(credentials.private_key))}` }) });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
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
function decode(v) {
  if ('stringValue' in v) return v.stringValue; if ('integerValue' in v) return Number(v.integerValue); if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue; if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  return null;
}
const token = await accessToken();
const sourceResponse = await fetch(`https://firestore.googleapis.com/v1/${name('blocks', 'belen_trigo_d2_musculacion_2026_10_06')}`, { headers: { Authorization: `Bearer ${token}` } });
if (!sourceResponse.ok) throw new Error(`No se pudo leer el bloque base: ${sourceResponse.status}`);
const source = Object.fromEntries(Object.entries((await sourceResponse.json()).fields ?? {}).map(([key, item]) => [key, decode(item)]));
const changes = {
  'Press De Hombro - Landmine half kneeling': { weight: 27.5, reps: 8, series: 3, notes: '27,5 kg: 25 kg × 8 quedó en RPE 7-8 el 06-10. Progresión de 2,5 kg; objetivo RPE 8 y técnica estable por lado.' },
  'Elevación frontal - Mancuernas': { weight: 10, reps: 12, series: 3, notes: '10 kg: 3×10 fue RPE 8. Sobrecarga por repeticiones: 3×12; detener si supera RPE 8.' },
  'Leñador': { weight: 15, reps: 10, series: 3, notes: '15 kg: 12 kg × 12 quedó en RPE 7-8. Progresión conservadora de carga con 10 reps por lado; objetivo RPE 8.' },
  'Peso Muerto - Rumano con barra': { weight: 55, reps: 6, series: 2, notes: 'Ajuste de fatiga: ayer hubo sentadilla a RPE 8-9 e hip thrust a RPE 9. Hoy solo 2×6 con 55 kg, RPE ≤7, sin buscar sobrecarga en la bisagra.' },
  'Curl Femoral - Máquina sentado': { weight: 50, reps: 10, series: 2, notes: '50 kg × 12 terminó en RPE 9 el 06-10 y ayer hubo trabajo pesado de cadera. Mantener carga, 2×10, RPE ≤7-8.' },
};
const exercises = source.exercises.map((exercise) => ({ ...exercise, displayName: exercise.name, valueType: exercise.valueType ?? 'reps', value: changes[exercise.name]?.reps ?? exercise.reps, ...changes[exercise.name] }));
const blockId = 'belen_trigo_d2_musculacion_2026_10_14';
const plannedId = 'belen_trigo_d2_2026_10_14';
const block = { ...source, athleteId, title: 'MUSCULACION 2', exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now(), description: 'Mié 14-10. Día 2 ajustado con el registro del 06-10 y la fatiga real de la sesión pesada del 13-10. Se progresa solo donde el RPE dejó margen y se reduce la bisagra/isquios para preservar recuperación.' };
const planned = { athleteId, athleteName: 'Belén Trigo', blockId, blockTitle: 'MUSCULACION 2', date, day: 2, week: 4, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now };
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes: [{ update: { name: name('blocks', blockId), fields: fields(block) } }, { update: { name: name('planned_workouts', plannedId), fields: fields(planned) } }] }) });
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ plannedId, blockId, date, exercises: exercises.map(({ name, series, reps, weight }) => ({ name, series, reps, weight })) }, null, 2));
