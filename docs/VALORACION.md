# VALORACIÓN — Valor de mercado y costo de desarrollo

> Mantenida por los agentes de Nexus AI. Se actualiza con cada módulo o mejora entregada (PR).
> Método: horas reales estimadas que tomaría desarrollar el módulo desde cero × tarifa base **$25.000 CLP/hora** (ver comercial/SERVICIOS.md en el repo nexus-ai). Incluye diseño, desarrollo, pruebas y documentación; no incluye hosting ni licencias.

## Valor de mercado (lo que se puede cobrar)
> Estimación comercial: cuánto pagaría un cliente por resolver su problema, según precios de alternativas en el mercado chileno (nov 2026). Las horas de abajo son solo el costo interno de desarrollo.

- **Qué resuelve:** Gestión de alumnos, rutinas y planes para gimnasios y personal trainers.
- **Segmento:** personal trainers/coaches de fuerza (10-40 alumnos). Detalle en `docs/SALES.md`.
- **Competencia y precios (consulta 2026-11-22):**
  - TrueCoach: USD 26,34 / 57,99 / 136,99 al mes (5 / 20 / 50 clientes) — https://www.truecoach.co/pricing
  - Hevy Coach: USD 25 (1-10), 50 (11-25), 90 (26-50), 160 (51-100) — https://www.capterra.com/p/10015732/Hevy-Coach/pricing/
  - TrainingPeaks Premium (atleta): USD 19,95/mes o 134,99/año — https://trainingpeaks.com/pricing/for-athletes/ (precios de coach no verificados)
  - Trainerize: Free, desde USD 9 y USD 23; página inconsistente, no confiable — https://trainerize.com/pricing
  - AgendaPro Chile: $15.900 / 34.900 / 54.900 / 249.900 + IVA al mes — https://agendapro.com/cl/planes
  - BoxMagic: desde 39.900 y 69.990 al mes (moneda no verificada, probable CLP) — https://www.capterra.com/p/275373/Boxmagic/
  - GymMaster, Fitco, TeamUp, Mindbody: cifras previas no verificadas.
- **Precio sugerido a un cliente (PROPUESTA, ADR-002), CLP + IVA/mes:** Atleta $6.990; Coach (15 alumnos) $14.990; Coach Pro (40) $29.990; Equipo/Box desde $59.900; instalación Equipo $150.000.
- **Venta exclusiva a un cliente:** $1.500.000 – $3.000.000 (app con marca de un gimnasio). Estimación interna, no verificada con mercado.
- **Valor hoy como producto (sin clientes):** $4.000.000 – $8.000.000. Estimación interna, no verificada.
- **Nota:** el diferencial es fatiga por músculo, español y precio en CLP; faltan agenda, cobros y facturación para competir con BoxMagic/AgendaPro.


## Resumen
- **Costo de desarrollo estimado (horas × tarifa): $20.450.000 CLP**
- Horas acumuladas: 818 h
- Última actualización: 2026-11-15 (valoración inicial + T-001)
- Referencia de mercado: apps de entrenamiento para atleta/entrenador se venden por suscripción, p. ej. TrainingPeaks (https://www.trainingpeaks.com/pricing) y TrueCoach. Precios no verificados en esta ejecución; revisar las páginas. El valor aquí es costo de reemplazo, no precio de venta.

## Módulos
| Módulo / mejora | Descripción breve | Horas | Valor (CLP) | Fecha | PR |
|---|---|---|---|---|---|
| Base app (auth, shell, tema, navegación, responsive) | Login Firebase, AppShell con pestañas, tema oscuro | 40 | 1.000.000 | 2026-11-15 | inicial |
| Registro de entrenamiento | Log de series/circuito/tabata/descendente/RM, timers, guardado en Firestore, sesiones en vivo | 160 | 4.000.000 | 2026-11-15 | inicial |
| Catálogo de ejercicios y variantes | Ejercicios, carpetas, bloques, perfiles, importación masiva, editor de pesos musculares | 80 | 2.000.000 | 2026-11-15 | inicial |
| Rutinas y planificación semanal | Rutinas, asignación, planner, carga planificada, PDF | 120 | 3.000.000 | 2026-11-15 | inicial |
| Motor de fatiga y recuperación | Modelo por músculo, recálculo, auditoría, heatmap corporal | 110 | 2.750.000 | 2026-11-15 | inicial |
| Carga, volumen y RM | Cálculo de carga, RPE, RM, alertas de ajuste y progresión | 80 | 2.000.000 | 2026-11-15 | inicial |
| Progreso, estadísticas y logros | Gráficos, resúmenes, logros, alertas de progreso | 90 | 2.250.000 | 2026-11-15 | inicial |
| Perfil de entrenamiento y revisión semanal | Identidad de entrenamiento, revisión unificada, desequilibrios | 70 | 1.750.000 | 2026-11-15 | inicial |
| Reportes de atleta/periodo, PDF y export de stories | Reportes extensos, PDF, imágenes compartibles | 40 | 1.000.000 | 2026-11-15 | inicial |
| Scripts de datos y tests | ~56 scripts Node, 5 suites de test | 20 | 500.000 | 2026-11-15 | inicial |
| T-001 Documentación de arquitectura | ARCHITECTURE.md, comandos, valoración inicial | 8 | 200.000 | 2026-11-15 | #6 |

## Notas
- Horas de módulos iniciales son estimaciones por tamaño de código (~57.800 líneas Dart) y complejidad; no son mediciones.
- Valor de venta sugerido como producto (instalación + mensualidad): por definir tras T-003.
