import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const project = 'entrenamientoapplv';
const credentialsPath = 'secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json';
const canonicalId = 'movement_peso_muerto';
const sourceMappings = {
  movement_peso_muerto_rumano_con_barra: 'rumano_con_barra',
  HaWRELUzzTN5MOGreeLk: 'rumano_con_barra',
  '1dLxkmqyaIEaeSX5hvXR': 'rumano_en_deficit',
  Q8pvBvQ6fvRlaYUxRMAI: 'one_leg_rdl_barbell',
  S3iWIpwpTQzX1Hzvhj5U: 'landmine_rdl',
};
const collections = ['blocks', 'planned_workouts', 'workouts_logged'];

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
  const service = JSON.parse(readFileSync(credentialsPath, 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const h = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const p = b64(JSON.stringify({ iss: service.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: service.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${h}.${p}`; const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(service.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(service.private_key))}` }) });
  return (await response.json()).access_token;
}
async function list(token, collection) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${collection}?pageSize=1000`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()).documents ?? [];
}
async function update(token, collection, id, data) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${collection}/${id}`, { method: 'PATCH', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, encode(v)])) }) });
  if (!response.ok) throw new Error(await response.text());
}
async function remove(token, collection, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${collection}/${id}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok && response.status !== 404) throw new Error(await response.text());
}
function replace(value) {
  if (Array.isArray(value)) return value.map(replace);
  if (!value || typeof value !== 'object') return value;
  const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, replace(item)]));
  const mappedVariant = sourceMappings[result.exerciseId] ?? sourceMappings[result.movementId];
  if (mappedVariant) {
    result.exerciseId = canonicalId;
    result.movementId = canonicalId;
    result.movementName = 'Peso Muerto';
    result.variantId = mappedVariant;
    result.variantLabel = mappedVariant === 'rumano_con_barra' ? 'Rumano con barra' : mappedVariant === 'rumano_en_deficit' ? 'Rumano en déficit' : mappedVariant === 'one_leg_rdl_barbell' ? 'RDL unilateral con barra' : 'Rumano con landmine';
    result.name = `Peso Muerto - ${result.variantLabel}`;
    result.displayName = result.name;
  }
  if (sourceMappings[result.blockId] || sourceMappings[result.sourceBlockId]) {
    if (sourceMappings[result.blockId]) result.blockId = canonicalId;
    if (sourceMappings[result.sourceBlockId]) result.sourceBlockId = canonicalId;
  }
  return result;
}

const accessToken = await token();
const canonicalDocs = await list(accessToken, 'exercises');
const canonicalDoc = canonicalDocs.find((doc) => idOf(doc) === canonicalId);
if (!canonicalDoc) throw new Error('No se encontró el ejercicio canónico Peso Muerto.');
const canonicalData = fields(canonicalDoc);
const canonicalVariants = Array.isArray(canonicalData.variants) ? canonicalData.variants : [];
const addedVariants = [
  { id: 'rumano_en_deficit', label: 'Rumano en déficit', familyId: 'deadlift', techniqueId: 'romanian', techniqueLabel: 'Rumano', group: 'Peso libre', equipment: ['Barra', 'Steps'], resistanceType: 'free', isUnilateral: false, trackRM: true, trackProgression: true, trainingDiscipline: 'fuerza', movementIntent: 'full' },
  { id: 'one_leg_rdl_barbell', label: 'RDL unilateral con barra', familyId: 'deadlift', techniqueId: 'romanian_unilateral', techniqueLabel: 'Rumano unilateral', group: 'Peso libre', equipment: ['Barra'], resistanceType: 'free', isUnilateral: true, trackRM: false, trackProgression: false, trainingDiscipline: 'fuerza', movementIntent: 'full' },
  { id: 'landmine_rdl', label: 'Rumano con landmine', familyId: 'deadlift', techniqueId: 'romanian', techniqueLabel: 'Rumano', group: 'Peso libre', equipment: ['Barra', 'Landmine'], resistanceType: 'free', isUnilateral: false, trackRM: false, trackProgression: false, trainingDiscipline: 'fuerza', movementIntent: 'full' },
];
const mergedVariants = [...canonicalVariants];
for (const incoming of addedVariants) {
  const index = mergedVariants.findIndex((item) => item.id === incoming.id);
  if (index >= 0) mergedVariants[index] = { ...mergedVariants[index], ...incoming };
  else mergedVariants.push(incoming);
}
await update(accessToken, 'exercises', canonicalId, { ...canonicalData, variants: mergedVariants, updatedAt: new Date().toISOString() });
let migrated = 0;
for (const collection of collections) {
  for (const doc of await list(accessToken, collection)) {
    const id = idOf(doc); const data = fields(doc); const updated = replace(data);
    if (JSON.stringify(data) !== JSON.stringify(updated)) {
      await update(accessToken, collection, id, updated); migrated += 1;
      console.log(`Migrado ${collection}/${id}`);
    }
  }
}
for (const sourceId of Object.keys(sourceMappings)) await remove(accessToken, 'exercises', sourceId);
console.log(`Duplicados RDL eliminados: ${Object.keys(sourceMappings).length}. Referencias migradas: ${migrated}. Canonical: ${canonicalId}`);
