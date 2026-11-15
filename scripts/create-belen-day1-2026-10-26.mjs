import { readFileSync } from 'node:fs';
import { createSign, randomBytes } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const dryRun = process.argv.includes('--dry-run');
const now = new Date().toISOString();
const date = '2026-10-26T03:00:00Z';
// Sesión ya realizada el lun 26-10 (20:15-21:20 hora Chile), todo a RPE 7.
const startedAt = '2026-10-26T23:15:00Z';
const finishedAt = '2026-10-27T00:20:00Z';
const performedRpe = 7;

const b64 = (value) => Buffer.from(value).toString('base64url');
async function accessToken() {
  const issuedAt = Math.floor(Date.now() / 1000);
  const unsigned = `${b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64(JSON.stringify({ iss: credentials.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: credentials.token_uri, iat: issuedAt, exp: issuedAt + 3600 }))}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(credentials.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(credentials.private_key))}` }) });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
}
function decode(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  throw new Error('Tipo Firestore no soportado');
}
// Las fechas del workout son Timestamp en la app (`data['date'] as Timestamp`).
class Ts { constructor(iso) { this.iso = iso; } }
function value(data) {
  if (data === null) return { nullValue: null };
  if (data instanceof Ts) return { timestampValue: data.iso };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data) ? { integerValue: String(data) } : { doubleValue: data };
  if (typeof data === 'string') return { stringValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)])) } };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)]));
const name = (path) => `projects/${projectId}/databases/(default)/documents/${path}`;
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const getDoc = async (token, path) => {
  const response = await fetch(`${base}/${path}`, { headers: { Authorization: `Bearer ${token}` } });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${path} ${response.status}: ${await response.text()}`);
  return Object.fromEntries(Object.entries((await response.json()).fields ?? {}).map(([key, item]) => [key, decode(item)]));
};
const listDocs = async (token, path) => {
  const docs = []; let pageToken = '';
  do {
    const response = await fetch(`${base}/${path}?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ''}`, { headers: { Authorization: `Bearer ${token}` } });
    if (!response.ok) throw new Error(`${path} ${response.status}: ${await response.text()}`);
    const json = await response.json(); docs.push(...(json.documents ?? [])); pageToken = json.nextPageToken ?? '';
  } while (pageToken);
  return docs.map((doc) => ({ id: doc.name.split('/').pop(), ...decode({ mapValue: { fields: doc.fields ?? {} } }) }));
};
const commit = async (token, writes) => {
  const response = await fetch(`${base}:commit`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }) });
  if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
};

// ── Sesión ─────────────────────────────────────────────────────────────────
// Lun 26-10. Semana 6, día 1: viene de 7 días sin entrenar tras el torso del
// 19-10. Cargas desde lo realizado, mantenidas o levemente progresadas.
const source = 'belen_trigo_d1_musculacion_2026_10_13';
const plan = [
  { name: 'Sentadilla - Barra trasera', series: 4, reps: 6, weight: 52.5, notes: '52,5 kg: el 13-10 hizo 4×6 a RPE 8-8-8-9. Se mantiene tras la semana sin entrenar; si las 4 quedan en RPE ≤8, la próxima sube a 55 kg. Descanso 2 min.' },
  { name: 'Hip Thrust - Máquina con discos', series: 3, reps: 8, weight: 57.5, notes: '57,5 kg: el 13-10 subió por su cuenta a 60 kg × 6 a RPE 9. Un escalón menos para hacer 8 reps con pausa de 1 s arriba. Descanso 2 min.' },
  { name: 'Press De Pecho - Barra en banco plano', series: 3, reps: 10, weight: 27.5, notes: '27,5 kg: el 19-10 hizo 10-15-12 reps a RPE 9-10-10. Cortar en 10 aunque salgan más: el objetivo es RPE 8, sin fallo. Descanso 2 min.' },
  { name: 'Jalon Al Pecho - Agarre ancho', series: 3, reps: 10, weight: 35, notes: '35 kg: 30 kg × 12 quedó en RPE 8 estable el 13-10. Sube la carga y bajan las reps; si no completa 10 limpias, volver a 30 × 12. Depresión escapular antes de tirar.' },
  { name: 'Curl De Biceps - Barra Z', series: 3, reps: 12, weight: 14, notes: '14 kg: el 19-10 abrió con 16 kg y bajó a 14 kg a RPE 9. Las 3 series con 14 kg, estrictas, sin balanceo.' },
  { name: 'Extension De Triceps - Cuerda en polea', series: 3, reps: 12, weight: 15, notes: '15 kg: las dos últimas veces la cambió por mancuerna sobre cabeza o la saltó. Hacerla con cuerda en polea, codos fijos pegados al cuerpo. Descanso 60 s.' },
];

const blockId = 'belen_trigo_d1_musculacion_2026_10_26';
const plannedId = 'belen_trigo_d1_2026_10_26';
const title = 'MUSCULACION 1';
// Mismo formato de ID que `collection().add()`.
const workoutId = Array.from(randomBytes(20), (byte) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'[byte % 62]).join('');

const token = await accessToken();

// Salvaguardas: no duplicar ni registrar dos veces el lunes.
if (await getDoc(token, `planned_workouts/${plannedId}`)) throw new Error(`Ya existe planned_workouts/${plannedId}`);
if (await getDoc(token, `blocks/${blockId}`)) throw new Error(`Ya existe blocks/${blockId}`);
const query = async (collection, field) => {
  const response = await fetch(`${base}:runQuery`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: collection }], where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: { stringValue: athleteId } } } } }),
  });
  return (await response.json()).filter((r) => r.document).map((r) => decode({ mapValue: { fields: r.document.fields } }));
};
const sameDayPlanned = (await query('planned_workouts', 'athleteId')).filter((p) => String(p.date ?? '').startsWith('2026-10-26'));
if (sameDayPlanned.length) throw new Error(`Ya hay planned_workouts el 26-10: ${sameDayPlanned.map((p) => p.blockTitle).join(', ')}`);
const logged = await query('workouts_logged', 'userId');
const newerLogs = logged.filter((w) => String(w.date) >= '2026-10-20');
if (newerLogs.length) throw new Error(`Ya hay registros desde el 20-10: ${newerLogs.map((w) => `${w.date} ${w.sessionName}`).join(', ')}`);

const sourceBlock = await getDoc(token, `blocks/${source}`);
const exercises = plan.map((item) => {
  const found = sourceBlock?.exercises?.find((exercise) => exercise.name === item.name);
  if (!found) throw new Error(`No encontré ${item.name} en ${source}`);
  const { instanceId, durationMinutes, ...rest } = found;
  return { ...rest, series: item.series, reps: item.reps, value: item.reps, weight: item.weight, notes: item.notes };
});

const block = {
  type: 'Series', folder: 'BELEN', athleteId, isLibraryTemplate: true, title,
  description: 'Lun 26-10. Semana 6, día 1. Vuelve tras 7 días sin entrenar (último: torso del 19-10), así que se mantienen las cargas o se progresa levemente desde lo realizado. Descansos: 2 min en sentadilla, hip thrust y press; 60-90 s en el resto.',
  exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now(),
};
const planned = {
  athleteId, athleteName: 'Belén Trigo', blockId, blockTitle: title,
  date, day: 1, week: 6, order: 0, status: 'planned', createdAt: now, blockUpdatedAt: now,
};

// Mismo formato que WorkoutSaveService._processSeries / _identitySnapshot.
const performed = [{
  type: 'Series', blockIndex: 0, blockTitle: title, plannedWorkoutId: plannedId, blockId,
  exercises: exercises.map((exercise, index) => ({
    exercise: exercise.name,
    exerciseId: exercise.exerciseId, movementId: exercise.movementId, movementName: exercise.movementName,
    variantId: exercise.variantId, variantLabel: exercise.variantLabel, displayName: exercise.displayName ?? exercise.name,
    resistanceType: exercise.resistanceType,
    exerciseInstanceId: `${exercise.exerciseId}_${exercise.variantId}_${index}`,
    plannedWorkoutId: plannedId, blockId,
    plannedSetsSnapshot: Array.from({ length: exercise.series }, () => ({ reps: exercise.reps, weight: exercise.weight, perSide: exercise.perSide === true })),
    perSide: exercise.perSide === true,
    sets: Array.from({ length: exercise.series }, () => ({ reps: exercise.reps, weight: exercise.weight, rpe: performedRpe })),
  })),
}];

// ── Carga muscular: port de WorkoutLoadService.calculateLoadFromWorkout ─────
const defaultRpeFactors = { 1: 0, 2: 0.15, 3: 0.3, 4: 0.45, 5: 0.6, 6: 0.85, 7: 1, 8: 1.15, 9: 1.3, 10: 1.5 };
const rpeSettings = await getDoc(token, 'admin_settings/rpe_factors');
const rpeFactor = (rpe) => { const key = Math.min(10, Math.max(1, Math.round(rpe))); return rpeSettings?.[String(key)] ?? defaultRpeFactors[key]; };
const folderFactors = Object.fromEntries((await listDocs(token, 'exercise_folders')).filter((f) => f.name).map((f) => [f.name, f.multiplier ?? 1]));
const rawLoad = {};
for (const entry of performed[0].exercises) {
  const catalog = await getDoc(token, `exercises/${entry.exerciseId}`);
  if (!catalog) throw new Error(`Sin catálogo: ${entry.exerciseId}`);
  const variant = (catalog.variants ?? []).find((v) => v.id === entry.variantId);
  const overrides = variant?.muscleWeightOverrides;
  const weights = overrides && Object.keys(overrides).length ? overrides : catalog.muscleWeights;
  if (!weights || !Object.keys(weights).length) throw new Error(`Sin muscleWeights: ${entry.exerciseId}`);
  for (const set of entry.sets) {
    const folder = folderFactors[catalog.exerciseType ?? ''] ?? 1;
    const exerciseFactor = (set.weight ?? 0) > 7 && folder < 0.8 ? 1 : folder;
    for (const [muscle, weight] of Object.entries(weights)) {
      const key = muscle === 'traps' ? 'trapsUpper' : muscle;
      rawLoad[key] = (rawLoad[key] ?? 0) + set.rpe * rpeFactor(set.rpe) * exerciseFactor * weight;
    }
  }
}
const muscleLoad = Object.fromEntries(Object.entries(rawLoad).map(([muscle, load]) => [muscle, 100 * (1 - Math.exp(-load / 45))]));

const workout = {
  userId: athleteId, sessionName: title,
  date: new Ts(finishedAt), startedAt: new Ts(startedAt), finishedAt: new Ts(finishedAt),
  durationMinutes: Math.round((Date.parse(finishedAt) - Date.parse(startedAt)) / 60000),
  performed, plannedWorkoutIds: [plannedId], plannedBlockIds: [blockId], muscleLoad,
};

// ── Fatiga: port de FatigueRecalculationService.applySessionAndPersist ──────
const defaultRecovery = {
  calves: 0.6, forearms: 0.6, abs: 0.6, lowerAbs: 0.6, obliques: 0.6, midDelts: 0.6, rearDelts: 0.6, biceps: 0.6,
  triceps: 0.65, frontDelts: 0.65, trapsUpper: 0.65, lowerTraps: 0.65, serratus: 0.65, psoas: 0.65,
  upperChest: 0.7, lats: 0.7, midBack: 0.7, rombs: 0.7, lowerBack: 0.7,
  quads: 0.74, chest: 0.74, hamstrings: 0.74, glutes: 0.74, midGlutes: 0.74, adductors: 0.74,
};
const recoverySettings = await getDoc(token, 'admin_settings/muscle_recovery');
const recoveryFactor = (muscle) => recoverySettings?.[muscle] ?? defaultRecovery[muscle];
const sessionDate = new Date(finishedAt);
const fatigueDoc = await getDoc(token, `users/${athleteId}/fatigue_state/latest`);
const state = {};
for (const [muscle, fatigue] of Object.entries(fatigueDoc?.fatigue ?? {})) {
  if (!(muscle in defaultRecovery)) continue;
  const lastUpdate = fatigueDoc.lastUpdateByMuscle?.[muscle];
  state[muscle] = { fatigue, lastUpdate: lastUpdate ? new Date(lastUpdate) : sessionDate };
}
const latestUpdate = Object.values(state).reduce((latest, s) => (s.lastUpdate > latest ? s.lastUpdate : latest), new Date(0));
if (latestUpdate > sessionDate) throw new Error(`fatigue_state tiene datos posteriores al 26-10 (${latestUpdate.toISOString()}): usar "Recalcular fatiga"`);
const snapshot = () => Object.fromEntries(Object.entries(state).map(([m, s]) => [m, s.fatigue]));
const fatigueBefore = snapshot();
const hoursSinceLastWorkout = Object.keys(state).length ? Math.floor((sessionDate - latestUpdate) / 60000) / 60 : 0;
for (const [muscle, s] of Object.entries(state)) {
  const hours = Math.floor((sessionDate - s.lastUpdate) / 60000) / 60;
  if (s.fatigue > 0 && hours > 0) s.fatigue = Math.min(100, Math.max(0, s.fatigue * Math.pow(Math.pow(recoveryFactor(muscle), 1 / 24), hours)));
  else if (s.fatigue <= 0) s.fatigue = 0;
  s.lastUpdate = sessionDate;
}
const fatigueAfterRecovery = snapshot();
for (const [muscle, load] of Object.entries(muscleLoad)) {
  state[muscle] ??= { fatigue: 0, lastUpdate: sessionDate };
  state[muscle] = { fatigue: Math.min(100, Math.max(0, state[muscle].fatigue + Math.max(0, load))), lastUpdate: sessionDate };
}
const fatigueAfter = snapshot();
const relevant = Object.values(fatigueAfter).filter((v) => v >= 5);
const globalFatigue = relevant.length ? Math.min(100, relevant.reduce((a, b) => a + b, 0) / relevant.length) : 0;
const auditCount = (await listDocs(token, `users/${athleteId}/fatigue_audit`)).length;
const auditId = String(auditCount).padStart(4, '0');

console.log(JSON.stringify({
  dryRun, block: blockId, planned: plannedId, workout: `workouts_logged/${workoutId}`, audit: auditId,
  exercises: exercises.map((e) => `${e.name}: ${e.series}×${e.reps} @ ${e.weight} (RPE ${performedRpe})`),
  muscleLoad: Object.fromEntries(Object.entries(muscleLoad).map(([m, v]) => [m, +v.toFixed(1)])),
  fatigueAfterRecovery: Object.fromEntries(Object.entries(fatigueAfterRecovery).map(([m, v]) => [m, +v.toFixed(1)])),
  fatigueAfter: Object.fromEntries(Object.entries(fatigueAfter).map(([m, v]) => [m, +v.toFixed(1)])),
  globalFatigue: +globalFatigue.toFixed(1),
}, null, 2));
if (dryRun) process.exit(0);

await commit(token, [
  { update: { name: name(`blocks/${blockId}`), fields: fields(block) }, currentDocument: { exists: false } },
  { update: { name: name(`planned_workouts/${plannedId}`), fields: fields(planned) }, currentDocument: { exists: false } },
  { update: { name: name(`workouts_logged/${workoutId}`), fields: fields(workout) }, currentDocument: { exists: false } },
]);
await commit(token, [
  { update: { name: name(`users/${athleteId}/fatigue_state/latest`), fields: fields({
    generatedAt: new Ts(new Date().toISOString()),
    fatigue: fatigueAfter,
    lastUpdateByMuscle: Object.fromEntries(Object.entries(state).map(([m, s]) => [m, new Ts(s.lastUpdate.toISOString())])),
  }) } },
  { update: { name: name(`users/${athleteId}`), fields: fields({ globalFatigue, lastFatigueCalculation: new Ts(new Date().toISOString()) }) }, updateMask: { fieldPaths: ['globalFatigue', 'lastFatigueCalculation'] } },
  { update: { name: name(`users/${athleteId}/fatigue_audit/${auditId}`), fields: fields({
    workoutDate: new Ts(finishedAt), hoursSinceLastWorkout, loadApplied: muscleLoad,
    fatigueBefore, fatigueAfterRecovery, fatigueAfter, isFirstWorkout: Object.keys(fatigueBefore).length === 0, isRecoveryOnly: false,
  }) }, currentDocument: { exists: false } },
]);
console.log('OK');
