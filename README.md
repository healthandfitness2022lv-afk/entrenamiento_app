# 📱 Entrenamiento App

Aplicación de **entrenamiento y seguimiento de rendimiento** desarrollada en **Flutter**, orientada a atletas y entrenadores, con un enorme foco en **registro exhaustivo**, **manejo de fatiga**, **trazabilidad** y **análisis progresivo** del entrenamiento.

---

## 🧠 Objetivo del proyecto

Este proyecto busca reemplazar herramientas genéricas o informales (notas, planillas, memoria) por un sistema **estructurado, auditable e inteligente**, capaz de:

- **Registrar entrenamientos hipercomplejos**: Tipos de bloques diferenciados como *Series tradicionales*, *Series descendentes* (drop sets), *Buscar RM* (objetivos dinámicos), *Circuitos* y *Tabata*.
- **Carga y Fatiga Muscular Científica**: Calcular el tonelaje o estrés repartido por músculo según la ponderación (muscle weights) de cada ejercicio, afectando un estado persistente de fatiga y recuperación a lo largo del tiempo.
- **Medición de Progreso Inteligente**: Detectar nuevos PRs (Récords Personales), la serie más pesada histórica, récords de volumen por sesión, o una *mejor eficiencia* (mismo peso manejado con menor RPE).
- **Asistencia Activa**: Sugerir pesos basados en el historial de repeticiones de la misma persona, o sugerir repeticiones basadas en el historial de peso manejado, en tiempo real mientras el usuario entrena.
- **Mantener historial completo sin pérdida de datos** para respaldar una UI limpia con analíticas detalladas (Volume, RPE, Heatmaps corporales).

La prioridad arquitectónica del proyecto es la **correctitud del modelo de dominio y la trazabilidad**, por sobre decisiones puramente visuales, garantizando consistencia en todas las métricas.

---

## 🛠️ Stack tecnológico

- **Frontend**: Flutter (Mobile/Web), Dart.
- **Backend Backend-as-a-Service**: Firebase (Authentication, Firestore, Hosting).
- **Gráficos y Visualización**: `fl_chart`, visualizadores de Heatmaps con SVG para las zonas corporales.
- **Gestión de Estado**: Patrón ViewModel con `ChangeNotifier` (ej. `LogWorkoutViewModel`) aislando el UI de la lógica de negocio.

---

## 🧱 Arquitectura general y Patrones

El sistema está profundamente particionado para separar las responsabilidades matemáticas/calculadoras de las vistas:

- **Vistas (Screens/Widgets)**: Puramente declarativas. Se encargan del Layout (ej. `LogWorkoutScreen`, `MyWorkoutsScreen`, `DescendingSeriesBlockWidget`).
- **ViewModels**: Manejan el estado transitorio e interactivo complejo (ej. `LogWorkoutViewModel` para manejar estados de temporizadores intra-entrenamiento, text controllers de cientos de inputs de sets).
- **Servicios (Services)**: Pura lógica de negocio y cálculos sin estado. 
  - `WorkoutSaveService`: Orquestador sagrado que interpreta un plan y una ejecución en el cliente para consolidar el guardado en Firestore.
  - `ProgressAlertService`: Motor de análisis de datos para logros ("New PR", "Volume PR").
  - `WorkoutVolumeService`, `WorkoutMetricsService`, `WorkoutRmService`, `WorkoutLoadService`: Servicios matemáticos especializados por cada aspecto aislado de un entrenamiento.
  - `FatigueService`: Determina degradación/recuperación del músculo en el tiempo.
  - `WorkoutSuggestionService`: Analiza transacciones pasadas y calcula la mejor estimación de levantamiento.

### Principios clave adoptados

- Los **modelos no dependen de la UI**.
- La **lógica vive en services**, no en las screens.
- Las pantallas **orquestan** (piden datos a Services o ligan ViewModels), no calculan pesadamente.
- La **trazabilidad histórica es sagrada** (nunca se sobreescriben workouts pasados para calzar analíticas nuevas, las analíticas se adaptan o leen el modelo estricto).

---

## 🚨 Reglas críticas (NO romper)

Estas reglas son **invariantes del sistema** para mantener la integridad de los datos de salud y progreso del usuario:

- ❌ **No duplicar** entrenamientos, sets o movimientos.
- ❌ **No recalcular fatiga automáticamente** sin un evento explícito amarrado al tiempo.
- ❌ **No borrar o mutar historial** para “arreglar” datos. El historial es inmutable a no ser explicitado por el usuario.
- ❌ **No mezclar lógica de dominio** dentro del build() en la UI.
- ❌ **No introducir efectos colaterales silenciosos**.

Si una solución viola una de estas reglas, **es incorrecta**.

---

## 📂 Archivos y módulos críticos

Cambios en estos archivos deben ser **altamente testeados, mínimos y justificados** debido a su peso en el core lógico de la aplicación:

- **Manejadores de fatiga y carga**: `workout_load_service.dart`, `fatigue_service.dart` (o `fatigue_recalculation_service.dart`).
- **Persistencia**: `workout_save_service.dart` (Este es el puente de guardado entre el frontend interactivo y el modelo que quedará para siempre).
- **Motor Asistente y Progreso**: `workout_suggestion_service.dart`, `progress_alert_service.dart`, `workout_rm_service.dart`.
- **Modelos estructurales**: `muscle_catalog.dart` y todo dentro de `lib/models/`.

Antes de modificar cualquiera de ellos:
1. Entender el flujo completo. 
2. Evaluar cómo reaccionarán módulos hermanos (ej. Cambiar cómo se mide un RM afectará directamente las sugerencias y los reportes de logros).
3. Mantener compatibilidad absoluta con datos estructurales históricos ya en base de datos.

---

## 🤖 Uso con agentes de IA (ChatGPT / Copilot)

Este repositorio ha madurado y está optimizado para trabajo estructurado asistido por IA.

### Buenas prácticas al pedir cambios:
- Indicar explícitamente **qué capa tocar**: UI, Service/ViewModel, o el modelo Firestore.
- Para requerimientos que impactan a la lógica de levantamiento, mencionar expresamente cómo aplica a `Series`, `Series descendentes`, `Buscar RM` u otros tipos de bloque.
- Nunca asumir que recalcular, limpiar masivamente o ignorar reglas estrictas de fatiga/RM es un "fix" rápido aceptable.

Ejemplos correctos:
- “Modifica la visualización en MyWorkoutsScreen para separar el bloque Series Descendentes del resto de series, sin tocar el modelado de datos subyacente.”
- “El LogWorkoutScreen necesita autoguardar el estado; impleméntalo únicamente a nivel de LogWorkoutViewModel sin afectar WorkoutSaveService.”
- “Agrega una nueva métrica de eficiencia al servicio ProgressAlertService basándote en que si el RPE es menor con igual peso = logro.”

---

## 🚀 Estado del proyecto

- Entorno rico en funcionalidades para usuarios hiper exigentes, no solo casuales.
- Arquitectura fuertemente desacoplada (paso actual de estado).
- Se prioriza estabilidad y robustez del tracking sobre la velocidad de desarrollo.
- Pensado para escalar en **análisis de datos masivo, más métricas y tipos de ciclos**.

---

## 👤 Autor

Proyecto desarrollado por **Héctor Álvarez**  
Enfocado en sistemas con **trazabilidad real**, **modelo sólido**, **física real del entrenamiento** y **pensamiento de largo plazo**.
