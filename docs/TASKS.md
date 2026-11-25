# TASKS — Cola de trabajo

Estados: `PENDIENTE` → `EN_CURSO` → `EN_REVISION` → `HECHA` · también `BLOQUEADA (motivo)`.
Prioridad: P0 (urgente) · P1 · P2. Pasan a `HECHA` al fusionar: el humano, o el agente cuando el PR cumple la auto-fusión (ADR-003).

| ID | Prioridad | Estado | Título | Rama | Checkpoint / Notas | PR | Valor (CLP) |
|----|-----------|--------|--------|------|--------------------|----|-------------|
| T-001 | P1 | HECHO | Completar ARCHITECTURE.md inspeccionando el código real | claude/T-001-architecture-valoracion | Solo docs; sin tests (flutter no disponible en sesión); QA automático en PR | https://github.com/healthandfitness2022lv-afk/entrenamiento_app/pull/6 | $20.450.000 (incl. inicial) |
| T-002 | P2 | PENDIENTE | Diagnóstico de calidad: análisis estático y tests, registrar fallos como tareas | claude/T-002-diagnostico-calidad | 2026-11-24: desbloqueada por ADR-002 (CI `flutter-ci` en GitHub Actions). Continuar la rama existente: traer `main`, empujar y usar la salida real del check `flutter-ci` como informe | — | por estimar |
| T-003 | P2 | PENDIENTE | Análisis comercial (sales): cliente objetivo, propuesta de valor, precios y 3 mejoras prioritarias | — | — | — | por estimar |
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
