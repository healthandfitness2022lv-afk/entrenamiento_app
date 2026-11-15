import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const athleteName = 'Belén Trigo';
const blockId = 'belen_trigo_d3_musculacion_2026_10_02';
const plannedId = 'belen_trigo_d3_2026_10_02';
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
const exercise = (data) => ({ ...data, displayName: data.name, valueType: 'reps', trackRM: false, trackProgression: false });

// Referencia: 24-09, día 3 realizado. Se busca RPE 8-9, sin repetir el fallo
// de elevaciones laterales (5 kg x 15 llegó a RPE 9-10).
const exercises = [
  exercise({
    name: 'Press Banca inclinado DB', exerciseId: 'xVUHkvMloZM5TMQQ5UrA', movementId: 'xVUHkvMloZM5TMQQ5UrA',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', resistanceType: 'free', equipment: 'Mancuernas, Banco inclinado',
    series: 3, reps: 10, value: 10, weight: 12.5, perSide: true,
    notes: 'Progresión desde 10 kg x 12 a RPE 7-8. Meta: RPE 8-9; si supera RPE 9, terminar con 10 kg.',
  }),
  exercise({
    name: 'Remo - Pecho apoyado', exerciseId: 'movement_remo', movementId: 'movement_remo',
    variantId: 'pecho_apoyado', variantLabel: 'Pecho apoyado', techniqueId: 'pecho_apoyado', resistanceType: 'free', equipment: 'Mancuernas, Banco inclinado',
    series: 4, reps: 12, value: 12, weight: 12.5, perSide: true,
    notes: 'El remo con barra fue 20 kg x 15 a RPE 7. Usar apoyo de pecho y ajustar a RPE 8, sin cargar la zona lumbar.',
  }),
  exercise({
    name: 'Jalon Al Pecho - Polea baja, agarre cerrado', exerciseId: 'movement_jalon_al_pecho', movementId: 'movement_jalon_al_pecho',
    variantId: 'polea_baja_agarre_cerrado', variantLabel: 'Polea baja, agarre cerrado', techniqueId: 'polea_baja_agarre_cerrado', resistanceType: 'guided', equipment: 'Polea baja',
    series: 3, reps: 12, value: 12, weight: 37.5, perSide: false,
    notes: 'Progresión desde 35 kg x 15 a RPE 8. Pausa breve abajo y sin balanceo; objetivo RPE 8-9.',
  }),
  exercise({
    name: 'Elevacion Lateral - Mancuernas', exerciseId: 'movement_elevacion_lateral', movementId: 'movement_elevacion_lateral',
    variantId: 'mancuernas', variantLabel: 'Mancuernas', techniqueId: 'mancuernas', resistanceType: 'free', equipment: 'Mancuernas',
    series: 3, reps: 12, value: 12, weight: 5, perSide: true,
    notes: 'Mantener 5 kg, pero bajar a 12 reps: la semana pasada 15 reps alcanzó RPE 9-10. No buscar fallo.',
  }),
  exercise({
    name: 'Face Pull - Cuerda en polea', exerciseId: 'movement_face_pull_cuerda_en_polea', movementId: 'movement_face_pull_cuerda_en_polea',
    variantId: 'original', variantLabel: 'Face pull con cuerda', techniqueId: 'original', resistanceType: 'guided', equipment: 'Polea alta, Cuerda',
    series: 3, reps: 12, value: 12, weight: 27.5, perSide: false,
    notes: 'Progresión moderada desde 25 kg x 15 a RPE 7-8. Tirar a la frente y separar cuerda; objetivo RPE 8.',
  }),
  exercise({
    name: 'Press Pallof - Polea', exerciseId: 'NhKDOyUbYVtdr2AD5jLe', movementId: 'NhKDOyUbYVtdr2AD5jLe',
    variantId: 'cable', variantLabel: 'Polea', techniqueId: 'standing', resistanceType: 'guided', equipment: 'Polea ajustable',
    series: 3, reps: 12, value: 12, weight: 12.5, perSide: true,
    notes: 'Progresión desde 10 kg x 15 a RPE 7. Exhalar al extender y resistir la rotación; RPE 8.',
  }),
  exercise({
    name: 'Trote - Caminadora', exerciseId: 'movement_trote', movementId: 'movement_trote',
    variantId: 'caminadora', variantLabel: 'Caminadora', techniqueId: 'caminadora', resistanceType: 'bodyweight', equipment: 'Caminadora',
    series: 1, reps: 600, value: 600, valueType: 'time', durationMinutes: 10, weight: 1, perSide: false,
    notes: '10 minutos suaves, RPE 6-7. La referencia fue RPE 8, por lo que hoy es descarga aeróbica, no progresión.',
  }),
];

const block = {
  isLibraryTemplate: true, title: 'MUSCULACION 3', athleteId, folder: 'BELEN', type: 'Series', exercises,
  description: 'Semana 2, día 3. Progresión basada en las series realizadas el 24-09-2026. Descansos: 90 s en press, remo y jalón; 45-60 s en accesorios. Registrar RPE en cada serie.',
  createdAt: now, updatedAt: now, libraryOrder: Date.now(),
};
const planned = {
  athleteId, athleteName, blockId, blockTitle: 'MUSCULACION 3', date: '2026-10-02T03:00:00Z',
  day: 3, week: 2, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now,
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
