import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const projectId = 'entrenamientoapplv';
const args = Object.fromEntries(process.argv.slice(2).reduce((all, value, index, list) => {
  if (!value.startsWith('--')) return all;
  const key = value.slice(2);
  all.push([key, list[index + 1]?.startsWith('--') ? true : list[index + 1] ?? true]);
  return all;
}, []));

const normalize = (value) => String(value ?? '')
  .normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
  .replace(/\bbarbell\b/g, 'barra')
  .replace(/\bdumbbells?\b|\bdb\b/g, 'mancuerna')
  .replace(/\bplates?\b/g, 'disco')
  .replace(/\bcables?\b/g, 'polea')
  .replace(/\bbands?\b/g, 'banda elastica')
  .replace(/\bmachine\b/g, 'maquina')
  .replace(/\brdl\b/g, 'rumano')
  .replace(/\bkb\b|\bktb\b/g, 'kettlebell')
  .replace(/olimpica|olympic/g, '')
  .replace(/[^a-z0-9]+/g, ' ').trim().replace(/\s+/g, ' ');

function encode(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return Number.isInteger(value)
    ? { integerValue: String(value) } : { doubleValue: value };
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encode) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)])) } };
}
function decode(value) {
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  return value;
}
function b64(input) { return Buffer.from(input).toString('base64url'); }
async function token(credentialsPath) {
  const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }))}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(account.private_key))}` }) });
  if (!response.ok) throw new Error(`Authentication failed (${response.status})`);
  return (await response.json()).access_token;
}
async function list(base, accessToken, collection) {
  const response = await fetch(`${base}/${collection}?pageSize=500`, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(`Could not read ${collection} (${response.status})`);
  return (await response.json()).documents?.map((document) => ({
    id: document.name.split('/').at(-1),
    fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decode(value)])),
  })) ?? [];
}
function variantIdentity(variant) {
  const technique = normalize(variant.techniqueId || variant.techniqueLabel);
  const equipment = (variant.equipment ?? []).map(normalize).filter(Boolean).sort().join('|');
  const label = normalize(variant.label)
    .replace(/\bmancuernas\b/g, 'mancuerna')
    .replace(/\bkettlebells\b/g, 'kettlebell');
  // Equipment alone never identifies a movement: a front squat and a back
  // squat may both use a bar. Keep the technical label in the identity and
  // only unify literal/normalization aliases (Barra/Barbell is handled by
  // explicit catalog migration, not by this deletion tool).
  return `${technique}::${label}::${equipment}`;
}
function isReferenced(usageDocuments, exerciseId, variant) {
  const id = String(variant.id ?? '');
  if (!id) return true;
  return usageDocuments.some((document) => {
    const raw = JSON.stringify(document.fields);
    // A textual label match is intentionally conservative for legacy records.
    return raw.includes(id) ||
      (raw.includes(exerciseId) && normalize(variant.label).length > 3 && raw.toLowerCase().includes(String(variant.label).toLowerCase()));
  });
}

const credentialsPath = args.credentialsPath;
if (!credentialsPath) throw new Error('Use --credentialsPath <service-account.json>.');
const execute = args.execute === true;
if (execute && args.confirm !== projectId) throw new Error(`Use --execute --confirm ${projectId}.`);
const accessToken = await token(credentialsPath);
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const [exercises, blocks, planned, logged] = await Promise.all([
  list(base, accessToken, 'exercises'), list(base, accessToken, 'blocks'),
  list(base, accessToken, 'planned_workouts'), list(base, accessToken, 'workouts_logged'),
]);
const usageDocuments = [...blocks, ...planned, ...logged];
const updates = [];
const report = [];
for (const exercise of exercises) {
  const variants = Array.isArray(exercise.fields.variants) ? exercise.fields.variants : [];
  const groups = new Map();
  for (const variant of variants) {
    const key = variantIdentity(variant);
    groups.set(key, [...(groups.get(key) ?? []), variant]);
  }
  const removed = [];
  const remaining = [];
  for (const group of groups.values()) {
    if (group.length === 1) { remaining.push(group[0]); continue; }
    const sorted = [...group].sort((a, b) => String(a.id).localeCompare(String(b.id)));
    remaining.push(sorted[0]);
    for (const duplicate of sorted.slice(1)) {
      if (isReferenced(usageDocuments, exercise.id, duplicate)) {
        remaining.push(duplicate);
      } else {
        removed.push({ id: duplicate.id, label: duplicate.label, identity: variantIdentity(duplicate) });
      }
    }
  }
  if (!removed.length) continue;
  updates.push({ id: exercise.id, variants: remaining });
  report.push({ exercise: exercise.fields.name, id: exercise.id, removed, kept: remaining.map((item) => ({ id: item.id, label: item.label })) });
}
console.log(JSON.stringify({ mode: execute ? 'APPLY' : 'DRY-RUN', exercises: exercises.length, candidates: report.length, removedVariants: report.reduce((total, item) => total + item.removed.length, 0), report }, null, 2));
if (!execute || updates.length === 0) process.exit(0);
for (const update of updates) {
  const response = await fetch(`${base}:commit`, {
    method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ writes: [{ update: { name: `projects/${projectId}/databases/(default)/documents/exercises/${update.id}`, fields: { variants: encode(update.variants), updatedAt: encode(new Date().toISOString()) } }, updateMask: { fieldPaths: ['variants', 'updatedAt'] } }] }),
  });
  if (!response.ok) throw new Error(`Could not update ${update.id}: ${await response.text()}`);
}
