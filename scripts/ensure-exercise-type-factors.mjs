import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const credentialsPath = process.argv[2];
if (!credentialsPath) throw new Error('Uso: node ensure-exercise-type-factors.mjs <service-account.json>');
const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const base = `https://firestore.googleapis.com/v1/projects/${account.project_id}/databases/(default)/documents`;
const b64 = (value) => Buffer.from(value).toString('base64url');
const encode = (value) => {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'number') return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)])) } };
};

async function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${header}.${claim}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const response = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(account.private_key))}` }) });
  if (!response.ok) throw new Error(`Token: ${response.status}`);
  return (await response.json()).access_token;
}

const access = await token();
const listResponse = await fetch(`${base}/exercise_folders?pageSize=1000`, { headers: { Authorization: `Bearer ${access}` } });
if (!listResponse.ok) throw new Error(`exercise_folders: ${listResponse.status}`);
const documents = (await listResponse.json()).documents ?? [];
const existing = new Map(documents.map((doc) => [doc.fields?.name?.stringValue, doc.name.split('/').at(-1)]));
const desired = [
  ['Fuerza unilateral', 1.10],
  ['Halterofilia', 1.35],
  ['Hipertrofia aislada', 0.85],
  ['Balístico', 0.90],
];
const created = [];
for (const [name, multiplier] of desired) {
  if (existing.has(name)) continue;
  const id = name.toLowerCase().replace(/[^a-z0-9]+/g, '_');
  const fields = {
    name: encode(name),
    multiplier: encode(multiplier),
    createdAt: encode(new Date().toISOString()),
    updatedAt: encode(new Date().toISOString()),
  };
  const response = await fetch(`${base}/exercise_folders/${id}`, { method: 'PATCH', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields }) });
  if (!response.ok) throw new Error(`${name}: ${response.status} ${await response.text()}`);
  created.push({ id, name, multiplier });
}
console.log(JSON.stringify({ created, alreadyPresent: desired.filter(([name]) => existing.has(name)).map(([name]) => name) }, null, 2));
