// Marca `valueType: 'time'` en ejercicios registrados (workouts_logged) que
// en su bloque de origen son por tiempo. Hasta este cambio el guardado no
// persistía esa marca, y la revisión semanal leía los SEGUNDOS guardados en
// `reps` como repeticiones (un trote de 600 s contaba como 600 reps).
//
// El bloque de origen se resuelve por `blockId` del bloque realizado y el
// ejercicio por `exerciseInstanceId` o, si falta, por nombre.
//
// Preview:  node scripts/backfill-logged-time-valuetype.mjs --projectId X --credentialsPath secrets/serviceAccountKey.json
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
const norm = (s) => String(s ?? "").trim().toLowerCase();

async function main() {
  const args = argsOf(process.argv.slice(2));
  const { projectId } = args;
  const execute = args.execute === true;
  const credentialsPath = resolve(args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS ?? "");
  if (!projectId) throw new Error("Falta --projectId.");
  if (!existsSync(credentialsPath)) throw new Error("No existen las credenciales.");
  if (execute && args.confirm !== projectId) {
    throw new Error(`Para ejecutar usa --execute --confirm ${projectId}.`);
  }

  const token = await accessToken(credentialsPath);
  const api = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  const listAll = async (collectionId) => {
    const r = await fetch(`${api}:runQuery`, {
      method: "POST",
      headers,
      body: JSON.stringify({ structuredQuery: { from: [{ collectionId }] } }),
    });
    if (!r.ok) throw new Error(`Consulta ${collectionId} (${r.status}): ${await r.text()}`);
    return (await r.json()).map((x) => x.document).filter(Boolean);
  };

  // Ejercicios por tiempo de cada bloque: blockId → { byInstance, byName }
  const timeByBlock = new Map();
  for (const doc of await listAll("blocks")) {
    const byInstance = new Set();
    const byName = new Set();
    for (const ex of doc.fields?.exercises?.arrayValue?.values ?? []) {
      const f = ex.mapValue?.fields ?? {};
      if (str(f.valueType) !== "time") continue;
      if (str(f.exerciseInstanceId)) byInstance.add(str(f.exerciseInstanceId));
      byName.add(norm(str(f.name)));
    }
    if (byInstance.size || byName.size) timeByBlock.set(doc.name.split("/").at(-1), { byInstance, byName });
  }

  // Bloques planificados por atleta y día (fecha planificada = medianoche
  // local; +12 h cae siempre en el mismo día UTC).
  const plannedBlocksByAthleteDay = new Map();
  for (const doc of await listAll("planned_workouts")) {
    const f = doc.fields ?? {};
    // La fecha puede estar como timestamp o como texto ISO (datos viejos).
    const date = f.date?.timestampValue ?? str(f.date);
    if (!date || !str(f.blockId)) continue;
    const day = new Date(new Date(date).getTime() + 12 * 3600e3).toISOString().slice(0, 10);
    const key = `${str(f.athleteId)}|${day}`;
    if (!plannedBlocksByAthleteDay.has(key)) plannedBlocksByAthleteDay.set(key, []);
    plannedBlocksByAthleteDay.get(key).push(str(f.blockId));
  }
  // Día local del entrenamiento (Chile, UTC-3/-4).
  const loggedDay = (iso) => new Date(new Date(iso).getTime() - 4 * 3600e3).toISOString().slice(0, 10);

  const writes = [];
  const report = [];
  for (const doc of await listAll("workouts_logged")) {
    let changed = false;
    // Respaldo cuando el bloque realizado no guarda su `blockId`: los bloques
    // planificados del entrenamiento o, si tampoco están, los de ese día.
    const when =
      doc.fields?.startedAt?.timestampValue ?? str(doc.fields?.startedAt) ??
      doc.fields?.date?.timestampValue ?? str(doc.fields?.date);
    const plannedIds = (doc.fields?.plannedBlockIds?.arrayValue?.values ?? []).map(str);
    const workoutBlockIds = plannedIds.length
      ? plannedIds
      : (plannedBlocksByAthleteDay.get(`${str(doc.fields?.userId)}|${when ? loggedDay(when) : ""}`) ?? []);
    for (const blk of doc.fields?.performed?.arrayValue?.values ?? []) {
      const bf = blk.mapValue?.fields ?? {};
      const candidates = (str(bf.blockId) ? [str(bf.blockId)] : workoutBlockIds)
        .map((id) => timeByBlock.get(id))
        .filter(Boolean);
      if (!candidates.length) continue;
      const time = {
        byInstance: new Set(candidates.flatMap((c) => [...c.byInstance])),
        byName: new Set(candidates.flatMap((c) => [...c.byName])),
      };
      const exercises = [
        ...(bf.exercises?.arrayValue?.values ?? []),
        ...(bf.rounds?.arrayValue?.values ?? []).flatMap(
          (r) => r.mapValue?.fields?.exercises?.arrayValue?.values ?? [],
        ),
      ];
      for (const ex of exercises) {
        const f = ex.mapValue?.fields ?? {};
        if (str(f.valueType) === "time") continue;
        const isTime =
          time.byInstance.has(str(f.exerciseInstanceId)) ||
          time.byName.has(norm(str(f.exercise) ?? str(f.name))) ||
          time.byName.has(norm(str(f.displayName)));
        if (!isTime) continue;
        f.valueType = { stringValue: "time" };
        changed = true;
        report.push(`${doc.name.split("/").at(-1)} · ${str(f.exercise)}`);
      }
    }
    if (changed) {
      writes.push({
        update: { name: doc.name, fields: { performed: doc.fields.performed } },
        updateMask: { fieldPaths: ["performed"] },
      });
    }
  }

  console.log(report.length ? report.join("\n") : "Nada que corregir.");
  console.log(`${execute ? "" : "[preview] "}${report.length} ejercicios en ${writes.length} entrenamientos`);
  if (!execute || !writes.length) return;
  for (let i = 0; i < writes.length; i += 400) {
    const r = await fetch(`${api}:commit`, {
      method: "POST",
      headers,
      body: JSON.stringify({ writes: writes.slice(i, i + 400) }),
    });
    if (!r.ok) throw new Error(`Firestore rechazó la corrección (${r.status}): ${await r.text()}`);
  }
  console.log("Listo.");
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
