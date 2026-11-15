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

function toBase64Url(input) {
  return (Buffer.isBuffer(input) ? input : Buffer.from(input))
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function fsValue(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(fsValue) } };
  if (typeof value === "object") {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, item]) => [key, fsValue(item)]),
        ),
      },
    };
  }
  throw new Error(`Valor Firestore no soportado: ${typeof value}`);
}

function decode(value) {
  if (!value || typeof value !== "object") return value;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return value.timestampValue;
  if ("mapValue" in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue?.fields ?? {}).map(([key, item]) => [
        key,
        decode(item),
      ]),
    );
  }
  if ("arrayValue" in value) {
    return (value.arrayValue?.values ?? []).map(decode);
  }
  return value;
}

function documentId(document) {
  return document.name.split("/").pop();
}

async function accessToken() {
  const serviceAccount = JSON.parse(readFileSync(credentialsPath, "utf8"));
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = toBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = toBase64Url(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: serviceAccount.token_uri,
      iat: issuedAt,
      exp: issuedAt + 3600,
    }),
  );
  const unsigned = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");
  signer.update(unsigned);
  signer.end();
  const assertion = `${unsigned}.${toBase64Url(signer.sign(serviceAccount.private_key))}`;
  const response = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Token: ${response.status} ${await response.text()}`);
  return (await response.json()).access_token;
}

function collectionUrl(collection) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents/${collection}`;
}

function documentResource(collection, id) {
  return `projects/${projectId}/databases/${databaseId}/documents/${collection}/${id}`;
}

async function listCollection(token, collection) {
  const response = await fetch(`${collectionUrl(collection)}?pageSize=1000`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`Listar ${collection}: ${response.status} ${await response.text()}`);
  return (await response.json()).documents ?? [];
}

async function commit(token, writes) {
  if (!writes.length) return;
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
  if (!response.ok) throw new Error(`Commit: ${response.status} ${await response.text()}`);
}

function deleteWrite(collection, id) {
  return { delete: documentResource(collection, id) };
}

function patchWrite(collection, id, fields) {
  return {
    update: {
      name: documentResource(collection, id),
      fields: Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, fsValue(value)])),
    },
  };
}

function templateTitle(sourceTitle, day) {
  return sourceTitle.replace(/^M1 D\d+\s*[-·]\s*/, `D${day} · `);
}

const folders = [
  { name: "01 · Lower potencia y fuerza", order: 1 },
  { name: "02 · Upper fuerza", order: 2 },
  { name: "03 · Hipertrofia full body", order: 3 },
  { name: "04 · Potencia y transferencia", order: 4 },
  { name: "05 · Accesorios", order: 5 },
];

// Nombres reutilizables: describen el contenido del bloque, no el día ni el
// mesociclo desde el que se originó.
const reusableFolders = [
  { name: "01 · Fuerza", order: 1 },
  { name: "02 · Potencia", order: 2 },
  { name: "03 · Hipertrofia", order: 3 },
  { name: "04 · Core y estabilidad", order: 4 },
  { name: "05 · Accesorios", order: 5 },
];

const reusableBlocks = [
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

async function main() {
  const token = await accessToken();
  const [blocks, planned, oldFolders] = await Promise.all([
    listCollection(token, "blocks"),
    listCollection(token, "planned_workouts"),
    listCollection(token, "block_folders"),
  ]);
  const plannedIds = new Set(planned.map((doc) => decode(doc.fields?.blockId)));
  const source = blocks
    .map((doc) => ({ doc, id: documentId(doc), data: Object.fromEntries(Object.entries(doc.fields ?? {}).map(([key, value]) => [key, decode(value)])) }))
    .filter(({ id }) => /^hector_padel_m1_d[1-5]_b[1-4]$/.test(id))
    .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  if (source.length !== 20) throw new Error(`Se esperaban 20 bloques fuente de M1 y se encontraron ${source.length}.`);

  const visibleUnreferenced = blocks
    .map((doc) => ({ id: documentId(doc), data: Object.fromEntries(Object.entries(doc.fields ?? {}).map(([key, value]) => [key, decode(value)])) }))
    .filter(({ id, data }) => !plannedIds.has(id) && (data.athleteId == null || data.athleteId === athleteId));

  const deleteWrites = [
    ...visibleUnreferenced.map(({ id }) => deleteWrite("blocks", id)),
    ...oldFolders.map((doc) => deleteWrite("block_folders", documentId(doc))),
  ];
  const templateWrites = source.map(({ data }, index) => {
    const day = Math.floor(index / 4) + 1;
    const blockOrder = (index % 4) + 1;
    const definition = reusableBlocks.find(
      (item) => item.key === `d${day}_b${blockOrder}`,
    );
    if (!definition) throw new Error(`Falta definición reutilizable d${day}_b${blockOrder}.`);
    const templateId = `library_hector_d${day}_b${blockOrder}`;
    return patchWrite("blocks", templateId, {
      ...data,
      title: definition.title,
      athleteId,
      folder: definition.folder,
      isLibraryTemplate: true,
      libraryOrder: definition.order,
      templateDay: day,
      templateBlockOrder: blockOrder,
      sourceBlockId: `hector_padel_m1_d${day}_b${blockOrder}`,
      sourceMesocycleId: "hector_padel_recomposicion_2026_09",
      createdAt: new Date().toISOString(),
    });
  });
  const folderWrites = reusableFolders.map((folder) =>
    patchWrite("block_folders", `library_hector_${folder.order}`, {
      name: folder.name,
      order: folder.order,
      scope: "hector",
      athleteId,
      createdAt: new Date().toISOString(),
    }),
  );

  console.log(JSON.stringify({
    mode: apply ? "APPLY" : "DRY-RUN",
    currentBlocks: blocks.length,
    referencedBlocksKept: blocks.filter((doc) => plannedIds.has(documentId(doc))).length,
    oldVisibleBlocksDeleted: visibleUnreferenced.length,
    oldFoldersDeleted: oldFolders.length,
    templatesCreated: templateWrites.length,
    foldersCreated: folderWrites.length,
    templateFolders: reusableFolders,
  }, null, 2));
  if (!apply) return;

  await commit(token, deleteWrites);
  await commit(token, [...templateWrites, ...folderWrites]);
  console.log("Biblioteca reconstruida y referencias de planned_workouts conservadas.");
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
