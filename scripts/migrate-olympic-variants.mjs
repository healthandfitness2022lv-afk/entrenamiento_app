import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentialsPath = 'secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json';
const dryRun = !process.argv.includes('--apply');
const idFor = (name) => `movement_${name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')}`;
const normalize = (name) => name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
const fsValue = (value) => value === null ? { nullValue: null } : typeof value === 'string' ? { stringValue: value } : typeof value === 'boolean' ? { booleanValue: value } : typeof value === 'number' ? (Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value }) : Array.isArray(value) ? { arrayValue: { values: value.map(fsValue) } } : { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, fsValue(v)])) } };
const decode = (v) => {
  if (!v) return v;
  if (v.stringValue !== undefined) return v.stringValue;
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.doubleValue !== undefined) return v.doubleValue;
  if (v.booleanValue !== undefined) return v.booleanValue;
  if (v.nullValue !== undefined) return null;
  if (v.arrayValue) return (v.arrayValue.values ?? []).map(decode);
  if (v.mapValue) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, x]) => [k, decode(x)]));
  return v.timestampValue ?? v;
};
const fieldsOf = (doc) => Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, decode(v)]));
const documentId = (doc) => doc.name.split('/').pop();
const toBase64Url = (input) => Buffer.from(input).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

async function accessToken() {
  const service = JSON.parse(readFileSync(credentialsPath, 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const header = toBase64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = toBase64Url(JSON.stringify({ iss: service.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: service.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${header}.${payload}`; const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(service.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${toBase64Url(signer.sign(service.private_key))}` }) });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()).access_token;
}
async function list(token) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/exercises?pageSize=1000`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()).documents ?? [];
}
async function write(token, id, data) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/exercises/${id}`, { method: 'PATCH', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, fsValue(v)])) }) });
  if (!response.ok) throw new Error(`${id}: ${await response.text()}`);
}

const weights = { quads: .22, glutes: .24, hamstrings: .12, trapsUpper: .16, lowerBack: .08, abs: .08, midGlutes: .05, adductors: .05 };
const steps = '1. Coloca los implementos y adopta una postura atlética estable.\n2. Flexiona caderas y rodillas manteniendo la espalda neutra.\n3. Extiende con potencia y recibe el implemento con control.\n4. Estabiliza, vuelve al inicio y repite con una ejecución fluida.';
const variant = (id, label, equipment, discipline, intent, unilateral = false, rm = false, progression = false) => ({ id, label, group: 'Peso libre', equipment, resistanceType: 'free', isUnilateral: unilateral, trackRM: rm, trackProgression: progression, trainingDiscipline: discipline, movementIntent: intent });
const standardVariants = [
  variant('barbell_olympic', 'Barra olímpica', ['Barra'], 'halterofilia', 'full', false, true, true),
  variant('landmine', 'Landmine', ['Barra', 'Landmine'], 'balistico', 'power', false, false, false),
  variant('dumbbell', 'Mancuernas', ['Mancuernas'], 'balistico', 'power', true, false, false),
  variant('kettlebell', 'Kettlebell', ['Kettlebell'], 'balistico', 'power', true, false, false),
  variant('medball', 'Balón medicinal', ['Balón medicinal'], 'metabolico', 'conditioning', false, false, false),
];
const newCleanJerk = {
  name: 'Clean & Jerk', movementClass: 'compound', exerciseType: 'Halterofilia', resistanceType: 'free', equipment: ['Barra'], isUnilateral: false,
  instructions: steps, muscleWeights: weights, variants: standardVariants, trackRM: true, trackProgression: true, catalogStatus: 'reviewed_single', catalogReviewedBy: 'ai_initial_review_v1', videoUrl: '', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
};
const rotation = {
  name: 'Giro 180° con landmine', aliases: ['Landmine 180° Rotacional'], movementClass: 'compound', exerciseType: 'Balísticos', resistanceType: 'free', equipment: ['Barra', 'Landmine'], isUnilateral: true,
  instructions: '1. Coloca un extremo de la barra en el landmine y sujeta el otro con ambas manos frente al cuerpo.\n2. Adopta una postura atlética con caderas y rodillas semiflexionadas y el abdomen activo.\n3. Gira con potencia desde caderas y tronco llevando la barra hacia un lado sin perder el control lumbar.\n4. Regresa al centro y rota hacia el lado contrario, alternando 180° de forma fluida.',
  muscleWeights: { obliques: .35, abs: .15, midGlutes: .15, glutes: .12, quads: .08, lowerBack: .08, lats: .04, serratus: .03 },
  variants: [variant('bilateral_alternating', 'Bilateral alternado 180°', ['Barra', 'Landmine'], 'balistico', 'power', true, false, false)], trackRM: false, trackProgression: false, catalogStatus: 'reviewed_single', catalogReviewedBy: 'ai_initial_review_v1', videoUrl: '', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
};
const deadliftVariant = (techniqueId, techniqueLabel, equipmentId, label, equipment, discipline = 'fuerza', rm = true, progression = true) => ({
  id: `${techniqueId}_${equipmentId}`,
  label,
  familyId: 'deadlift',
  techniqueId,
  techniqueLabel,
  group: equipment.includes('Trap bar') ? 'Peso libre' : 'Peso libre',
  equipment,
  resistanceType: 'free',
  isUnilateral: false,
  trackRM: rm,
  trackProgression: progression,
  trainingDiscipline: discipline,
  movementIntent: 'full',
  muscleWeightOverrides: techniqueId === 'romanian'
    ? { hamstrings: .45, glutes: .30, lowerBack: .15, adductors: .10 }
    : techniqueId === 'sumo'
      ? { adductors: .30, glutes: .30, quads: .20, hamstrings: .10, lowerBack: .10 }
      : techniqueId === 'trap_bar'
        ? { quads: .25, glutes: .30, hamstrings: .20, trapsUpper: .15, lowerBack: .10 }
        : { glutes: .30, hamstrings: .25, quads: .15, lowerBack: .20, trapsUpper: .10 },
});
const deadlift = {
  name: 'Peso Muerto', familyId: 'deadlift', movementClass: 'compound', exerciseType: 'Fuerza', resistanceType: 'free', equipment: ['Barra', 'Mancuernas', 'Kettlebell', 'Trap bar'], isUnilateral: false,
  instructions: steps,
  muscleWeights: { glutes: .30, hamstrings: .25, quads: .15, lowerBack: .20, trapsUpper: .10 },
  variants: [
    deadliftVariant('conventional', 'Convencional', 'barbell', 'Convencional con barra', ['Barra']),
    deadliftVariant('conventional', 'Convencional', 'trap_bar', 'Convencional con trap bar', ['Trap bar']),
    deadliftVariant('romanian', 'Rumano', 'barbell', 'Rumano con barra', ['Barra']),
    deadliftVariant('romanian', 'Rumano', 'dumbbell', 'Rumano con mancuernas', ['Mancuernas'], 'hipertrofia', false, false),
    deadliftVariant('romanian', 'Rumano', 'kettlebell', 'Rumano con kettlebell', ['Kettlebell'], 'hipertrofia', false, false),
    deadliftVariant('sumo', 'Sumo', 'barbell', 'Sumo con barra', ['Barra']),
    deadliftVariant('sumo', 'Sumo', 'kettlebell', 'Sumo con kettlebell', ['Kettlebell'], 'fuerza', false, false),
    deadliftVariant('deficit', 'Déficit', 'barbell', 'Déficit con barra', ['Barra']),
    deadliftVariant('stiff_leg', 'Piernas rígidas', 'barbell', 'Piernas rígidas con barra', ['Barra']),
    deadliftVariant('rack_pull', 'Desde bloques / Rack pull', 'barbell', 'Rack pull con barra', ['Barra']),
  ], trackRM: true, trackProgression: true, catalogStatus: 'reviewed_single', catalogReviewedBy: 'ai_initial_review_v1', videoUrl: '', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
};

const token = await accessToken();
const docs = await list(token);
const byName = new Map(docs.map((doc) => [normalize(fieldsOf(doc).name ?? ''), { id: documentId(doc), data: fieldsOf(doc) }]));
const updates = [];
for (const family of ['Clean', 'Power Clean', 'Snatch', 'Power Snatch', 'Jerk', 'Push Jerk', 'Split Jerk']) {
  const match = [...byName.entries()].find(([name]) => name === normalize(family));
  const current = match?.[1];
  const key = match?.[0];
  const currentVariants = Array.isArray(current?.data.variants) ? current.data.variants : [];
  if (!current) {
    updates.push({
      id: idFor(family),
      data: {
        name: family,
        movementClass: 'compound',
        exerciseType: family.startsWith('Power') ? 'Balísticos' : 'Halterofilia',
        resistanceType: 'free',
        equipment: ['Barra'],
        isUnilateral: family === 'Split Jerk',
        instructions: steps,
        muscleWeights: weights,
        variants: standardVariants.map((item) => ({ ...item, familyId: normalize(family).replace(/ /g, '_'), techniqueId: family.startsWith('Power') ? 'power' : 'full', techniqueLabel: family, movementIntent: family.startsWith('Power') ? 'power' : item.movementIntent })),
        trackRM: true,
        trackProgression: true,
        catalogStatus: 'reviewed_single',
        catalogReviewedBy: 'ai_initial_review_v1',
        videoUrl: '',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    });
    continue;
  }
  const classifiedExisting = currentVariants.map((item) => {
    const equipment = item.equipment ?? [];
    const text = equipment.join(' ').toLowerCase();
    const discipline = text.includes('med') ? 'metabolico' : text.includes('kettlebell') || text.includes('mancuer') || text.includes('landmine') ? 'balistico' : 'halterofilia';
    return {
      ...item,
      trainingDiscipline: item.trainingDiscipline ?? discipline,
      movementIntent: item.movementIntent ?? (family.startsWith('Power') ? 'power' : 'full'),
      trackProgression: item.trackProgression === true || discipline === 'halterofilia',
      trackRM: item.trackRM === true || discipline === 'halterofilia',
    };
  });
  const familyId = normalize(family).replace(/ /g, '_');
  const techniqueId = family.toLowerCase().includes('power') ? 'power' : 'full';
  const familyVariants = standardVariants.map((incoming) => ({
    ...incoming,
    familyId,
    techniqueId,
    techniqueLabel: family,
  }));
  const merged = [...classifiedExisting];
  for (const incoming of familyVariants) {
    const index = merged.findIndex((item) => item.id === incoming.id);
    if (index >= 0) merged[index] = { ...merged[index], ...incoming };
    else merged.push(incoming);
  }
  updates.push({ id: current.id, data: { ...current.data, variants: merged, equipment: [...new Set(merged.flatMap((v) => v.equipment ?? []))], updatedAt: new Date().toISOString() } });
  byName.delete(key);
}
for (const item of [newCleanJerk, rotation, deadlift]) {
  const enrichedItem = {
    ...item,
    variants: item.variants.map((variant) => ({
      ...variant,
      familyId: variant.familyId ?? normalize(item.name).replace(/ /g, '_'),
      techniqueId: variant.techniqueId ?? 'default',
      techniqueLabel: variant.techniqueLabel ?? item.name,
    })),
  };
  const existing = byName.get(normalize(item.name));
  if (!existing) {
    updates.push({ id: idFor(item.name), data: enrichedItem });
    continue;
  }
  const oldVariants = Array.isArray(existing.data.variants) ? existing.data.variants : [];
  const mergedVariants = enrichedItem.variants.map((incoming) => {
    const match = oldVariants.find((old) => normalize(old.label ?? '') === normalize(incoming.label));
    return match ? { ...incoming, id: match.id ?? incoming.id, needsReview: match.needsReview === true } : incoming;
  });
  for (const old of oldVariants) {
    if (!mergedVariants.some((variant) => variant.id === old.id)) mergedVariants.push(old);
  }
  updates.push({ id: existing.id, data: { ...existing.data, ...enrichedItem, variants: mergedVariants, updatedAt: new Date().toISOString() } });
}
console.log(JSON.stringify({ mode: dryRun ? 'DRY-RUN' : 'APPLY', updates: updates.map((item) => ({ id: item.id, name: item.data.name, variants: item.data.variants.map((v) => `${v.label}:${v.trainingDiscipline}`) })) }, null, 2));
if (!dryRun) for (const item of updates) await write(token, item.id, item.data);
