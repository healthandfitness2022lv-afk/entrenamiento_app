import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';

const projectId = 'entrenamientoapplv';
const athleteId = 'sG1LXxO2GlcBFBh8u0MjknKmcfP2';
const credentials = JSON.parse(readFileSync('secrets/serviceAccountKey.json', 'utf8'));
const dryRun = process.argv.includes('--dry-run');
const now = new Date().toISOString();

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
function value(data) {
  if (data === null) return { nullValue: null };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data) ? { integerValue: String(data) } : { doubleValue: data };
  if (typeof data === 'string') return { stringValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)])) } };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([key, item]) => [key, value(item)]));
const name = (collection, id) => `projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const getDoc = async (token, collection, id) => {
  const response = await fetch(`${base}/${collection}/${id}`, { headers: { Authorization: `Bearer ${token}` } });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${collection}/${id} ${response.status}: ${await response.text()}`);
  return Object.fromEntries(Object.entries((await response.json()).fields ?? {}).map(([key, item]) => [key, decode(item)]));
};

// ── Semana 7, día 2 (mar 03-11) ─────────────────────────────────────────────
// El D2 del 27-10 no se hizo: se repiten sus cargas, salidas de lo realizado
// el 14-10 y el 06-10. El D1 lo hizo ayer (02-11), igual que antes del 27-10.
const days = [
  {
    day: 2, date: '2026-11-03T03:00:00Z',
    blocks: [
      {
        id: 'belen_trigo_d2_musculacion_2026_11_03', source: 'belen_trigo_d2_musculacion_2026_10_14', title: 'MUSCULACION 2',
        description: 'Mar 03-11. Semana 7, día 2 (el del 27-10 no se hizo). Ayer hizo el D1; la bisagra vuelve a 3 series. Descansos: 90 s en landmine y rumano, 60 s en el resto.',
        plan: [
          { name: 'Press De Hombro - Landmine half kneeling', series: 3, reps: 10, weight: 27.5, notes: '27,5 kg por lado: el 19-10 hizo 3×10 a RPE 8-9-9. Consolidar a RPE 8 antes de subir a 30 kg. Glúteo de la rodilla apoyada apretado, sin arquear la zona lumbar.' },
          { name: 'Elevación frontal - Mancuernas', series: 3, reps: 15, weight: 10, notes: '10 kg: tres sesiones seguidas de 3×12 a RPE 8. Sube a 15 reps; si las 3 quedan en RPE ≤8, la próxima va con 12 kg. Sin balanceo de cadera.' },
          { name: 'Leñador', series: 3, reps: 12, weight: 15, notes: '15 kg por lado: 3×10 a RPE 8 estable el 14-10. Sube a 12 reps; el giro sale de la cadera, brazos casi extendidos.' },
          { name: 'Peso Muerto - Rumano con barra', series: 3, reps: 8, weight: 57.5, notes: '57,5 kg: el 06-10 hizo 60 × 8 a RPE 8-9 y el 14-10 solo 2 series con 55 kg. Vuelve a 3 series; espalda neutra, barra pegada a las piernas, bajar hasta media tibia.' },
          { name: 'Curl Femoral - Máquina sentado', series: 3, reps: 12, weight: 50, notes: '50 kg: el 14-10 hizo 2×10 a RPE 7-8. Vuelve a 3×12; bajada controlada de 2 s.' },
        ],
      },
      {
        id: 'belen_trigo_d2_metcon_2026_11_03', source: 'belen_trigo_d2_metcon_2026_10_06', title: 'METCON 1', circuit: true,
        description: 'Mar 03-11. Semana 7, día 2. 3 rondas, mismo circuito del 06-10 (no se hace desde entonces). Descanso 60-90 s entre rondas.',
        notes: {
          'Ketlebell swing americano': '16 kg × 12: se mantiene. El impulso sale de la cadera, no de los brazos; espalda neutra arriba.',
          'Step Up - Peso corporal': '6 por pierna: apoyar todo el pie en el cajón y subir sin impulsarse con la pierna de abajo.',
          'Tuck Up': '12 reps a ritmo controlado; si la zona lumbar se despega del piso, acortar el rango.',
          'Dominada - Australiana': '6 reps: RPE 8-9 la última vez. Cuerpo en línea, pecho a la barra; si cuesta, pies más cerca.',
        },
      },
    ],
  },
];

const token = await accessToken();

const plannedQuery = await fetch(`${base}:runQuery`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'planned_workouts' }], where: { fieldFilter: { field: { fieldPath: 'athleteId' }, op: 'EQUAL', value: { stringValue: athleteId } } } } }),
});
const existingPlanned = (await plannedQuery.json()).filter((r) => r.document).map((r) => decode({ mapValue: { fields: r.document.fields } }));

const writes = [];
const summary = [];
for (const day of days) {
  // Salvaguarda: no duplicar un día que ya tenga algo planificado.
  const sameDay = existingPlanned.filter((p) => String(p.date ?? '').startsWith(day.date.slice(0, 10)));
  if (sameDay.length) throw new Error(`Ya hay planned_workouts el ${day.date.slice(0, 10)}: ${sameDay.map((p) => p.blockTitle).join(', ')}`);

  for (const [order, item] of day.blocks.entries()) {
    if (await getDoc(token, 'blocks', item.id)) throw new Error(`Ya existe blocks/${item.id}`);
    const source = await getDoc(token, 'blocks', item.source);
    if (!source) throw new Error(`No existe blocks/${item.source}`);

    let exercises;
    if (item.circuit) {
      // Circuito y Tabata: se copian tal cual, solo cambian las notas.
      exercises = source.exercises.map((exercise) => ({ ...exercise, notes: item.notes[exercise.name] ?? exercise.notes }));
    } else {
      exercises = item.plan.map((planned) => {
        const found = source.exercises.find((exercise) => exercise.name === planned.name);
        if (!found) throw new Error(`No encontré ${planned.name} en ${item.source}`);
        const { instanceId, durationMinutes, ...rest } = found;
        const isTime = found.valueType === 'time';
        return {
          ...rest, series: planned.series, reps: planned.reps, value: planned.reps, weight: planned.weight, notes: planned.notes,
          ...(isTime ? { durationMinutes: planned.reps / 60 } : {}),
        };
      });
    }

    const { createdAt, updatedAt, libraryOrder, ...sourceRest } = source;
    const block = { ...sourceRest, athleteId, folder: 'BELEN', isLibraryTemplate: true, title: item.title, description: item.description, exercises, createdAt: now, updatedAt: now, libraryOrder: Date.now() + writes.length };
    const plannedId = item.id.replace(/_(musculacion|metcon|tabata_planchas)_/, (_, kind) => (kind === 'musculacion' ? '_' : `_${kind === 'metcon' ? 'metcon' : 'tabata'}_`));
    const planned = { athleteId, athleteName: 'Belén Trigo', blockId: item.id, blockTitle: item.title, date: day.date, day: day.day, week: 7, order, status: 'planned', createdAt: now, blockUpdatedAt: now };

    writes.push({ update: { name: name('blocks', item.id), fields: fields(block) }, currentDocument: { exists: false } });
    writes.push({ update: { name: name('planned_workouts', plannedId), fields: fields(planned) }, currentDocument: { exists: false } });
    summary.push({ date: day.date.slice(0, 10), day: day.day, order, block: item.id, planned: plannedId, title: item.title, exercises: exercises.map((e) => `${e.name}: ${e.series ?? '-'}×${e.reps ?? e.value ?? '-'} @ ${e.weight ?? '-'}`) });
  }
}

console.log(JSON.stringify({ dryRun, summary }, null, 2));
if (dryRun) process.exit(0);

const response = await fetch(`${base}:commit`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }) });
if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
console.log(`OK: ${writes.length} documentos`);
