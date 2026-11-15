import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const credentialsPath = process.argv[2];
if (!credentialsPath) throw new Error('Use credentials path');
const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const b64 = (v) => Buffer.from(v).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }))}`;
const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
const auth = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(account.private_key))}` }) });
const accessToken = (await auth.json()).access_token;
const base = 'https://firestore.googleapis.com/v1/projects/entrenamientoapplv/databases/(default)/documents';
const decode = (v) => {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  return null;
};
async function list(collection) {
  const response = await fetch(`${base}/${collection}?pageSize=500`, { headers: { Authorization: `Bearer ${accessToken}` } });
  const payload = await response.json();
  return (payload.documents ?? []).map((document) => ({ id: document.name.split('/').at(-1), fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decode(value)])) }));
}
const [planned, blocks] = await Promise.all([list('planned_workouts'), list('blocks')]);
const selectedAthlete = '71DheGSwhtfDEfN4tk3TlI7Kzut1';
const start = new Date('2026-09-21T00:00:00Z');
const end = new Date('2026-09-28T00:00:00Z');
const selected = planned.filter((item) => item.fields.athleteId === selectedAthlete && new Date(item.fields.date) >= start && new Date(item.fields.date) < end);
const blockMap = new Map(blocks.map((item) => [item.id, item.fields]));
const result = selected.map((item) => {
  const block = blockMap.get(item.fields.blockId) ?? {};
  const exercises = (block.exercises ?? []).map((exercise) => ({
    name: exercise.displayName ?? exercise.name ?? exercise.movementName,
    exerciseId: exercise.exerciseId ?? exercise.movementId ?? null,
    variantId: exercise.variantId ?? null,
    technique: exercise.techniqueLabel ?? null,
    discipline: exercise.trainingDiscipline ?? null,
    intent: exercise.movementIntent ?? null,
    series: exercise.series ?? null,
    reps: exercise.reps ?? exercise.value ?? null,
    weight: exercise.weight ?? null,
    perSide: exercise.perSide === true,
  }));
  return { date: item.fields.date, blockId: item.fields.blockId, title: block.title, type: block.type, exerciseCount: exercises.length, exercises };
});
console.log(JSON.stringify({ week: '2026-09-21..2026-09-27', plannedSessions: result.length, sessions: result }, null, 2));
