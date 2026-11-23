# DECISIONS — Registro de decisiones (ADR)

Estados: `PROPUESTA` (requiere aprobación humana) · `APROBADA` · `RECHAZADA` · `SUPERADA`.
Solo el humano cambia `PROPUESTA` → `APROBADA/RECHAZADA`.

## ADR-001 — Adopción de Nexus AI
- Estado: APROBADA
- Fecha: 2026-11-15
- Contexto: operar el repo con agentes autónomos con revisión humana obligatoria.
- Decisión: agentes trabajan en ramas `claude/*` y entregan PRs en borrador; `main` protegida.
- Consecuencias: ningún cambio llega a producción sin merge humano.

## ADR-002 — Segmento, modelo de negocio y precios sugeridos
- Estado: PROPUESTA
- Fecha: 2026-11-22
- Contexto: T-003; detalle y fuentes en `docs/SALES.md`.
- Decisión propuesta: foco en personal trainers/coaches (10-40 alumnos). Suscripción mensual en CLP + IVA: Atleta $6.990, Coach (15 alumnos) $14.990, Coach Pro (40) $29.990, Equipo/Box desde $59.900 + instalación $150.000. Pago anual con 2 meses gratis; prueba 14 días.
- Consecuencias: compromete promesas a clientes; cobro automático (Webpay/Mercado Pago/Flow) sería otra decisión crítica (dependencia/costo). Requiere revisar reglas de Firebase y política de privacidad antes de onboardear clientes reales.
