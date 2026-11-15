import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createSign } from "node:crypto";

const projectId = "entrenamientoapplv";
const databaseId = "(default)";
const athleteId = "71DheGSwhtfDEfN4tk3TlI7Kzut1";
const credentialsPath = resolve(
  "secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json",
);
const apply = process.argv.includes("--apply");

const folders = [
  { name: "01 · Fuerza", order: 1 },
  { name: "02 · Potencia", order: 2 },
  { name: "03 · Hipertrofia", order: 3 },
  { name: "04 · Core y estabilidad", order: 4 },
  { name: "05 · Accesorios", order: 5 },
];

const blocks = [
  ["d1_b1", "Potencia lower · Jump squat + power clean", "02 · Potencia", 201],
  ["d1_b2", "Fuerza lower · Sentadilla trasera + peso muerto rumano", "01 · Fuerza", 101],
  ["d1_b3", "Hipertrofia lower · Hack squat + curl femoral", "03 · Hipertrofia", 301],
  ["d1_b4", "Core antirotación · Press Pallof", "04 · Core y estabilidad", 401],
  ["d2_b1", "Potencia upper · Lanzamiento de balón", "02 · Potencia", 202],
  ["d2_b2", "Fuerza push · Press banca + press de hombro", "01 · Fuerza", 102],
  ["d2_b3", "Fuerza upper mixta · Remo + dominada + press unilateral", "01 · Fuerza", 103],
  ["d2_b4", "Accesorios upper · Face pull + brazos", "05 · Accesorios", 501],
  ["d3_b1", "Hipertrofia upper · Press inclinado + remo", "03 · Hipertrofia", 302],
  ["d3_b2", "Hipertrofia lower · Hip thrust + búlgara + femoral", "03 · Hipertrofia", 303],
  ["d3_b3", "Accesorios · Hombro lateral + aductores", "05 · Accesorios", 502],
  ["d3_b4", "Core y control · Dead bug", "04 · Core y estabilidad", 402],
  ["d4_b1", "Potencia lower · Salto lateral + trap bar", "02 · Potencia", 203],
  ["d4_b2", "Fuerza-velocidad · Push press + leñador", "02 · Potencia", 204],
  ["d4_b3", "Potencia rotacional · Landmine + sprint lateral", "02 · Potencia", 205],
  ["d4_b4", "Accesorios lower · Sóleo y gemelo", "05 · Accesorios", 503],
  ["d5_b1", "Hipertrofia push-pull · Press pecho + jalón", "03 · Hipertrofia", 304],
  ["d5_b2", "Hipertrofia full body · Máquinas", "03 · Hipertrofia", 305],
  ["d5_b3", "Accesorios · Cuádriceps + femoral + hombro", "05 · Accesorios", 504],
  ["d5_b4", "Brazos en polea · Bíceps + tríceps", "05 · Accesorios", 505],
].map(([key, title, folder, order]) => ({ key, title, folder, order }));

function base64Url(input) {
  return (Buffer.isBuffer(input) ? input : Buffer.from(input))
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function fsValue(value) {
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  throw new Error(`Tipo no soportado: ${typeof value}`);
}

function resource(collection, id) {
  return `projects/${projectId}/databases/${databaseId}/documents/${collection}/${id}`;
}

function updateWrite(collection, id, values) {
  const fieldPaths = Object.keys(values);
  return {
    update: {
      name: resource(collection, id),
      fields: Object.fromEntries(
        Object.entries(values).map(([key, value]) => [key, fsValue(value)]),
      ),
    },
    updateMask: { fieldPaths },
  };
}

async function accessToken() {
  const account = JSON.parse(readFileSync(credentialsPath, "utf8"));
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: account.token_uri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${payload}`);
  signer.end();
  const assertion = `${header}.${payload}.${base64Url(signer.sign(account.private_key))}`;
  const response = await fetch(account.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
}

async function main() {
  const writes = [
    ...blocks.map((block) =>
      updateWrite("blocks", `library_hector_${block.key}`, {
        title: block.title,
        folder: block.folder,
        libraryOrder: block.order,
      }),
    ),
    ...folders.map((folder) =>
      updateWrite("block_folders", `library_hector_${folder.order}`, {
        name: folder.name,
        order: folder.order,
        scope: "hector",
        athleteId,
      }),
    ),
  ];

  console.log(
    JSON.stringify(
      {
        mode: apply ? "APPLY" : "DRY-RUN",
        blocks: blocks.length,
        folders: folders.map((folder) => folder.name),
        names: blocks.map((block) => block.title),
      },
      null,
      2,
    ),
  );
  if (!apply) return;

  const token = await accessToken();
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents:commit`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ writes }),
    },
  );
  if (!response.ok) throw new Error(`Commit ${response.status}: ${await response.text()}`);
  console.log(`Actualizados ${blocks.length} bloques y ${folders.length} carpetas.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
