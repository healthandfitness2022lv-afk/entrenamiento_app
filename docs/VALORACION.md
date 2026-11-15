# VALORACIÓN — Valor estimado del desarrollo

> Mantenida por los agentes de Nexus AI. Se actualiza con cada módulo o mejora entregada (PR).
> Método: horas reales estimadas que tomaría desarrollar el módulo desde cero × tarifa base **$25.000 CLP/hora** (ver comercial/SERVICIOS.md en el repo nexus-ai). Incluye diseño, desarrollo, pruebas y documentación; no incluye hosting ni licencias.

## Resumen
- **Valor total estimado: $20.450.000 CLP**
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
