---
name: nexus-run
description: Ejecuta un ciclo del equipo Nexus AI - toma la siguiente tarea de docs/TASKS.md, la planifica, implementa, prueba y entrega un PR en borrador. Úsalo en ejecuciones programadas o cuando el usuario diga "nexus run".
---
# Ciclo Nexus AI

Actúas como Director Técnico. Sigue exactamente el ciclo de CLAUDE.md.

1. **Contexto**: lee CLAUDE.md, docs/TASKS.md, últimas 10 líneas de docs/RUNLOG.md.
2. **Selección**: el estado real no siempre está en `main`. Antes de elegir, lista los PR abiertos (`gh api "repos/OWNER/REPO/pulls?state=open&per_page=100"`) y las ramas `claude/T-*` remotas, y lee su `docs/TASKS.md` (`git show origin/<rama>:docs/TASKS.md`).
   - **Primero, cerrar lo pendiente:** si hay un PR propio abierto que ya cumple la auto-fusión (paso 7b), fusiónalo y sigue; si tiene CI rojo o QA rechazado, esa es la tarea de esta ejecución (corrígelo en su rama).
   - Luego reanuda la tarea `EN_CURSO` o toma la `PENDIENTE` de mayor prioridad que no tenga ya un PR abierto ni esté `BLOQUEADA` en su rama.
   - Si no hay ninguna, termina con "sin trabajo" (no gastes más). Si todo está detenido esperando al humano (PR que no califican para auto-fusión o decisiones `PROPUESTA`), dilo explícitamente en el resumen final, con los PR y decisiones que necesitan al dueño.
3. **Rama**: `claude/T-xxx-slug`. Si existe en remoto, haz checkout y continúa desde el checkpoint.
4. **Plan**: si la tarea toca más de 2 archivos o cambia estructura → `architect`. Si hay una decisión crítica → regístrala como PROPUESTA y termina.
5. **Implementación**: `developer`. Checkpoint + commit + push tras cada paso.
6. **QA**: `qa` revisa el diff. Los tests y el análisis **no se corren en la sesión** (no hay Flutter en la nube): tras el push, espera el check `flutter-ci` del último commit:
   `gh api repos/OWNER/REPO/commits/$(git rev-parse HEAD)/check-runs --jq '.check_runs[] | select(.name=="flutter-ci") | "\(.status) \(.conclusion) \(.id)"'`
   Revisa cada ~60 s (máx. 15 min). Si falla, lee el log (`gh api repos/OWNER/REPO/actions/jobs/<id>/logs | tail -200`) y vuelve a `developer`. Si RECHAZADO o CI rojo tras 2 iteraciones → BLOQUEADA con el motivo. Si el check no aparece en 15 min, deja el PR en borrador y anótalo.
7. **Entrega**: abre el PR en borrador con la API REST (GraphQL no está disponible en sesiones en la nube, así que `gh pr create` falla):
   `gh api repos/OWNER/REPO/pulls -f title="T-xxx: ..." -f head="claude/T-xxx-slug" -f base="RAMA_POR_DEFECTO" -F draft=true -f body="$(cat /tmp/pr.md)"`
   El cuerpo incluye: resumen, archivos, cómo probar, riesgos, veredicto QA y estado de `flutter-ci`. Si la API falla, deja la rama publicada y reporta el enlace `https://github.com/OWNER/REPO/compare/RAMA_POR_DEFECTO...claude/T-xxx-slug`.
7b. **Auto-fusión (ADR-003)**: solo si se cumplen TODAS las condiciones de CLAUDE.md (QA APROBADO, `flutter-ci` success en el último commit, sin archivos protegidos, sin decisiones `PROPUESTA`). Comprueba los archivos con `gh api "repos/OWNER/REPO/pulls/N/files?per_page=100" --jq '.[].filename'`. Antes de fusionar, deja los docs (pasos 8 y 9, con la tarea `HECHA` y el enlace al PR) commiteados en la rama y espera de nuevo `flutter-ci` en verde para ese commit. Luego:
   `gh api -X POST repos/OWNER/REPO/pulls/N/ccr/ready_for_review` y `gh api -X PUT repos/OWNER/REPO/pulls/N/merge -f merge_method=squash -f sha=<sha del último commit>`.
   Si la fusión falla (conflicto, rama desactualizada), no fuerces nada: deja el PR en borrador, tarea `EN_REVISION`, y anótalo.
8. **Valoración**: actualiza `docs/VALORACION.md` en la misma rama. Lo principal es el **valor de mercado** (sección "Valor de mercado"): cuánto se puede cobrar por la necesidad que resuelve la app, comparando con precios reales de alternativas en Chile (con fuentes); si la mejora entregada permite cobrar más o vender a otro tipo de cliente, actualiza precio a cliente, venta exclusiva y "Valor hoy como producto" y explica por qué. Además, como costo interno, agrega una fila por el módulo o mejora entregada (horas estimadas desde cero × $25.000 CLP/h, enlace al PR), recalcula el valor total y las horas acumuladas, y escribe el valor en la columna "Valor (CLP)" de la tarea en TASKS.md. Si el archivo no existe o su valor total es $0, primero haz la **valoración inicial**: una fila por cada módulo que ya existe en el código (marcada "inicial" en la columna PR), con sus horas y valor, y recién después suma la mejora de esta ejecución.
9. **Cierre**: tarea → `HECHA` si se auto-fusionó, o `EN_REVISION` si queda para el humano; línea en RUNLOG; commit, push. Si la tarea queda `BLOQUEADA`, abre igual un PR en borrador con los docs para que el bloqueo sea visible desde `main`.

Presupuesto: respeta el campo "Presupuesto" de la tarea. Al acercarte, guarda checkpoint y termina.
