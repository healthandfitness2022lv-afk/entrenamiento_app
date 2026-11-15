import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const project = 'entrenamientoapplv';
const credentialsPath = 'secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json';
const apply = process.argv.includes('--apply');
const b64 = (v) => Buffer.from(v).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const decode = (v) => v?.stringValue ?? (v?.integerValue !== undefined ? Number(v.integerValue) : v?.doubleValue ?? v?.booleanValue ?? (v?.timestampValue ?? undefined));
const fields = (doc) => Object.fromEntries(Object.entries(doc.fields ?? {}).map(([k, v]) => [k, decode(v)]));
const idOf = (doc) => doc.name.split('/').pop();
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
async function remove(accessToken, id) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/blocks/${id}`, { method: 'DELETE', headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok && response.status !== 404) throw new Error(`${id}: ${await response.text()}`);
}
const accessToken = await token();
const [blockDocs, plannedDocs] = await Promise.all([list(accessToken, 'blocks'), list(accessToken, 'planned_workouts')]);
const referenced = new Set(plannedDocs.map(fields).map((data) => data.blockId?.toString()).filter(Boolean));
const candidates = blockDocs.map((doc) => ({ id: idOf(doc), data: fields(doc) })).filter(({ id, data }) => data.isLibraryTemplate === true && !referenced.has(id));
if (apply) for (const candidate of candidates) await remove(accessToken, candidate.id);
console.log(JSON.stringify({ apply, plannedReferences: referenced.size, candidates: candidates.map(({ id, data }) => ({ id, title: data.title ?? '', folder: data.folder ?? '' })), deleted: apply ? candidates.length : 0 }, null, 2));
