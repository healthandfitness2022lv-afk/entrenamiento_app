import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Usage: node scripts/consolidate-olympic-families.mjs <service-account.json> [--apply]
const credentialsPath = process.argv[2];
const apply = process.argv.includes('--apply');
if (!credentialsPath) throw new Error('Provide a service-account JSON path.');
const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const base = `https://firestore.googleapis.com/v1/projects/${account.project_id}/databases/(default)/documents`;
const normalize = (value) => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const b64 = (value) => Buffer.from(value).toString('base64url');

async function token() {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }))}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(account.private_key))}` }) });
  if (!response.ok) throw new Error(`Token: ${response.status}`);
  return (await response.json()).access_token;
}
function decode(v) {
  if (!v || typeof v !== 'object') return v;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, x]) => [k, decode(x)]));
  return null;
}
function encode(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)])) } };
}
async function list(access, collection) {
  const response = await fetch(`${base}/${collection}?pageSize=1000`, { headers: { Authorization: `Bearer ${access}` } });
  if (!response.ok) throw new Error(`${collection}: ${response.status}`);
  return ((await response.json()).documents ?? []).map((doc) => ({ id: doc.name.split('/').at(-1), data: Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, decode(v)])) }));
}
async function put(access, collection, id, data) {
  const response = await fetch(`${base}/${collection}/${id}`, { method: 'PATCH', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).filter(([key]) => !key.startsWith('_')).map(([key, value]) => [key, encode(value)])) }) });
  if (!response.ok) throw new Error(`${collection}/${id}: ${response.status} ${await response.text()}`);
}

const definitions = {
  snatch: { canonical: 'Snatch', type: 'Halterofilia', variants: [
    ['Snatch', 'barbell_olympic', 'Squat Snatch', 'Halterofilia', 'halterofilia', 'full', ['Barra']],
    ['Power Snatch', 'power_barbell', 'Power Snatch', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'hang_barbell', 'Hang Snatch', 'Halterofilia', 'halterofilia', 'full', ['Barra']],
    ['Hang power Snatch', 'hang_power_barbell', 'Hang Power Snatch', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'pull_barbell', 'Snatch Pull', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'hang_pull_barbell', 'Hang Snatch Pull', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'deadlift_barbell', 'Peso muerto de Snatch', 'Halterofilia', 'halterofilia', 'full', ['Barra']],
    ['Hang high Snatch pull', 'high_pull_barbell', 'Snatch High Pull', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['DB Snatch alternado', 'alternating_dumbbell', 'Snatch alternado', 'Balístico', 'balistico', 'power', ['Mancuernas']],
    ['Landmine Snatch', 'landmine', 'Snatch', 'Balístico', 'balistico', 'power', ['Barra', 'Landmine']],
  ]},
  clean: { canonical: 'Clean', type: 'Halterofilia', variants: [
    ['Clean', 'barbell_olympic', 'Squat Clean', 'Halterofilia', 'halterofilia', 'full', ['Barra']],
    ['Power Clean', 'power_barbell', 'Power Clean', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'hang_barbell', 'Hang Clean', 'Halterofilia', 'halterofilia', 'full', ['Barra']],
    ['Hang power clean', 'hang_power_barbell', 'Hang Power Clean', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'pull_barbell', 'Clean Pull', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'hang_pull_barbell', 'Hang Clean Pull', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['', 'deadlift_barbell', 'Peso muerto de Clean', 'Halterofilia', 'halterofilia', 'full', ['Barra']],
    ['Landmine Clean', 'landmine', 'Clean', 'Balístico', 'balistico', 'power', ['Barra', 'Landmine']],
    ['Medball Squat Clean', 'squat_medball', 'Squat Clean', 'Metabólico', 'metabolico', 'conditioning', ['Balón medicinal']],
  ]},
  jerk: { canonical: 'Jerk', type: 'Halterofilia', variants: [
    ['Jerk', 'barbell_olympic', 'Jerk', 'Halterofilia', 'halterofilia', 'full', ['Barra']],
    ['Push Jerk', 'push_barbell', 'Push Jerk', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['Split Jerk', 'split_barbell', 'Split Jerk', 'Halterofilia', 'halterofilia', 'power', ['Barra']],
    ['Landmine Split Jerk unilateral', 'split_landmine', 'Split Jerk', 'Balístico', 'balistico', 'power', ['Barra', 'Landmine']],
  ]},
};
function variant(id, label, type, discipline, intent, equipment) {
  const techniqueId = id === 'barbell_olympic'
    ? (label === 'Jerk' ? 'jerk' : 'full')
    : id.replace(/_(barbell|dumbbell|medball|landmine)$/, '');
  return { id, label: equipment.includes('Landmine') ? `${label} · Landmine` : `${label} · ${equipment[0]}`, group: 'Peso libre', equipment, resistanceType: 'free', isUnilateral: id.includes('alternating') || id.includes('split_landmine'), trackRM: type === 'Halterofilia', trackProgression: type === 'Halterofilia', exerciseType: type, trainingDiscipline: discipline, movementIntent: intent, familyId: '', techniqueId, techniqueLabel: label };
}
function enrichExistingVariant(family, current) {
  const equipment = Array.isArray(current.equipment) ? current.equipment : [];
  const usesLandmine = equipment.includes('Landmine');
  const usesMedball = equipment.includes('Balón medicinal');
  const usesBarbell = equipment.includes('Barra') && !usesLandmine;
  const type = usesBarbell ? 'Halterofilia' : usesMedball ? 'Metabólico' : 'Balístico';
  const discipline = usesBarbell ? 'halterofilia' : usesMedball ? 'metabolico' : 'balistico';
  const intent = usesMedball ? 'conditioning' : usesBarbell ? 'full' : 'power';
  const technique = family === 'jerk' && usesBarbell ? 'jerk' : usesBarbell ? 'full' : 'power';
  return {
    ...current,
    familyId: family,
    techniqueId: technique,
    techniqueLabel: family === 'jerk' && usesBarbell ? 'Jerk' : usesBarbell ? `Squat ${family[0].toUpperCase()}${family.slice(1)}` : current.label,
    exerciseType: type,
    trainingDiscipline: discipline,
    movementIntent: intent,
  };
}
function olympicVariantWeights(family, variantId) {
  const snatch = {
    barbell_olympic: { quads: .20, glutes: .15, hamstrings: .10, lowerBack: .10, trapsUpper: .15, lats: .10, frontDelts: .07, midDelts: .04, abs: .05, obliques: .04 },
    power_barbell: { quads: .16, glutes: .17, hamstrings: .15, lowerBack: .13, trapsUpper: .17, lats: .09, frontDelts: .04, abs: .05, obliques: .04 },
    hang_barbell: { quads: .12, glutes: .16, hamstrings: .19, lowerBack: .14, trapsUpper: .18, lats: .10, frontDelts: .03, abs: .04, obliques: .04 },
    hang_power_barbell: { quads: .12, glutes: .17, hamstrings: .18, lowerBack: .14, trapsUpper: .18, lats: .10, frontDelts: .03, abs: .04, obliques: .04 },
    high_pull_barbell: { quads: .08, glutes: .18, hamstrings: .20, lowerBack: .16, trapsUpper: .21, lats: .11, abs: .03, obliques: .03 },
    pull_barbell: { quads: .08, glutes: .18, hamstrings: .20, lowerBack: .16, trapsUpper: .21, lats: .11, abs: .03, obliques: .03 },
    hang_pull_barbell: { quads: .05, glutes: .16, hamstrings: .24, lowerBack: .18, trapsUpper: .21, lats: .10, abs: .03, obliques: .03 },
    deadlift_barbell: { quads: .04, glutes: .22, hamstrings: .27, lowerBack: .20, trapsUpper: .13, lats: .07, abs: .04, obliques: .03 },
  };
  const clean = {
    barbell_olympic: { quads: .25, glutes: .16, hamstrings: .10, lowerBack: .09, trapsUpper: .15, lats: .08, frontDelts: .07, midDelts: .04, abs: .04, obliques: .02 },
    power_barbell: { quads: .20, glutes: .17, hamstrings: .14, lowerBack: .12, trapsUpper: .16, lats: .08, frontDelts: .05, midDelts: .03, abs: .03, obliques: .02 },
    hang_barbell: { quads: .16, glutes: .17, hamstrings: .18, lowerBack: .14, trapsUpper: .17, lats: .08, frontDelts: .03, midDelts: .02, abs: .03, obliques: .02 },
    hang_power_barbell: { quads: .16, glutes: .18, hamstrings: .17, lowerBack: .14, trapsUpper: .17, lats: .08, frontDelts: .03, midDelts: .02, abs: .03, obliques: .02 },
    pull_barbell: { quads: .14, glutes: .20, hamstrings: .18, lowerBack: .14, trapsUpper: .19, lats: .08, frontDelts: .03, abs: .02, midDelts: .01, obliques: .01 },
    hang_pull_barbell: { quads: .10, glutes: .18, hamstrings: .23, lowerBack: .17, trapsUpper: .20, lats: .07, frontDelts: .02, abs: .01, midDelts: .01, obliques: .01 },
    deadlift_barbell: { quads: .16, glutes: .22, hamstrings: .25, lowerBack: .20, trapsUpper: .10, lats: .04, abs: .02, obliques: .01 },
  };
  const profiles = family === 'snatch' ? snatch : family === 'clean' ? clean : {};
  const direct = profiles[variantId];
  if (direct) return direct;
  if (['landmine', 'dumbbell', 'kettlebell', 'alternating_dumbbell'].includes(variantId)) {
    return family === 'clean' ? clean.power_barbell : snatch.power_barbell;
  }
  if (variantId.includes('medball')) {
    return family === 'clean'
      ? { quads: .24, glutes: .18, hamstrings: .10, abs: .12, obliques: .10, frontDelts: .10, lats: .08, lowerBack: .08 }
      : { quads: .14, glutes: .16, hamstrings: .12, abs: .16, obliques: .14, frontDelts: .12, lats: .08, lowerBack: .08 };
  }
  return null;
}
function rewrite(value, redirect) {
  if (Array.isArray(value)) return value.map((item) => rewrite(item, redirect));
  if (!value || typeof value !== 'object') return value;
  const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, rewrite(item, redirect)]));
  const sourceId = result.exerciseId ?? result.movementId;
  const target = redirect.get(sourceId);
  if (!target) return result;
  return { ...result, exerciseId: target.exerciseId, movementId: target.exerciseId, variantId: target.variantId, variantLabel: target.label, familyId: target.family, techniqueId: target.techniqueId, techniqueLabel: target.techniqueLabel, exerciseType: target.exerciseType, trainingDiscipline: target.discipline, movementIntent: target.intent, displayName: `${target.movementName} - ${target.label}`, name: `${target.movementName} - ${target.label}` };
}

const access = await token();
const exercises = await list(access, 'exercises');
const byName = new Map(exercises.map((item) => [normalize(item.data.name), item]));
const updates = [];
const redirects = new Map();
for (const [family, config] of Object.entries(definitions)) {
  const parent = byName.get(normalize(config.canonical));
  if (!parent) throw new Error(`Canonical exercise missing: ${config.canonical}`);
  const variants = (Array.isArray(parent.data.variants) ? parent.data.variants : [])
    .map((current) => enrichExistingVariant(family, current));
  for (const [sourceName, id, label, type, discipline, intent, equipment] of config.variants) {
    const source = byName.get(normalize(sourceName));
    const incoming = { ...variant(id, label, type, discipline, intent, equipment), familyId: family };
    const existingIndex = variants.findIndex((item) => item.id === id);
    if (existingIndex >= 0) variants[existingIndex] = { ...variants[existingIndex], ...incoming };
    else variants.push(incoming);
    if (source && source.id !== parent.id) redirects.set(source.id, { exerciseId: parent.id, movementName: parent.data.name, variantId: id, label: incoming.label, family, techniqueId: incoming.techniqueId, techniqueLabel: label, exerciseType: type, discipline, intent });
  }
  for (let index = 0; index < variants.length; index += 1) {
    const weights = olympicVariantWeights(family, variants[index].id);
    if (weights) variants[index] = { ...variants[index], muscleWeightOverrides: weights };
  }
  updates.push({ collection: 'exercises', id: parent.id, data: { ...parent.data, familyId: family, exerciseType: config.type, trainingDiscipline: 'halterofilia', movementIntent: 'power', variants, updatedAt: new Date().toISOString() } });
}
for (const [sourceId, target] of redirects) {
  const source = exercises.find((item) => item.id === sourceId);
  updates.push({ collection: 'exercises', id: sourceId, data: { ...source.data, mergedInto: target.exerciseId, canonicalExerciseId: target.exerciseId, familyId: target.family, updatedAt: new Date().toISOString() } });
}
for (const collection of ['blocks', 'planned_workouts', 'workouts_logged', 'routines']) {
  const docs = await list(access, collection);
  for (const doc of docs) {
    const next = rewrite(doc.data, redirects);
    if (JSON.stringify(next) !== JSON.stringify(doc.data)) updates.push({ collection, id: doc.id, data: { ...next, updatedAt: new Date().toISOString() } });
  }
}
console.log(JSON.stringify({ mode: apply ? 'APPLY' : 'DRY-RUN', parents: updates.filter((item) => item.collection === 'exercises' && !item.data.mergedInto).map((item) => ({ id: item.id, name: item.data.name, family: item.data.familyId, variants: item.data.variants.filter((variant) => ['snatch', 'clean', 'jerk'].includes(variant.familyId)).map((variant) => `${variant.techniqueId} · ${variant.label} · ${variant.exerciseType}`) })), redirects: [...redirects.entries()].map(([from, to]) => ({ from, to: `${to.movementName} / ${to.variantId}` })), dependentDocuments: updates.filter((item) => item.collection !== 'exercises').map((item) => `${item.collection}/${item.id}`) }, null, 2));
if (apply) for (const update of updates) await put(access, update.collection, update.id, update.data);
