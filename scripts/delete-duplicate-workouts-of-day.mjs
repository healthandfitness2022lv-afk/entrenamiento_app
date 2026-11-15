// Borra los entrenamientos de un usuario en un día dado, conservando el
// primero (por hora de guardado). Pensado para limpiar duplicados creados por
// guardados que fallaron a mitad de camino. También borra las
// load_adjustment_alerts asociadas a los entrenamientos eliminados.
//
// Preview:  node scripts/delete-duplicate-workouts-of-day.mjs --projectId X
//             --credentialsPath secrets/serviceAccountKey.json
//             --name "hector" --day 2026-09-23
// Ejecutar: agregar --execute --confirm <projectId>
//
// Después de ejecutar, usar "Recalcular fatiga" en el perfil: los guardados
// fallidos ya habían sumado su carga al estado de fatiga.
import { createSign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

function argsOf(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item.startsWith("--")) continue;
    const key = item.slice(2);
    const next = argv[index + 1];
    if (next && !next.startsWith("--")) {
      args[key] = next;
      index += 1;
    } else {
      args[key] = true;
    }
  }
  return args;
}

function base64Url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

async function accessToken(credentialsPath) {
  const credentials = JSON.parse(readFileSync(credentialsPath, "utf8"));
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64Url(
    JSON.stringify({
      iss: credentials.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: credentials.token_uri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");
  signer.update(unsigned);
  signer.end();
  const assertion = `${unsigned}.${base64Url(signer.sign(credentials.private_key))}`;
  const response = await fetch(credentials.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`No se pudo autenticar (${response.status}).`);
  return (await response.json()).access_token;
}

function plain(value) {
  if (!value || typeof value !== "object") return value;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  return undefined;
}

async function runQuery(baseUrl, token, structuredQuery) {
  const response = await fetch(`${baseUrl}:runQuery`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ structuredQuery }),
  });
  if (!response.ok) {
    throw new Error(`Consulta rechazada (${response.status}): ${await response.text()}`);
  }
  return (await response.json())
    .map((row) => row.document)
    .filter(Boolean);
}

const fieldEq = (field, stringValue) => ({
  fieldFilter: {
    field: { fieldPath: field },
    op: "EQUAL",
    value: { stringValue },
  },
});

async function main() {
  const args = argsOf(process.argv.slice(2));
  const { projectId, name, day } = args;
  const execute = args.execute === true;
  const credentialsArg =
    args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!projectId || !name || !day) {
    throw new Error("Faltan --projectId, --name o --day (YYYY-MM-DD).");
  }
  if (!credentialsArg) {
    throw new Error("Define GOOGLE_APPLICATION_CREDENTIALS o --credentialsPath.");
  }
  const credentialsPath = resolve(credentialsArg);
  if (!existsSync(credentialsPath)) throw new Error("No existen las credenciales.");
  if (execute && args.confirm !== projectId) {
    throw new Error(`Para ejecutar usa --execute --confirm ${projectId}.`);
  }

  const token = await accessToken(credentialsPath);
  const baseUrl =
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}` +
    "/databases/(default)/documents";

  // Buscar el usuario por nombre (cualquier campo de texto que lo contenga).
  const users = await runQuery(baseUrl, token, { from: [{ collectionId: "users" }] });
  const fold = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const needle = fold(name);
  const matches = users.filter((doc) =>
    Object.values(doc.fields ?? {}).some((v) => {
      const s = plain(v);
      return typeof s === "string" && fold(s).includes(needle);
    }),
  );
  if (matches.length !== 1) {
    console.log(
      JSON.stringify(
        matches.map((d) => ({
          uid: d.name.split("/").at(-1),
          name: plain(d.fields?.name),
          email: plain(d.fields?.email),
        })),
        null,
        2,
      ),
    );
    throw new Error(`Se esperaba 1 usuario para '${name}', hay ${matches.length}.`);
  }
  const uid = matches[0].name.split("/").at(-1);

  // Día en hora local de la máquina (Chile).
  const dayStart = new Date(`${day}T00:00:00`);
  const dayEnd = new Date(dayStart.getTime() + 24 * 3600 * 1000);

  const allWorkouts = await runQuery(baseUrl, token, {
    from: [{ collectionId: "workouts_logged" }],
    where: fieldEq("userId", uid),
  });
  if (args.recent) {
    const recent = allWorkouts
      .map((doc) => ({
        id: doc.name.split("/").at(-1),
        session: plain(doc.fields?.sessionName),
        startedAt: plain(doc.fields?.startedAt),
        date: plain(doc.fields?.date),
      }))
      .sort((a, b) => new Date(b.date) - new Date(a.date))
      .slice(0, Number(args.recent));
    console.log(JSON.stringify({ total: allWorkouts.length, recent }, null, 2));
    return;
  }
  const workouts = allWorkouts
    .map((doc) => ({
      name: doc.name,
      id: doc.name.split("/").at(-1),
      sessionName: plain(doc.fields?.sessionName),
      startedAt: plain(doc.fields?.startedAt) ?? plain(doc.fields?.date),
      date: plain(doc.fields?.date),
    }))
    // Por `date` (momento del guardado), que es la fecha que muestra la app.
    .filter((w) => {
      const t = new Date(w.date);
      return t >= dayStart && t < dayEnd;
    })
    .sort((a, b) => new Date(a.date) - new Date(b.date));

  const [keep, ...remove] = workouts;
  const alertDeletes = [];
  for (const w of remove) {
    const alerts = await runQuery(baseUrl, token, {
      from: [{ collectionId: "load_adjustment_alerts" }],
      where: fieldEq("workoutId", w.id),
    });
    alertDeletes.push(...alerts.map((a) => a.name));
  }

  const local = (iso) => (iso ? new Date(iso).toLocaleString("es-CL") : null);
  console.log(
    JSON.stringify(
      {
        mode: execute ? "execute" : "preview",
        user: { uid, name: plain(matches[0].fields?.name) },
        day,
        keep: keep && { id: keep.id, session: keep.sessionName, startedAt: local(keep.startedAt), savedAt: local(keep.date) },
        delete: remove.map((w) => ({ id: w.id, session: w.sessionName, startedAt: local(w.startedAt), savedAt: local(w.date) })),
        alertsToDelete: alertDeletes.length,
      },
      null,
      2,
    ),
  );
  if (!execute || remove.length === 0) return;

  const writes = [...remove.map((w) => w.name), ...alertDeletes].map((n) => ({ delete: n }));
  const response = await fetch(`${baseUrl}:commit`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ writes }),
  });
  if (!response.ok) {
    throw new Error(`Firestore rechazó el borrado (${response.status}): ${await response.text()}`);
  }
  console.log(`Borrados ${remove.length} entrenamientos y ${alertDeletes.length} alertas.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
