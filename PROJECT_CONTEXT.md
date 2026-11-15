# Project Context

## Purpose
This is a Flutter fitness training app focused on:
- Workout logging
- Fatigue tracking
- Muscle heatmap visualization
- Training progression analysis

## Tech Stack
- Flutter
- Firebase Auth
- Firestore
- Flutter Web + Android

## Core Rules (DO NOT BREAK)
- Never duplicate workout logs
- Never recalculate fatigue unless explicitly requested
- Preserve historical data integrity
- UI changes must not affect domain logic

## Architecture
- lib/models → domain models
- lib/services → business logic (timers, fatigue, audio)
- lib/screens → UI
- Avoid tight coupling between screens and services

## Critical Files
- fatigue_recalculation_service.dart
- tabata_timer_service.dart
- muscle_catalog.dart

Changes to these files must be minimal and justified.

## Perfil de Entrenamiento (Resumen en español)

### Qué intenta medir
El perfil semanal mezcla dos fuentes:
- días ya realizados: usa `workouts_logged`
- días aún no realizados: usa `planned_workouts`

Regla principal:
- si un día ya tiene entrenamiento registrado, ese día reemplaza lo planificado
- si no tiene entrenamiento registrado, se mantiene la planificación

### Qué campos del ejercicio sí se usan
El perfil ahora depende principalmente de metadata explícita del catálogo:
- `exerciseType`
- `resistanceType`
  - `free`
  - `guided`
  - `bodyweight`
- `movementClass`
  - `compound`
  - `isolation`
- `isUnilateral`

### Qué campos ya no se usan para perfilar
- `equipment`
- `trackRM`

### Perfiles visibles
- `Powerlifting`
- `Deportista`
- `Hipertrofia`
- `Acondicionamiento`

`Híbrido` ya no sale como categoría explícita. Si una semana es mixta, eso se refleja con varias barras altas a la vez.

### Fórmula base de carga

```text
volumeUnits = baseSets * (repsEquivalent / 10) * perSideMultiplier
muscleLoad = volumeUnits * muscleWeight * exerciseFolderFactor * structureFactor
exerciseLoad = suma de todos los muscleLoad del ejercicio
```

Donde:
- `baseSets`: sets planificados o sets/rondas realmente ejecutados
- `repsEquivalent`: reps reales o inferidas
- `perSideMultiplier`: `2.0` si fue por lado/unilateral, `1.0` si no
- `muscleWeight`: sale de `muscleWeights`
- `exerciseFolderFactor`: sale de `exercise_folders.multiplier`
- `structureFactor`: sale de `WorkoutLoadService.structureFactor(...)`

### Buckets de reps
- `1-5`
- `6-12`
- `13+`

### Fórmula del score por perfil
Cada ejercicio aporta a todos los perfiles activos con distintos pesos:

```text
scoreEjercicioPerfil =
  exerciseLoad
  * baseProfileDistribution[perfil]
  * equipmentModifier[perfil]
  * repsModifier[perfil]
  * blockModifier[perfil]
  * attributeModifier[perfil]
```

Después:
- se suman todos los ejercicios de la semana
- se añade un bonus estructural pequeño según ratios globales semanales

### Señal principal: `exerciseType`
Este es el eje más importante del modelo.

Ejemplos:

#### Fuerza
- Powerlifting: `0.58`
- Deportista: `0.22`
- Hipertrofia: `0.15`
- Acondicionamiento: `0.05`

#### Potencia
- Powerlifting: `0.05`
- Deportista: `0.74`
- Hipertrofia: `0.03`
- Acondicionamiento: `0.18`

#### Balístico
- Powerlifting: `0.02`
- Deportista: `0.70`
- Hipertrofia: `0.03`
- Acondicionamiento: `0.25`

#### Hipertrofia
- Powerlifting: `0.02`
- Deportista: `0.06`
- Hipertrofia: `0.84`
- Acondicionamiento: `0.08`

#### Accesorio
- Powerlifting: `0.02`
- Deportista: `0.08`
- Hipertrofia: `0.74`
- Acondicionamiento: `0.16`

#### Aislamiento
- Powerlifting: `0.00`
- Deportista: `0.03`
- Hipertrofia: `0.87`
- Acondicionamiento: `0.10`

#### Calistenia / peso corporal
- Powerlifting: `0.12`
- Deportista: `0.48`
- Hipertrofia: `0.20`
- Acondicionamiento: `0.20`

### Modificadores por `resistanceType`

#### `bodyweight`
- Powerlifting: `0.82`
- Deportista: `1.15`
- Hipertrofia: `0.95`
- Acondicionamiento: `1.10`

#### `guided`
- Powerlifting: `0.55`
- Deportista: `0.70`
- Hipertrofia: `1.35`
- Acondicionamiento: `1.00`

#### `free`
- Powerlifting: `1.12`
- Deportista: `1.10`
- Hipertrofia: `0.92`
- Acondicionamiento: `1.00`

### Modificadores por reps

#### `1-5`
- Powerlifting: `1.22`
- Deportista: `1.08`
- Hipertrofia: `0.80`
- Acondicionamiento: `0.65`

#### `6-12`
- Powerlifting: `0.92`
- Deportista: `0.98`
- Hipertrofia: `1.10`
- Acondicionamiento: `0.95`

#### `13+`
- Powerlifting: `0.00`
- Deportista: `0.80`
- Hipertrofia: `0.45`
- Acondicionamiento: `1.30`

### Modificadores por bloque

#### `Buscar RM`
- Powerlifting: `1.12`
- Deportista: `1.02`
- Hipertrofia: `0.95`
- Acondicionamiento: `0.90`

#### `Circuito`
- Powerlifting: `1.00`
- Deportista: `1.03`
- Hipertrofia: `1.00`
- Acondicionamiento: `1.05`

#### `Tabata`
- Powerlifting: `0.90`
- Deportista: `1.06`
- Hipertrofia: `0.95`
- Acondicionamiento: `1.12`

### Modificadores por atributos
Hoy siguen activos:
- `unilateral`
- `compound`
- `isolation`

`trackRM` ya no influye en el perfil.

### Bonus estructural global
Después de sumar los ejercicios, el servicio agrega un bonus pequeño por:
- bilateral vs unilateral
- compuesto vs aislado
- balance torso/pierna
- balance empuje/tirón
- exposición global a acondicionamiento

### Cómo interpreta lo ejecutado

#### Series / Buscar RM / Series descendentes
- usa sets reales
- usa promedio real de reps si existe

#### Circuito / EMOM
- agrupa repeticiones del mismo ejercicio
- usa número de apariciones como `baseSets`
- usa promedio de reps registradas

#### Tabata
- usa rondas registradas
- usa reps registradas si existen
- si no hay reps, usa `work / 5` como aproximación

### Dónde tocar si quieres recalibrar
- `baseProfileDistributionForType(...)`
- `equipmentModifiers(...)`
- `repsModifiers(...)`
- `blockModifiers(...)`
- `attributeModifiers(...)`
- `balanceBonuses` dentro de `analyze(...)`

## Training Identity Profile

### Goal
The weekly training profile is intended to describe the week's training intention using a mixed source:
- Logged days use `workouts_logged`
- Pending days use `planned_workouts`

This means the profile is not purely planned and not purely historical. It is:
- real for completed days
- projected for remaining days

### Main Files
- `lib/screens/unified_weekly_review_screen.dart`
- `lib/services/training_identity_service.dart`

### Data Sources

#### Planned days
Source:
- `planned_workouts`
- referenced `blocks`
- `exercises`
- `exercise_folders`

#### Logged days
Source:
- `workouts_logged`
- embedded `performed` blocks
- `exercises`
- `exercise_folders`

Rule:
- if a calendar day already has a logged workout, that day replaces the planned workout for load/profile purposes
- if a day has no logged workout yet, planning remains active for that day

Implementation reference:
- `loggedSnapshot` and `completedDates` in `lib/screens/unified_weekly_review_screen.dart`

### Explicit Exercise Metadata Used
The profile should now depend on explicit exercise metadata, not `equipment`.

Used fields from `exercises`:
- `exerciseType`
- `resistanceType`
  - `free`
  - `guided`
  - `bodyweight`
- `movementClass`
  - `compound`
  - `isolation`
- `isUnilateral`
- `trackRM`
  - currently kept in the model but no longer affects the profile score

Important:
- `equipment` should not be considered for training profile classification anymore

## ActualizaciÃ³n: %1RM HistÃ³rica

El perfil de entrenamiento ahora incorpora una capa adicional de intensidad relativa usando la misma base de sets que alimenta [exercise_rm_detail_screen.dart](lib/screens/exercise_rm_detail_screen.dart).

### Fuente de datos

- Se recorren todos los documentos de `workouts_logged` del atleta.
- De cada entrenamiento se usa `WorkoutRMService.extractAllValidRMSetCandidates(performed)`.
- Eso entrega los mismos sets vÃ¡lidos por ejercicio, reps y peso efectivo que usa la vista de RM.

### CÃ¡lculo de `1RM` histÃ³rica

Para cada ejercicio normalizado:

```text
historical1RM = max(weight * (1 + reps / 30))
```

Notas:
- usa Epley, igual que la visualizaciÃ³n de RM del ejercicio
- se toma el mejor valor histÃ³rico conocido
- la clave de agrupaciÃ³n usa `WorkoutRMService.normalizeExerciseName(...)`

### CÃ¡lculo de `%1RM`

Para cada ejercicio semanal del perfil:

```text
percent1RM = referenceWeight / historical1RM
```

Donde `referenceWeight` es:
- `logged`: el peso efectivo mÃ¡s alto detectado dentro de ese bloque
- `planned`: `ex['weight']` o, si existen sets planificados, el peso mÃ¡s alto de esos sets

Si no hay peso o no existe `historical1RM`, el valor queda `null` y el bucket pasa a `unknown`.

### Buckets de `%1RM`

- `<55%`
- `55-70%`
- `70-80%`
- `80-90%`
- `90%+`
- `unknown`

### Nueva fÃ³rmula de score por perfil

```text
scoreEjercicioPerfil =
  exerciseLoad
  * baseProfileDistribution[perfil]
  * repsModifier[perfil]
  * percent1RMModifier[perfil]
  * blockModifier[perfil]
  * attributeModifier[perfil]
```

### Efecto conceptual de `%1RM`

- `<55%`: favorece mÃ¡s `Acondicionamiento`
- `55-70%`: zona media, algo mÃ¡s amigable con `Hipertrofia`
- `70-80%`: casi neutra
- `80-90%`: empuja hacia `Powerlifting`
- `90%+`: empuja fuerte hacia `Powerlifting`

Esto no reemplaza el rol de `exerciseType` ni de las reps. Solo refina la lectura de intensidad real del ejercicio dentro del perfil semanal.
- if explicit metadata exists, it overrides old heuristics

### Active Profiles
Current visible profiles:
- `Powerlifting`
- `Deportista`
- `Hipertrofia`
- `Acondicionamiento`

Important:
- `Hibrido` is no longer used as an explicit output category
- if a week is mixed, that should appear naturally as several bars with similar weight

### Weekly Flow

#### Step 1. Build weekly exercise contributions
For each relevant exercise in the week:
- resolve exercise catalog entry
- resolve explicit metadata
- resolve reps bucket
- calculate base load
- distribute contribution across profiles

#### Step 2. Accumulate weekly structural ratios
The screen accumulates:
- family load
- reps bucket load
- unilateral/bilateral load
- free/guided/bodyweight load
- compound/isolation load
- anatomical distribution

#### Step 3. Run profile analysis
`TrainingIdentityService.analyze(...)` converts weekly exercise contributions into:
- profile scores
- score breakdown
- evidence
- per-exercise debug contributions

### Load Formula
The current weekly contribution per exercise is based on planned or logged work translated to a weighted load.

Base exercise load:

```text
volumeUnits = baseSets * (repsEquivalent / 10) * perSideMultiplier
muscleLoad = volumeUnits * muscleWeight * exerciseFolderFactor * structureFactor
exerciseLoad = sum(muscleLoad for all involved muscles)
```

Where:
- `baseSets`
  - from planned block structure or logged performed sets/rounds
- `repsEquivalent`
  - actual or inferred reps
- `perSideMultiplier`
  - currently `2.0` if marked per-side/unilateral in that exercise contribution, otherwise `1.0`
- `muscleWeight`
  - from `exercise.muscleWeights`
- `exerciseFolderFactor`
  - from `exercise_folders.multiplier`
- `structureFactor`
  - from `WorkoutLoadService.structureFactor(...)`

Implementation reference:
- `_applyIdentityExerciseLoad(...)` in `lib/screens/unified_weekly_review_screen.dart`

### Reps Buckets
Current buckets:
- `1-5`
- `6-12`
- `13+`

Bucket assignment:
- use actual/target reps if available
- if missing, infer from exercise family / block type

Implementation reference:
- `repBucketFor(...)` in `lib/services/training_identity_service.dart`

### Profile Score Formula
Each exercise does not belong to one profile only. It contributes proportionally to all active profiles.

Per profile:

```text
exerciseProfileScore =
  exerciseLoad
  * baseProfileDistribution[profile]
  * equipmentModifier[profile]
  * repsModifier[profile]
  * blockModifier[profile]
  * attributeModifier[profile]
```

Then all exercise contributions are summed over the week.

After that, a small global structural bonus is added using weekly ratios such as:
- bilateral vs unilateral
- compound vs isolation
- push/pull balance
- upper/lower balance
- conditioning exposure

### Base Distribution by `exerciseType`
This is the most important signal in the current model.

Examples from `baseProfileDistributionForType(...)`:

#### `Fuerza`
- Powerlifting: `0.58`
- Deportista: `0.22`
- Hipertrofia: `0.15`
- Acondicionamiento: `0.05`

#### `Potencia`
- Powerlifting: `0.05`
- Deportista: `0.74`
- Hipertrofia: `0.03`
- Acondicionamiento: `0.18`

#### `Balistico`
- Powerlifting: `0.02`
- Deportista: `0.70`
- Hipertrofia: `0.03`
- Acondicionamiento: `0.25`

#### `Hipertrofia`
- Powerlifting: `0.02`
- Deportista: `0.06`
- Hipertrofia: `0.84`
- Acondicionamiento: `0.03`

#### `Accesorio`
- Powerlifting: `0.02`
- Deportista: `0.08`
- Hipertrofia: `0.74`
- Acondicionamiento: `0.16`

#### `Aislamiento`
- Powerlifting: `0.00`
- Deportista: `0.03`
- Hipertrofia: `0.87`
- Acondicionamiento: `0.10`

#### `Calistenia / Bodyweight`
- Powerlifting: `0.12`
- Deportista: `0.48`
- Hipertrofia: `0.20`
- Acondicionamiento: `0.20`

### Resistance Type Modifiers
Applied through `equipmentModifiers(...)`, but driven by `resistanceType`, not `equipment`.

#### `bodyweight`
- Powerlifting: `0.82`
- Deportista: `1.15`
- Hipertrofia: `0.95`
- Acondicionamiento: `1.10`

#### `guided`
- Powerlifting: `0.55`
- Deportista: `0.70`
- Hipertrofia: `1.35`
- Acondicionamiento: `1.00`

#### `free`
- Powerlifting: `1.12`
- Deportista: `1.10`
- Hipertrofia: `0.92`
- Acondicionamiento: `1.00`

### Reps Modifiers
Applied through `repsModifiers(...)`.

#### `1-5`
- Powerlifting: `1.22`
- Deportista: `1.08`
- Hipertrofia: `0.80`
- Acondicionamiento: `0.65`

#### `6-12`
- Powerlifting: `0.92`
- Deportista: `0.98`
- Hipertrofia: `1.10`
- Acondicionamiento: `0.95`

#### `13+`
- Powerlifting: `0.00`
- Deportista: `0.80`
- Hipertrofia: `0.45`
- Acondicionamiento: `1.30`

### Block Modifiers
Applied through `blockModifiers(...)`.

#### `Buscar RM`
- Powerlifting: `1.12`
- Deportista: `1.02`
- Hipertrofia: `0.95`
- Acondicionamiento: `0.90`

#### `Circuito`
- Powerlifting: `1.00`
- Deportista: `1.03`
- Hipertrofia: `1.00`
- Acondicionamiento: `1.05`

#### `Tabata`
- Powerlifting: `0.90`
- Deportista: `1.06`
- Hipertrofia: `0.95`
- Acondicionamiento: `1.12`

### Attribute Modifiers
Applied through `attributeModifiers(...)`.

Currently active:
- `unilateral`
- `compound`
- `isolation`

Currently inactive for profile scoring:
- `trackRM`

Examples:

#### if unilateral
- Powerlifting reduced
- Deportista increased
- Acondicionamiento slightly increased

#### if compound
- Powerlifting increased
- Deportista increased

#### if isolation
- Hipertrofia increased
- Powerlifting reduced
- Deportista reduced

### Weekly Structural Bonuses
After summing exercise-level contributions, the service adds a small global bonus.

Examples:
- `Powerlifting`
  - benefits from bilateral and compound concentration
  - penalized slightly by conditioning dominance
- `Deportista`
  - benefits from upper/lower balance, push/pull balance, unilateral exposure and power exposure
- `Hipertrofia`
  - benefits from guided ratio, isolation ratio and hypertrophy family load
- `Acondicionamiento`
  - benefits from conditioning family load, `13+` reps and whole-body balance

### Logged Workout Interpretation
When using `workouts_logged`, the screen converts performed blocks into identity contributions:

#### `Series / Series descendentes / Buscar RM`
- use actual performed set count
- average performed reps if present

#### `Circuito / EMOM`
- group repeated rounds by exercise
- use number of appearances as `baseSets`
- use average logged reps

#### `Tabata`
- use logged rounds
- use logged reps when available
- otherwise infer repsEquivalent from `work / 5`

### Important Current Simplifications
- `equipment` is ignored for profile scoring
- `trackRM` is ignored for profile scoring
- `perSide` still influences volume through `perSideMultiplier`
- if logged exercise names do not match exercise catalog names, those entries are skipped
- if an exercise has missing metadata, the service falls back to family/type-based inference

### If You Want To Recalibrate
The first places to edit are:
- `baseProfileDistributionForType(...)`
- `equipmentModifiers(...)`
- `repsModifiers(...)`
- `blockModifiers(...)`
- `attributeModifiers(...)`
- weekly `balanceBonuses` inside `analyze(...)`
