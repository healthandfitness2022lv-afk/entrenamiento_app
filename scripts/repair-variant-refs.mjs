// Detecta y repara referencias a variantes que ya no existen en el catálogo
// (ids renombrados por scripts de consolidación). Revisa workouts_logged,
// planned_workouts y blocks (incluidas subcolecciones).
//
// Resolución de cada id huérfano (exerciseId + variantId):
//   1. --map exerciseId:idViejo=idNuevo (explícito, se puede repetir con coma)
//   2. `variantAliases` del ejercicio en el catálogo
//   3. mismo label (normalizado) que alguna variante actual
//
// Al ejecutar: reescribe variantId/variantLabel en los documentos y guarda
// `variantAliases.<idViejo> = idNuevo` en el ejercicio, para que la app lo
// resuelva aunque quede algún documento sin reparar.
//
// IMPORTANTE: los scripts que renombren ids de variantes deberían correr
// este script después (o escribir variantAliases ellos mismos).
//
// Preview:  node scripts/repair-variant-refs.mjs --projectId X --credentialsPath secrets/serviceAccountKey.json
// Ejecutar: agregar --execute --confirm <projectId>
import { createSign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

function argsOf(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith("--")) continue;
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      args[item.slice(2)] = next;
      i += 1;
    } else {
      args[item.slice(2)] = true;
    }
  }
  return args;
}

const base64Url = (input) =>
  Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

async function accessToken(credentialsPath) {
  const credentials = JSON.parse(readFileSync(credentialsPath, "utf8"));
  const now = Math.floor(Date.now() / 1000);
  const unsigned =
    `${base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.` +
    base64Url(
      JSON.stringify({
        iss: credentials.client_email,
        scope: "https://www.googleapis.com/auth/datastore",
        aud: credentials.token_uri,
        iat: now,
        exp: now + 3600,
      }),
    );
  const signer = createSign("RSA-SHA256");
  signer.update(unsigned);
  signer.end();
  const response = await fetch(credentials.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64Url(signer.sign(credentials.private_key))}`,
    }),
  });
  if (!response.ok) throw new Error(`No se pudo autenticar (${response.status}).`);
  return (await response.json()).access_token;
}

const str = (v) => v?.stringValue;

const normalizeKey = (s) =>
  String(s ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();

/** Recorre el JSON tipado de Firestore y llama `visit` en cada mapa. */
function walkMaps(value, visit) {
  if (!value || typeof value !== "object") return;
  if (value.mapValue) {
    const fields = value.mapValue.fields ?? {};
    visit(fields);
    Object.values(fields).forEach((v) => walkMaps(v, visit));
  } else if (value.arrayValue) {
    (value.arrayValue.values ?? []).forEach((v) => walkMaps(v, visit));
  }
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const { projectId } = args;
  const execute = args.execute === true;
  const credentialsArg = args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!projectId) throw new Error("Falta --projectId.");
  if (!credentialsArg) throw new Error("Define GOOGLE_APPLICATION_CREDENTIALS o --credentialsPath.");
  const credentialsPath = resolve(credentialsArg);
  if (!existsSync(credentialsPath)) throw new Error("No existen las credenciales.");
  if (execute && args.confirm !== projectId) {
    throw new Error(`Para ejecutar usa --execute --confirm ${projectId}.`);
  }

  const explicit = new Map();
  for (const entry of String(args.map ?? "").split(",").filter(Boolean)) {
    const match = entry.match(/^([^:]+):([^=]+)=(.+)$/);
    if (!match) throw new Error(`--map inválido: '${entry}' (formato exerciseId:idViejo=idNuevo)`);
    explicit.set(`${match[1]}|${match[2]}`, match[3]);
  }

  const token = await accessToken(credentialsPath);
  const root = `projects/${projectId}/databases/(default)/documents`;
  const api = `https://firestore.googleapis.com/v1/${root}`;
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

  async function listAll(collectionId) {
    const r = await fetch(`${api}:runQuery`, {
      method: "POST",
      headers,
      body: JSON.stringify({ structuredQuery: { from: [{ collectionId, allDescendants: true }] } }),
    });
    if (!r.ok) throw new Error(`Consulta ${collectionId} rechazada (${r.status}): ${await r.text()}`);
    return (await r.json()).map((row) => row.document).filter(Boolean);
  }

  // Catálogo: exerciseId → { name, variants: Map(id → label), aliases }
  const catalog = new Map();
  for (const doc of await listAll("exercises")) {
    const id = doc.name.split("/").at(-1);
    const fields = doc.fields ?? {};
    const variants = new Map();
    for (const v of fields.variants?.arrayValue?.values ?? []) {
      const f = v.mapValue?.fields ?? {};
      if (str(f.id)) variants.set(str(f.id), str(f.label) ?? "");
    }
    const aliases = {};
    for (const [k, v] of Object.entries(fields.variantAliases?.mapValue?.fields ?? {})) {
      aliases[k] = str(v);
    }
    catalog.set(id, { name: str(fields.name), variants, aliases });
  }

  const resolveOrphan = (exerciseId, variantId, variantLabel) => {
    const cat = catalog.get(exerciseId);
    const candidates = [
      explicit.get(`${exerciseId}|${variantId}`),
      cat.aliases[variantId],
      [...cat.variants].find(([, label]) => variantLabel && normalizeKey(label) === normalizeKey(variantLabel))?.[0],
    ];
    return candidates.find((c) => c && cat.variants.has(c)) ?? null;
  };

  const orphans = new Map(); // key → { exercise, variantId, label, target, docs:Set }
  const docUpdates = []; // { name, fields, changedTop:Set }

  for (const collection of ["workouts_logged", "planned_workouts", "blocks"]) {
    for (const doc of await listAll(collection)) {
      const changedTop = new Set();
      for (const [top, value] of Object.entries(doc.fields ?? {})) {
        walkMaps(value, (fields) => {
          const exerciseId = str(fields.exerciseId);
          const variantId = str(fields.variantId);
          if (!exerciseId || !variantId) return;
          const cat = catalog.get(exerciseId);
          if (!cat || cat.variants.has(variantId)) return;
          const label = str(fields.variantLabel);
          const key = `${exerciseId}|${variantId}`;
          const target = resolveOrphan(exerciseId, variantId, label);
          if (!orphans.has(key)) {
            orphans.set(key, { exercise: cat.name, exerciseId, variantId, label, target, docs: new Set() });
          }
          orphans.get(key).docs.add(`${collection}/${doc.name.split("/").at(-1)}`);
          if (!target) return;
          fields.variantId = { stringValue: target };
          if (fields.variantLabel) fields.variantLabel = { stringValue: cat.variants.get(target) };
          changedTop.add(top);
        });
      }
      if (changedTop.size) docUpdates.push({ name: doc.name, fields: doc.fields, changedTop });
    }
  }

  const report = [...orphans.values()].map((o) => ({
    exercise: o.exercise,
    exerciseId: o.exerciseId,
    from: o.variantId,
    label: o.label,
    to: o.target ?? "SIN RESOLVER (usa --map)",
    docs: o.docs.size,
  }));
  console.log(JSON.stringify({ mode: execute ? "execute" : "preview", orphans: report, docsToUpdate: docUpdates.length }, null, 2));
  if (!execute) return;

  const writes = docUpdates.map((u) => ({
    update: {
      name: u.name,
      fields: Object.fromEntries([...u.changedTop].map((k) => [k, u.fields[k]])),
    },
    updateMask: { fieldPaths: [...u.changedTop].map((k) => `\`${k}\``) },
  }));
  for (const o of orphans.values()) {
    if (!o.target) continue;
    writes.push({
      update: {
        name: `${root}/exercises/${o.exerciseId}`,
        fields: { variantAliases: { mapValue: { fields: { [o.variantId]: { stringValue: o.target } } } } },
      },
      updateMask: { fieldPaths: [`variantAliases.\`${o.variantId}\``] },
    });
  }
  for (let i = 0; i < writes.length; i += 400) {
    const r = await fetch(`${api}:commit`, {
      method: "POST",
      headers,
      body: JSON.stringify({ writes: writes.slice(i, i + 400) }),
    });
    if (!r.ok) throw new Error(`Firestore rechazó la reparación (${r.status}): ${await r.text()}`);
  }
  console.log(`Reparados ${docUpdates.length} documentos y ${report.filter((o) => o.to && !o.to.startsWith("SIN")).length} alias.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
