import { createSign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const PROJECT_ID = "entrenamientoapplv";

function argsOf(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith("--")) continue;
    const key = item.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      args[key] = next;
      i += 1;
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

async function serviceAccountToken(path) {
  const credentials = JSON.parse(readFileSync(path, "utf8"));
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

function normalize(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

const baseAliases = new Map([
  ["bulgarian squat", "sentadilla bulgara"],
  ["curl de biceps barra z", "curl de biceps"],
  ["curl de biceps polea baja", "curl de biceps"],
  ["curl femoral maquina sentado", "curl femoral"],
  ["curl femoral maquina tumbado", "curl femoral"],
  ["dominada agarre prono", "dominada"],
  ["elevacion de pantorrillas maquina sentado", "elevacion de pantorrillas"],
  ["elevacion lateral mancuernas", "elevacion lateral"],
  ["extension de cuadriceps bilateral en maquina", "extension de cuadriceps"],
  ["extension de triceps cuerda en polea", "extension de triceps"],
  ["face pull cuerda en polea", "face pull"],
  ["facepull con polea", "face pull"],
  ["jalon al pecho agarre ancho", "jalon al pecho"],
  ["jalon con polea alta agarre amplio", "jalon al pecho"],
  ["jalon con polea baja agarre cerrado", "jalon al pecho"],
  ["jalon polea alta agarre cerrado", "jalon al pecho"],
  ["jalon polea baja agarre abierto", "jalon al pecho"],
  ["landmine press explosivo", "landmine press"],
  ["landmine press unilateral", "landmine press"],
  ["peso muerto rumano en deficit", "peso muerto"],
  ["peso muerto barra hex", "peso muerto"],
  ["peso muerto rumano", "peso muerto"],
  ["peso muerto trap bar", "peso muerto"],
  ["press de hombro barra", "press de hombro"],
  ["press de hombro maquina selectorizada", "press de hombro"],
  ["press de hombro db ktb", "press de hombro"],
  ["press de hombro sentado", "press de hombro"],
  ["press de hombros", "press de hombro"],
  ["press militar", "press de hombro"],
  ["press de pecho barra en banco plano", "press de pecho"],
  ["press de pecho maquina selectorizada", "press de pecho"],
  ["press banca", "press de pecho"],
  ["press banca con mancuernas", "press de pecho"],
  ["press banca inclinado db", "press de pecho"],
  ["pullover con barra", "pullover"],
  ["pullover con polea", "pullover"],
  ["remo maquina sentada", "remo"],
  ["remo pecho apoyado", "remo"],
  ["remo con barra", "remo"],
  ["remo en trx", "remo"],
  ["remo t en landmine", "remo"],
  ["remo unilateral con ktb", "remo"],
  ["goblet squat", "sentadilla"],
  ["sentadilla trasera con barra", "sentadilla"],
  ["sentadilla sumo ktb", "sentadilla"],
  ["sentadilla bulgara mancuernas", "sentadilla bulgara"],
  ["estocadas alternadas", "estocada"],
  ["estocada knee drive", "estocada"],
  ["step up a cajon", "step up"],
  ["step up bilateral", "step up"],
  ["step up explosivo con knee drive", "step up"],
  ["thrusther", "thruster"],
]);

const variantLabels = new Map([
  ["bulgarian squat", "Original"],
  ["curl de biceps barra z", "Barra Z"],
  ["curl de biceps polea baja", "Polea baja"],
  ["curl femoral maquina sentado", "Máquina sentado"],
  ["curl femoral maquina tumbado", "Máquina tumbado"],
  ["peso muerto rumano en deficit", "Rumano en déficit"],
  ["peso muerto barra hex", "Barra hexagonal"],
  ["peso muerto trap bar", "Trap bar"],
  ["peso muerto rumano", "Rumano con barra"],
  ["dominada agarre prono", "Agarre prono"],
  ["elevacion de pantorrillas maquina sentado", "Máquina sentado"],
  ["elevacion lateral mancuernas", "Mancuernas"],
  ["extension de cuadriceps bilateral en maquina", "Bilateral en máquina"],
  ["extension de triceps cuerda en polea", "Cuerda en polea"],
  ["face pull cuerda en polea", "Cuerda en polea"],
  ["facepull con polea", "Polea"],
  ["jalon al pecho agarre ancho", "Agarre ancho"],
  ["jalon con polea alta agarre amplio", "Agarre ancho"],
  ["jalon con polea baja agarre cerrado", "Polea baja, agarre cerrado"],
  ["jalon polea alta agarre cerrado", "Agarre cerrado"],
  ["jalon polea baja agarre abierto", "Polea baja, agarre abierto"],
  ["landmine press explosivo", "Explosivo"],
  ["landmine press unilateral", "Unilateral"],
  ["pullover con barra", "Barra"],
  ["pullover con polea", "Polea alta"],
  ["press de hombro barra", "Barra"],
  ["press de hombro maquina selectorizada", "Máquina selectorizada"],
  ["press de hombro db ktb", "Mancuerna o kettlebell"],
  ["press de hombro sentado", "Mancuernas sentado"],
  ["press de hombros", "Original"],
  ["press militar", "Barra"],
  ["press de pecho barra en banco plano", "Barra en banco plano"],
  ["press de pecho maquina selectorizada", "Máquina selectorizada"],
  ["press banca", "Barra en banco plano"],
  ["press banca con mancuernas", "Mancuernas en banco plano"],
  ["press banca inclinado db", "Mancuernas inclinado"],
  ["remo maquina sentada", "Máquina sentada"],
  ["remo pecho apoyado", "Pecho apoyado"],
  ["remo con barra", "Barra"],
  ["remo en trx", "TRX"],
  ["remo t en landmine", "Landmine T"],
  ["remo unilateral con ktb", "Kettlebell unilateral"],
  ["goblet squat", "Goblet"],
  ["sentadilla trasera con barra", "Barra trasera"],
  ["sentadilla sumo ktb", "Sumo con kettlebell"],
  ["sentadilla bulgara mancuernas", "Mancuernas"],
  ["estocadas alternadas", "Alternadas"],
  ["estocada knee drive", "Knee drive"],
  ["step up a cajon", "Caja"],
  ["step up bilateral", "Bilateral"],
  ["step up explosivo con knee drive", "Explosivo con knee drive"],
  ["thrusther", "Barra"],
]);

const stableVariantIds = new Map([
  [
    "sentadilla",
    new Map([
      ["barra frontal", "barbell_front"],
      ["barra trasera", "barbell_back"],
      ["belt squat", "belt_squat"],
      ["goblet con mancuerna", "goblet_dumbbell"],
      ["goblet con kettlebell", "goblet_kettlebell"],
      ["hack squat", "hack"],
      ["landmine", "landmine"],
      ["máquina smith", "smith"],
      ["peso corporal", "bodyweight"],
      ["safety bar", "safety_bar"],
      ["sentadilla pendular", "pendulum"],
    ]),
  ],
]);

function canonicalName(name) {
  const key = normalize(name);
  return baseAliases.get(key) ?? key;
}

function fromFirestore(value) {
  if (!value || typeof value !== "object") return value;
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return value.timestampValue;
  if ("mapValue" in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue?.fields ?? {}).map(([key, item]) => [
        key,
        fromFirestore(item),
      ]),
    );
  }
  if ("arrayValue" in value) {
    return (value.arrayValue?.values ?? []).map(fromFirestore);
  }
  return value;
}

function toFirestore(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toFirestore) } };
  }
  return {
    mapValue: {
      fields: Object.fromEntries(
        Object.entries(value).map(([key, item]) => [key, toFirestore(item)]),
      ),
    },
  };
}

async function listExercises(baseUrl, token) {
  const response = await fetch(`${baseUrl}/exercises?pageSize=500`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`No se pudo leer exercises (${response.status}).`);
  const data = await response.json();
  return (data.documents ?? []).map((document) => ({
    id: document.name.split("/").at(-1),
    fields: Object.fromEntries(
      Object.entries(document.fields ?? {}).map(([key, value]) => [
        key,
        fromFirestore(value),
      ]),
    ),
  }));
}

function variantKey(variant) {
  return normalize(variant.label || variant.id || "original");
}

function mergeVariants(documents, canonical) {
  const byKey = new Map();
  for (const document of documents) {
    const nameKey = normalize(document.fields.name);
    const rawVariants = Array.isArray(document.fields.variants)
      ? document.fields.variants
      : [];
    if (rawVariants.length === 0) {
      const label = variantLabels.get(nameKey) ??
        (nameKey === canonical ? "Original" : document.fields.name);
      rawVariants.push({
        id: normalize(label).replace(/ /g, "_"),
        label,
        group: document.fields.exerciseType === "Calistenia"
          ? "Peso corporal"
          : "Peso libre",
        equipment: Array.isArray(document.fields.equipment)
          ? document.fields.equipment
          : [],
        resistanceType: document.fields.resistanceType ?? "free",
        trackRM: document.fields.trackRM === true,
        trackProgression: document.fields.trackProgression === true,
        isUnilateral: document.fields.isUnilateral === true,
      });
    }
    for (const raw of rawVariants) {
      const variant = { ...raw };
      const key = variantKey(variant);
      if (nameKey !== canonical && variantLabels.has(nameKey)) {
        const label = variantLabels.get(nameKey);
        if (label === "Original") continue;
        variant.id = normalize(label).replace(/ /g, "_");
        variant.label = label;
      } else if (key === "original" && nameKey !== canonical) {
        continue;
      }
      const nextKey = variantKey(variant);
      const previous = byKey.get(nextKey);
      if (!previous) {
        byKey.set(nextKey, variant);
      } else {
        byKey.set(nextKey, {
          ...previous,
          ...variant,
          equipment: [...new Set([...(previous.equipment ?? []), ...(variant.equipment ?? [])])],
          trackRM: previous.trackRM === true || variant.trackRM === true,
          trackProgression:
            previous.trackProgression === true || variant.trackProgression === true,
          needsReview: previous.needsReview === true || variant.needsReview === true,
        });
      }
    }
  }
  const values = [...byKey.values()];
  if (values.length > 1) {
    for (const key of [...byKey.keys()]) {
      if (key === "original") byKey.delete(key);
    }
  }
  return [...byKey.values()].sort((a, b) =>
    String(a.label ?? "").localeCompare(String(b.label ?? ""), "es"),
  );
}

function chooseSurvivor(documents) {
  return [...documents].sort((a, b) => {
    const aBase = a.id.startsWith("movement_") ? 0 : 1;
    const bBase = b.id.startsWith("movement_") ? 0 : 1;
    if (aBase !== bBase) return aBase - bBase;
    const aName = String(a.fields.name ?? "");
    const bName = String(b.fields.name ?? "");
    return aName.length - bName.length || a.id.localeCompare(b.id);
  })[0];
}

async function commit(baseUrl, token, writes) {
  for (let index = 0; index < writes.length; index += 400) {
    const response = await fetch(`${baseUrl}:commit`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ writes: writes.slice(index, index + 400) }),
    });
    if (!response.ok) {
      const details = await response.text();
      throw new Error(`Firestore rechazó la unificación (${response.status}): ${details}`);
    }
  }
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const projectId = args.projectId ?? PROJECT_ID;
  const execute = args.execute === true;
  let token = args.accessToken ?? process.env.FIREBASE_ACCESS_TOKEN;
  const credentialPath = args.credentialsPath ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!token && credentialPath) {
    const path = resolve(credentialPath);
    if (!existsSync(path)) throw new Error("No existen las credenciales indicadas.");
    token = await serviceAccountToken(path);
  }
  if (!token) throw new Error("Usa --accessToken, FIREBASE_ACCESS_TOKEN o GOOGLE_APPLICATION_CREDENTIALS.");
  if (execute && args.confirm !== projectId) {
    throw new Error(`Para ejecutar usa --execute --confirm ${projectId}.`);
  }

  const baseUrl =
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}` +
    "/databases/(default)/documents";
  const documentBase =
    `projects/${projectId}/databases/(default)/documents`;
  const documents = await listExercises(baseUrl, token);
  if (args.repairStableIds === true) {
    const writes = [];
    for (const document of documents) {
      if (document.fields.mergedInto) continue;
      const movement = canonicalName(document.fields.name);
      const stable = stableVariantIds.get(movement);
      if (!stable || !Array.isArray(document.fields.variants)) continue;
      let changed = false;
      const variants = document.fields.variants.map((raw) => {
        const variant = { ...raw };
        const labelKey = normalize(variant.label);
        const stableId = stable.get(labelKey);
        if (stableId && variant.id !== stableId) {
          variant.id = stableId;
          changed = true;
        }
        if (movement === "sentadilla" && labelKey === "barra trasera" &&
            variant.trackProgression !== true) {
          variant.trackProgression = true;
          changed = true;
        }
        return variant;
      });
      if (!changed) continue;
      const update = {
        variants,
        trackProgression: variants.some((variant) => variant.trackProgression === true),
        trackRM: variants.some((variant) => variant.trackRM === true),
        updatedAt: new Date().toISOString(),
      };
      writes.push({
        update: {
          name: `${documentBase}/exercises/${document.id}`,
          fields: Object.fromEntries(
            Object.entries(update).map(([key, value]) => [key, toFirestore(value)]),
          ),
        },
        updateMask: { fieldPaths: Object.keys(update) },
      });
    }
    console.log(JSON.stringify({
      mode: execute ? "execute" : "preview",
      repairedDocuments: writes.length,
      repair: "stable_variant_ids",
    }, null, 2));
    if (!execute) return;
    await commit(baseUrl, token, writes);
    console.log("Identidades de variantes reparadas.");
    return;
  }
  const groups = new Map();
  for (const document of documents) {
    if (document.fields.mergedInto) continue;
    const key = canonicalName(document.fields.name);
    groups.set(key, [...(groups.get(key) ?? []), document]);
  }

  const plans = [];
  for (const [canonical, group] of groups) {
    if (group.length < 2) continue;
    const survivor = chooseSurvivor(group);
    const duplicates = group.filter((document) => document.id !== survivor.id);
    const variants = mergeVariants(group, canonical);
    plans.push({ canonical, survivor, duplicates, variants });
  }

  console.log(JSON.stringify({
    mode: execute ? "execute" : "preview",
    documents: documents.length,
    duplicateGroups: plans.length,
    duplicateDocuments: plans.reduce((sum, plan) => sum + plan.duplicates.length, 0),
    groups: plans.map((plan) => ({
      movement: plan.canonical,
      survivor: `${plan.survivor.fields.name} (${plan.survivor.id})`,
      merged: plan.duplicates.map((document) => `${document.fields.name} (${document.id})`),
      variants: plan.variants.map((variant) => variant.label),
    })),
  }, null, 2));
  if (!execute) return;

  const writes = [];
  for (const plan of plans) {
    const survivorData = plan.survivor.fields;
    const equipment = [...new Set(plan.variants.flatMap((variant) => variant.equipment ?? []))];
    const mergedFrom = [
      ...(Array.isArray(survivorData.mergedFrom) ? survivorData.mergedFrom : []),
      ...plan.duplicates.map((document) => document.id),
    ];
    const update = {
      name: plan.survivor.fields.name,
      variants: plan.variants,
      equipment,
      trackRM: plan.variants.some((variant) => variant.trackRM === true),
      trackProgression: plan.variants.some((variant) => variant.trackProgression === true),
      catalogStatus: "ready",
      mergedFrom: [...new Set(mergedFrom)],
      unifiedAt: new Date().toISOString(),
    };
    writes.push({
      update: {
        name: `${documentBase}/exercises/${plan.survivor.id}`,
        fields: Object.fromEntries(Object.entries(update).map(([key, value]) => [key, toFirestore(value)])),
      },
      updateMask: { fieldPaths: Object.keys(update) },
    });
    for (const duplicate of plan.duplicates) {
      const duplicateUpdate = {
        mergedInto: plan.survivor.id,
        canonicalExerciseId: plan.survivor.id,
        catalogStatus: "merged_duplicate",
        unifiedAt: new Date().toISOString(),
      };
      writes.push({
        update: {
          name: `${documentBase}/exercises/${duplicate.id}`,
          fields: Object.fromEntries(Object.entries(duplicateUpdate).map(([key, value]) => [key, toFirestore(value)])),
        },
        updateMask: { fieldPaths: Object.keys(duplicateUpdate) },
      });
    }
  }
  await commit(baseUrl, token, writes);
  console.log(`Unificación completada: ${plans.length} grupos y ${writes.length} documentos actualizados.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
