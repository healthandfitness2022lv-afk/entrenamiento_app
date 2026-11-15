import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const blockId = 'belen_trigo_d3_musculacion_2026_10_16';
const plannedId = 'belen_trigo_d3_2026_10_16';
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

// Semana 4, día 3. Referencia: día 3 realizado el jueves 08-10-2026.
// Tras RPE 9 sostenido se conserva la carga y se recortan repeticiones; se progresa solo donde quedó margen.
const overrides = {
  'Press Banca inclinado DB': { series: 3, reps: 8, weight: 12.5, notes: '12,5 kg: 3×10 llegó a RPE 9-9-10 el 08-10 (y el martes hubo press plano a RPE 8-9). Misma carga, 3×8, objetivo RPE 8.' },
  'Remo - Barra': { series: 4, reps: 12, weight: 27.5, notes: '27,5 kg: 25 kg × 15 quedó en RPE 7-8-8-9 el 08-10. Sube 2,5 kg y baja a 12 reps; espalda neutra, objetivo RPE 8.' },
  'Jalon Al Pecho - Polea baja, agarre cerrado': { series: 3, reps: 10, weight: 35, notes: '35 kg: dos semanas seguidas en RPE 9-9-9 con 12 reps. Misma carga, 3×10 con pausa abajo, objetivo RPE 8.' },
  'Elevacion Lateral - Mancuernas': { series: 3, reps: 13, weight: 5, notes: '5 kg × 13: RPE 9-8-8 el 08-10 y el miércoles hubo landmine y elevación frontal a RPE 8-9. Se mantiene, sin fallo.' },
  'Face Pull - Cuerda en polea': { series: 3, reps: 12, weight: 32.5, notes: '32,5 kg: 30 kg × 12 quedó en RPE 7-8-8 el 08-10. Progresión de 2,5 kg; si pasa de RPE 9, volver a 30.' },
  'Press Pallof - Banda elástica': { series: 3, reps: 15, weight: 12.5, notes: 'Misma banda: 3×12 a RPE 7-8-8 el 08-10. Sobrecarga por repeticiones, 3×15 por lado, objetivo RPE 8.' },
  'Trote - Caminadora': { series: 1, reps: 480, durationMinutes: 8, weight: 1, notes: '8 minutos a RPE 6-7: las últimas tres veces los 10 min terminaron en RPE 8-9. Ritmo conversacional, no es progresión.' },
};

const token = await accessToken();
const sourceResponse = await fetch(`https://firestore.googleapis.com/v1/${name('blocks', 'belen_trigo_d3_musculacion_2026_10_08')}`, { headers: { Authorization: `Bearer ${token}` } });
if (!sourceResponse.ok) throw new Error(`Bloque fuente ${sourceResponse.status}: ${await sourceResponse.text()}`);
const source = Object.fromEntries(Object.entries((await sourceResponse.json()).fields).map(([key, item]) => [key, decode(item)]));
const exercises = source.exercises.map((exercise) => {
  const override = overrides[exercise.name];
  if (!override) throw new Error(`Sin definición para ${exercise.name}`);
  return { ...exercise, ...override, value: override.reps };
});
const block = {
  ...source, athleteId, title: 'MUSCULACION 3', exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now(),
  description: 'Vie 16-10. Semana 4, día 3, desde lo realizado el 08-10-2026. Se mantiene carga donde hubo RPE 9 sostenido (press inclinado, jalón) y se progresa en remo, face pull y Pallof. Descansos: 90 s en press, remo y jalón; 45-60 s en accesorios.',
};
const planned = { athleteId, athleteName: 'Belén Trigo', blockId, blockTitle: 'MUSCULACION 3', date: '2026-10-16T03:00:00Z', day: 3, week: 4, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now };

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ writes: [
    { update: { name: name('blocks', blockId), fields: fields(block) } },
    { update: { name: name('planned_workouts', plannedId), fields: fields(planned) } },
  ] }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ plannedId, blockId, date: planned.date, exercises: exercises.map(({ name, series, reps, weight, valueType }) => `${name}: ${series}×${reps} @ ${weight} (${valueType})`) }, null, 2));
