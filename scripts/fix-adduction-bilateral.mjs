import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const credentialsPath = process.argv[2] ?? 'secrets/serviceAccountKey.json';
const apply = process.argv.includes('--apply');
const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const b64 = (value) => Buffer.from(value).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({
  iss: account.client_email,
  scope: 'https://www.googleapis.com/auth/datastore',
  aud: account.token_uri,
  iat: now,
  exp: now + 3600,
}))}`;
const signer = createSign('RSA-SHA256');
signer.update(unsigned);
signer.end();
const auth = await fetch(account.token_uri, {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: `${unsigned}.${b64(signer.sign(account.private_key))}`,
  }),
});
if (!auth.ok) throw new Error(`Token: ${auth.status}`);
const token = (await auth.json()).access_token;
const url = `https://firestore.googleapis.com/v1/projects/${account.project_id}/databases/(default)/documents/exercises/movement_aductor_maquina_copenhagen`;
const responseToJs = (value) => {
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(responseToJs);
  if ('mapValue' in value) {
    return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, responseToJs(item)]));
  }
  return null;
};
const jsToFirestore = (value) => {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(jsToFirestore) } };
  if (value && typeof value === 'object') {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, jsToFirestore(item)])) } };
  }
  return { nullValue: null };
};
const fields = {
  isUnilateral: { booleanValue: false },
  updatedAt: { timestampValue: new Date().toISOString() },
};
console.log(JSON.stringify({ mode: apply ? 'APPLY' : 'DRY-RUN', exercise: 'Aducción de cadera', isUnilateral: false }, null, 2));
if (!apply) process.exit(0);
const current = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
if (!current.ok) throw new Error(`Get: ${current.status} ${await current.text()}`);
const currentDocument = await current.json();
const currentVariants = responseToJs(currentDocument.fields?.variants);
if (Array.isArray(currentVariants)) {
  const original = currentVariants.find((variant) => variant.id === 'original');
  if (original) original.isUnilateral = false;
  fields.variants = jsToFirestore(currentVariants);
}
const response = await fetch(`${url}?updateMask.fieldPaths=isUnilateral&updateMask.fieldPaths=updatedAt&updateMask.fieldPaths=variants`, {
  method: 'PATCH',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ fields }),
});
if (!response.ok) throw new Error(`Patch: ${response.status} ${await response.text()}`);
console.log('Aducción de cadera corregida como bilateral.');
