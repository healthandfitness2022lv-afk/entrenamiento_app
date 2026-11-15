import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const project = 'entrenamientoapplv';
const credentialsPath = process.argv[2];
const apply = process.argv.includes('--apply');
if (!credentialsPath) throw new Error('Use: node fix-hang-power-snatch.mjs <credentials.json> [--apply]');
const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const b64 = (value) => Buffer.from(value).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }))}`;
const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
const auth = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(account.private_key))}` }) });
const accessToken = (await auth.json()).access_token;
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const decode = (v) => {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  return null;
};
const encode = (v) => {
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  if (v && typeof v === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([key, item]) => [key, encode(item)])) } };
  return { nullValue: null };
};
async function get(path) {
  const response = await fetch(`${base}/${path}`, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(`${path}: ${await response.text()}`);
  const document = await response.json();
  return { id: document.name.split('/').at(-1), fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decode(value)])) };
}
const exercise = await get('exercises/TENcpqXxXUMy09OHWpkS');
const block = await get('blocks/library_hector_d1_b1');
const extension = await get('exercises/movement_extension_de_cuadriceps');
const extensionBlock = await get('blocks/hector_padel_m1_d3_b2');
const variant = {
  id: 'hang_power_barbell',
  label: 'Barra · Hang Power',
  group: 'Peso libre',
  equipment: ['Barra olímpica'],
  resistanceType: 'free',
  trackRM: true,
  trackProgression: true,
  trainingDiscipline: 'halterofilia',
  movementIntent: 'power',
  familyId: 'snatch',
  techniqueId: 'hang_power',
  techniqueLabel: 'Hang Power',
  isUnilateral: false,
};
const variants = (exercise.fields.variants ?? []).map((item) => ({ ...item, ...variant, id: variant.id }));
const updatedExercise = { ...exercise.fields, exerciseType: 'Halterofilia', variants: [variant], equipment: ['Barra olímpica'], trackRM: true, trackProgression: true, updatedAt: new Date().toISOString() };
const exercises = (block.fields.exercises ?? []).map((item) => {
  if (String(item.name ?? item.exercise ?? '').toLowerCase() !== 'hang power snatch') return item;
  return { ...item, name: 'Hang Power Snatch - Barra · Hang Power', movementName: 'Hang Power Snatch', displayName: 'Hang Power Snatch - Barra · Hang Power', exerciseId: exercise.id, movementId: exercise.id, variantId: variant.id, variantLabel: variant.label, techniqueId: variant.techniqueId, techniqueLabel: variant.techniqueLabel, familyId: variant.familyId, equipment: 'Barra olímpica', resistanceType: 'free', trainingDiscipline: variant.trainingDiscipline, movementIntent: variant.movementIntent, trackRM: true, trackProgression: true };
});
const updatedBlock = { ...block.fields, exercises, updatedAt: new Date().toISOString() };
const extensionVariants = (extension.fields.variants ?? []).map((item) =>
  item.id === 'unilateral_en_maquina'
    ? { ...item, trainingDiscipline: 'hipertrofia', movementIntent: 'full' }
    : item,
);
const updatedExtension = {
  ...extension.fields,
  exerciseType: 'Hipertrofia',
  variants: extensionVariants,
  updatedAt: new Date().toISOString(),
};
const updatedExtensionBlock = {
  ...extensionBlock.fields,
  exercises: (extensionBlock.fields.exercises ?? []).map((item) =>
    item.variantId === 'unilateral_en_maquina'
      ? { ...item, trainingDiscipline: 'hipertrofia', movementIntent: 'full' }
      : item,
  ),
  updatedAt: new Date().toISOString(),
};
console.log(JSON.stringify({ mode: apply ? 'APPLY' : 'DRY-RUN', exerciseId: exercise.id, blockId: block.id, variant, changedBlockExercise: exercises.find((item) => item.variantId === variant.id), extensionVariant: extensionVariants.find((item) => item.id === 'unilateral_en_maquina') }, null, 2));
if (!apply) process.exit(0);
for (const [path, fields] of [
  ['exercises/TENcpqXxXUMy09OHWpkS', updatedExercise],
  ['blocks/library_hector_d1_b1', updatedBlock],
  ['exercises/movement_extension_de_cuadriceps', updatedExtension],
  ['blocks/hector_padel_m1_d3_b2', updatedExtensionBlock],
]) {
  const response = await fetch(`${base}/${path}`, { method: 'PATCH', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, encode(value)])) }) });
  if (!response.ok) throw new Error(`${path}: ${await response.text()}`);
}
