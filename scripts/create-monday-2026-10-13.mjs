import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const today = '2026-10-13T03:00:00Z';
const tomorrow = '2026-10-14T03:00:00Z';
const now = new Date().toISOString();
const hectorId = '71DheGSwhtfDEfN4tk3TlI7Kzut1';
const belenId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';

const b64 = (value) => Buffer.from(value).toString('base64url');
async function token() {
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
function value(data) {
  if (data === null) return { nullValue: null };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data) ? { integerValue: String(data) } : { doubleValue: data };
  if (typeof data === 'string') return { stringValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, value(v)])) } };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([k, v]) => [k, value(v)]));
const name = (collection, id) => `projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
async function raw(tokenValue, collection, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/${name(collection, id)}`, { headers: { Authorization: `Bearer ${tokenValue}` } });
  if (!response.ok) throw new Error(`No se pudo leer ${collection}/${id}: ${response.status}`);
  return response.json();
}
function decode(v) {
  if ('stringValue' in v) return v.stringValue; if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue; if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue; if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, x]) => [k, decode(x)]));
  return null;
}
const data = (document) => Object.fromEntries(Object.entries(document.fields ?? {}).map(([k, v]) => [k, decode(v)]));

// No se aumenta carga tras RPE 9 sostenido: se conserva el peso y se baja el objetivo de repeticiones.
const belenExercise = (item) => ({ ...item, displayName: item.name, value: item.reps, valueType: 'reps', trackRM: item.trackRM ?? true, trackProgression: item.trackProgression ?? true });
const belenBlock = {
  athleteId: belenId, folder: 'BELEN', isLibraryTemplate: true, title: 'MUSCULACION 1', type: 'Series',
  description: 'Lun 13-10. Consolidación tras el lunes 05-10: los principales quedaron en RPE 8-9 (varios 9), por lo que no se aumenta carga; se recortan repeticiones para sostener técnica y dejar margen. Descansos: 2 min en sentadilla/hip thrust/press y 75-90 s en accesorios.',
  createdAt: now, updatedAt: now, libraryOrder: Date.now(),
  exercises: [
    belenExercise({ name: 'Sentadilla - Barra trasera', exerciseId: 'movement_sentadilla', movementId: 'movement_sentadilla', movementName: 'Sentadilla', familyId: 'squat', variantId: 'barbell_back', variantLabel: 'Barra trasera', techniqueId: 'barbell_back', techniqueLabel: 'Barra trasera', exerciseType: 'Fuerza', trainingDiscipline: 'fuerza', movementIntent: 'full', resistanceType: 'free', equipment: 'Barra, Rack', series: 4, reps: 6, weight: 52.5, perSide: false, isUnilateral: false, notes: '52,5 kg: 4×8 fue RPE 8-9-9-9 el 05-10. Hoy 4×6, RPE objetivo 7-8; no subir si la técnica cambia.' }),
    belenExercise({ name: 'Hip Thrust - Máquina con discos', exerciseId: 'movement_hip_thrust', movementId: 'movement_hip_thrust', movementName: 'Hip Thrust', familyId: 'hip_thrust', variantId: 'maquina_con_discos', variantLabel: 'Máquina con discos', techniqueId: 'maquina_con_discos', techniqueLabel: 'Máquina con discos', exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia', movementIntent: 'full', resistanceType: 'guided', equipment: 'Hip thrust con discos', series: 3, reps: 10, weight: 55, perSide: false, isUnilateral: false, notes: '55 kg: el 3×12 terminó RPE 9. Consolidar con 3×10 y pausa de 1 s arriba; RPE 7-8.' }),
    belenExercise({ name: 'Press De Pecho - Barra en banco plano', exerciseId: 'movement_press_de_pecho', movementId: 'movement_press_de_pecho', movementName: 'Press De Pecho', familyId: 'chest_press', variantId: 'barra_en_banco_plano', variantLabel: 'Barra en banco plano', techniqueId: 'barra_en_banco_plano', techniqueLabel: 'Barra en banco plano', exerciseType: 'Fuerza', trainingDiscipline: 'fuerza', movementIntent: 'full', resistanceType: 'free', equipment: 'Barra, Banco', series: 3, reps: 8, weight: 25, perSide: false, isUnilateral: false, notes: '25 kg: 3×12 fue RPE 9. Hacer 3×8 con 1-2 repeticiones en reserva; si RPE >8, bajar a 22,5 kg.' }),
    belenExercise({ name: 'Jalon Al Pecho - Agarre ancho', exerciseId: 'movement_jalon_al_pecho', movementId: 'movement_jalon_al_pecho', movementName: 'Jalon Al Pecho', familyId: 'jalon_al_pecho', variantId: 'agarre_ancho', variantLabel: 'Agarre ancho', techniqueId: 'agarre_ancho', techniqueLabel: 'Agarre ancho', exerciseType: 'Hipertrofia', trainingDiscipline: 'hipertrofia', movementIntent: 'full', resistanceType: 'guided', equipment: 'Polea alta', series: 3, reps: 12, weight: 30, perSide: false, isUnilateral: false, notes: '30 kg: 3×15 fue RPE 9. Consolidar 3×12, RPE 7-8, con depresión escapular antes de tirar.' }),
    belenExercise({ name: 'Curl De Biceps - Barra Z', exerciseId: 'movement_curl_de_biceps', movementId: 'movement_curl_de_biceps', movementName: 'Curl De Biceps', familyId: 'biceps_curl', variantId: 'barra_z', variantLabel: 'Barra Z', techniqueId: 'barra_z', techniqueLabel: 'Barra Z', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', resistanceType: 'free', equipment: 'Barra Z', series: 3, reps: 10, weight: 14, perSide: false, isUnilateral: false, notes: '14 kg: 3×12 llegó a RPE 8-9-9. Mantener carga y hacer 3×10 con ejecución estricta.' }),
    belenExercise({ name: 'Extension De Triceps - Cuerda en polea', exerciseId: 'movement_extension_de_triceps', movementId: 'movement_extension_de_triceps', movementName: 'Extension De Triceps', familyId: 'triceps_extension', variantId: 'cuerda_en_polea', variantLabel: 'Cuerda en polea', techniqueId: 'cuerda_en_polea', techniqueLabel: 'Cuerda en polea', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', resistanceType: 'guided', equipment: 'Polea alta, Cuerda', series: 3, reps: 12, weight: 15, perSide: false, isUnilateral: false, notes: '15 kg: 3×15 fue RPE 9. Hoy 3×12 a RPE 7-8; si las tres quedan ≤7, subir a 17,5 kg la próxima exposición.' }),
  ],
};

const hectorSources = [
  ['hector_alvarez_d1_2026_10_06_potencia_1', 'hector_alvarez_d1_2026_10_13_potencia_1'],
  ['hector_alvarez_d1_2026_10_06_hipertrofia_1', 'hector_alvarez_d1_2026_10_13_hipertrofia_1'],
  ['hector_alvarez_d1_2026_10_06_fuerza_1', 'hector_alvarez_d1_2026_10_13_fuerza_1'],
  ['hector_alvarez_d1_2026_10_06_core_1', 'hector_alvarez_d1_2026_10_13_core_1'],
];
const todayHectorPlans = ['6Fv8H6i0uO5tJTKojRaC', 'YgjMHxneTYdryi6Bu8cz', '4GJZkTBTKhGhGExQvRP6'];
const tokenValue = await token();
const sourceDocuments = await Promise.all(hectorSources.map(([source]) => raw(tokenValue, 'blocks', source)));
const hectorBlocks = sourceDocuments.map((document, index) => {
  const block = data(document); const [, cloneId] = hectorSources[index];
  return { cloneId, block: { ...block, athleteId: hectorId, createdAt: now, updatedAt: now, libraryOrder: Date.now() + index, title: block.title, description: `${block.description ?? ''} Lun 13-10: se repite la progresión planificada para el 06-10 porque no hay registro realizado ese lunes. Referencia real: 28-09.`.trim() } };
});
const writes = [
  ...hectorBlocks.map(({ cloneId, block }) => ({ update: { name: name('blocks', cloneId), fields: fields(block) } })),
  { update: { name: name('blocks', 'belen_trigo_d1_musculacion_2026_10_13'), fields: fields(belenBlock) } },
  { update: { name: name('planned_workouts', 'belen_trigo_d1_2026_10_13'), fields: fields({ athleteId: belenId, athleteName: 'Belén Trigo', blockId: 'belen_trigo_d1_musculacion_2026_10_13', blockTitle: 'MUSCULACION 1', date: today, day: 1, week: 4, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now }) } },
  ...hectorBlocks.map(({ cloneId, block }, index) => ({ update: { name: name('planned_workouts', `hector_alvarez_d1_2026_10_13_${index + 1}`), fields: fields({ athleteId: hectorId, athleteName: 'Héctor Álvarez', blockId: cloneId, blockTitle: block.title, date: today, day: 1, week: 4, order: index, status: 'planned', createdAt: now, blockUpdatedAt: now }) } })),
  ...todayHectorPlans.map((id) => ({ update: { name: name('planned_workouts', id), fields: { date: value(tomorrow) } }, updateMask: { fieldPaths: ['date'] } })),
];
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, { method: 'POST', headers: { Authorization: `Bearer ${tokenValue}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }) });
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ date: today, belen: belenBlock.exercises.map(({ name, series, reps, weight }) => `${name}: ${series}×${reps} @ ${weight} kg`), hectorBlocks: hectorBlocks.map(({ cloneId, block }) => ({ cloneId, title: block.title, exercises: block.exercises.map(({ name, series, reps, weight }) => `${name}: ${series}×${reps} @ ${weight} kg`) })), shiftedHectorPlansTo: tomorrow }, null, 2));
