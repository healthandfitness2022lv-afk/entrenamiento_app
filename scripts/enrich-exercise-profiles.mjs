import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createSign } from "node:crypto";

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      args[key] = next;
      i += 1;
    } else {
      args[key] = "true";
    }
  }
  return args;
}

function toBase64Url(inputValue) {
  const buffer = Buffer.isBuffer(inputValue)
    ? inputValue
    : Buffer.from(inputValue);
  return buffer
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function encodePathSegments(value) {
  return value
    .split("/")
    .filter(Boolean)
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

function convertFirestoreValue(value) {
  if (!value || typeof value !== "object") return value;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return value.timestampValue;
  if ("mapValue" in value) {
    const fields = value.mapValue?.fields ?? {};
    return Object.fromEntries(
      Object.entries(fields).map(([key, fieldValue]) => [
        key,
        convertFirestoreValue(fieldValue),
      ]),
    );
  }
  if ("arrayValue" in value) {
    return (value.arrayValue?.values ?? []).map(convertFirestoreValue);
  }
  return value;
}

function convertFirestoreDocument(document) {
  const fields = document.fields ?? {};
  return {
    _name: document.name,
    ...Object.fromEntries(
      Object.entries(fields).map(([key, value]) => [key, convertFirestoreValue(value)]),
    ),
  };
}

function toFirestoreValue(value) {
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (value === null) return { nullValue: null };
  throw new Error(`Tipo no soportado para Firestore: ${typeof value}`);
}

async function getAccessToken(credentialsPath) {
  const raw = readFileSync(credentialsPath, "utf8");
  const serviceAccount = JSON.parse(raw);

  const issuedAt = Math.floor(Date.now() / 1000);
  const expiresAt = issuedAt + 3600;
  const header = toBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = toBase64Url(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: serviceAccount.token_uri,
      iat: issuedAt,
      exp: expiresAt,
    }),
  );

  const unsignedJwt = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");
  signer.update(unsignedJwt);
  signer.end();
  const assertion = `${unsignedJwt}.${toBase64Url(signer.sign(serviceAccount.private_key))}`;

  const response = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`No se pudo obtener access token: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  return data.access_token;
}

async function listExercises({ projectId, databaseId, credentialsPath, pageSize }) {
  const token = await getAccessToken(credentialsPath);
  const url =
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}` +
    `/databases/${encodeURIComponent(databaseId)}/documents/exercises?pageSize=${encodeURIComponent(String(pageSize))}`;

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!response.ok) {
    throw new Error(`Firestore respondió ${response.status}: ${await response.text()}`);
  }

  const data = await response.json();
  return (data.documents ?? []).map(convertFirestoreDocument);
}

async function patchExercise({
  projectId,
  databaseId,
  credentialsPath,
  documentId,
  updates,
}) {
  const token = await getAccessToken(credentialsPath);
  const params = new URLSearchParams();
  for (const key of Object.keys(updates)) {
    params.append("updateMask.fieldPaths", key);
  }

  const url =
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}` +
    `/databases/${encodeURIComponent(databaseId)}/documents/exercises/${encodePathSegments(documentId)}?${params.toString()}`;

  const fields = Object.fromEntries(
    Object.entries(updates).map(([key, value]) => [key, toFirestoreValue(value)]),
  );

  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });

  if (!response.ok) {
    throw new Error(`No se pudo actualizar ${documentId}: ${response.status} ${await response.text()}`);
  }
}

function shouldReview(exercise, forceAll) {
  if (forceAll) return true;
  return !exercise.resistanceType || !exercise.movementClass || typeof exercise.isUnilateral !== "boolean";
}

function normalizeChoice(value) {
  return value.trim().toLowerCase();
}

async function askChoice(rl, prompt, options, currentValue) {
  const label = options.map((option) => option.key).join("/");
  const current = currentValue ? ` [actual: ${currentValue}]` : "";
  while (true) {
    const raw = await rl.question(`${prompt} (${label})${current}: `);
    const answer = normalizeChoice(raw);
    if (!answer && currentValue) return currentValue;
    const selected = options.find((option) => option.key === answer);
    if (selected) return selected.value;
    if (answer === "s") return "__skip__";
    if (answer === "q") return "__quit__";
    output.write("Respuesta inválida. Usa una opción, 's' para saltar o 'q' para salir.\n");
  }
}

async function askBoolean(rl, prompt, currentValue) {
  const current =
    typeof currentValue === "boolean"
      ? ` [actual: ${currentValue ? "si" : "no"}]`
      : "";
  while (true) {
    const raw = await rl.question(`${prompt} (si/no)${current}: `);
    const answer = normalizeChoice(raw);
    if (!answer && typeof currentValue === "boolean") return currentValue;
    if (["si", "s", "y", "yes"].includes(answer)) return true;
    if (["no", "n"].includes(answer)) return false;
    if (answer === "skip") return "__skip__";
    if (answer === "q") return "__quit__";
    output.write("Respuesta inválida. Usa si/no, 'skip' o 'q'.\n");
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectId = args.projectId;
  const databaseId = args.databaseId ?? "(default)";
  const pageSize = Number(args.pageSize ?? "500");
  const credentialsPathArg =
    args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const forceAll = args.all === "true";

  if (!projectId) throw new Error("Falta --projectId");
  if (!credentialsPathArg) throw new Error("Falta --credentialsPath");

  const credentialsPath = resolve(credentialsPathArg);
  if (!existsSync(credentialsPath)) {
    throw new Error(`No se encontró el archivo de credenciales en '${credentialsPath}'.`);
  }

  const exercises = await listExercises({
    projectId,
    databaseId,
    credentialsPath,
    pageSize,
  });

  const rl = createInterface({ input, output });
  let updated = 0;

  try {
    for (const exercise of exercises) {
      if (!shouldReview(exercise, forceAll)) continue;

      const documentId = exercise._name.split("/").pop();
      output.write(`\n=== ${exercise.name} ===\n`);
      output.write(`Tipo actual: ${exercise.exerciseType ?? "-"}\n`);
      output.write(`equipment: ${(exercise.equipment ?? []).join(", ") || "-"}\n`);
      output.write(
        `Campos actuales -> resistanceType: ${exercise.resistanceType ?? "-"} | movementClass: ${exercise.movementClass ?? "-"} | isUnilateral: ${
          typeof exercise.isUnilateral === "boolean" ? String(exercise.isUnilateral) : "-"
        }\n`,
      );

      const resistanceType = await askChoice(
        rl,
        "Tipo de resistencia",
        [
          { key: "libre", value: "free" },
          { key: "guiado", value: "guided" },
          { key: "pc", value: "bodyweight" },
        ],
        exercise.resistanceType,
      );
      if (resistanceType === "__quit__") break;
      if (resistanceType === "__skip__") continue;

      const movementClass = await askChoice(
        rl,
        "Tipo de ejercicio",
        [
          { key: "comp", value: "compound" },
          { key: "aisl", value: "isolation" },
        ],
        exercise.movementClass,
      );
      if (movementClass === "__quit__") break;
      if (movementClass === "__skip__") continue;

      const isUnilateral = await askBoolean(
        rl,
        "Es unilateral",
        exercise.isUnilateral,
      );
      if (isUnilateral === "__quit__") break;
      if (isUnilateral === "__skip__") continue;

      await patchExercise({
        projectId,
        databaseId,
        credentialsPath,
        documentId,
        updates: {
          resistanceType,
          movementClass,
          isUnilateral,
        },
      });

      updated += 1;
      output.write(`Guardado ${exercise.name}\n`);
    }
  } finally {
    rl.close();
  }

  output.write(`\nListo. Ejercicios actualizados: ${updated}\n`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
