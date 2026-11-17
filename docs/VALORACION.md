# VALORACIÓN — Valor de mercado y costo de desarrollo

> Mantenida por los agentes de Nexus AI. Se actualiza con cada módulo o mejora entregada (PR).
> Método: horas reales estimadas que tomaría desarrollar el módulo desde cero × tarifa base **$25.000 CLP/hora** (ver comercial/SERVICIOS.md en el repo nexus-ai). Incluye diseño, desarrollo, pruebas y documentación; no incluye hosting ni licencias.

## Valor de mercado (lo que se puede cobrar)
> Estimación comercial: cuánto pagaría un cliente por resolver su problema, según precios de alternativas en el mercado chileno (nov 2026). Las horas de abajo son solo el costo interno de desarrollo.

- **Qué resuelve:** Gestión de alumnos, rutinas y planes para gimnasios y personal trainers.
- **Competencia y precios de referencia:** GymMaster desde USD 25/mes, Fitco desde USD 79/mes, TeamUp/Mindbody ~USD 99/mes; en Chile BoxMagic y AgendaPro.
- **Precio a un cliente:** Gimnasio chico $30.000–$60.000/mes; personal trainer $10.000–$20.000/mes; instalación $150.000–$300.000
- **Venta exclusiva a un cliente:** $1.500.000 – $3.000.000 (app con la marca de un gimnasio)
- **Valor hoy como producto (sin clientes):** $4.000.000 – $8.000.000
- **Nota:** Mercado con competidores fuertes; el diferencial es precio local y app con la marca del propio gimnasio.
- Fuentes: apps.shopify.com/bsale · guiadesoftware.com/blog/mejor-software-gestion-inventario-pymes-latam · capterra.es (GymMaster, Fitco, Boxmagic) · zenoti.com/es/thecheckin/best-fitness-gym-software-2026 · ecosistemastartup.com (easycancha) · 2x3.cl/p/precios-desarrollo-aplicacion-movil


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
