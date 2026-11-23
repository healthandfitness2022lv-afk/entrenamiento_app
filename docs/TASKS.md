# TASKS — Cola de trabajo

Estados: `PENDIENTE` → `EN_CURSO` → `EN_REVISION` → `HECHA` · también `BLOQUEADA (motivo)`.
Prioridad: P0 (urgente) · P1 · P2. Solo el humano mueve tareas a `HECHA` (al hacer merge).

| ID | Prioridad | Estado | Título | Rama | Checkpoint / Notas | PR | Valor (CLP) |
|----|-----------|--------|--------|------|--------------------|----|-------------|
| T-001 | P1 | HECHO | Completar ARCHITECTURE.md inspeccionando el código real | claude/T-001-architecture-valoracion | Solo docs; sin tests (flutter no disponible en sesión); QA automático en PR | https://github.com/healthandfitness2022lv-afk/entrenamiento_app/pull/6 | $20.450.000 (incl. inicial) |
| T-002 | P2 | BLOQUEADA (entorno: el proxy de la sesión en la nube bloquea storage.googleapis.com, no se puede instalar el SDK Dart/Flutter; ejecutar en una máquina con Flutter o habilitar el host) | Diagnóstico de calidad: análisis estático y tests, registrar fallos como tareas | claude/T-002-diagnostico-calidad | 2026-11-22: `flutter --version` falla al descargar Dart SDK (curl 56, CONNECT 403) | — | por estimar |
| T-003 | P2 | EN_CURSO | Análisis comercial (sales): cliente objetivo, propuesta de valor, precios y 3 mejoras prioritarias | claude/T-003-analisis-comercial | Inicio: subagente sales | — | por estimar |
| T-004 | P1 | PENDIENTE | Informe semanal con marca del entrenador, compartible por WhatsApp | — | — | — | por estimar |
| T-005 | P1 | PENDIENTE | Panel "Mis alumnos" con semáforo de fatiga y adherencia | — | — | — | por estimar |
| T-006 | P2 | PENDIENTE | Modo demo y plantillas de planificación para onboarding rápido | — | — | — | por estimar |

## Detalle de tareas

### T-001 — Completar ARCHITECTURE.md
- Objetivo: describir stack, módulos, flujo de datos, cómo testear. Rellenar "Comandos del proyecto" en CLAUDE.md.
- Criterio de aceptación: documentos reflejan el código; **docs/VALORACION.md con la valoración inicial de todos los módulos existentes** (horas × $25.000 CLP/h y referencia de mercado); PR en borrador abierto.
- Presupuesto: 40 turnos.

### T-002 — Diagnóstico de calidad
- Objetivo: ejecutar análisis estático y tests del stack; por cada problema relevante crear una tarea nueva (P1/P2). No corregir aún.
- Criterio de aceptación: informe en el PR con salida real de los comandos.
- Presupuesto: 30 turnos.

### T-003 — Análisis comercial
- Responsable: subagente `sales` (requiere T-001 hecha para conocer la app).
- Objetivo: crear docs/SALES.md (segmento, propuesta de valor, competidores con precios, planes sugeridos) y sección "Visión comercial" en ROADMAP.md; proponer 3 mejoras como tareas nuevas.
- Criterio de aceptación: PR con docs/SALES.md y tareas nuevas en TASKS.md.
- Presupuesto: 30 turnos.

### T-004 — Informe semanal con marca del entrenador, compartible por WhatsApp
- Objetivo: el coach genera en un toque un informe semanal por alumno (carga, volumen, RM destacados, fatiga por músculo, adherencia) con su nombre/logo/color, exportable a PDF e imagen vía `share_plus`. Reutiliza `athlete_report_service`, `training_period_report_service` y el export de stories.
- Criterio de aceptación: pantalla de configuración de marca (nombre, color, logo opcional) guardada localmente (`shared_preferences`); informe PDF/imagen con esa marca; tests de la composición de datos del informe (servicio puro); `flutter analyze` y `flutter test` en verde. Si se quiere guardar la marca en Firestore o compartir por enlace público, es cambio de esquema/reglas: proponer en DECISIONS.md (decisión crítica), no implementar.
- Presupuesto: 30 turnos.

### T-005 — Panel "Mis alumnos" con semáforo de fatiga y adherencia
- Objetivo: vista de entrenador que lista a todos sus alumnos con semáforo (fatiga alta, sin entrenar hace N días, alerta de carga) para priorizar a quién escribir. Hoy solo existe selección de un atleta a la vez (`athlete_selection_service`).
- Criterio de aceptación: lista ordenada por prioridad usando `fatigue_state`, `workouts_logged` y `load_adjustment_alerts` existentes (solo lectura); acceso rápido al alumno; lógica del semáforo en servicio puro con tests; sin cambios de esquema. Verificar antes que las reglas actuales permiten al coach leer datos de varios alumnos; si no, registrar PROPUESTA de cambio de reglas (decisión crítica) y marcar BLOQUEADA (aprobación).
- Presupuesto: 35 turnos.

### T-006 — Modo demo y plantillas de planificación para onboarding rápido
- Objetivo: que un coach nuevo vea valor en minutos: modo demo con datos ficticios en memoria (sin escribir en Firestore) y 4-6 plantillas de planificación (fuerza 3 días, hipertrofia 4 días, full body 2 días, etc.) aplicables al planner. Sirve también como herramienta de venta en demos.
- Criterio de aceptación: demo accesible desde el login sin crear cuenta ni tocar datos reales; plantillas definidas como datos locales y aplicables a `planned_workouts` del alumno elegido; tests de las plantillas (estructura válida y ejercicios existentes en el catálogo); sin cambios de reglas ni despliegue.
- Presupuesto: 30 turnos.
