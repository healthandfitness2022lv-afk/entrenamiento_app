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

// ── Semana 6 (26-10 → 01-11), días 2 a 4 ───────────────────────────────────
// El D1 (lun 26-10) ya está cargado y registrado. Cargas desde lo realizado,
// mantenidas o levemente progresadas; donde hubo RPE 9-10 se baja el objetivo.
const days = [
  {
    day: 2, date: '2026-10-27T03:00:00Z',
    blocks: [
      {
        id: 'belen_trigo_d2_musculacion_2026_10_27', source: 'belen_trigo_d2_musculacion_2026_10_14', title: 'MUSCULACION 2',
        description: 'Mar 27-10. Semana 6, día 2. Ayer hizo sentadilla e hip thrust a RPE 7, así que la bisagra vuelve a 3 series. Descansos: 90 s en landmine y rumano, 60 s en el resto.',
        plan: [
          { name: 'Press De Hombro - Landmine half kneeling', series: 3, reps: 10, weight: 27.5, notes: '27,5 kg por lado: el 19-10 hizo 3×10 a RPE 8-9-9. Consolidar a RPE 8 antes de subir a 30 kg. Glúteo de la rodilla apoyada apretado, sin arquear la zona lumbar.' },
          { name: 'Elevación frontal - Mancuernas', series: 3, reps: 15, weight: 10, notes: '10 kg: tres sesiones seguidas de 3×12 a RPE 8. Sube a 15 reps; si las 3 quedan en RPE ≤8, la próxima va con 12 kg. Sin balanceo de cadera.' },
          { name: 'Leñador', series: 3, reps: 12, weight: 15, notes: '15 kg por lado: 3×10 a RPE 8 estable el 14-10. Sube a 12 reps; el giro sale de la cadera, brazos casi extendidos.' },
          { name: 'Peso Muerto - Rumano con barra', series: 3, reps: 8, weight: 57.5, notes: '57,5 kg: el 06-10 hizo 60 × 8 a RPE 8-9 y el 14-10 solo 2 series con 55 kg. Vuelve a 3 series; espalda neutra, barra pegada a las piernas, bajar hasta media tibia.' },
          { name: 'Curl Femoral - Máquina sentado', series: 3, reps: 12, weight: 50, notes: '50 kg: el 14-10 hizo 2×10 a RPE 7-8. Vuelve a 3×12; bajada controlada de 2 s.' },
        ],
      },
      {
        id: 'belen_trigo_d2_metcon_2026_10_27', source: 'belen_trigo_d2_metcon_2026_10_06', title: 'METCON 1', circuit: true,
        description: 'Mar 27-10. Semana 6, día 2. 3 rondas, mismo circuito del 06-10 (la semana pasada no se hizo). Descanso 60-90 s entre rondas.',
        notes: {
          'Ketlebell swing americano': '16 kg × 12: se mantiene. El impulso sale de la cadera, no de los brazos; espalda neutra arriba.',
          'Step Up - Peso corporal': '6 por pierna: apoyar todo el pie en el cajón y subir sin impulsarse con la pierna de abajo.',
          'Tuck Up': '12 reps a ritmo controlado; si la zona lumbar se despega del piso, acortar el rango.',
          'Dominada - Australiana': '6 reps: RPE 8-9 la última vez. Cuerpo en línea, pecho a la barra; si cuesta, pies más cerca.',
        },
      },
    ],
  },
  {
    day: 3, date: '2026-10-29T03:00:00Z',
    blocks: [
      {
        id: 'belen_trigo_d3_musculacion_2026_10_29', source: 'belen_trigo_d3_musculacion_2026_10_16', title: 'MUSCULACION 3',
        description: 'Jue 29-10. Semana 6, día 3, desde lo realizado el 16-10. Se mantiene carga donde hubo RPE 9 sostenido (press inclinado, elevación lateral, face pull) y se progresa en remo y jalón. Descansos: 90 s en press, remo y jalón; 45-60 s en accesorios.',
        plan: [
          { name: 'Press Banca inclinado DB', series: 3, reps: 8, weight: 12.5, notes: '12,5 kg por mano: el 16-10 hizo 3×8 a RPE 9-8-9. Misma carga hasta que salga a RPE 8; escápulas atrás y abajo.' },
          { name: 'Remo - Barra', series: 4, reps: 10, weight: 30, notes: '30 kg: el 16-10 hizo 27,5 kg × 12 a RPE 8 en las 4 series. Sube 2,5 kg y baja a 10 reps; espalda neutra, tirar hacia el ombligo.' },
          { name: 'Jalon Al Pecho - Polea baja, agarre cerrado', series: 3, reps: 12, weight: 35, notes: '35 kg: el 16-10 hizo 3×10 a RPE 8. Vuelve a 12 reps; pausa de 1 s abajo y sin balancear el tronco.' },
          { name: 'Elevacion Lateral - Mancuernas', series: 3, reps: 12, weight: 5, notes: '5 kg: tres sesiones con RPE 9 sostenido a 13 reps. Baja a 12, bajada de 2 s y sin encoger los hombros.' },
          { name: 'Face Pull - Cuerda en polea', series: 3, reps: 10, weight: 32.5, notes: '32,5 kg: el 16-10 hizo 3×12 a RPE 9. Misma carga con 10 reps; codos altos, separar la cuerda al final.' },
          { name: 'Press Pallof - Banda elástica', series: 3, reps: 15, weight: 12.5, notes: 'Misma banda: 3×15 a RPE 8 el 16-10. Agregar pausa de 2 s con los brazos extendidos, sin girar la cadera.' },
          { name: 'Trote - Caminadora', series: 1, reps: 600, weight: 1, notes: '10 minutos: el 16-10 terminó en RPE 9. Bajar la velocidad para quedar en RPE 7, a ritmo conversacional.' },
        ],
      },
    ],
  },
  {
    day: 4, date: '2026-11-01T03:00:00Z',
    blocks: [
      {
        id: 'belen_trigo_d4_musculacion_2026_11_01', source: 'belen_trigo_d4_musculacion_2026_10_18', title: 'MUSCULACION 4',
        description: 'Dom 01-11. Semana 6, día 4, desde lo realizado el 18-10. La prensa, la búlgara y la extensión de cuádriceps llegaron a RPE 9-10: se mantiene o se baja el objetivo. Descansos: 2 min en prensa, 90 s en búlgara, 60 s en accesorios.',
        plan: [
          { name: 'Prensa De Piernas - Máquina inclinada', series: 4, reps: 10, weight: 70, notes: '70 kg: el 18-10 hizo 4×10 a RPE 9-9-9-10. Se mantiene; si la 3.ª serie llega a RPE 9, la 4.ª se hace a 8 reps. No despegar la cadera del respaldo abajo.' },
          { name: 'Sentadilla Bulgara - Mancuernas', series: 3, reps: 10, weight: 7.5, notes: '7,5 kg por mano: 3×12 fue RPE 9-9-10 el 18-10. Vuelve a 10 reps por pierna; rodilla en la línea del pie.' },
          { name: 'Extension De Cuadriceps - Bilateral en máquina', series: 3, reps: 12, weight: 50, notes: '50 kg: el 18-10 la serie con 55 kg fue RPE 9. Las 3 series con 50 kg; 1 s arriba apretando.' },
          { name: 'Curl Femoral - Máquina tumbado', series: 3, reps: 10, weight: 35, notes: '35 kg: el 18-10 hizo 30 kg × 12 a RPE 8 estable. Sube la carga y bajan las reps; cadera pegada a la camilla.' },
          { name: 'Rueda abdominal', series: 3, reps: 10, weight: 1, notes: 'El 18-10 hizo 3×8 a RPE 7-8-7 y el 19-10 no la hizo. Progresión a 10 reps; zona lumbar neutra, si cuesta, rango más corto.' },
          { name: 'Bicicleta', series: 1, reps: 600, weight: 1, notes: '10 minutos suaves a RPE 6-7. El 18-10 no la hizo: hacerla al final, después del Tabata de planchas.' },
        ],
      },
      {
        id: 'belen_trigo_d4_tabata_planchas_2026_11_01', source: 'belen_trigo_d4_tabata_planchas_2026_10_18', title: 'TABATA PLANCHAS', circuit: true,
        description: 'Dom 01-11. 4 rondas de 20 s / 10 s, igual que el 18-10.',
        notes: {},
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
    const planned = { athleteId, athleteName: 'Belén Trigo', blockId: item.id, blockTitle: item.title, date: day.date, day: day.day, week: 6, order, status: 'planned', createdAt: now, blockUpdatedAt: now };

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
