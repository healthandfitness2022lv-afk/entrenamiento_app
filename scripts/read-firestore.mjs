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

function toBase64Url(input) {
  const buffer = Buffer.isBuffer(input) ? input : Buffer.from(input);
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
  if ("referenceValue" in value) return value.referenceValue;
  if ("geoPointValue" in value) return value.geoPointValue;
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
    _createTime: document.createTime,
    _updateTime: document.updateTime,
    ...Object.fromEntries(
      Object.entries(fields).map(([key, value]) => [key, convertFirestoreValue(value)]),
    ),
  };
}

async function getAccessToken(credentialsPath) {
  const raw = readFileSync(credentialsPath, "utf8");
  const serviceAccount = JSON.parse(raw);

  if (!serviceAccount.client_email || !serviceAccount.private_key || !serviceAccount.token_uri) {
    throw new Error("El JSON no parece ser una service account válida.");
  }

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
  const signature = signer.sign(serviceAccount.private_key);
  const assertion = `${unsignedJwt}.${toBase64Url(signature)}`;

  const response = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`No se pudo obtener access token: ${response.status} ${text}`);
  }

  const data = await response.json();
  return data.access_token;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectId = args.projectId;
  const collectionPath = args.collectionPath;
  const documentId = args.documentId;
  const databaseId = args.databaseId ?? "(default)";
  const pageSize = Number(args.pageSize ?? "25");
  const credentialsPathArg = args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (!projectId) throw new Error("Falta --projectId.");
  if (!collectionPath) throw new Error("Falta --collectionPath.");
  if (!credentialsPathArg) {
    throw new Error("Define GOOGLE_APPLICATION_CREDENTIALS o usa --credentialsPath.");
  }

  const credentialsPath = resolve(credentialsPathArg);
  if (!existsSync(credentialsPath)) {
    throw new Error(`No se encontró el archivo de credenciales en '${credentialsPath}'.`);
  }

  const token = await getAccessToken(credentialsPath);
  const encodedCollectionPath = encodePathSegments(collectionPath);
  const baseUrl =
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}` +
    `/databases/${encodeURIComponent(databaseId)}/documents/${encodedCollectionPath}`;

  const url = documentId
    ? `${baseUrl}/${encodePathSegments(documentId)}`
    : `${baseUrl}?pageSize=${encodeURIComponent(String(pageSize))}`;

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Firestore respondió ${response.status}: ${text}`);
  }

  const data = await response.json();
  if (documentId) {
    console.log(JSON.stringify(convertFirestoreDocument(data), null, 2));
    return;
  }

  const documents = (data.documents ?? []).map(convertFirestoreDocument);
  console.log(JSON.stringify(documents, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
