import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const account = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const base = `https://firestore.googleapis.com/v1/projects/${account.project_id}/databases/(default)/documents`;
const b64 = (value) => Buffer.from(value).toString('base64url');
const encode = (value) => typeof value === 'number'
  ? (Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value })
  : { stringValue: value };

async function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${header}.${claim}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned); signer.end();
  const response = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(account.private_key))}` }) });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()).access_token;
}

const desired = new Map([
  ['Balísticos', 0.65],
  ['Balístico', 0.65],
  ['Fuerza', 1.35],
  ['Halterofilia', 1.45],
]);
const access = await token();
const listResponse = await fetch(`${base}/exercise_folders?pageSize=1000`, { headers: { Authorization: `Bearer ${access}` } });
if (!listResponse.ok) throw new Error(await listResponse.text());
const documents = (await listResponse.json()).documents ?? [];
const updates = [];
for (const document of documents) {
  const name = document.fields?.name?.stringValue;
  if (!desired.has(name)) continue;
  const multiplier = desired.get(name);
  const current = Number(document.fields?.multiplier?.doubleValue ?? document.fields?.multiplier?.integerValue ?? 1);
  if (current === multiplier) continue;
  const id = document.name.split('/').pop();
  const response = await fetch(`${base}/exercise_folders/${id}?updateMask.fieldPaths=multiplier`, { method: 'PATCH', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: { multiplier: encode(multiplier) } }) });
  if (!response.ok) throw new Error(`${name}: ${await response.text()}`);
  updates.push({ name, from: current, to: multiplier });
}
console.log(JSON.stringify({ updates }, null, 2));
