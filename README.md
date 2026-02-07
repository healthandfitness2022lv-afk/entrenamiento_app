# 📱 Entrenamiento App

Aplicación de **entrenamiento y seguimiento de rendimiento** desarrollada en **Flutter**, orientada a atletas y entrenadores, con foco en **registro detallado**, **fatiga**, **trazabilidad** y **análisis progresivo** del entrenamiento.

---

## 🧠 Objetivo del proyecto

Este proyecto busca reemplazar registros informales (notas, planillas, memoria) por un sistema **estructurado, auditable y extensible**, capaz de:

- Registrar entrenamientos complejos (series, circuitos, EMOM, Tabata, etc.)
- Analizar **fatiga muscular** por grupo muscular
- Visualizar activación mediante **heatmaps corporales**
- Detectar progreso, estancamiento y nuevos PRs
- Mantener **historial completo sin pérdida de datos**
- Escalar a **Web y Android** desde una sola base de código

La prioridad del proyecto es la **correctitud del modelo y la trazabilidad**, por sobre decisiones puramente visuales.

---

## 🛠️ Stack tecnológico

- **Flutter** (Web + Android)
- **Dart**
- **Firebase**
  - Authentication
  - Firestore
  - Hosting (Web)
- Visualización con gráficos (`fl_chart`)
- SVGs para mapas corporales y heatmaps

---

## 🧱 Arquitectura general




### Principios clave

- Los **modelos no dependen de la UI**
- La **lógica vive en services**, no en screens
- Las pantallas **orquestan**, no calculan
- La trazabilidad histórica es **sagrada**

---

## 🚨 Reglas críticas (NO romper)

Estas reglas son **invariantes del sistema**:

- ❌ No duplicar entrenamientos, sets o movimientos
- ❌ No recalcular fatiga automáticamente sin un evento explícito
- ❌ No borrar historial para “arreglar” datos
- ❌ No mezclar lógica de dominio dentro de la UI
- ❌ No introducir efectos colaterales silenciosos

Si una solución viola una de estas reglas, **es incorrecta**.

---

## 📂 Archivos y módulos críticos

Cambios en estos archivos deben ser **mínimos y justificados**:

- `fatigue_recalculation_service.dart`
- `tabata_timer_service.dart`
- `muscle_catalog.dart`
- Modelos base en `lib/models/`

Antes de modificar cualquiera de ellos:
1. Entender el flujo completo
2. Evaluar efectos secundarios
3. Mantener compatibilidad con datos históricos

---

## 🤖 Uso con agentes de IA (ChatGPT / Copilot)

Este repositorio está preparado para trabajo asistido por IA.

### Buenas prácticas al pedir cambios:
- Indicar explícitamente **qué NO tocar**
- Especificar si el cambio es:
  - UI
  - lógica de negocio
  - modelo de datos
- Nunca asumir que recalcular, limpiar o borrar datos es aceptable

Ejemplos correctos:
- “Agrega esta visualización sin tocar el cálculo de fatiga”
- “Refactoriza este widget sin modificar servicios”
- “Detecta el origen del bug, no lo ocultes”

---

## 🚀 Estado del proyecto

- En desarrollo activo
- Enfoque incremental
- Se prioriza estabilidad sobre velocidad
- Arquitectura pensada para escalar (más métricas, más análisis, más usuarios)

---

## 👤 Autor

Proyecto desarrollado por **Héctor Álvarez**  
Enfocado en sistemas con **trazabilidad real**, **modelo sólido** y **pensamiento de largo plazo**.
