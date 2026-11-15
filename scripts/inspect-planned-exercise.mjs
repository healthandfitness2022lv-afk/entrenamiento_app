import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const needle = (process.argv[2] ?? '').toLowerCase();
const credentialsPath = process.argv[3];
if (!needle || !credentialsPath) {
  throw new Error('Use: node inspect-planned-exercise.mjs <exercise text> <credentials path>');
}
const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const now = Math.floor(Date.now() / 1000);
const encode = (value) => Buffer.from(value).toString('base64url');
const unsigned = `${encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${encode(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }))}`;
const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
const tokenResponse = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${encode(signer.sign(account.private_key))}` }) });
const accessToken = (await tokenResponse.json()).access_token;
const decode = (value) => {
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  return null;
};
const base = 'https://firestore.googleapis.com/v1/projects/entrenamientoapplv/databases/(default)/documents';
async function list(collection) {
  const response = await fetch(`${base}/${collection}?pageSize=500`, { headers: { Authorization: `Bearer ${accessToken}` } });
  const payload = await response.json();
  return (payload.documents ?? []).map((document) => ({ id: document.name.split('/').at(-1), fields: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decode(value)])) }));
}
const [blocks, planned, exercises] = await Promise.all([list('blocks'), list('planned_workouts'), list('exercises')]);
const matchingBlocks = blocks.filter((block) => JSON.stringify(block.fields).toLowerCase().includes(needle));
const blockIds = new Set(matchingBlocks.map((block) => block.id));
console.log(JSON.stringify({
  catalogMatches: exercises.filter((exercise) => String(exercise.fields.name ?? '').toLowerCase().includes(needle)).map((exercise) => ({ id: exercise.id, name: exercise.fields.name, exerciseType: exercise.fields.exerciseType, variants: exercise.fields.variants, muscleWeights: exercise.fields.muscleWeights })),
  matchingBlocks: matchingBlocks.map((block) => ({ id: block.id, title: block.fields.title, type: block.fields.type, exercises: block.fields.exercises })),
  plannedOccurrences: planned.filter((item) => blockIds.has(item.fields.blockId)).map((item) => ({ id: item.id, date: item.fields.date, athleteId: item.fields.athleteId, blockId: item.fields.blockId, loadOverrides: item.fields.loadOverrides, progression: item.fields.loadProgression })),
}, null, 2));
