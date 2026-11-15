import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const databaseId = '(default)';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));

function b64(value) {
  return Buffer.from(value).toString('base64url');
}

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64(JSON.stringify({
    iss: credentials.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: credentials.token_uri,
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const assertion = `${unsigned}.${b64(signer.sign(credentials.private_key))}`;
  const response = await fetch(credentials.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Token ${response.status}: ${await response.text()}`);
  return (await response.json()).access_token;
}

function value(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map((item) => valueOf(item)) } };
  if (typeof value === 'object') {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, valueOf(v)])) } };
  }
  throw new Error(`Unsupported Firestore value: ${typeof value}`);
}

const valueOf = value;

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)]));
}

function documentName(collection, id) {
  return `projects/${projectId}/databases/${databaseId}/documents/${collection}/${id}`;
}

// Día 5 (dom 27-09): full body moderado, 60-70 min sin cardio.
// Carga semanal (L-M-Mi-V): deltoides medio/anterior ~90, isquios/glúteos ~85, dorsales 80,
// brazos ~70. Lo menos trabajado: pecho (15-19), trapecio inferior (14), serrato (11),
// glúteo medio (13), romboides/deltoide posterior (~30), abdomen bajo (26).
// -> Eje en pecho + espalda alta; pierna unilateral moderada; sin press de hombro ni bisagra.
//    Tríceps con peso libre a pedido del entrenador.
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const athleteName = 'Belén Trigo';
const blockId = 'belen_trigo_d5_full_body_2026_09_27';
const plannedId = 'belen_trigo_d5_2026_09_27';
const replacedBlockId = 'belen_trigo_d5_recuperacion_2026_09_27';
const now = new Date().toISOString();

const exercise = (data) => ({
  ...data,
  displayName: data.name,
  valueType: data.valueType ?? 'reps',
  trackRM: false,
  trackProgression: false,
});

const blockExercises = [
  exercise({
    // Mi: inclinado DB 10 kg x12 @RPE 7-8 -> plano 12 kg x10 para RPE ~8.
    name: 'Press De Pecho - Mancuernas en banco plano', exerciseId: 'movement_press_de_pecho', movementId: 'movement_press_de_pecho',
    variantId: 'mancuernas_en_banco_plano', variantLabel: 'Mancuernas en banco plano', techniqueId: 'mancuernas_en_banco_plano', resistanceType: 'free',
    equipment: 'Mancuernas, Banco', series: 4, reps: 10, value: 10, weight: 12, perSide: true,
    notes: 'Ejercicio principal del día: RPE 8 en las últimas series. Si 12 kg queda liviano, subir a 14.',
  }),
  exercise({
    // Carga total (barra Smith + discos). Mi: Remo con barra 20 kg x15 @RPE 7.
    name: 'Remo - Máquina Smith', exerciseId: 'movement_remo', movementId: 'movement_remo',
    variantId: 'maquina_smith', variantLabel: 'Máquina Smith', techniqueId: 'maquina_smith', resistanceType: 'guided',
    equipment: 'Máquina Smith', series: 3, reps: 10, value: 10, weight: 25, perSide: false,
    notes: 'Peso total incluyendo la barra. Torso ~45°, tirar al ombligo y juntar escápulas. Ajustar a RPE 8.',
  }),
  exercise({
    name: 'Step Up - Mancuernas', exerciseId: 'movement_step_up', movementId: 'movement_step_up',
    variantId: 'mancuernas', variantLabel: 'Mancuernas', techniqueId: 'mancuernas', resistanceType: 'free',
    equipment: 'Mancuernas, Caja', series: 3, reps: 8, value: 8, weight: 7.5, perSide: true,
    notes: 'Cajón a la altura de la rodilla. Empujar con la pierna de arriba, sin impulso de la de abajo. RPE 7.',
  }),
  exercise({
    name: 'One leg Hip Thrusth', exerciseId: 'm7jYDaRbNsQqbYTzKGEQ', movementId: 'm7jYDaRbNsQqbYTzKGEQ',
    variantId: 'original', variantLabel: 'Original', techniqueId: 'original', resistanceType: 'bodyweight',
    equipment: 'Banco, Peso corporal', series: 3, reps: 12, value: 12, weight: 1, perSide: true,
    notes: 'Pausa de 2" arriba, pelvis nivelada (que no caiga el lado libre).',
  }),
  exercise({
    // Mi: 25 kg x15 @RPE 7-8.
    name: 'Face Pull - Cuerda en polea', exerciseId: 'movement_face_pull_cuerda_en_polea', movementId: 'movement_face_pull_cuerda_en_polea',
    variantId: 'original', variantLabel: 'Face pull con cuerda', techniqueId: 'original', resistanceType: 'guided',
    equipment: 'Polea alta, Cuerda', series: 3, reps: 15, value: 15, weight: 25, perSide: false,
    notes: 'Tirar hacia la frente separando la cuerda, codos altos. Pausa de 1" atrás.',
  }),
  exercise({
    // Primer registro de esta variante; L: sobre cabeza a dos manos 10 kg x12 @RPE 7-9.
    name: 'Extension De Triceps - Acostado con mancuernas', exerciseId: 'movement_extension_de_triceps', movementId: 'movement_extension_de_triceps',
    variantId: 'mancuerna_acostado', variantLabel: 'Acostado con mancuernas', techniqueId: 'lying_dumbbell', resistanceType: 'free',
    equipment: 'Mancuernas, Banco', series: 3, reps: 12, value: 12, weight: 5, perSide: true,
    notes: 'Codos fijos apuntando al techo, bajar las mancuernas al lado de la cabeza. RPE 8.',
  }),
];

const block = {
  isLibraryTemplate: true,
  title: 'FULL BODY 1',
  athleteId,
  folder: 'BELEN',
  type: 'Series',
  description: 'Full body moderado (60-70 min, sin cardio). Descansos: 90" en los tres primeros ejercicios, 45-60" en el resto. El atleta registra el RPE durante la sesión.',
  exercises: blockExercises,
  createdAt: now,
  updatedAt: now,
  libraryOrder: Date.now(),
};

const planned = {
  athleteId,
  athleteName,
  blockId,
  blockTitle: 'FULL BODY 1',
  date: '2026-09-27T03:00:00Z',
  day: 5,
  week: 1,
  order: 0,
  status: 'planned',
  createdAt: now,
  blockUpdatedAt: now,
};

const token = await accessToken();
const writes = [
  { update: { name: documentName('blocks', blockId), fields: fields(block) } },
  { update: { name: documentName('planned_workouts', plannedId), fields: fields(planned) } },
  // Reemplaza la primera propuesta del día (recuperación), que no se usará.
  { delete: documentName('blocks', replacedBlockId) },
];

const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents:commit`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ writes }),
});
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(JSON.stringify({ athlete: athleteName, blockId, plannedId, date: planned.date, exercises: blockExercises.map((item) => `${item.name} ${item.series}x${item.reps}${item.perSide ? '/lado' : ''}`) }, null, 2));
