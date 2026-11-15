// Agrega la variante "Máquina Smith" al movimiento Remo (movement_remo), clonando la
// variante "Barra". Idempotente: si ya existe, no hace nada.
import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const b64 = (value) => Buffer.from(value).toString('base64url');

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({
    iss: credentials.client_email, scope: 'https://www.googleapis.com/auth/datastore',
    aud: credentials.token_uri, iat: now, exp: now + 3600,
  }))}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const response = await fetch(credentials.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64(signer.sign(credentials.private_key))}`,
    }),
  });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
}

const token = await accessToken();
const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/exercises/movement_remo`;
const doc = await (await fetch(url, { headers: { Authorization: `Bearer ${token}` } })).json();
const variants = doc.fields.variants.arrayValue.values;
const idOf = (v) => v.mapValue.fields.id.stringValue;

if (variants.some((v) => idOf(v) === 'maquina_smith')) {
  console.log('La variante maquina_smith ya existe.');
  process.exit(0);
}

const base = structuredClone(variants.find((v) => idOf(v) === 'barra'));
const f = base.mapValue.fields;
f.id = { stringValue: 'maquina_smith' };
f.label = { stringValue: 'Máquina Smith' };
f.techniqueId = { stringValue: 'maquina_smith' };
f.techniqueLabel = { stringValue: 'Máquina Smith' };
f.resistanceType = { stringValue: 'guided' };
f.equipment = { arrayValue: { values: [{ stringValue: 'Máquina Smith' }] } };
f.group = { stringValue: 'Máquina' };
f.trackRM = { booleanValue: false };

const equipment = doc.fields.equipment?.arrayValue?.values ?? [];
if (!equipment.some((e) => e.stringValue === 'Máquina Smith')) equipment.push({ stringValue: 'Máquina Smith' });

const mask = ['variants', 'equipment', 'updatedAt'].map((p) => `updateMask.fieldPaths=${p}`).join('&');
const response = await fetch(`${url}?${mask}&currentDocument.updateTime=${encodeURIComponent(doc.updateTime)}`, {
  method: 'PATCH',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    fields: {
      variants: { arrayValue: { values: [...variants, base] } },
      equipment: { arrayValue: { values: equipment } },
      updatedAt: { stringValue: new Date().toISOString() },
    },
  }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(`Variante maquina_smith agregada a Remo (${variants.length + 1} variantes).`);
