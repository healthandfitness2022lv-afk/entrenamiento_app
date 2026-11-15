// Fija la ponderación muscular (muscleWeightOverrides) de UNA variante del
// catálogo, sin tocar el ejercicio padre ni las demás variantes.
//
// node scripts/set-variant-muscle-weights.mjs --projectId X
//   --credentialsPath secrets/serviceAccountKey.json
//   --exerciseId movement_snatch --variantId snatch_landmine
//   --weights "glutes=0.18,quads=0.17,..."
// Agregar --execute --confirm <projectId> para escribir (sin eso, preview).
//
// Después, "Recalcular fatiga" en el perfil de cada atleta que la use.
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

async function main() {
  const args = argsOf(process.argv.slice(2));
  const { projectId, exerciseId, variantId } = args;
  const execute = args.execute === true;
  const credentialsArg = args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!projectId || !exerciseId || !variantId || !args.weights) {
    throw new Error("Faltan --projectId, --exerciseId, --variantId o --weights.");
  }
  const credentialsPath = resolve(credentialsArg ?? "");
  if (!existsSync(credentialsPath)) throw new Error("No existen las credenciales.");
  if (execute && args.confirm !== projectId) {
    throw new Error(`Para ejecutar usa --execute --confirm ${projectId}.`);
  }

  const weights = Object.fromEntries(
    String(args.weights)
      .split(",")
      .map((pair) => pair.split("=").map((s) => s.trim()))
      .map(([muscle, value]) => {
        const n = Number(value);
        if (!muscle || !Number.isFinite(n)) throw new Error(`Peso inválido: ${muscle}=${value}`);
        return [muscle, n];
      }),
  );
  const total = Object.values(weights).reduce((a, b) => a + b, 0);

  const token = await accessToken(credentialsPath);
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/exercises/` +
    encodeURIComponent(exerciseId);
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error(`No se pudo leer el ejercicio (${response.status}).`);
  const doc = await response.json();
  const variants = doc.fields?.variants?.arrayValue?.values ?? [];
  const index = variants.findIndex((v) => v.mapValue?.fields?.id?.stringValue === variantId);
  if (index < 0) throw new Error(`La variante '${variantId}' no existe en '${exerciseId}'.`);

  const variantFields = variants[index].mapValue.fields;
  const toPlain = (m) =>
    Object.fromEntries(
      Object.entries(m?.mapValue?.fields ?? {}).map(([k, v]) => [k, Number(v.doubleValue ?? v.integerValue)]),
    );
  console.log(
    JSON.stringify(
      {
        mode: execute ? "execute" : "preview",
        variant: variantFields.label?.stringValue,
        before: toPlain(variantFields.muscleWeightOverrides),
        after: weights,
        total: Number(total.toFixed(3)),
      },
      null,
      2,
    ),
  );
  if (!execute) return;

  variantFields.muscleWeightOverrides = {
    mapValue: {
      fields: Object.fromEntries(Object.entries(weights).map(([k, v]) => [k, { doubleValue: v }])),
    },
  };
  const patch = await fetch(`${url}?updateMask.fieldPaths=variants`, {
    method: "PATCH",
    headers,
    body: JSON.stringify({ fields: { variants: { arrayValue: { values: variants } } } }),
  });
  if (!patch.ok) throw new Error(`Firestore rechazó el cambio (${patch.status}): ${await patch.text()}`);
  console.log("Ponderación actualizada.");
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
