import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const project = 'entrenamientoapplv';
const exerciseId = 'FDCDa97OexuHToc7xnlp';
const credentialsPath = 'secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json';
const b64 = (v) => Buffer.from(v).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const encode = (v) => v === null ? { nullValue: null } : typeof v === 'string' ? { stringValue: v } : typeof v === 'boolean' ? { booleanValue: v } : typeof v === 'number' ? (Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v }) : Array.isArray(v) ? { arrayValue: { values: v.map(encode) } } : { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)])) } };
async function token() {
  const service = JSON.parse(readFileSync(credentialsPath, 'utf8')); const now = Math.floor(Date.now() / 1000);
  const h = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' })); const p = b64(JSON.stringify({ iss: service.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: service.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${h}.${p}`; const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(service.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(service.private_key))}` }) });
  if (!response.ok) throw new Error(await response.text()); return (await response.json()).access_token;
}
const variant = (id, label, group, equipment, resistanceType, discipline, intent, techniqueId, unilateral = false) => ({ id, label, group, equipment, resistanceType, trainingDiscipline: discipline, movementIntent: intent, familyId: 'jump_squat', techniqueId, techniqueLabel: label, trackRM: false, trackProgression: false, isUnilateral: unilateral, muscleWeightOverrides: { quads: .40, glutes: .30, calves: .20, hamstrings: .10 } });
const variants = [
  variant('bodyweight', 'Peso corporal', 'Peso corporal', ['Peso corporal'], 'bodyweight', 'potencia', 'power', 'standard'),
  variant('bodyweight_metabolic', 'Peso corporal · Metabólico', 'Peso corporal', ['Peso corporal'], 'bodyweight', 'metabolico', 'conditioning', 'metabolic'),
  variant('barbell', 'Barra', 'Peso libre', ['Barra'], 'free', 'potencia', 'power', 'standard'),
  variant('dumbbell', 'Mancuernas', 'Peso libre', ['Mancuernas'], 'free', 'potencia', 'power', 'standard'),
  variant('kettlebell', 'Kettlebell', 'Peso libre', ['Kettlebell'], 'free', 'potencia', 'power', 'standard'),
  variant('abalakov', 'Abalakov', 'Peso corporal', ['Peso corporal'], 'bodyweight', 'potencia', 'power', 'abalakov'),
];
const now = new Date().toISOString();
const fields = Object.fromEntries(Object.entries({ name: 'Jump Squat', exerciseType: 'Potencia', resistanceType: 'free', equipment: ['Peso corporal', 'Barra', 'Mancuernas', 'Kettlebell'], movementClass: 'compound', trackRM: false, trackProgression: false, variants, catalogStatus: 'reviewed_variants', catalogReviewedBy: 'ai_jump_squat_variants_v1', updatedAt: now }).map(([k, v]) => [k, encode(v)]));
const accessToken = await token();
const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/exercises/${exerciseId}`, { method: 'PATCH', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields }) });
if (!response.ok) throw new Error(await response.text());
const blockRef = 'hector_padel_m1_d4_b3';
const blockResponse = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/blocks/${blockRef}`, { method: 'GET', headers: { Authorization: `Bearer ${accessToken}` } });
if (blockResponse.ok) {
  const block = await blockResponse.json();
  const blockFields = block.fields ?? {};
  const rawExercises = blockFields.exercises?.arrayValue?.values ?? [];
  const exercises = rawExercises.map((value) => {
    const item = value.mapValue?.fields ?? {};
    const name = item.name?.stringValue?.toLowerCase() ?? '';
    if (!name.includes('jump squat')) return value;
    return { mapValue: { fields: { ...item, name: { stringValue: 'Jump Squat' }, displayName: { stringValue: 'Jump Squat - Barra' }, exerciseId: { stringValue: exerciseId }, variantId: { stringValue: 'barbell' }, variantLabel: { stringValue: 'Barra' }, familyId: { stringValue: 'jump_squat' }, techniqueId: { stringValue: 'standard' }, equipment: { arrayValue: { values: [{ stringValue: 'Barra' }] } }, resistanceType: { stringValue: 'free' } } } };
  });
  const updateResponse = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/blocks/${blockRef}`, { method: 'PATCH', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: { ...blockFields, exercises: { arrayValue: { values: exercises } }, updatedAt: { stringValue: now } } }) });
  if (!updateResponse.ok) throw new Error(await updateResponse.text());
}
const duplicateId = 'z63uCFihp4alskElXe9x';
const duplicateResponse = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/exercises/${duplicateId}`, { method: 'DELETE', headers: { Authorization: `Bearer ${accessToken}` } });
if (!duplicateResponse.ok && duplicateResponse.status !== 404) throw new Error(await duplicateResponse.text());
console.log(JSON.stringify({ exerciseId, migratedBlock: blockRef, deletedDuplicate: duplicateId, variants: variants.map((v) => ({ id: v.id, label: v.label, discipline: v.trainingDiscipline, intent: v.movementIntent })) }, null, 2));
