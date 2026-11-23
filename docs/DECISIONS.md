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
- Estado: PROPUESTA
- Fecha: 2026-11-23
- Contexto: T-002 exige salida real de `flutter analyze` y `flutter test`. Las sesiones en la nube de los agentes no pueden instalar el SDK: la descarga del Dart SDK (Flutter engine 4d35714800b9) desde el almacenamiento de Google es rechazada por la política de red del proxy (`curl: (56) CONNECT tunnel failed, response 403`). Sin SDK, ningún agente puede validar código Flutter (también afecta a futuras tareas de implementación).
- Opciones:
  1. Agregar `.github/workflows/flutter-ci.yml` (subosito/flutter-action, canal stable) que corra `flutter pub get`, `flutter analyze` y `flutter test` en push a `claude/**` y en PRs a `main`. Los agentes leen el resultado con `gh api .../actions/runs`. Consume minutos de Actions (repo privado: cupo gratuito mensual; exceso es de pago).
  2. Permitir en la política de red el host de descarga del SDK (`storage.googleapis.com`) para las sesiones de agentes.
  3. El dueño ejecuta `flutter analyze` y `flutter test` localmente y pega la salida en el PR de T-002.
- Recomendación: opción 1 (deja verificación automática permanente para todas las tareas) o, si no se quiere gastar minutos, opción 2.
- Consecuencias: hasta decidir, T-002 queda BLOQUEADA y ninguna tarea de código puede pasar QA con tests reales.
