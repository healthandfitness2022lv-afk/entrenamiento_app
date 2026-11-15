import { readFileSync } from "node:fs";
import { createSign } from "node:crypto";

const projectId = "entrenamientoapplv";
const credentialsPath = "secrets/entrenamientoapplv-firebase-adminsdk-fbsvc-f746e3a4e5.json";
const documentId = "movement_landmine_clean";

const toBase64Url = (input) => Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
const fsValue = (value) => {
  if (value === null) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(fsValue) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, fsValue(item)])) } };
};

async function token() {
  const service = JSON.parse(readFileSync(credentialsPath, "utf8"));
  const now = Math.floor(Date.now() / 1000);
  const header = toBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = toBase64Url(JSON.stringify({ iss: service.client_email, scope: "https://www.googleapis.com/auth/datastore", aud: service.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256"); signer.update(unsigned); signer.end();
  const response = await fetch(service.token_uri, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${toBase64Url(signer.sign(service.private_key))}` }) });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()).access_token;
}

const data = {
  name: "Landmine Clean",
  movementClass: "compound",
  exerciseType: "Balísticos",
  resistanceType: "free",
  equipment: ["Barra", "Landmine"],
  isUnilateral: false,
  instructions: "1. Coloca un extremo de la barra en el landmine y sujeta el otro con ambas manos.\n2. Baja con una bisagra de cadera y rodillas flexionadas, manteniendo la espalda neutra.\n3. Extiende caderas y rodillas con potencia para recibir la barra a la altura de los hombros.\n4. Estabiliza la recepción, vuelve a la posición inicial y repite con control.",
  muscleWeights: { quads: 0.25, glutes: 0.25, hamstrings: 0.12, trapsUpper: 0.18, lowerBack: 0.08, abs: 0.07, midDelts: 0.05 },
  variants: [{ id: "bilateral", label: "Bilateral", equipment: ["Barra", "Landmine"], resistanceType: "free", isUnilateral: false, trackRM: true, trackProgression: true, group: "Peso libre" }],
  catalogStatus: "reviewed_single",
  catalogReviewedBy: "ai_initial_review_v1",
  videoUrl: "",
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
};

const accessToken = await token();
const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/exercises/${documentId}`;
const response = await fetch(url, { method: "PATCH", headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, fsValue(value)])) }) });
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(`Ejercicio creado/actualizado: ${documentId}`);
