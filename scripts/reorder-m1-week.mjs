import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const project = 'entrenamientoapplv';
const credentialsPath = 'secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json';
const athleteId = '71DheGSwhtfDEfN4tk3TlI7Kzut1';

const decode = (v) => {
  if (!v) return v;
  if (v.stringValue !== undefined) return v.stringValue;
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.doubleValue !== undefined) return v.doubleValue;
  if (v.booleanValue !== undefined) return v.booleanValue;
  if (v.nullValue !== undefined) return null;
  if (v.timestampValue !== undefined) return v.timestampValue;
  if (v.arrayValue) return (v.arrayValue.values ?? []).map(decode);
  if (v.mapValue) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, x]) => [k, decode(x)]));
  return v;
};
const encode = (v) => v === null ? { nullValue: null } : typeof v === 'string' ? { stringValue: v } : typeof v === 'boolean' ? { booleanValue: v } : typeof v === 'number' ? (Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v }) : Array.isArray(v) ? { arrayValue: { values: v.map(encode) } } : { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)])) } };
const fields = (doc) => Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, decode(v)]));
const idOf = (doc) => doc.name.split('/').pop();
const b64 = (v) => Buffer.from(v).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

async function token() {
  const service = JSON.parse(readFileSync(credentialsPath, 'utf8')); const now = Math.floor(Date.now() / 1000);
  const h = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' })); const p = b64(JSON.stringify({ iss: service.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: service.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${h}.${p}`; const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(service.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(service.private_key))}` }) });
  if (!response.ok) throw new Error(await response.text()); return (await response.json()).access_token;
}
async function list(accessToken, collection) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${collection}?pageSize=1000`, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(await response.text()); return (await response.json()).documents ?? [];
}
async function update(accessToken, collection, id, data) {
  const encodedFields = Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, encode(v)]),
  );
  // Firestore date fields must remain Timestamp values. The generic encoder
  // represents ISO dates as strings, so restore this field explicitly.
  if (collection === 'planned_workouts' && typeof data.date === 'string') {
    encodedFields.date = { timestampValue: new Date(data.date).toISOString() };
  }
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${collection}/${id}`, { method: 'PATCH', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: encodedFields }) });
  if (!response.ok) throw new Error(`${collection}/${id}: ${await response.text()}`);
}
async function remove(accessToken, collection, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${collection}/${id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok && response.status !== 404) throw new Error(`${collection}/${id}: ${await response.text()}`);
}

const accessToken = await token();
const blockDocs = await list(accessToken, 'blocks');
const blockMap = new Map(blockDocs.map((doc) => [idOf(doc), fields(doc)]));
const targetBlockIds = ['hector_padel_m1_d1_b2', 'library_hector_d1_b2', 'hector_padel_m1_d2_b4', 'library_hector_d2_b4', 'hector_padel_m1_d4_b1', 'hector_padel_m1_d4_b3'];
const modifiedBlocks = [];
for (const id of targetBlockIds) {
  const block = blockMap.get(id); if (!block) continue;
  const exercises = [...(block.exercises ?? [])];
  if (id.endsWith('d4_b1')) {
    block.exercises = exercises.filter((exercise) => !String(exercise.name ?? exercise.displayName ?? '').toLowerCase().startsWith('peso muerto'));
    block.notes = 'Pliometría pura: el peso muerto se programa como bisagra de fuerza, no dentro de este bloque.';
  }
  if (id.endsWith('d4_b3')) {
    block.exercises = exercises.map((exercise) => String(exercise.name ?? exercise.displayName ?? '').toLowerCase().includes('giro 180') ? { ...exercise, reps: 6, value: 6, perSide: true } : exercise);
  }
  if (id.endsWith('d2_b4')) {
    const exists = exercises.some((exercise) => exercise.exerciseId === 'movement_remo' && exercise.variantId === 'maquina_sentada');
    if (!exists) exercises.splice(1, 0, {
      instanceId: 'm1_d2_b4_remo_maquina', name: 'Remo - Máquina sentada', movementName: 'Remo', displayName: 'Remo - Máquina sentada', exerciseId: 'movement_remo', movementId: 'movement_remo', variantId: 'maquina_sentada', variantLabel: 'Máquina sentada', familyId: 'row', techniqueId: 'horizontal_row', techniqueLabel: 'Remo horizontal', equipment: 'Remo sentado, Máquina de remo', resistanceType: 'guided', trackRM: true, trackProgression: false, isUnilateral: false, series: 3, reps: 10, value: 10, valueType: 'reps', weight: 0,
    });
    block.exercises = exercises;
  }
  block.updatedAt = new Date().toISOString();
  await update(accessToken, 'blocks', id, block); modifiedBlocks.push(id);
}

const plannedDocs = await list(accessToken, 'planned_workouts');
const orderByBlockId = {
  library_hector_d1_b1: 0, hector_padel_m1_d1_b2: 1, hector_padel_m1_d1_b3: 2, hector_padel_m1_d1_b4: 3,
  hector_padel_m1_d2_b1: 0, hector_padel_m1_d2_b2: 1, hector_padel_m1_d2_b3: 2, hector_padel_m1_d2_b4: 3,
  hector_padel_m1_d3_b2: 0, hector_padel_m1_d3_b1: 1,
  hector_padel_m1_d4_b1: 0, hector_padel_m1_d4_b3: 1, hector_padel_m1_d4_b2: 2,
  hector_padel_m1_d5_b1: 0, hector_padel_m1_d5_b2: 1,
};
const start = Date.parse('2026-09-21T00:00:00Z'); const end = Date.parse('2026-09-28T00:00:00Z');
const modifiedPlans = [];
for (const doc of plannedDocs) {
  const id = idOf(doc); const plan = fields(doc); const date = Date.parse(plan.date ?? '');
  if (plan.athleteId !== athleteId || orderByBlockId[plan.blockId] === undefined) continue;
  plan.order = orderByBlockId[plan.blockId]; plan.blockUpdatedAt = new Date().toISOString();
  // Distribución solicitada e idempotente: lunes, martes, jueves, viernes y
  // sábado. Se asigna la fecha absoluta del microciclo para no desplazarla
  // nuevamente si el script se ejecuta más de una vez.
  const dayMatch = plan.blockId.match(/_d([1-5])_/);
  const targetOffset = { 1: 0, 2: 1, 3: 3, 4: 4, 5: 5 }[Number(dayMatch?.[1] ?? 0)];
  // 03:00 UTC corresponde a las 00:00 en Chile durante este microciclo;
  // evita que Flutter convierta la sesión al día anterior.
  if (targetOffset !== undefined) plan.date = new Date(start + targetOffset * 24 * 60 * 60 * 1000 + 3 * 60 * 60 * 1000).toISOString();
  await update(accessToken, 'planned_workouts', id, plan); modifiedPlans.push(id);
}

// Limpieza segura: solo elimina plantillas de biblioteca sin referencias en
// ninguna planificación. Los bloques fuente y los usados por cualquier atleta
// quedan intactos.
const referencedBlockIds = new Set(plannedDocs.map((doc) => fields(doc).blockId).filter(Boolean));
const deletedUnusedLibraryBlocks = [];
const markedPlannedLibraryBlocks = [];
for (const doc of blockDocs) {
  const id = idOf(doc);
  const block = fields(doc);
  if (referencedBlockIds.has(id)) {
    if (block.isLibraryTemplate !== true) {
      await update(accessToken, 'blocks', id, { isLibraryTemplate: true });
      markedPlannedLibraryBlocks.push(id);
    }
    continue;
  }
  if (block.isLibraryTemplate === false) continue;
  await remove(accessToken, 'blocks', id);
  deletedUnusedLibraryBlocks.push(id);
}
console.log(JSON.stringify({ modifiedBlocks, modifiedPlannedWorkouts: modifiedPlans.length, markedPlannedLibraryBlocks, deletedUnusedLibraryBlocks, rules: ['Potencia primero D1/D2', 'Peso muerto fuera de pliometría', 'Remo horizontal añadido a accesorios upper', 'Giro 180° reducido a 3x6 por lado', 'D5 ordenado', 'Días: lunes, martes, jueves, viernes y sábado'] }, null, 2));
