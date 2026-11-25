# TASKS — Cola de trabajo

Estados: `PENDIENTE` → `EN_CURSO` → `EN_REVISION` → `HECHA` · también `BLOQUEADA (motivo)`.
Prioridad: P0 (urgente) · P1 · P2. Solo el humano mueve tareas a `HECHA` (al hacer merge).

| ID | Prioridad | Estado | Título | Rama | Checkpoint / Notas | PR | Valor (CLP) |
|----|-----------|--------|--------|------|--------------------|----|-------------|
| T-001 | P1 | HECHO | Completar ARCHITECTURE.md inspeccionando el código real | claude/T-001-architecture-valoracion | Solo docs; sin tests (flutter no disponible en sesión); QA automático en PR | https://github.com/healthandfitness2022lv-afk/entrenamiento_app/pull/6 | $20.450.000 (incl. inicial) |
| T-002 | P2 | EN_REVISION | Diagnóstico de calidad: análisis estático y tests, registrar fallos como tareas | claude/T-002-diagnostico-calidad | 2026-11-25: informe docs/DIAGNOSTICO_CALIDAD.md con salida real de flutter-ci (0 errores, 1 warning, 79 infos; 35/35 tests). Creadas T-007..T-010 (T-004..T-006 reservadas por PR #9) | https://github.com/healthandfitness2022lv-afk/entrenamiento_app/pull/PRNUM | $150.000 |
| T-003 | P2 | PENDIENTE | Análisis comercial (sales): cliente objetivo, propuesta de valor, precios y 3 mejoras prioritarias | — | — | — | por estimar |
| T-007 | P1 | PENDIENTE | Corregir 10 usos de BuildContext tras await (use_build_context_synchronously) | — | Riesgo de excepción al guardar entrenamiento, asignar rutina y en planner. Ver docs/DIAGNOSTICO_CALIDAD.md | — | por estimar |
| T-008 | P2 | PENDIENTE | Limpieza de lints menores (warning unused_import, avoid_print y 67 infos cosméticos) | — | Sin cambio funcional | — | por estimar |
| T-009 | P2 | PENDIENTE | Ampliar tests: servicios de fatiga, RM, volumen y guardado de entrenamiento | — | Hoy 5/31 servicios con test | — | por estimar |
| T-010 | P2 | PENDIENTE | Inventario de dependencias desactualizadas (70 paquetes) y plan de actualización | — | Saltos mayores de Firebase = decisión crítica | — | por estimar |
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

### T-007 — BuildContext tras await
- Objetivo: en los 10 puntos que marca `flutter analyze` (lista en docs/DIAGNOSTICO_CALIDAD.md) agregar `if (!mounted) return;` / `if (!context.mounted) return;` o capturar `ScaffoldMessenger`/`Navigator` antes del `await`. En `log_workout_screen.dart:1806` revisar que `WorkoutSaveService` no use un `context` desmontado.
- Criterio de aceptación: la regla `use_build_context_synchronously` queda en 0; `flutter-ci` verde; sin cambio de comportamiento visible.
- Presupuesto: 25 turnos.

### T-008 — Limpieza de lints menores
- Objetivo: dejar `flutter analyze` sin warnings y con el mínimo de infos (quitar import sin uso, reemplazar `print` por `debugPrint`, llaves en if/for, renombrar parámetros `sum`/`count`, comentarios de `lib/utils/notes.dart`).
- Criterio de aceptación: 0 warnings; infos ≤ 5 justificadas; tests verdes. Requiere T-007 primero para no chocar en los mismos archivos.
- Presupuesto: 25 turnos.

### T-009 — Ampliar tests de servicios críticos
- Objetivo: tests unitarios para `fatigue_service`, `muscle_recovery_service`, `workout_rm_service`, `workout_volume_service` y la parte de cálculo de `workout_save_service`. Si hace falta simular Firestore, proponer `fake_cloud_firestore` (dev_dependency gratuita) en DECISIONS antes de agregarla.
- Criterio de aceptación: ≥ 4 suites nuevas en verde en `flutter-ci`.
- Presupuesto: 40 turnos.

### T-010 — Dependencias desactualizadas
- Objetivo: agregar un paso temporal o manual de `flutter pub outdated` en CI, clasificar los 70 paquetes (parche/menor seguros vs mayores con riesgo) y proponer el plan en DECISIONS (PROPUESTA). No actualizar versiones mayores sin aprobación.
- Criterio de aceptación: informe con tabla de paquetes y ADR propuesto.
- Presupuesto: 20 turnos.
