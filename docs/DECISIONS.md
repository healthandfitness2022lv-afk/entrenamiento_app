# DECISIONS — Registro de decisiones (ADR)

Estados: `PROPUESTA` (requiere aprobación humana) · `APROBADA` · `RECHAZADA` · `SUPERADA`.
Solo el humano cambia `PROPUESTA` → `APROBADA/RECHAZADA`.

## ADR-001 — Adopción de Nexus AI
- Estado: APROBADA
- Fecha: 2026-11-15
- Contexto: operar el repo con agentes autónomos con revisión humana obligatoria.
- Decisión: agentes trabajan en ramas `claude/*` y entregan PRs en borrador; `main` protegida.
- Consecuencias: ningún cambio llega a producción sin merge humano.

## ADR-002 — CI de Flutter (analyze + test) en GitHub Actions
- Estado: APROBADA (dueño, 2026-11-24)
- Contexto: las sesiones en la nube de los agentes no pueden instalar el SDK de Flutter (el proxy rechaza la descarga desde `storage.googleapis.com`, CONNECT 403). Sin SDK ninguna tarea de código podía pasar QA con tests reales y T-002 quedó bloqueada.
- Decisión: `.github/workflows/flutter-ci.yml` (subosito/flutter-action, canal stable) corre `flutter pub get`, `flutter analyze --no-fatal-infos --no-fatal-warnings` y `flutter test` en push a `claude/**` y en PR a `main`. Los agentes leen el resultado con `gh api .../check-runs` y los logs del job.
- Consecuencias: consume minutos de GitHub Actions (repo privado: cupo gratuito mensual; ~2-4 min por ejecución). Los avisos de análisis no bloquean hasta que T-002 los convierta en tareas.

## ADR-003 — Auto-fusión de PR de agentes con QA + CI en verde
- Estado: APROBADA (dueño, 2026-11-24)
- Contexto: la cola se detenía porque cada tarea esperaba un merge humano (p. ej. T-004..T-006 solo existían en el PR #9 sin fusionar).
- Decisión: el agente puede fusionar (squash, vía `gh api -X PUT .../pulls/N/merge`) su propio PR si: QA APROBADO; check `flutter-ci` en verde sobre el último commit; el PR no toca `.github/`, `.claude/`, `firestore.rules`, `storage.rules`, `firebase.json`, `pubspec.yaml` ni `CLAUDE.md`; y no contiene decisiones `PROPUESTA`. Todo lo demás queda en borrador para el humano. El guard solo permite el endpoint de merge y sigue bloqueando editar workflows y hooks, para que un agente no pueda debilitar el control que lo autoriza a fusionar.
- Consecuencias: cambios de código llegan a `main` sin revisión humana previa (no hay despliegue automático: desplegar sigue siendo del humano). Revertible quitando esta ADR y la excepción del guard.

