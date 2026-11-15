import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const project = 'entrenamientoapplv';
const athleteId = '71DheGSwhtfDEfN4tk3TlI7Kzut1';
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
const ex = (name, series = 3, reps = 10) => ({ name, displayName: name, series, reps, value: reps, valueType: 'reps', weight: 0 });
const definitions = {
  d1_b1: ['POTENCIA 1', '02 · Potencia', ['Jump squat', 'Power clean', 'Hang power snatch']],
  d1_b2: ['FUERZA 1', '01 · Fuerza', ['Sentadilla trasera', 'Peso muerto rumano con barra']],
  d1_b3: ['HIPERTROFIA 1', '03 · Hipertrofia', ['Hack squat', 'Pantorrillas', 'Aductores']],
  d1_b4: ['CORE 1', '04 · Core y estabilidad', ['Press Pallof', 'Lanzamiento lateral de balón', 'Leñador']],
  d2_b1: ['POTENCIA 2', '02 · Potencia', ['Lanzamiento sobre cabeza', 'Landmine snatch', 'Landmine split jerk']],
  d2_b2: ['FUERZA 2', '01 · Fuerza', ['Press banca con barra', 'Press militar con barra']],
  d2_b3: ['CALISTENIA 1', '01 · Fuerza', ['Dominada', 'Fondos', 'Flexiones']],
  d2_b4: ['ACCESORIOS 1', '05 · Accesorios', ['Face pull', 'Plancha Copenhagen', 'Remo máquina sentada']],
  d3_b1: ['HIPERTROFIA 3', '03 · Hipertrofia', ['Press inclinado con mancuernas', 'Jalón al pecho', 'Extensión de tríceps']],
  d3_b2: ['HIPERTROFIA 2', '03 · Hipertrofia', ['Hip thrust', 'Sentadilla búlgara', 'Curl femoral', 'Extensión de cuádriceps']],
  d4_b1: ['PLIOMETRIA 1', '02 · Potencia', ['Lateral bound and stick', 'Salto a cajón']],
  d4_b2: ['POTENCIA 4', '02 · Potencia', ['Hex bar jump squat', 'Push press', 'Landmine thruster']],
  d4_b3: ['POTENCIA 3', '02 · Potencia', ['Jump squat con barra', 'Desplazamiento lateral + sprint', 'Giro 180° con landmine']],
  d5_b1: ['HIPERTROFIA 4', '03 · Hipertrofia', ['Press de pecho', 'Kneeling landmine chest press', 'Rueda abdominal']],
  d5_b2: ['PIERNAS 1', '01 · Fuerza', ['Sentadilla trasera', 'RDL unilateral con barra', 'Step up']],
};
function documentName(collection, id) { return `projects/${project}/databases/(default)/documents/${collection}/${id}`; }
async function commit(accessToken, writes) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:commit`, { method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }) });
  if (!response.ok) throw new Error(await response.text());
}
async function remove(accessToken, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/blocks/${id}`, { method: 'DELETE', headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok && response.status !== 404) throw new Error(await response.text());
}
function write(id, data) { return { update: { name: documentName('blocks', id), fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, encode(v)])) } }; }
const now = new Date().toISOString();
const blockData = (key, [title, folder, names], isTemplate) => ({ title, name: title, type: 'Series', athleteId, folder, isLibraryTemplate: true, libraryOrder: Number(key.match(/d(\d+)_b(\d+)/)[1]) * 100 + Number(key.match(/d(\d+)_b(\d+)/)[2]), exercises: names.map((name) => ex(name)), createdAt: now, updatedAt: now, sourceKey: key, ...(isTemplate ? { templateOf: `hector_padel_m1_${key}` } : {}) });
const accessToken = await token();
const writes = [];
for (const [key, definition] of Object.entries(definitions)) {
  writes.push(write(`hector_padel_m1_${key}`, blockData(key, definition, false)));
  writes.push(write(`library_hector_${key}`, blockData(key, definition, true)));
}
await commit(accessToken, writes);
await remove(accessToken, 'hector_padel_m4_d5_b4');
console.log(JSON.stringify({ restored: Object.keys(definitions).length, createdOrUpdatedDocuments: writes.length, deletedEmptyRootBlock: 'hector_padel_m4_d5_b4' }, null, 2));
