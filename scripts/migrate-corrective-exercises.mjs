import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Uso:
// node scripts/migrate-corrective-exercises.mjs <service-account.json>
// node scripts/migrate-corrective-exercises.mjs <service-account.json> --apply --confirm Correctivos
//
// Crea el tipo visible "Correctivos" y mueve únicamente movimientos cuyo
// nombre coincide con los patrones explícitos de abajo. Revise el dry-run
// antes de aplicar: un face pull programado para hipertrofia puede quedarse
// deliberadamente en esa categoría si así lo decide el entrenador.

const credentialsPath = process.argv[2];
const apply = process.argv.includes('--apply');
const confirmed = process.argv.includes('--confirm') &&
    process.argv[process.argv.indexOf('--confirm') + 1] === 'Correctivos';

if (!credentialsPath) {
  throw new Error('Uso: node scripts/migrate-corrective-exercises.mjs <service-account.json> [--apply --confirm Correctivos]');
}
if (apply && !confirmed) {
  throw new Error('Para aplicar use también: --confirm Correctivos');
}

const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const projectId = account.project_id;
const baseUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const documentRoot = `projects/${projectId}/databases/(default)/documents`;
const now = () => new Date().toISOString();

const correctivePatterns = [
  /\bface\s*pull\b/i,
  /\bpush[ -]?up\s*(plus|serrato|serratus)\b/i,
  /\b(flexion|flexión)\s*(plus|serrato|serratus)\b/i,
  /\b(elevacion|elevación|raise)\s*w\b/i,
  /\bprone\s*w\b/i,
  /\bwall\s*slide\b/i,
  /\brotacion\s*externa\b/i,
  /\brotación\s*externa\b/i,
  /\bscapular\b/i,
  /\bpress\s+pallof\b/i,
];

const b64 = (value) => Buffer.from(value).toString('base64url');
async function accessToken() {
  const epoch = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64(JSON.stringify({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: account.token_uri,
    iat: epoch,
    exp: epoch + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const response = await fetch(account.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64(signer.sign(account.private_key))}`,
    }),
  });
  if (!response.ok) throw new Error(`Token: ${response.status}`);
  return (await response.json()).access_token;
}

function decode(value) {
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(
    Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]),
  );
  return null;
}

function encode(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encode) } };
  return {
    mapValue: {
      fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)])),
    },
  };
}

async function listCollection(token, collection) {
  const response = await fetch(`${baseUrl}/${collection}?pageSize=1000`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`${collection}: ${response.status} ${await response.text()}`);
  return (await response.json()).documents ?? [];
}

function fieldsOf(document) {
  return Object.fromEntries(
    Object.entries(document.fields ?? {}).map(([key, value]) => [key, decode(value)]),
  );
}

function isCorrective(data) {
  const searchable = [data.name, data.exerciseType, ...(data.equipment ?? [])]
    .filter(Boolean)
    .join(' ');
  return correctivePatterns.some((pattern) => pattern.test(searchable));
}

function correctedVariants(rawVariants, isPallof = false) {
  if (!Array.isArray(rawVariants)) return rawVariants;
  return rawVariants.map((variant) => ({
    ...variant,
    trainingDiscipline: 'correctivos',
    movementIntent: 'stability',
    trackRM: false,
    trackProgression: false,
    ...(isPallof ? {
      familyId: 'anti_rotation',
      techniqueId: variant.id === 'cable_kneeling' ? 'kneeling' : 'standing',
      techniqueLabel:
          variant.id === 'cable_kneeling'
            ? 'Antirotación de rodillas'
            : 'Antirotación de pie',
      isUnilateral: true,
    } : {}),
  }));
}

async function main() {
  const token = await accessToken();
  const [folders, exercises] = await Promise.all([
    listCollection(token, 'exercise_folders'),
    listCollection(token, 'exercises'),
  ]);

  const matches = exercises
    .map((document) => ({ id: document.name.split('/').at(-1), data: fieldsOf(document) }))
    .filter(({ data }) => isCorrective(data))
    .filter(({ data }) => data.exerciseType !== 'Correctivos');
  const hasFolder = folders.some((document) => fieldsOf(document).name === 'Correctivos');

  console.log(JSON.stringify({
    mode: apply ? 'APPLY' : 'DRY-RUN',
    folderWillBeCreated: !hasFolder,
    multiplier: 0.55,
    exercisesToMove: matches.map(({ id, data }) => ({ id, name: data.name, from: data.exerciseType ?? 'Otros' })),
  }, null, 2));
  if (!apply) return;

  const writes = [];
  if (!hasFolder) {
    writes.push({
      update: {
        name: `${documentRoot}/exercise_folders/correctivos`,
        fields: {
          name: encode('Correctivos'),
          multiplier: encode(0.55),
          createdAt: encode(now()),
          updatedAt: encode(now()),
        },
      },
    });
  }
  for (const { id, data } of matches) {
    const fields = {
      exerciseType: encode('Correctivos'),
      trackRM: encode(false),
      trackProgression: encode(false),
      updatedAt: encode(now()),
    };
    if (Array.isArray(data.variants)) {
      fields.variants = encode(
        correctedVariants(data.variants, /\bpress\s+pallof\b/i.test(data.name ?? '')),
      );
    }
    writes.push({
      update: { name: `${documentRoot}/exercises/${id}`, fields },
      updateMask: { fieldPaths: Object.keys(fields) },
    });
  }
  if (writes.isEmpty) return;
  const response = await fetch(`${baseUrl}:commit`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ writes }),
  });
  if (!response.ok) throw new Error(`Commit: ${response.status} ${await response.text()}`);
  console.log(`Aplicado: categoría Correctivos y ${matches.length} ejercicio(s) actualizados.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
