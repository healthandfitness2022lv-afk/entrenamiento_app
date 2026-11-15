import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Uso: node scripts/set-hang-power-snatch-family.mjs <service-account.json> --apply [--clean-jerk]
const credentialsPath = process.argv[2];
const apply = process.argv.includes('--apply');
if (!credentialsPath) {
  throw new Error('Uso: node scripts/set-hang-power-snatch-family.mjs <service-account.json> [--apply]');
}

const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const b64 = (value) => Buffer.from(value).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
const payload = b64(JSON.stringify({
  iss: account.client_email,
  scope: 'https://www.googleapis.com/auth/datastore',
  aud: account.token_uri,
  iat: now,
  exp: now + 3600,
}));
const unsigned = `${header}.${payload}`;
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
const base = `https://firestore.googleapis.com/v1/projects/${account.project_id}/databases/(default)/documents`;
const cleanJerk = process.argv.includes('--clean-jerk');
const target = cleanJerk
  ? {
      id: 'movement_clean_jerk',
      name: 'Clean & Jerk',
      familyId: 'clean_jerk',
      techniqueId: 'default',
      techniqueLabel: 'Clean & Jerk',
    }
  : {
      id: 'TENcpqXxXUMy09OHWpkS',
      name: 'Hang Power Snatch',
      familyId: 'snatch',
      techniqueId: 'hang_power',
      techniqueLabel: 'Hang Power',
    };
const fields = {
  familyId: { stringValue: target.familyId },
  techniqueId: { stringValue: target.techniqueId },
  techniqueLabel: { stringValue: target.techniqueLabel },
  trainingDiscipline: { stringValue: 'halterofilia' },
  movementIntent: { stringValue: 'power' },
  updatedAt: { timestampValue: new Date().toISOString() },
};

console.log(JSON.stringify({ mode: apply ? 'APPLY' : 'DRY-RUN', exercise: target.name, familyId: target.familyId }, null, 2));
if (!apply) process.exit(0);

const query = new URLSearchParams();
for (const field of Object.keys(fields)) query.append('updateMask.fieldPaths', field);
const response = await fetch(`${base}/exercises/${target.id}?${query}`, {
  method: 'PATCH',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ fields }),
});
if (!response.ok) throw new Error(`Patch: ${response.status} ${await response.text()}`);
console.log(`Familia base actualizada: ${target.familyId}.`);
