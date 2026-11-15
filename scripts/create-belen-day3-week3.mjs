import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const athleteName = 'Belén Trigo';
const blockId = 'belen_trigo_d3_musculacion_2026_10_08';
const plannedId = 'belen_trigo_d3_2026_10_08';
const now = new Date().toISOString();

const b64 = (value) => Buffer.from(value).toString('base64url');
async function accessToken() {
  const issuedAt = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({
    iss: credentials.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: credentials.token_uri,
    iat: issuedAt,
    exp: issuedAt + 3600,
  }))}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const response = await fetch(credentials.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64(signer.sign(credentials.private_key))}`,
    }),
  });
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
const exercise = (data) => ({ valueType: 'reps', ...data, displayName: data.name, trackRM: false, trackProgression: false });

// Referencia: 02-10, día 3 realizado (y los accesorios recuperados el 05-10).
// Se fijan las variantes que realmente usa (remo con barra, Pallof con banda).
const exercises = [
  exercise({
    name: 'Press Banca inclinado DB', exerciseId: 'xVUHkvMloZM5TMQQ5UrA', movementId: 'xVUHkvMloZM5TMQQ5UrA',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', resistanceType: 'free', equipment: 'Mancuernas, Banco inclinado',
    series: 3, reps: 10, value: 10, weight: 12.5, perSide: true,
    notes: '12,5 kg: 3×10 a RPE 8-9-9 el 02-10; se consolida la carga antes de subir. Si la última serie queda en RPE ≤ 8, la próxima semana 3×12.',
  }),
  exercise({
    name: 'Remo - Barra', exerciseId: 'movement_remo', movementId: 'movement_remo', movementName: 'Remo',
    variantId: 'barra', variantLabel: 'Barra', techniqueId: 'barra', resistanceType: 'free', equipment: 'Barra',
    series: 4, reps: 15, value: 15, weight: 25, perSide: false,
    notes: '25 kg totales, 4×15: el 02-10 hizo 20-25-25-25 × 15 a RPE 7-8-8-9 (reemplazó el remo con pecho apoyado ambas semanas). Espalda neutra; si se pierde la postura, bajar a 12 reps.',
  }),
  exercise({
    name: 'Jalon Al Pecho - Polea baja, agarre cerrado', exerciseId: 'movement_jalon_al_pecho', movementId: 'movement_jalon_al_pecho',
    variantId: 'polea_baja_agarre_cerrado', variantLabel: 'Polea baja, agarre cerrado', techniqueId: 'polea_baja_agarre_cerrado', resistanceType: 'guided', equipment: 'Polea baja',
    series: 3, reps: 12, value: 12, weight: 35, perSide: false,
    notes: '35 kg: el 02-10 no subió a 37,5 y 3×12 con 35 quedó en RPE 9. Se repite buscando RPE 8-9 con pausa breve abajo.',
  }),
  exercise({
    name: 'Elevacion Lateral - Mancuernas', exerciseId: 'movement_elevacion_lateral', movementId: 'movement_elevacion_lateral',
    variantId: 'mancuernas', variantLabel: 'Mancuernas', techniqueId: 'mancuernas', resistanceType: 'free', equipment: 'Mancuernas',
    series: 3, reps: 13, value: 13, weight: 5, perSide: true,
    notes: '5 kg, 13 reps: 3×12 a RPE 8 estable el 02-10. Se sube una repetición; 15 reps llegó a RPE 9-10 en la semana 1. No buscar fallo.',
  }),
  exercise({
    name: 'Face Pull - Cuerda en polea', exerciseId: 'movement_face_pull_cuerda_en_polea', movementId: 'movement_face_pull_cuerda_en_polea',
    variantId: 'original', variantLabel: 'Face pull con cuerda', techniqueId: 'original', resistanceType: 'guided', equipment: 'Polea alta, Cuerda',
    series: 3, reps: 12, value: 12, weight: 30, perSide: false,
    notes: '30 kg: 3×12 con 27,5 a RPE 8 estable el 02-10. Si pasa de RPE 9, volver a 27,5.',
  }),
  exercise({
    name: 'Press Pallof - Banda elástica', exerciseId: 'NhKDOyUbYVtdr2AD5jLe', movementId: 'NhKDOyUbYVtdr2AD5jLe', movementName: 'Press Pallof',
    variantId: 'band', variantLabel: 'Banda elástica', techniqueId: 'standing', resistanceType: 'free', equipment: 'Banda elástica',
    series: 3, reps: 12, value: 12, weight: 12.5, perSide: true,
    notes: 'Misma banda (registrada como 12,5): 3×12 a RPE 8-8-8 el 02-10 y 8-8-9 el 05-10. Se mantiene; exhalar al extender y resistir la rotación.',
  }),
  exercise({
    name: 'Trote - Caminadora', exerciseId: 'movement_trote', movementId: 'movement_trote',
    variantId: 'caminadora', variantLabel: 'Caminadora', techniqueId: 'caminadora', resistanceType: 'bodyweight', equipment: 'Caminadora',
    series: 1, reps: 600, value: 600, valueType: 'time', durationMinutes: 10, weight: 1, perSide: false,
    notes: '10 minutos suaves, RPE 6-7. Las dos semanas terminó en RPE 8: bajar el ritmo, no es progresión.',
  }),
];

const block = {
  isLibraryTemplate: true, title: 'MUSCULACION 3', athleteId, folder: 'BELEN', type: 'Series', exercises,
  description: 'Semana 3, día 3. Cargas reestimadas desde lo realizado el 02-10-2026. Descansos: 90 s en press, remo y jalón; 45-60 s en accesorios. Registrar RPE en cada serie.',
  createdAt: now, updatedAt: now, libraryOrder: Date.now(),
};
const planned = {
  athleteId, athleteName, blockId, blockTitle: 'MUSCULACION 3', date: '2026-10-08T03:00:00Z',
  day: 3, week: 3, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now,
};

const token = await accessToken();
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ writes: [
    { update: { name: name('blocks', blockId), fields: fields(block) } },
    { update: { name: name('planned_workouts', plannedId), fields: fields(planned) } },
  ] }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ plannedId, blockId, date: planned.date, exercises: exercises.map(({ name, series, reps, weight, perSide }) => ({ name, sets: series, reps, weight, perSide })) }, null, 2));
