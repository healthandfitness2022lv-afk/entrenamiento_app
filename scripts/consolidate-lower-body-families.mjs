import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Consolidates the existing lower-body catalog. It never deletes legacy docs;
// they are retained with a redirect to the canonical movement.
const credentialsPath = process.argv[2];
if (!credentialsPath) throw new Error('Provide a service-account JSON path.');
const account = JSON.parse(readFileSync(resolve(credentialsPath), 'utf8'));
const base = `https://firestore.googleapis.com/v1/projects/${account.project_id}/databases/(default)/documents`;
const b64 = (value) => Buffer.from(value).toString('base64url');

async function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64(JSON.stringify({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: account.token_uri, iat: now, exp: now + 3600 }));
  const unsigned = `${header}.${claim}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned); signer.end();
  const response = await fetch(account.token_uri, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${b64(signer.sign(account.private_key))}` }) });
  if (!response.ok) throw new Error(`Token request failed: ${response.status}`);
  return (await response.json()).access_token;
}
function decode(value) {
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decode(item)]));
  return null;
}
function encode(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encode) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)])) } };
}
async function list(access, collection) {
  const response = await fetch(`${base}/${collection}?pageSize=1000`, { headers: { Authorization: `Bearer ${access}` } });
  if (!response.ok) throw new Error(`${collection}: ${response.status}`);
  return ((await response.json()).documents ?? []).map((document) => ({ id: document.name.split('/').at(-1), raw: document.fields ?? {}, data: Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decode(value)])) }));
}
async function patchFields(access, collection, id, fields) {
  const query = Object.keys(fields).map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`).join('&');
  const response = await fetch(`${base}/${collection}/${id}?${query}`, { method: 'PATCH', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, encode(value)])) }) });
  if (!response.ok) throw new Error(`${collection}/${id}: ${response.status} ${await response.text()}`);
}
function addOrReplace(variants, incoming) {
  const index = variants.findIndex((variant) => variant.id === incoming.id);
  if (index >= 0) variants[index] = { ...variants[index], ...incoming };
  else variants.push(incoming);
}
function standardVariant({ id, label, equipment, type = 'Fuerza', discipline = 'fuerza', intent = 'full', unilateral = false, group = 'Peso libre', resistanceType = 'free', familyId, techniqueId, trackRM = false, trackProgression = false, muscleWeightOverrides = {} }) {
  return { id, label, group, equipment, resistanceType, trackRM, trackProgression, isUnilateral: unilateral, exerciseType: type, trainingDiscipline: discipline, movementIntent: intent, familyId, techniqueId, techniqueLabel: label, ...(Object.keys(muscleWeightOverrides).length ? { muscleWeightOverrides } : {}) };
}
const normalized = (value) => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const familySlug = (name) => normalized(name).replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
function disciplineFor(type) {
  const value = normalized(type);
  if (value.includes('pliometr')) return 'pliometria';
  if (value.includes('balist')) return 'balistico';
  if (value.includes('potencia')) return 'potencia';
  if (value.includes('halter') || value.includes('olimp')) return 'halterofilia';
  if (value.includes('hipert') || value.includes('acces') || value.includes('aisla')) return 'hipertrofia';
  if (value.includes('calisten') || value.includes('peso corporal')) return 'calistenia';
  if (value.includes('core') || value.includes('estab')) return 'core';
  if (value.includes('correct') || value.includes('movil')) return 'correctivos';
  if (value.includes('cardio') || value.includes('metab') || value.includes('condic')) return 'metabolico';
  return 'fuerza';
}
function intentFor(type) {
  const value = normalized(type);
  if (value.includes('pliometr') || value.includes('balist') || value.includes('potencia')) return 'power';
  if (value.includes('cardio') || value.includes('metab') || value.includes('condic')) return 'conditioning';
  if (value.includes('correct') || value.includes('core') || value.includes('estab') || value.includes('movil')) return 'control';
  if (value.includes('aisla')) return 'isolation';
  return 'full';
}

const configs = [
  {
    id: 'movement_peso_muerto', familyId: 'deadlift', type: 'Fuerza', discipline: 'fuerza', intent: 'full',
    redirects: { amzE6XOCqNbjttPa57Of: 'trap_bar', movement_peso_muerto_trap_bar: 'trap_bar' },
    normalize: (variant) => ({ ...variant, familyId: 'deadlift', exerciseType: variant.id.includes('polea') || variant.id === 'smith' ? 'Hipertrofia' : 'Fuerza', trainingDiscipline: variant.id.includes('polea') || variant.id === 'smith' ? 'hipertrofia' : 'fuerza', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('one_leg') || variant.isUnilateral === true }),
  },
  {
    id: 'movement_sentadilla', familyId: 'squat', type: 'Fuerza', discipline: 'fuerza', intent: 'full',
    redirects: { D0ttG9Vm6fbbB3mPPRO5: 'barbell_back', IeB3KTkNjqzOfjk75GEf: 'goblet_kettlebell', FDCDa97OexuHToc7xnlp: 'jump_bodyweight', uuRIjz0xImOyRp6G1Dui: 'jump_trap_bar', '8VF5BrO3OYvFS0HsytqG': 'pistol_bodyweight', vBYsWlh91xXhsgTWjHaI: 'cossack_bodyweight', s7dW4Ooi45WTGhBrvXs2: 'cossack_landmine' },
    normalize: (variant) => ({ ...variant, familyId: 'squat', exerciseType: 'Fuerza', trainingDiscipline: 'fuerza', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'jump_bodyweight', label: 'Salto vertical', equipment: ['Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'squat', techniqueId: 'jump' }),
      standardVariant({ id: 'jump_metabolic', label: 'Salto vertical · Metabólico', equipment: ['Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'conditioning', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'squat', techniqueId: 'jump' }),
      standardVariant({ id: 'jump_barbell', label: 'Salto con barra', equipment: ['Barra'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', familyId: 'squat', techniqueId: 'jump' }),
      standardVariant({ id: 'jump_dumbbell', label: 'Salto con mancuernas', equipment: ['Mancuernas'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', familyId: 'squat', techniqueId: 'jump' }),
      standardVariant({ id: 'jump_kettlebell', label: 'Salto con kettlebell', equipment: ['Kettlebell'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', familyId: 'squat', techniqueId: 'jump' }),
      standardVariant({ id: 'jump_abalakov', label: 'Abalakov', equipment: ['Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'squat', techniqueId: 'jump' }),
      standardVariant({ id: 'jump_trap_bar', label: 'Salto con trap bar', equipment: ['Trap bar'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', familyId: 'squat', techniqueId: 'jump' }),
      standardVariant({ id: 'pistol_bodyweight', label: 'Pistol squat', equipment: ['Peso corporal'], type: 'Calistenia', discipline: 'calistenia', intent: 'full', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'squat', techniqueId: 'pistol' }),
      standardVariant({ id: 'cossack_bodyweight', label: 'Cossack squat', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'squat', techniqueId: 'cossack' }),
      standardVariant({ id: 'cossack_landmine', label: 'Cossack squat con landmine', equipment: ['Barra', 'Landmine'], type: 'Fuerza', discipline: 'fuerza', intent: 'full', unilateral: true, familyId: 'squat', techniqueId: 'cossack' }),
    ],
  },
  {
    id: 'movement_sentadilla_bulgara', familyId: 'split_squat', type: 'Fuerza', discipline: 'fuerza', intent: 'full',
    redirects: { ntpWlA1JxMa8tIuTxHAR: 'mancuernas', movement_sentadilla_bulgara_mancuernas: 'mancuernas' },
    normalize: (variant) => ({ ...variant, familyId: 'split_squat', exerciseType: variant.id === 'bodyweight' ? 'Calistenia' : 'Fuerza', trainingDiscipline: variant.id === 'bodyweight' ? 'calistenia' : 'fuerza', movementIntent: 'full', techniqueId: variant.techniqueId || 'rear_foot_elevated', techniqueLabel: variant.techniqueLabel || 'Búlgara', isUnilateral: true }),
    additions: [
      standardVariant({ id: 'plyo_jump_bodyweight', label: 'Búlgara con salto', equipment: ['Banco', 'Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'split_squat', techniqueId: 'rear_foot_elevated_jump' }),
      standardVariant({ id: 'plyo_knee_drive_bodyweight', label: 'Búlgara explosiva con rodilla alta', equipment: ['Banco', 'Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'split_squat', techniqueId: 'rear_foot_elevated_knee_drive' }),
      standardVariant({ id: 'plyo_step_tap_bodyweight', label: 'Búlgara con toque rápido al step', equipment: ['Banco', 'Step', 'Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'split_squat', techniqueId: 'rear_foot_elevated_step_tap' }),
    ],
  },
  {
    id: 'movement_curl_de_biceps', familyId: 'biceps_curl', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation',
    redirects: { movement_curl_de_biceps_barra_z: 'barra_z', movement_curl_de_biceps_polea_baja: 'polea_baja', '8E50wfjQ59MGkkKPHHQk': 'polea_baja', dZrwiGU4k8ynKUF7lkqX: 'concentrado_mancuerna', r2p9pb7TGVTcfgavMT8c: 'barra_z' },
    normalize: (variant) => ({ ...variant, familyId: 'biceps_curl', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('mancuerna') || variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'concentrado_mancuerna', label: 'Concentrado con mancuerna', equipment: ['Mancuerna'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', unilateral: true, familyId: 'biceps_curl', techniqueId: 'concentration' }),
      standardVariant({ id: 'martillo_mancuernas', label: 'Martillo con mancuernas', equipment: ['Mancuernas'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', unilateral: true, familyId: 'biceps_curl', techniqueId: 'hammer' }),
      standardVariant({ id: 'martillo_cruzado_mancuerna', label: 'Martillo cruzado', equipment: ['Mancuerna'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', unilateral: true, familyId: 'biceps_curl', techniqueId: 'cross_body_hammer' }),
      standardVariant({ id: 'inclinado_mancuernas', label: 'Inclinado con mancuernas', equipment: ['Mancuernas', 'Banco inclinado'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', unilateral: true, familyId: 'biceps_curl', techniqueId: 'incline' }),
      standardVariant({ id: 'inverso_barra_z', label: 'Inverso con barra Z', equipment: ['Barra Z'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', familyId: 'biceps_curl', techniqueId: 'reverse' }),
    ],
  },
  {
    id: 'movement_extension_de_triceps', familyId: 'triceps_extension', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation',
    redirects: { '3EKyJ6VBkgHaGXOzHmol': 'barra_en_polea', '5Xm1cfvsH1GubGn1TkOk': 'mancuerna_sobre_cabeza', movement_extension_de_triceps_cuerda_en_polea: 'cuerda_en_polea', zJ1ebrVtRJDBHrj7ccK7: 'polea_sobre_cabeza', RoH7QYKcKp0Lumlc4lKY: 'barra_z_acostado' },
    normalize: (variant) => ({ ...variant, familyId: 'triceps_extension', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('mancuerna') || variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'polea_sobre_cabeza', label: 'Polea sobre cabeza', equipment: ['Polea alta', 'Cuerda'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', familyId: 'triceps_extension', techniqueId: 'overhead_cable' }),
      standardVariant({ id: 'mancuerna_acostado', label: 'Acostado con mancuernas', equipment: ['Mancuernas', 'Banco'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', unilateral: true, familyId: 'triceps_extension', techniqueId: 'lying_dumbbell' }),
      standardVariant({ id: 'patada_mancuerna', label: 'Patada con mancuerna', equipment: ['Mancuerna', 'Banco'], type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', unilateral: true, familyId: 'triceps_extension', techniqueId: 'kickback' }),
    ],
  },
  {
    id: 'B9wLn9cgyDHRBnpUZ5cr', name: 'Plancha', familyId: 'plank', type: 'Correctivos', discipline: 'correctivos', intent: 'control',
    redirects: { chiI25iuwFhNWF8Z2oyX: 'alta_bodyweight', '4WKbR97YKrpItGyrDZ0r': 'lateral_derecha', ukEDKOBF2eXkCjWPkjZR: 'lateral_izquierda' },
    removeVariantIds: ['copenhague'],
    normalize: (variant) => ({ ...variant, id: variant.id === 'original' ? 'antebrazos_bodyweight' : variant.id, label: variant.id === 'original' ? 'Con antebrazos' : variant.label, familyId: 'plank', exerciseType: 'Correctivos', trainingDiscipline: 'correctivos', movementIntent: 'control', techniqueId: variant.techniqueId || 'forearm', techniqueLabel: variant.techniqueLabel || 'Plancha con antebrazos', isUnilateral: false }),
    additions: [
      standardVariant({ id: 'alta_bodyweight', label: 'Con brazos extendidos', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'plank', techniqueId: 'high' }),
      standardVariant({ id: 'lateral_derecha', label: 'Lateral derecha', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'plank', techniqueId: 'side' }),
      standardVariant({ id: 'lateral_izquierda', label: 'Lateral izquierda', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'plank', techniqueId: 'side' }),
      standardVariant({ id: 'toques_hombro', label: 'Con toques de hombro', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'plank', techniqueId: 'shoulder_tap' }),
      standardVariant({ id: 'body_saw', label: 'Body saw', equipment: ['Deslizadores', 'Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'plank', techniqueId: 'body_saw' }),
      standardVariant({ id: 'carga_antebrazos', label: 'Con carga en antebrazos', equipment: ['Disco', 'Peso corporal'], type: 'Fuerza', discipline: 'fuerza', intent: 'full', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'plank', techniqueId: 'weighted_forearm' }),
    ],
  },
  {
    id: 'movement_press_de_hombro', familyId: 'shoulder_press', type: 'Fuerza', discipline: 'fuerza', intent: 'full',
    redirects: {
      AzrwoDh8tmSxJSNMklBR: 'mancuerna_o_kettlebell', doFMAxktHhnHrZlYQZiK: 'mancuernas', umo31SUvkQlBFZjUCzwD: 'barra', sr4Z7wfwkZxQmiQBykeB: 'mancuernas_sentado', w56w7BLlS23t3LgSXwy2: 'arnold_mancuernas', movement_press_de_hombro_barra: 'barra', movement_press_de_hombro_maquina_selectorizada: 'maquina_selectorizada',
      movement_landmine_press: { fallback: 'landmine_bilateral', variantMap: { bilateral: 'landmine_bilateral', explosivo: 'landmine_explosivo', unilateral: 'landmine_unilateral' } },
      movement_landmine_press_explosivo: 'landmine_explosivo', movement_landmine_press_unilateral: 'landmine_unilateral', FfoZNKsgf5OwA2IRoPqA: 'landmine_push_press', Ho4YvA6pvZItvuAXHPYc: 'push_press', lrcBpdahRJH8lZ96MaYP: 'landmine_half_kneeling',
    },
    normalize: (variant) => ({ ...variant, familyId: 'shoulder_press', exerciseType: ['maquina_selectorizada', 'smith', 'mancuernas_sentado'].includes(variant.id) ? 'Hipertrofia' : 'Fuerza', trainingDiscipline: ['maquina_selectorizada', 'smith', 'mancuernas_sentado'].includes(variant.id) ? 'hipertrofia' : 'fuerza', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('unilateral') || variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'arnold_mancuernas', label: 'Arnold press', equipment: ['Mancuernas'], type: 'Hipertrofia', discipline: 'hipertrofia', intent: 'full', unilateral: true, familyId: 'shoulder_press', techniqueId: 'arnold' }),
      standardVariant({ id: 'push_press', label: 'Push press', equipment: ['Barra'], type: 'Potencia', discipline: 'potencia', intent: 'power', familyId: 'shoulder_press', techniqueId: 'push_press', trackRM: true, trackProgression: true }),
      standardVariant({ id: 'landmine_bilateral', label: 'Landmine bilateral', equipment: ['Barra', 'Landmine'], type: 'Fuerza', discipline: 'fuerza', intent: 'full', familyId: 'shoulder_press', techniqueId: 'landmine' }),
      standardVariant({ id: 'landmine_unilateral', label: 'Landmine unilateral', equipment: ['Barra', 'Landmine'], type: 'Fuerza', discipline: 'fuerza', intent: 'full', unilateral: true, familyId: 'shoulder_press', techniqueId: 'landmine' }),
      standardVariant({ id: 'landmine_explosivo', label: 'Landmine explosivo', equipment: ['Barra', 'Landmine'], type: 'Potencia', discipline: 'potencia', intent: 'power', familyId: 'shoulder_press', techniqueId: 'landmine' }),
      standardVariant({ id: 'landmine_push_press', label: 'Landmine push press', equipment: ['Barra', 'Landmine'], type: 'Potencia', discipline: 'potencia', intent: 'power', unilateral: true, familyId: 'shoulder_press', techniqueId: 'landmine_push_press' }),
      standardVariant({ id: 'landmine_half_kneeling', label: 'Landmine half kneeling', equipment: ['Barra', 'Landmine'], type: 'Fuerza', discipline: 'fuerza', intent: 'full', unilateral: true, familyId: 'shoulder_press', techniqueId: 'landmine_half_kneeling' }),
    ],
  },
  {
    id: 'movement_press_de_pecho', familyId: 'chest_press', type: 'Fuerza', discipline: 'fuerza', intent: 'full',
    redirects: { LGpxd3fl3T7XKL82JWlZ: 'barra_en_banco_plano', LfIHY49dWESEOa3YRyla: 'mancuernas_en_banco_plano', movement_press_de_pecho_barra_en_banco_plano: 'barra_en_banco_plano', movement_press_de_pecho_maquina_selectorizada: 'maquina_selectorizada', xVUHkvMloZM5TMQQ5UrA: 'mancuernas_inclinado', ieEOe909t1oxOWVeJnG9: 'landmine_half_kneeling', gLBnGBJKlXvr5pcmwVfb: 'pliometrico_medicinal' },
    normalize: (variant) => ({ ...variant, familyId: 'chest_press', exerciseType: ['maquina_con_discos', 'maquina_selectorizada', 'poleas'].includes(variant.id) ? 'Hipertrofia' : 'Fuerza', trainingDiscipline: ['maquina_con_discos', 'maquina_selectorizada', 'poleas'].includes(variant.id) ? 'hipertrofia' : 'fuerza', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'landmine_half_kneeling', label: 'Landmine half kneeling', equipment: ['Barra', 'Landmine'], type: 'Fuerza', discipline: 'fuerza', intent: 'full', unilateral: true, familyId: 'chest_press', techniqueId: 'landmine_half_kneeling' }),
      standardVariant({ id: 'landmine_bilateral', label: 'Landmine bilateral', equipment: ['Barra', 'Landmine'], type: 'Fuerza', discipline: 'fuerza', intent: 'full', familyId: 'chest_press', techniqueId: 'landmine' }),
      standardVariant({ id: 'pliometrico_medicinal', label: 'Pase de pecho pliométrico', equipment: ['Balón medicinal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', familyId: 'chest_press', techniqueId: 'plyometric' }),
    ],
  },
  {
    id: 'movement_thruster', familyId: 'thruster', type: 'Potencia', discipline: 'potencia', intent: 'power',
    redirects: { P2AoDcmwFmZp5Tv96Ozl: 'landmine', VFti7uJHfLseaI3uDvoo: 'landmine' },
    normalize: (variant) => ({ ...variant, familyId: 'thruster', exerciseType: 'Potencia', trainingDiscipline: 'potencia', movementIntent: 'power', techniqueId: variant.techniqueId || 'thruster', techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('unilateral') || variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'wall_ball', label: 'Wall ball', equipment: ['Balón medicinal', 'Pared'], type: 'Balístico', discipline: 'balistico', intent: 'power', familyId: 'thruster', techniqueId: 'wall_ball' }),
      standardVariant({ id: 'landmine_unilateral', label: 'Landmine unilateral', equipment: ['Barra', 'Landmine'], type: 'Potencia', discipline: 'potencia', intent: 'power', unilateral: true, familyId: 'thruster', techniqueId: 'landmine' }),
    ],
  },
  {
    id: 'movement_hip_thrust', familyId: 'hip_thrust', type: 'Fuerza', discipline: 'fuerza', intent: 'full',
    redirects: { movement_hip_thrust_barra: 'barbell', m7jYDaRbNsQqbYTzKGEQ: 'unilateral_bodyweight', XImVpWOyvnDMGSvOmzcf: 'bridge_bodyweight' },
    normalize: (variant) => ({ ...variant, familyId: 'hip_thrust', exerciseType: ['maquina_smith', 'maquina_con_discos'].includes(variant.id) ? 'Hipertrofia' : 'Fuerza', trainingDiscipline: ['maquina_smith', 'maquina_con_discos'].includes(variant.id) ? 'hipertrofia' : 'fuerza', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'bridge_bodyweight', label: 'Puente de glúteo · Peso corporal', equipment: ['Peso corporal'], type: 'Calistenia', discipline: 'calistenia', intent: 'full', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'hip_thrust', techniqueId: 'bridge', muscleWeightOverrides: { lowerBack: 0.15, abs: 0.15, glutes: 0.5, hamstrings: 0.2 } }),
      standardVariant({ id: 'unilateral_bodyweight', label: 'Unilateral', equipment: ['Banco', 'Peso corporal'], type: 'Calistenia', discipline: 'calistenia', intent: 'full', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'hip_thrust', techniqueId: 'single_leg' }),
      standardVariant({ id: 'unilateral_mancuerna', label: 'Unilateral con mancuerna', equipment: ['Mancuerna', 'Banco'], type: 'Fuerza unilateral', discipline: 'fuerza', intent: 'full', unilateral: true, familyId: 'hip_thrust', techniqueId: 'single_leg' }),
    ],
  },
  {
    id: 'movement_dominada', familyId: 'pull_up', type: 'Calistenia', discipline: 'calistenia', intent: 'full',
    redirects: { C99K5FmVbkWt8zBmmH9F: 'agarre_cerrado' },
    normalize: (variant) => ({ ...variant, familyId: 'pull_up', exerciseType: variant.id === 'lastrada' ? 'Fuerza' : 'Calistenia', trainingDiscipline: variant.id === 'lastrada' ? 'fuerza' : 'calistenia', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: false }),
    additions: [
      standardVariant({ id: 'agarre_cerrado', label: 'Agarre cerrado', equipment: ['Barra fija'], type: 'Calistenia', discipline: 'calistenia', intent: 'full', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'pull_up', techniqueId: 'close_grip' }),
    ],
  },
  {
    id: 'ZWCB4bjmA8jefKtoItbf', familyId: 'push_up', type: 'Calistenia', discipline: 'calistenia', intent: 'full',
    redirects: { zBgb5RMZyu1zDubyLRdJ: 'escapular' },
    normalize: (variant) => ({ ...variant, familyId: 'push_up', exerciseType: variant.id === 'lastrada' ? 'Fuerza' : 'Calistenia', trainingDiscipline: variant.id === 'lastrada' ? 'fuerza' : 'calistenia', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: false }),
    additions: [
      standardVariant({ id: 'escapular', label: 'Escapular', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'push_up', techniqueId: 'scapular' }),
      standardVariant({ id: 'diamante', label: 'Diamante', equipment: ['Peso corporal'], type: 'Calistenia', discipline: 'calistenia', intent: 'full', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'push_up', techniqueId: 'diamond' }),
      standardVariant({ id: 'explosiva', label: 'Explosiva', equipment: ['Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'push_up', techniqueId: 'explosive' }),
    ],
  },
  {
    id: 'movement_estocada', familyId: 'lunge', type: 'Fuerza unilateral', discipline: 'fuerza', intent: 'full',
    redirects: { T0BvnGh6WIBoSoGvO5fn: 'torsion_toracica', xIoawzSqLbPrmcY0sriM: 'landmine_reverse_knee_drive_press' },
    normalize: (variant) => ({ ...variant, familyId: 'lunge', exerciseType: variant.id === 'maquina_smith' ? 'Hipertrofia' : 'Fuerza unilateral', trainingDiscipline: variant.id === 'maquina_smith' ? 'hipertrofia' : 'fuerza', movementIntent: 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: true }),
    additions: [
      standardVariant({ id: 'torsion_toracica', label: 'Con torsión torácica', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'lunge', techniqueId: 'thoracic_rotation' }),
      standardVariant({ id: 'landmine_reverse_knee_drive_press', label: 'Landmine reversa + knee drive + press', equipment: ['Barra', 'Landmine'], type: 'Potencia', discipline: 'potencia', intent: 'power', unilateral: true, familyId: 'lunge', techniqueId: 'reverse_knee_drive_press' }),
    ],
  },
  {
    id: 'movement_step_up', familyId: 'step_up', type: 'Fuerza unilateral', discipline: 'fuerza', intent: 'full',
    redirects: { qTZC4A37vdTh6QEnfaBj: 'reactivo_alternado', bNej84PRh7oLK3YQMmeH: 'hop' },
    normalize: (variant) => ({ ...variant, familyId: 'step_up', exerciseType: variant.id.includes('explosivo') ? 'Pliometría' : variant.id === 'maquina_smith' ? 'Hipertrofia' : 'Fuerza unilateral', trainingDiscipline: variant.id.includes('explosivo') ? 'pliometria' : variant.id === 'maquina_smith' ? 'hipertrofia' : 'fuerza', movementIntent: variant.id.includes('explosivo') ? 'power' : 'full', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: true }),
    additions: [
      standardVariant({ id: 'reactivo_alternado', label: 'Salto reactivo alternado', equipment: ['Step', 'Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'step_up', techniqueId: 'reactive_alternating' }),
      standardVariant({ id: 'hop', label: 'Hop al step', equipment: ['Step', 'Peso corporal'], type: 'Pliometría', discipline: 'pliometria', intent: 'power', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'step_up', techniqueId: 'hop' }),
    ],
  },
  {
    id: 'movement_extension_de_cuadriceps', familyId: 'knee_extension', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', redirects: {},
    normalize: (variant) => ({ ...variant, familyId: 'knee_extension', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('unilateral') || variant.isUnilateral === true }),
  },
  {
    id: 'movement_curl_femoral', familyId: 'knee_flexion', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', redirects: {},
    normalize: (variant) => ({ ...variant, familyId: 'knee_flexion', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('pie') || variant.isUnilateral === true }),
  },
  {
    id: 'movement_elevacion_de_pantorrillas', familyId: 'calf_raise', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', redirects: {},
    normalize: (variant) => ({ ...variant, familyId: 'calf_raise', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('unilateral') || variant.isUnilateral === true }),
  },
  {
    id: 'movement_elevacion_lateral', familyId: 'lateral_raise', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', redirects: {},
    normalize: (variant) => ({ ...variant, familyId: 'lateral_raise', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('unilateral') || variant.isUnilateral === true }),
  },
  {
    id: 'UpY3AePcziG5SYYeGGfK', familyId: 'front_raise', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', redirects: {},
    normalize: (variant) => ({ ...variant, familyId: 'front_raise', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: variant.id.includes('dumbbell') || variant.id.includes('mancuerna') || variant.isUnilateral === true }),
  },
  {
    id: 'movement_pullover', familyId: 'pullover', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation', redirects: {},
    normalize: (variant) => ({ ...variant, familyId: 'pullover', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || variant.id, techniqueLabel: variant.techniqueLabel || variant.label, isUnilateral: false }),
  },
  {
    id: 'movement_aductor_maquina_copenhagen', name: 'Aducción de cadera', familyId: 'hip_adduction', type: 'Hipertrofia aislada', discipline: 'hipertrofia', intent: 'isolation',
    redirects: { P4dj56b73Xf2H6uLhkbM: 'copenhagen' },
    normalize: (variant) => ({ ...variant, label: variant.id === 'original' ? 'Máquina de aductores' : variant.label, familyId: 'hip_adduction', exerciseType: 'Hipertrofia aislada', trainingDiscipline: 'hipertrofia', movementIntent: 'isolation', techniqueId: variant.techniqueId || 'machine', techniqueLabel: variant.techniqueLabel || 'Máquina de aductores', isUnilateral: variant.isUnilateral === true }),
    additions: [
      standardVariant({ id: 'copenhagen', label: 'Copenhague', equipment: ['Banco', 'Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', unilateral: true, group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'hip_adduction', techniqueId: 'copenhagen' }),
    ],
  },
  {
    id: 'movement_face_pull', name: 'Control escapular', familyId: 'scapular_control', type: 'Correctivos', discipline: 'correctivos', intent: 'control',
    redirects: { OCHmwsxRrQFIABHllscQ: 'w_bodyweight', KpcDFoWdKYUQBunsgNbR: 'y_bodyweight', '7XTZiU027bNEt3wxEGeg': 'reverse_fly_trx' },
    normalize: (variant) => ({ ...variant, familyId: 'scapular_control', exerciseType: 'Correctivos', trainingDiscipline: 'correctivos', movementIntent: 'control', techniqueId: 'face_pull', techniqueLabel: 'Face pull', isUnilateral: false }),
    additions: [
      standardVariant({ id: 'y_bodyweight', label: 'Elevación Y', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'scapular_control', techniqueId: 'y_raise' }),
      standardVariant({ id: 'w_bodyweight', label: 'Elevación W', equipment: ['Peso corporal'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'scapular_control', techniqueId: 'w_raise' }),
      standardVariant({ id: 'reverse_fly_trx', label: 'Reverse fly en TRX', equipment: ['TRX'], type: 'Correctivos', discipline: 'correctivos', intent: 'control', group: 'Peso corporal', resistanceType: 'bodyweight', familyId: 'scapular_control', techniqueId: 'reverse_fly' }),
    ],
  },
  {
    id: 'Hh6KExWwZiAxNxWqOScG', familyId: 'anti_extension_core', type: 'Core / Estabilidad', discipline: 'core', intent: 'control', redirects: {},
    normalize: (variant) => ({ ...variant, familyId: 'anti_extension_core', exerciseType: 'Core / Estabilidad', trainingDiscipline: 'core', movementIntent: 'control', techniqueId: variant.techniqueId || 'ab_wheel', techniqueLabel: variant.techniqueLabel || 'Rueda abdominal', isUnilateral: false }),
  },
  {
    id: 'h3iID1sViv8r10C9Ogco', name: 'Lanzamiento de balón medicinal', familyId: 'medicine_ball_throw', type: 'Potencia', discipline: 'potencia', intent: 'power',
    muscleWeights: {
      obliques: 0.1875, frontDelts: 0.09, lowerTraps: 0.015, glutes: 0.215,
      midBack: 0.01, lats: 0.12, psoas: 0.00625, midDelts: 0.01, rombs: 0.02,
      midGlutes: 0.045, lowerBack: 0.09375, lowerAbs: 0.01875, hamstrings: 0.09,
      trapsUpper: 0.01, abs: 0.01875, chest: 0.05,
    },
    redirects: { rAVjoB7lyoEz5hMe5eFu: 'lateral_pared' },
    normalize: (variant) => {
      const overhead = variant.id === 'original' || variant.id === 'sobre_cabeza_piso';
      return {
        ...variant,
        id: overhead ? 'sobre_cabeza_piso' : variant.id,
        label: overhead ? 'Sobre cabeza a piso' : variant.label,
        familyId: 'medicine_ball_throw',
        exerciseType: 'Potencia',
        trainingDiscipline: 'potencia',
        movementIntent: 'power',
        techniqueId: overhead ? 'overhead_slam' : (variant.techniqueId || variant.id),
        techniqueLabel: overhead ? 'Sobre cabeza a piso' : (variant.techniqueLabel || variant.label),
        isUnilateral: overhead ? false : variant.isUnilateral === true,
        ...(overhead ? {
          muscleWeightOverrides: {
            obliques: 0.075, frontDelts: 0.08, lowerTraps: 0.03, glutes: 0.18,
            midBack: 0.02, lats: 0.09, psoas: 0.0125, midDelts: 0.02, rombs: 0.04,
            midGlutes: 0.09, lowerBack: 0.0875, lowerAbs: 0.0375, hamstrings: 0.18,
            trapsUpper: 0.02, abs: 0.0375,
          },
        } : {}),
      };
    },
    additions: [
      standardVariant({
        id: 'lateral_pared', label: 'Lateral a pared', equipment: ['Balón medicinal', 'Pared'],
        type: 'Potencia', discipline: 'potencia', intent: 'power', unilateral: true,
        familyId: 'medicine_ball_throw', techniqueId: 'rotational_lateral_wall',
        muscleWeightOverrides: {
          lowerBack: 0.1, chest: 0.1, lats: 0.15, frontDelts: 0.1,
          obliques: 0.3, glutes: 0.25,
        },
      }),
    ],
  },
];

function rewriteRaw(value, redirects, catalog) {
  if (!value || typeof value !== 'object') return value;
  if (value.arrayValue) return { ...value, arrayValue: { ...value.arrayValue, values: (value.arrayValue.values ?? []).map((item) => rewriteRaw(item, redirects, catalog)) } };
  if (!value.mapValue) return value;
  const fields = Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, rewriteRaw(item, redirects, catalog)]));
  const sourceId = fields.exerciseId?.stringValue ?? fields.movementId?.stringValue;
  const target = redirects.get(sourceId);
  if (target) {
    const currentVariantId = fields.variantId?.stringValue;
    const variantId = target.variantMap?.[currentVariantId] ?? target.variantId;
    fields.exerciseId = { stringValue: target.exerciseId };
    fields.movementId = { stringValue: target.exerciseId };
    fields.variantId = { stringValue: variantId };
    fields.familyId = { stringValue: target.familyId };
    fields.techniqueId = { stringValue: target.techniqueId };
    fields.exerciseType = { stringValue: target.exerciseType };
  }
  const exerciseId = fields.exerciseId?.stringValue ?? fields.movementId?.stringValue;
  const variantId = fields.variantId?.stringValue;
  const movement = catalog.get(exerciseId);
  const variant = movement?.variants.get(variantId);
  if (movement && variant) {
    fields.exerciseId = { stringValue: exerciseId };
    fields.movementId = { stringValue: exerciseId };
    fields.variantId = { stringValue: variantId };
    fields.variantLabel = { stringValue: variant.label };
    fields.familyId = { stringValue: variant.familyId };
    fields.techniqueId = { stringValue: variant.techniqueId };
    fields.techniqueLabel = { stringValue: variant.techniqueLabel };
    fields.exerciseType = { stringValue: variant.exerciseType };
    fields.trainingDiscipline = { stringValue: variant.trainingDiscipline };
    fields.movementIntent = { stringValue: variant.movementIntent };
    if (variant.muscleWeightOverrides && Object.keys(variant.muscleWeightOverrides).length) {
      fields.muscleWeightOverrides = encode(variant.muscleWeightOverrides);
    }
    if (fields.name) fields.name = { stringValue: `${movement.name} - ${variant.label}` };
    if (fields.displayName) fields.displayName = { stringValue: `${movement.name} - ${variant.label}` };
  }
  return { ...value, mapValue: { ...value.mapValue, fields } };
}

const access = await token();
const exercises = await list(access, 'exercises');
const redirects = new Map();
const parentUpdates = [];
for (const config of configs) {
  const parent = exercises.find((exercise) => exercise.id === config.id);
  if (!parent) throw new Error(`Missing canonical exercise ${config.id}`);
  let variants = (Array.isArray(parent.data.variants) ? parent.data.variants : []).map(config.normalize);
  if (config.removeVariantIds) {
    variants = variants.filter((variant) => !config.removeVariantIds.includes(variant.id));
  }
  for (const addition of config.additions ?? []) addOrReplace(variants, addition);
  parentUpdates.push({ id: parent.id, fields: { ...(config.name ? { name: config.name } : {}), ...(config.muscleWeights ? { muscleWeights: config.muscleWeights } : {}), familyId: config.familyId, exerciseType: config.type, trainingDiscipline: config.discipline, movementIntent: config.intent, variants } });
  for (const [legacyId, redirect] of Object.entries(config.redirects)) {
    const variantId = typeof redirect === 'string' ? redirect : redirect.fallback;
    const variant = variants.find((item) => item.id === variantId);
    redirects.set(legacyId, { exerciseId: parent.id, variantId, variantMap: typeof redirect === 'string' ? undefined : redirect.variantMap, familyId: config.familyId, techniqueId: variant?.techniqueId ?? variantId, exerciseType: variant?.exerciseType ?? config.type });
  }
}
for (const update of parentUpdates) await patchFields(access, 'exercises', update.id, update.fields);
for (const [legacyId, target] of redirects) await patchFields(access, 'exercises', legacyId, { mergedInto: target.exerciseId, canonicalExerciseId: target.exerciseId, familyId: target.familyId });

// Older catalog entries remain valid movements, but lacked variant-level
// identity. Give them explicit, reviewable metadata rather than relying on
// implicit fallbacks from the parent exercise.
const configuredParents = new Set(configs.map((config) => config.id));
let normalizedCatalogEntries = 0;
for (const exercise of exercises) {
  if (configuredParents.has(exercise.id) || redirects.has(exercise.id) || exercise.data.mergedInto) continue;
  const type = String(exercise.data.exerciseType || 'Otros');
  const familyId = String(exercise.data.familyId || familySlug(exercise.data.name));
  const existingDiscipline = String(exercise.data.trainingDiscipline || '');
  const isCoreType = normalized(type).includes('core') || normalized(type).includes('estab');
  const discipline = isCoreType && existingDiscipline === 'correctivos'
      ? 'core'
      : String(existingDiscipline || disciplineFor(type));
  const intent = String(exercise.data.movementIntent || intentFor(type));
  const variants = (Array.isArray(exercise.data.variants) ? exercise.data.variants : []).map((variant) => ({
    ...variant,
    familyId: variant.familyId || familyId,
    exerciseType: variant.exerciseType || type,
    trainingDiscipline: variant.trainingDiscipline || discipline,
    movementIntent: variant.movementIntent || intent,
    techniqueId: variant.techniqueId || variant.id || 'original',
    techniqueLabel: variant.techniqueLabel || variant.label || 'Original',
  }));
  await patchFields(access, 'exercises', exercise.id, { familyId, trainingDiscipline: discipline, movementIntent: intent, variants });
  normalizedCatalogEntries += 1;
}

let rewrittenDocuments = 0;
const refreshedExercises = await list(access, 'exercises');
const catalog = new Map(
  refreshedExercises
    .filter((exercise) => !exercise.data.mergedInto)
    .map((exercise) => [
      exercise.id,
      {
        name: String(exercise.data.name || ''),
        variants: new Map((exercise.data.variants ?? []).map((variant) => [variant.id, variant])),
      },
    ]),
);
for (const collection of ['blocks', 'planned_workouts', 'workouts_logged', 'routines']) {
  for (const document of await list(access, collection)) {
    const raw = rewriteRaw({ mapValue: { fields: document.raw } }, redirects, catalog).mapValue.fields;
    if (JSON.stringify(raw) !== JSON.stringify(document.raw)) {
      const response = await fetch(`${base}/${collection}/${document.id}`, { method: 'PATCH', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: raw }) });
      if (!response.ok) throw new Error(`${collection}/${document.id}: ${response.status} ${await response.text()}`);
      rewrittenDocuments += 1;
    }
  }
}
console.log(JSON.stringify({ parents: parentUpdates.map((item) => ({ id: item.id, variants: item.fields.variants.length })), redirectedLegacyExercises: redirects.size, normalizedCatalogEntries, rewrittenDocuments }, null, 2));
