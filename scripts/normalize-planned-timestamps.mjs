import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const project = 'entrenamientoapplv';
const credentialsPath = 'secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json';
const apply = process.argv.includes('--apply');
const b64 = (v) => Buffer.from(v).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

async function token() {
  const service = JSON.parse(readFileSync(credentialsPath, 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64(JSON.stringify({ iss: service.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: service.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned); signer.end();
  const response = await fetch(service.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(service.private_key))}` }) });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()).access_token;
}

async function list(accessToken) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/planned_workouts?pageSize=1000`, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()).documents ?? [];
}

async function updateDate(accessToken, id, timestamp) {
  const url = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/planned_workouts/${id}?updateMask.fieldPaths=date`;
  const response = await fetch(url, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: { date: { timestampValue: timestamp } } }),
  });
  if (!response.ok) throw new Error(`${id}: ${await response.text()}`);
}

const accessToken = await token();
const docs = await list(accessToken);
const candidates = docs.map((doc) => {
  const raw = doc.fields?.date;
  const id = doc.name.split('/').pop();
  const date = raw?.timestampValue ?? raw?.stringValue;
  const parsed = date ? new Date(date) : null;
  return { id, rawType: raw ? Object.keys(raw)[0] : 'missing', date, timestamp: parsed && !Number.isNaN(parsed.getTime()) ? parsed.toISOString() : null };
}).filter((item) => item.rawType !== 'timestampValue');

const invalid = candidates.filter((item) => !item.timestamp);
if (invalid.length) throw new Error(`Fechas inválidas: ${JSON.stringify(invalid)}`);
if (apply) for (const item of candidates) await updateDate(accessToken, item.id, item.timestamp);
console.log(JSON.stringify({ apply, total: docs.length, candidates, normalized: apply ? candidates.length : 0 }, null, 2));
