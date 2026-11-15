# Cálculo del Perfil de Entrenamiento

> Última revisión: 2026-09-19. Este documento describe el sistema **vigente**
> en el código. La versión anterior de este archivo describía un modelo
> mucho más simple (fórmulas lineales tipo `score = ratio * peso`) que ya no
> existe — se mantuvo desactualizada mientras el código evolucionó. Si en el
> futuro cambia `training_identity_service.dart`, actualizar este documento
> en el mismo cambio, no después.

Este documento explica cómo se calcula el módulo "Perfil de entrenamiento",
implementado en:

- `lib/services/training_identity_service.dart` — el motor de cálculo
- `lib/screens/unified_weekly_review_screen.dart` — arma los datos de entrada
  (semana planificada y semana logueada) y llama al motor
- `lib/screens/planning_screen.dart` — punto de entrada: el botón con ícono
  de analytics ("Carga y revisión semanal") en la pantalla de Planificación
  abre `UnifiedWeeklyReviewScreen`, que es donde vive este cálculo

## Dónde se usa

`UnifiedWeeklyReviewScreen` calcula **tres** resultados de perfil, todos con
el mismo motor (`TrainingIdentityService.analyze`) pero distinta fuente:

- `trainingIdentity`: todos los ejercicios de la semana (planificados +
  logueados juntos).
- `plannedTrainingIdentity`: solo `source == 'planned'` — lo que se
  **programó**.
- `loggedTrainingIdentity`: solo `source == 'logged'` — lo que **realmente
  se ejecutó** (`workouts_logged`).

Esto permite comparar intención vs. ejecución real en la misma semana.

## Perfiles posibles

Definidos en el enum `TrainingProfile`:

- `powerlifting` → label "Fuerza máxima"
- `athlete` → label "Deportista"
- `hypertrophy` → label "Hipertrofia"
- `conditioning` → label "Acondicionamiento"
- `bodyweight` → label "Control y coordinación"
- `hybrid` → label "Híbrido" (existe en el enum y en varias tablas de
  modificadores, pero **no** participa del cálculo activo — ver
  `_activeProfiles` más abajo. Es remanente de una versión anterior del
  modelo; no se eliminó porque el enum es público y tocar su forma puede
  afectar serialización/UI en otros lugares no auditados en este cambio)

El cálculo real solo puntúa estos 5, vía `_activeProfiles`:

```dart
static const List<TrainingProfile> _activeProfiles = [
  TrainingProfile.powerlifting,
  TrainingProfile.athlete,
  TrainingProfile.hypertrophy,
  TrainingProfile.conditioning,
  TrainingProfile.bodyweight,
];
```

## Flujo general

1. `UnifiedWeeklyReviewScreen._calculateMuscularLoad()` construye un
   catálogo de ejercicios (`exerciseMap`) leyendo la colección `exercises`,
   indexado **por nombre normalizado Y por `exerciseId::variantId`** (líneas
   ~224-286). Cada variante hereda del ejercicio base los campos que no
   declara explícitamente (`resistanceType`, `equipment`,
   `trainingDiscipline`, `movementIntent`), salvo `isUnilateral` — ver
   advertencia en la sección "Inconsistencias conocidas".
2. Recorre `planned_workouts` de la semana (vía `_plannedDocsInRange`) y
   `workouts_logged` del atleta en el mismo rango.
3. Para cada ejercicio de cada bloque, resuelve sus atributos (ver
   "Atributos por ejercicio" abajo) y llama a `_applyIdentityExerciseLoad`,
   que arma un `TrainingIdentityExerciseContribution` y acumula las cargas
   agregadas (`totalLoad`, `intentFamilyLoad`, `repRangeLoad`, etc.).
4. Esas cargas agregadas se empaquetan en `TrainingIdentityInput`.
5. `TrainingIdentityService.analyze(input)` calcula los scores.

## Atributos que se resuelven por ejercicio

Para cada ejercicio planificado o logueado, antes de anotarlo, se resuelve:

| Atributo | Fuente primaria (explícita) | Fallback heurístico si falta |
|---|---|---|
| `exType` (`exerciseType`) | catálogo (`exercises.exerciseType` o de la variante) | `'Otro'` |
| `family` (`TrainingIntentFamily`) | `mapExerciseTypeToIntentFamily(exType)` — por palabras clave en `exType` | — |
| `inferredBodyweight` / `inferredGuided` / `inferredFree` | `exerciseData.resistanceType` (`'bodyweight'`, `'guided'`, `'free'`) | `isBodyweightType` / `isGuidedType` / `isFreeType` sobre el nombre+tipo+equipo, buscando palabras como "polea", "máquina", "barra", "mancuerna" |
| `inferredUnilateral` | `exerciseData.isUnilateral` (solo si `hasIsUnilateralField`) o `perSide == true` en el ejercicio planificado | `isUnilateralExercise` — busca "zancada", "step up", "a una mano/pierna", "unilateral" en nombre/tipo |
| `inferredRotational` | `exerciseData.movementPlane` (`'rotational'` o `'anti-rotational'`, campo nuevo en `ExerciseVariant`/`Exercise`, default `'sagittal'`) | `isRotationalExercise` — busca "pallof", "leñador", "windmill", "russian twist", "plancha lateral", "landmine snatch/twist", "lanzamiento lateral", "giro" en nombre/tipo |
| `inferredCompound` / `inferredIsolation` | `exerciseData.movementClass` (`'compound'`/`'isolation'`) | `isCompoundExercise` (familia fuerza/potencia, o ≥3 músculos ponderados) / `isIsolationExercise` (tipo contiene "aisla"/"acces", o ≤2 músculos) |
| `trackRm` | `exerciseData.trackRM == true` | — |
| `percent1RM` | `referenceWeight` (peso planificado/logueado) ÷ `historical1RM` (mejor RM histórico del atleta para ese ejercicio, solo si `_shouldUseHistorical1RM(exType)`) | `null` si no hay RM histórico o el peso es 0 |
| `repBucket` | `repBucketFor(blockType, targetReps, family)` — por reps si `targetReps > 0`, si no por tipo de bloque (Tabata→`13+`, Circuito/EMOM→`9-10`) o por familia | — |
| `classificationOrigin` | `'block override'` si el bloque planificado trae `movementIntentOverride`/`trainingDisciplineOverride`; `'logged snapshot'` si el set logueado trae su propio `movementIntent`; si no, `'base'` o `'variant'` según de dónde salió en el catálogo | — |

**Nota**: la mayoría de estos atributos ya vienen resueltos con datos
explícitos del catálogo (ver auditoría más abajo: solo ~4-5% del catálogo
cae en las heurísticas por texto). Las heurísticas existen como red de
seguridad para ejercicios legacy o recién creados, no como mecanismo
principal.

## Clasificación de "dosis" (`_classificationFor`)

Antes de puntuar, cada ejercicio se reclasifica a una de ~20 categorías
técnicas (`'fuerza'`, `'potencia'`, `'halterofilia'`, `'pliometria'`,
`'landmine potencia'`, `'hipertrofia aislada'`, `'calistenia basica'`,
`'correctivo'`, etc.) combinando `movementIntent`, `trainingDiscipline`,
`exerciseType` y patrones en el nombre. Esta clasificación decide qué fila
de `_baseIntentByType` se usa como distribución base de puntos entre
perfiles. Ejemplos de reglas no obvias:

- Un ejercicio "unilateral" con peso libre o corporal, y `exerciseType`
  fuerza, se reclasifica a `'fuerza unilateral'` (menos peso a powerlifting,
  algo de peso a `bodyweight` por el control extra que exige).
- Halterofilia (`snatch`, `clean`, `jerk`) nunca se trata como "potencia
  pura" — se reparte entre `athlete`, `bodyweight` (control/recepción) y
  algo de `conditioning`.
- Landmine solo se clasifica como `'landmine potencia'` si además hay señal
  de intención explosiva; un remo o press con landmine de hipertrofia
  conserva su clasificación normal.
- Ejercicios "correctivos" (nombres con "plus", "serrato", "scapular", o
  `movementIntent` de estabilidad/prehab) casi no aportan a hipertrofia o
  fuerza, aportan sobre todo a `bodyweight`/control.

## Cómo se calcula el score de cada ejercicio

Por cada ejercicio, se parte de una distribución base entre perfiles (según
su clasificación de dosis) y se la va multiplicando por una cadena de
modificadores, en este orden:

```
baseValue      = dose * technicalDoseMultiplier * intensity * baseProfileDistribution
afterEquipment = baseValue * equipmentModifiers        (bodyweight/free/guided)
afterReps      = afterEquipment * repsModifiers        (según repBucket)
afterPercent   = afterReps * percent1RMModifiers       (según %1RM)
afterIntent    = afterPercent * intentCoherenceModifiers  (¿la dosis real coincide con el tipo declarado?)
afterBlock     = afterIntent * blockModifiers          (Series/Circuito/Tabata/Buscar RM)
finalValue     = afterBlock * attributeModifiers        (trackRM, unilateral, compound, isolation, bodyweight)
```

Cada paso queda registrado en `scoreBreakdown[perfil][etiqueta]` para que la
UI (o un debug) pueda mostrar de dónde salió cada score, no solo el número
final.

### `dose` — la "cantidad" de estímulo

- Si el ejercicio tiene duración (`durationSeconds`, ej. planchas, carreras):
  `dose = (duration / 60) * rounds`.
- Si no: `dose = baseSets * repsEquivalent * profileSideMultiplier`.
  - `profileSideMultiplier`: si el ejercicio es unilateral (`perSideMultiplier
    >= 2`), NO se duplica 2x plano — se usa `1.2` si la clasificación es
    hipertrofia/accesorio (para no dejar que un accesorio unilateral domine
    el perfil semanal) o `1.5` en el resto de los casos (fuerza/atlético).

### `technicalDoseMultiplier`

Solo halterofilia/weightlifting recibe `×2.0`: reconoce que una serie de
arranque exige una secuencia técnica completa y recepción estable, así que
3×3 de arranque no debe verse "pequeño" frente a 3×3 de sentadilla.

### `intensity` (según `%1RM` — y ahora según RPE real cuando existe)

Si hay `percent1RM` efectivo: `intensity = clamp(0.75 + percent1RM * 0.5, 0.75, 1.25)`.
Si no hay ninguna referencia de intensidad: `intensity = 1.0` (neutro).

**El `percent1RM` "efectivo" no siempre es el de referenceWeight/RM
histórico** (2026-09-19). Para ejercicios logueados (`source == 'logged'`,
tipo Series/Series descendentes/Buscar RM) que tengan un RPE reportado por
el atleta en esa serie (`set['rpe']`, ya se guarda en Firestore desde
`workout_save_service.dart` pero antes no llegaba a este cálculo), se usa
`percent1RMFromRpe(rpe, reps)` — una tabla estándar RPE+reps→%1RM
(Tuchscherer/RTS) — **en vez de** `percent1RM` por peso/RM histórico. El RPE
real tiene prioridad total cuando está disponible, porque:

- Es la señal de esfuerzo percibido real de esa serie específica, no una
  estimación indirecta.
- Hoy la app no tiene ningún RM histórico registrado (base de datos
  reiniciada), así que `percent1RM` por peso es `null` para prácticamente
  todo — sin el RPE real, el modificador de intensidad estaba
  permanentemente apagado (`intensity = 1.0` para todo) tanto en
  `intensity` como en `percent1RMModifiers`/`intentCoherenceModifiers`
  (que dependían del mismo bucket, siempre `'unknown'` → neutro).
- Bloques Circuito/Tabata/EMOM no reportan RPE por ejercicio hoy, así que
  siguen sin esta señal (caen al comportamiento anterior). Lo mismo aplica
  al `source == 'planned'`, que nunca tiene esfuerzo percibido real por
  definición.

Funciones nuevas en `training_identity_service.dart`:
`percent1RMFromRpe({rpe, reps})` y `percent1RMBucketFor(percent1RM)`. El
campo nuevo `TrainingIdentityExerciseContribution.reportedRpe` (double?,
solo poblado para `logged`) es lo que dispara esta ruta.

### Patrón rotacional / anti-rotacional (2026-09-19)

Hasta ahora el modelo solo distinguía patrones sagitales clásicos (empuje,
tracción, tren superior/inferior vía `functionalGroups` en
`muscle_catalog.dart`). No existía ninguna noción de "rotacional" —
ejercicios como Press Pallof, Leñador, Russian Twist, Windmill, plancha
lateral, lanzamiento lateral de balón medicinal o landmine snatch/twist
quedaban clasificados solo por su tipo genérico (Correctivos, Metabólico,
Potencia, Balístico...), sin capturar la demanda común a todos ellos:
generar o resistir torque rotacional del tronco, clave en deportes de
raqueta, lanzamiento y contacto.

**Campo nuevo en el catálogo**: `movementPlane` en `ExerciseVariant`/
`Exercise` (`lib/models/exercise.dart`) y en el documento Firestore de
`exercises`/`variants[]`. Valores: `'sagittal'` (default), `'rotational'`
(genera torque rotacional deliberado) o `'anti-rotational'` (exige resistir
la rotación). Una variante sin el campo hereda el del ejercicio base (igual
que `resistanceType`); a diferencia de `isUnilateral`, este campo **sí**
tiene ese fallback de herencia.

**Resolución en `unified_weekly_review_screen.dart`**: `inferredRotational`
usa `exerciseData.movementPlane` si está declarado (`rotational` o
`anti-rotational` cuentan igual), y si no, cae en
`TrainingIdentityService.isRotationalExercise(name, type)` — heurística por
palabras clave, mismo patrón que `isUnilateralExercise`.

**Efecto en el score** (`attributeModifiers`, mismo criterio que ya se
usaba para `unilateral`): un ejercicio rotacional/anti-rotacional sube
`athlete` (×1.18) y `bodyweight` (×1.10, control motor), y baja levemente
`powerlifting` (×0.90) e `hypertrophy` (×0.92) — no es fuerza máxima ni
estímulo de hipertrofia local, es transferencia deportiva y control.

Solo `Press Pallof` ya tenía una señal reutilizable en el catálogo real
(`familyId: 'anti_rotation'` en sus variantes), pero `familyId` no es una
taxonomía compartida (es casi un id único por ejercicio) así que no sirve
como fuente general — de ahí el campo `movementPlane` nuevo y explícito en
vez de tratar de inferir desde `familyId`.

**Catálogo completado (2026-09-19)**: se escribió `movementPlane`
explícito en Firestore para 21 documentos de `exercises`, así que estos ya
no dependen de `isRotationalExercise` (la heurística sigue activa como red
de seguridad para ejercicios nuevos o legacy sin completar):

- `anti-rotational` a nivel de ejercicio completo: Press Pallof, Plancha
  lateral derecha, Plancha lateral izquierda, Bird Dog, Dead Bug, Tap
  Shoulder alternado, Remo unilateral con ktb.
- `rotational` a nivel de ejercicio completo: Leñador, Russian Twist,
  Windmill, Landmine Snatch, Giro 180° con landmine, Lanzamiento lateral de
  balón medicinal a pared, Rotación con Medball + step, Slam ball con
  rotación OH, Sombra Drive Revés + disco y Med ball.
- Solo en variantes puntuales (el resto del ejercicio queda `'sagittal'`):
  `Plancha` → variantes "Lateral derecha", "Lateral izquierda", "Con
  toques de hombro" (`anti-rotational`); `Lanzamiento de balón medicinal` →
  variante "Lateral a pared"; `Snatch` → variante "Snatch · Landmine";
  `Power Snatch` → variante "Landmine"; `Estocada` → variante "Con torsión
  torácica" (todas `rotational`).

Bird Dog, Dead Bug, Tap Shoulder alternado y Remo unilateral con ktb son
anti-rotacionales por resistencia pasiva (el tronco resiste el impulso de
rotar); Estocada con torsión torácica y Sombra Drive Revés son rotacionales
activos (generan un giro deliberado de tronco, el segundo simula el golpe
de revés de tenis/pádel). Ninguno de estos 6 fue detectado por
`isRotationalExercise` automáticamente — se identificaron revisando el
catálogo completo (168 ejercicios) a mano.

### Coherencia intención-dosis (`intentCoherenceModifiers`)

Este es el ajuste más importante para evitar que la etiqueta declarada del
ejercicio domine ciegamente sobre la dosis real programada. Ejemplos:

- Un ejercicio de `exerciseType` "fuerza" pero con **13+ reps**: penaliza
  fuertemente `powerlifting` (×0.18) y sube mucho `hypertrophy` (×1.55).
- El mismo tipo "fuerza" pero a **90%+ de 1RM**: sube `powerlifting` (×1.28)
  y penaliza `hypertrophy` (×0.74).
- Un ejercicio de "fuerza" metido dentro de un bloque Tabata/Circuito/EMOM:
  el aporte a `conditioning` se multiplica ×1.8 adicional.
- "Hipertrofia" a 1-3 reps también se corrige (sube algo `powerlifting`,
  baja algo `hypertrophy`) — la coherencia funciona en ambos sentidos.

### Límite de dominancia (70%)

Después de sumar todos los ejercicios y aplicar bonificaciones de equilibrio
corporal (push/pull, superior/inferior), `_rebalanceDominantProfile` revisa
si un perfil se llevó más del 70% del total. Si es así, lo recorta a 70% y
redistribuye el excedente proporcionalmente entre los demás. Esto evita que
una semana con un solo tipo de estímulo dominante muestre 95-100% en un
perfil — mantiene siempre algo de "segundo lugar" legible.

### Bonificaciones de equilibrio corporal

Se calculan aparte de los ejercicios individuales, a partir de
`totalLoad` (carga muscular acumulada, no de dosis):

- `pushPullBalance` / `upperLowerBalance` = `min(a,b) / max(a,b)` entre
  grupos funcionales (empuje/tracción, tren superior/inferior).
- Cada perfil recibe una combinación distinta de estos balances más algunos
  ratios de intención (ver `balanceBonuses` en el código) escalada por
  `totalIntentLoad * 0.04`, para que el efecto sea proporcional al volumen
  real de la semana (una semana corta no debería recibir el mismo bono en
  puntos absolutos que una semana grande).

## Selección de perfil principal y secundario

Los 5 scores activos se ordenan de mayor a menor. El primero es
`primaryProfile`, el segundo `secondaryProfile`. No hay umbral mínimo:
siempre hay principal y secundario, aunque los valores sean bajos o estén
muy cerca entre sí.

## Sesgos (`biases`)

Etiquetas de texto adicionales, no afectan los scores:

- `Predominio de empuje` / `Predominio de tracción` — ratio push/pull ≥ 1.3
- `Predominio de tren superior` / `Predominio de tren inferior` — ratio
  superior/inferior ≥ 1.25
- `Predominio unilateral` (unilateralRatio ≥ 0.3) / `Predominio bilateral`
  (bilateralRatio ≥ 0.7)
- `Predominio de máquinas y poleas` (guidedRatio ≥ 0.45)
- `Predominio de peso libre` (freeRatio ≥ 0.6)
- `Predominio de peso corporal` (bodyweightEquipmentRatio ≥ 0.3)
- `Orientación a la potencia` (powerRatio ≥ 0.2)
- `Trabajo correctivo y de estabilidad` (stabilityRatio ≥ 0.2)
- `Orientación al acondicionamiento` (conditioningRatio ≥ 0.3)
- `Desarrollo muscular localizado` (hypertrophyRatio + accessoryRatio ≥ 0.45)

## Evidencia textual (`evidence`)

Cinco líneas de resumen que se muestran en la UI: intención por familia
(fuerza/potencia/hipertrofia/accesorios/correctivos/control), distribución
de rango de reps, distribución de implementos (libre/guiado/corporal),
distribución de estructura (bilateral/unilateral/compuesto/aislamiento), y
% de carga con seguimiento de RM.

## Consideraciones importantes

### El perfil es semanal y comparable planificado-vs-logueado

A diferencia de versiones anteriores de este sistema, hoy sí se puede
comparar `plannedTrainingIdentity` contra `loggedTrainingIdentity` para la
misma semana, porque ambos usan el mismo motor y el mismo shape de datos.

### Depende de la calidad de los metadatos del catálogo

El modelo confía primero en datos explícitos del catálogo
(`resistanceType`, `movementClass`, `isUnilateral`, `trackRM`,
`muscleWeights`) y solo cae en heurísticas de texto cuando faltan. Auditoría
del catálogo real (2026-09-19, 168 ejercicios base / 490 unidades contando
variantes):

- **~4% de las unidades** (22/490) no tienen `resistanceType` explícito ni
  en la variante ni en el ejercicio base → dependen de `isFreeType` /
  `isGuidedType` / `isBodyweightType` por texto.
- **~5% de las unidades** (23/490) no declaran `isUnilateral` en la
  variante → dependen de `isUnilateralExercise` por texto.
- **13% de los ejercicios base** (22/168) no tienen `movementClass`.

Es una proporción baja: no amerita una campaña de limpieza masiva del
catálogo, pero sí vale la pena revisar esa veintena de ejercicios puntuales
si se detecta un perfil raro para una sesión que los incluya.

### Inconsistencia conocida: `isUnilateral` no hereda de la variante al padre

`unified_weekly_review_screen.dart` (líneas ~268-272) hace que
`resistanceType`, `equipment`, `trainingDiscipline` y `movementIntent` de
una variante caigan al valor del ejercicio base si la variante no lo
declara (`variant['x'] ?? data['x']`). **`isUnilateral` no tiene ese
fallback**: `hasIsUnilateralField` solo mira si la variante en sí declara el
campo, aunque el ejercicio base sí lo tenga. Esto es una inconsistencia
menor: si algún ejercicio base marca `isUnilateral` pero sus variantes no lo
repiten, esas variantes caen en la heurística de texto en vez de heredar el
dato correcto del padre.

### `analyzeLegacy` fue eliminado (2026-09-19)

Existía un segundo método `TrainingIdentityService.analyzeLegacy()` con un
modelo de scoring lineal mucho más simple (era el modelo que describía la
versión anterior de este documento). No tenía ningún caller en el código
— era muerto. Se eliminó junto con su helper `_clampScore`, que solo él
usaba. Si algo en el futuro necesita ese modelo de referencia, está en el
historial de git antes de este cambio.

### Los scores no son probabilidades

Un score de 72 no significa "72% de certeza" de que la semana sea de ese
perfil. Es la suma de puntos de afinidad bajo las reglas actuales, ya
recortada al rango 0-100 vía el límite de dominancia.

## Archivos a revisar si se quiere ajustar el modelo

- `lib/services/training_identity_service.dart` — todas las tablas de
  constantes (`_baseIntentByType`, `equipmentModifiers`, `repsModifiers`,
  `percent1RMModifiers`, `intentCoherenceModifiers`, `blockModifiers`,
  `attributeModifiers`) y la función `analyze`.
- `lib/screens/unified_weekly_review_screen.dart` — cómo se arma el
  catálogo de ejercicios (`exerciseMap`), cómo se resuelven los atributos
  por ejercicio, y cómo se separan `planned`/`logged`.
- `lib/models/exercise.dart` — shape del documento de ejercicio y sus
  variantes.

### RPE real solo cubre Series/Series descendentes/Buscar RM (2026-09-19)

Circuito, Tabata y EMOM no capturan RPE por ejercicio en el flujo de log
actual, así que esos bloques siguen sin señal de intensidad real y dependen
de `intensity = 1.0` (neutro) salvo que en el futuro se registre RM
histórico. Si se agrega captura de RPE a esos tipos de bloque,
`_extractLoggedExercises` (en `unified_weekly_review_screen.dart`) es el
lugar a tocar para propagar `reportedRpe` también ahí.

### Fix: "Halterofilia" caía en familia "Sin clasificar" (2026-09-19)

`mapExerciseTypeToIntentFamily` clasifica la familia únicamente por
palabras clave en `exerciseType` (no usa `_classificationFor`, que es una
función distinta y más fina, solo para la "dosis"). La condición de
`strength` buscaba `'olimp'` y `'weightlifting'` pero no `'halterofilia'`
—el valor real que usa el catálogo para ejercicios como Clean & Jerk, Power
Clean, Snatch, Jerk, Hang Power Snatch (`exerciseType: "Halterofilia"`)—.
Como ninguna otra rama matcheaba tampoco, esos ejercicios caían en
`TrainingIntentFamily.unknown` ("Sin clasificar" en la UI), afectando el
ratio de "Sin clasificar" mostrado en evidencia y dejándolos fuera de
`strengthRatio`/`intentFamilyLoad[strength]`. Se agregó `'halterofilia'` a
la condición de `strength`, consistente con cómo `_classificationFor` ya
trata el criterio "olímpico" como parte del espectro de fuerza en la
distribución de dosis. Verificado contra los 17 `exerciseType` distintos
del catálogo real: ninguno cae en `unknown` después del fix.

## Mejoras futuras a considerar

- Mover las tablas de constantes a Firestore (como ya se hizo con
  `RpeFactorService` para los factores de RPE), si se espera seguir
  recalibrando el modelo sin requerir un release de la app.
- Agregar tests de regresión con sesiones reales conocidas (ej. un día de
  fuerza puro, uno de hipertrofia, un circuito de acondicionamiento) que
  fijen el perfil esperado — hoy no hay ningún test sobre este archivo, y
  la cadena de ~7 modificadores multiplicativos por ejercicio hace fácil
  que un ajuste en una tabla rompa el balance de otro perfil sin que nadie
  lo note hasta verlo en producción.
- Corregir la inconsistencia de herencia de `isUnilateral` descrita arriba.
- Completar `resistanceType`/`isUnilateral`/`movementClass` en la veintena
  de ejercicios detectados por la auditoría.
- Extender la captura de RPE real a Circuito/Tabata/EMOM.
- Cuando exista RM histórico real registrado, decidir si combinar RPE real
  y `%1RM` por peso (hoy el RPE gana siempre que existe) en vez de que uno
  excluya al otro.
- Revisar si aparecen nuevos ejercicios rotacionales/anti-rotacionales al
  ampliar el catálogo y marcarles `movementPlane` explícito de entrada, en
  vez de depender de `isRotationalExercise` (que ya cubre los ~30 patrones
  con nombre obvio, pero no reemplaza el juicio sobre casos nuevos como los
  6 identificados a mano el 2026-09-19 — ver sección arriba).
- Evaluar si separar `rotational` y `anti-rotational` en dos atributos
  distintos en vez de tratarlos igual en `attributeModifiers` — hoy ambos
  suben `athlete`/`bodyweight` por igual, pero podrían merecer pesos algo
  distintos si se observa que uno predice mejor cierto deporte que el otro.
