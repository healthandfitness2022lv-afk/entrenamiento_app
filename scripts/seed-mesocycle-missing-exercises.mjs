import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createSign } from "node:crypto";

const projectId = "entrenamientoapplv";
const databaseId = "(default)";
const credentialsPath = resolve("secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json");
const apply = process.argv.includes("--apply");

const movements = [
  ['Extension De Triceps - Cuerda en polea', 'Extensión de tríceps con cuerda', 'Hipertrofia', 'isolation', 'guided', ['Polea alta', 'Cuerda'], { triceps: .9, frontDelts: .05, forearms: .05 }, false, false],
  ['Sentadilla Bulgara - Mancuernas', 'Sentadilla búlgara con mancuernas', 'Fuerza', 'compound', 'free', ['Mancuernas', 'Banco'], { quads: .4, glutes: .3, hamstrings: .12, adductors: .1, calves: .08 }, true, true],
  ['Dominada - Agarre prono', 'Dominada con agarre prono', 'Fuerza', 'compound', 'free', ['Barra de dominadas'], { lats: .5, biceps: .2, midBack: .15, lowerTraps: .1, forearms: .05 }, false, true],
  ['Elevacion Lateral - Mancuernas', 'Elevación lateral con mancuernas', 'Hipertrofia', 'isolation', 'free', ['Mancuernas'], { midDelts: .8, frontDelts: .1, trapsUpper: .1 }, false, false],
  ['Landmine Press - Unilateral', 'Landmine press unilateral', 'Fuerza', 'compound', 'free', ['Landmine', 'Barra'], { frontDelts: .35, midDelts: .25, triceps: .2, serratus: .1, obliques: .1 }, true, true],
  ['Hip Thrust - Barra', 'Hip thrust con barra', 'Fuerza', 'compound', 'free', ['Barra', 'Banco'], { glutes: .55, hamstrings: .2, quads: .1, adductors: .1, lowerBack: .05 }, false, true],
  ['Remo - Máquina sentada', 'Remo sentado en máquina', 'Hipertrofia', 'compound', 'guided', ['Máquina de remo'], { midBack: .4, lats: .3, biceps: .15, rearDelts: .1, lowerTraps: .05 }, false, true],
  ['Peso Muerto - Trap bar', 'Peso muerto con trap bar', 'Fuerza', 'compound', 'free', ['Trap bar'], { quads: .25, glutes: .3, hamstrings: .2, lowerBack: .15, trapsUpper: .1 }, false, true],
  ['Face Pull - Cuerda en polea', 'Face pull con cuerda', 'Hipertrofia', 'isolation', 'guided', ['Polea alta', 'Cuerda'], { rearDelts: .35, midBack: .25, lowerTraps: .2, biceps: .1, frontDelts: .1 }, false, false],
  ['Press De Pecho - Máquina selectorizada', 'Press de pecho en máquina selectorizada', 'Hipertrofia', 'compound', 'guided', ['Máquina de press', 'Máquina selectorizada'], { pecs: .55, frontDelts: .25, triceps: .2 }, false, true],
  ['Lateral bound & stick', 'Salto lateral con estabilización', 'Pliometría', 'compound', 'bodyweight', ['Peso corporal'], { glutes: .25, quads: .2, hamstrings: .15, calves: .15, obliques: .15, abs: .1 }, true, false],
  ['Curl De Biceps - Barra Z', 'Curl de bíceps con barra Z', 'Hipertrofia', 'isolation', 'free', ['Barra Z'], { biceps: .8, forearms: .2 }, false, true],
  ['Remo - Pecho apoyado', 'Remo con pecho apoyado', 'Hipertrofia', 'compound', 'free', ['Mancuernas', 'Banco inclinado'], { midBack: .4, lats: .3, biceps: .15, rearDelts: .1, lowerTraps: .05 }, false, true],
  ['Curl Femoral - Máquina sentado', 'Curl femoral en máquina sentado', 'Hipertrofia', 'isolation', 'guided', ['Máquina de curl femoral sentado'], { hamstrings: .8, glutes: .1, calves: .1 }, false, true],
  ['Extension De Cuadriceps - Bilateral en máquina', 'Extensión de cuádriceps bilateral en máquina', 'Hipertrofia', 'isolation', 'guided', ['Máquina de extensión de cuádriceps'], { quads: .9, calves: .05, glutes: .05 }, false, true],
  ['Press De Hombro - Barra', 'Press de hombro con barra', 'Fuerza', 'compound', 'free', ['Barra', 'Rack'], { frontDelts: .45, midDelts: .2, triceps: .2, upperChest: .1, abs: .05 }, false, true],
  ['Elevacion De Pantorrillas - Máquina sentado', 'Elevación de pantorrillas sentado en máquina', 'Hipertrofia', 'isolation', 'guided', ['Máquina de pantorrillas sentado'], { calves: .95, hamstrings: .05 }, false, true],
  ['Aductor máquina / Copenhagen', 'Aductor en máquina o Copenhagen', 'Hipertrofia', 'isolation', 'guided', ['Máquina de aductores', 'Banco'], { adductors: .65, obliques: .15, abs: .1, hamstrings: .1 }, true, false],
  ['Curl Femoral - Máquina tumbado', 'Curl femoral en máquina tumbado', 'Hipertrofia', 'isolation', 'guided', ['Máquina de curl femoral tumbado'], { hamstrings: .8, glutes: .1, calves: .1 }, false, true],
  ['Landmine Press - Explosivo', 'Landmine press explosivo', 'Potencia', 'compound', 'free', ['Landmine', 'Barra'], { frontDelts: .35, midDelts: .25, triceps: .2, serratus: .1, obliques: .1 }, false, true],
  ['Press De Hombro - Máquina selectorizada', 'Press de hombro en máquina selectorizada', 'Hipertrofia', 'compound', 'guided', ['Máquina de press de hombro'], { frontDelts: .45, midDelts: .25, triceps: .2, upperChest: .1 }, false, true],
  ['Dead Bug', 'Dead bug', 'Core', 'isolation', 'bodyweight', ['Peso corporal'], { abs: .45, lowerAbs: .35, obliques: .2 }, false, false],
  ['Jalon Al Pecho - Agarre ancho', 'Jalón al pecho con agarre ancho', 'Hipertrofia', 'compound', 'guided', ['Polea alta'], { lats: .45, midBack: .2, biceps: .2, lowerTraps: .1, forearms: .05 }, false, true],
  ['Press De Pecho - Barra en banco plano', 'Press de pecho con barra en banco plano', 'Fuerza', 'compound', 'free', ['Barra', 'Banco plano'], { pecs: .55, frontDelts: .25, triceps: .2 }, false, true],
  ['Curl De Biceps - Polea baja', 'Curl de bíceps en polea baja', 'Hipertrofia', 'isolation', 'guided', ['Polea baja'], { biceps: .8, forearms: .2 }, false, true],
  ['Press Pallof - Polea', 'Press Pallof en polea', 'Core', 'isolation', 'guided', ['Polea'], { obliques: .45, abs: .35, serratus: .1, frontDelts: .1 }, true, false],
  ['Peso Muerto - Rumano con barra', 'Peso muerto rumano con barra', 'Fuerza', 'compound', 'free', ['Barra'], { hamstrings: .45, glutes: .3, lowerBack: .15, adductors: .1 }, false, true],
];

function toBase64Url(input) { return (Buffer.isBuffer(input) ? input : Buffer.from(input)).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_'); }
function fsValue(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(fsValue) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, fsValue(item)])) } };
}
function decode(value) {
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue?.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  if ('arrayValue' in value) return (value.arrayValue?.values ?? []).map(decode);
  return value;
}
function slug(name) { return `movement_${name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')}`; }
function resource(id) { return `projects/${projectId}/databases/${databaseId}/documents/exercises/${id}`; }
function collectionUrl(collection) { return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents/${collection}`; }
function collectionResource(collection, id) { return `projects/${projectId}/databases/${databaseId}/documents/${collection}/${id}`; }
function url() { return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents/exercises`; }
async function token() {
  const account = JSON.parse(readFileSync(credentialsPath, 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const head = toBase64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const body = toBase64Url(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${head}.${body}`; const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${toBase64Url(signer.sign(account.private_key))}` }) });
  if (!response.ok) throw new Error(`Token ${response.status}`); return (await response.json()).access_token;
}
async function main() {
  const access = await token();
  const response = await fetch(`${url()}?pageSize=1000`, { headers: { Authorization: `Bearer ${access}` } });
  if (!response.ok) throw new Error(`Catálogo ${response.status}: ${await response.text()}`);
  const existing = (await response.json()).documents ?? [];
  const names = new Set(existing.map((doc) => String(decode(doc.fields?.name)).trim().toLowerCase()));
  const missing = movements.filter(([name]) => !names.has(name.trim().toLowerCase()));
  const writes = missing.map(([name, label, type, movementClass, resistanceType, equipment, muscleWeights, unilateral, trackRM]) => {
    const id = slug(name);
    const steps = `1. Colócate y ajusta el implemento manteniendo una postura estable.\n2. Inicia el movimiento con control y activa la musculatura indicada.\n3. Completa el recorrido sin compensaciones y mantén la técnica.\n4. Regresa de forma controlada y repite las repeticiones programadas.`;
    const variant = { id: 'original', label, group: resistanceType === 'guided' ? 'Máquina' : resistanceType === 'bodyweight' ? 'Peso corporal' : 'Peso libre', equipment, resistanceType, trackRM, isUnilateral: unilateral, needsReview: false };
    const fields = { name, instructions: steps, muscleWeights, exerciseType: type, movementClass, resistanceType, equipment, isUnilateral: unilateral, trackRM, variants: [variant], catalogStatus: 'reviewed_single', catalogReviewedBy: 'ai_initial_review_v1', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
    return { update: { name: resource(id), fields: Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, fsValue(value)])) } };
  });
  console.log(JSON.stringify({ mode: apply ? 'APPLY' : 'DRY-RUN', catalogBefore: existing.length, missingFound: missing.length, names: missing.map(([name]) => name), createdIds: writes.map((write) => write.update.name.split('/').pop()) }, null, 2));
  if (!apply) return;
  if (writes.length) {
    const commit = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents:commit`, { method: 'POST', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }) });
    if (!commit.ok) throw new Error(`Commit ${commit.status}: ${await commit.text()}`);
    console.log(`Creados ${writes.length} ejercicios faltantes.`);
  }

  const refreshed = await fetch(`${url()}?pageSize=1000`, { headers: { Authorization: `Bearer ${access}` } });
  const catalog = (await refreshed.json()).documents ?? [];
  const byName = new Map(catalog.map((doc) => [String(decode(doc.fields?.name)).trim().toLowerCase(), { id: doc.name.split('/').pop(), data: Object.fromEntries(Object.entries(doc.fields ?? {}).map(([key, value]) => [key, decode(value)])) }]));
  const blocksResponse = await fetch(`${collectionUrl('blocks')}?pageSize=1000`, { headers: { Authorization: `Bearer ${access}` } });
  const blockDocs = (await blocksResponse.json()).documents ?? [];
  const identityWrites = [];
  for (const doc of blockDocs) {
    const fields = Object.fromEntries(Object.entries(doc.fields ?? {}).map(([key, value]) => [key, decode(value)]));
    const exercises = Array.isArray(fields.exercises) ? fields.exercises.map((raw) => ({ ...raw })) : [];
    let changed = false;
    for (const exercise of exercises) {
      if (exercise.exerciseId) continue;
      const originalName = String(exercise.name ?? exercise.exercise ?? '').trim();
      const baseName = originalName.split(' - ')[0].trim().toLowerCase();
      const match = byName.get(originalName.toLowerCase()) ?? byName.get(baseName);
      if (!match) continue;
      const variants = Array.isArray(match.data.variants) ? match.data.variants : [];
      const suffix = originalName.includes(' - ') ? originalName.split(' - ').slice(1).join(' - ').trim().toLowerCase() : '';
      const variant = variants.find((item) => suffix && String(item.label ?? '').trim().toLowerCase().includes(suffix)) ?? variants[0];
      exercise.exerciseId = match.id;
      exercise.variantId = variant?.id ?? 'original';
      exercise.variantLabel = variant?.label ?? 'Original';
      exercise.displayName = originalName;
      changed = true;
    }
    if (changed) {
      identityWrites.push({ update: { name: collectionResource('blocks', doc.name.split('/').pop()), fields: { exercises: fsValue(exercises) } }, updateMask: { fieldPaths: ['exercises'] } });
    }
  }
  if (identityWrites.length) {
    const identityCommit = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents:commit`, { method: 'POST', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes: identityWrites }) });
    if (!identityCommit.ok) throw new Error(`Identidad ${identityCommit.status}: ${await identityCommit.text()}`);
  }
  console.log(`Identidad completada en ${identityWrites.length} bloques.`);
}
main().catch((error) => { console.error(error.message); process.exit(1); });
