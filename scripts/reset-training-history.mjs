import { createSign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const DERIVED_COLLECTIONS = [
  "achievements",
  "stats",
  "muscle_state",
  "fatigue_state",
  "fatigue_audit",
];

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

async function listDocuments({ baseUrl, token, path }) {
  const documents = [];
  let pageToken;
  do {
    const url = new URL(`${baseUrl}/${path}`);
    url.searchParams.set("pageSize", "500");
    url.searchParams.set("mask.fieldPaths", "__name__");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (response.status === 404) return documents;
    if (!response.ok) {
      throw new Error(`No se pudo listar ${path} (${response.status}).`);
    }
    const data = await response.json();
    documents.push(...(data.documents ?? []).map((document) => document.name));
    pageToken = data.nextPageToken;
  } while (pageToken);
  return documents;
}

async function commit(baseUrl, token, writes) {
  for (let index = 0; index < writes.length; index += 450) {
    const response = await fetch(`${baseUrl}:commit`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ writes: writes.slice(index, index + 450) }),
    });
    if (!response.ok) {
      throw new Error(`Firestore rechazó el reinicio (${response.status}).`);
    }
  }
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const projectId = args.projectId;
  const execute = args.execute === true;
  const credentialsArg =
    args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!projectId) throw new Error("Falta --projectId.");
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
  const users = await listDocuments({ baseUrl, token, path: "users" });
  const workouts = await listDocuments({
    baseUrl,
    token,
    path: "workouts_logged",
  });
  const deletes = workouts.map((name) => ({ delete: name }));
  const summary = { workouts: workouts.length, users: users.length, derived: {} };

  for (const userName of users) {
    const uid = userName.split("/").at(-1);
    for (const collection of DERIVED_COLLECTIONS) {
      const docs = await listDocuments({
        baseUrl,
        token,
        path: `users/${encodeURIComponent(uid)}/${collection}`,
      });
      summary.derived[collection] =
        (summary.derived[collection] ?? 0) + docs.length;
      deletes.push(...docs.map((name) => ({ delete: name })));
    }
    deletes.push({
      update: {
        name: userName,
        fields: { globalFatigue: { doubleValue: 0 } },
      },
      updateMask: {
        fieldPaths: ["globalFatigue", "lastFatigueCalculation"],
      },
    });
  }

  console.log(JSON.stringify({ mode: execute ? "execute" : "preview", ...summary }, null, 2));
  if (!execute) return;
  await commit(baseUrl, token, deletes);
  console.log("Reinicio completado y perfiles de fatiga restablecidos.");
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
