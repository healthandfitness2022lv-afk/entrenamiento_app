# SALES — Análisis comercial (T-003)

> Subagente `sales`. Fecha de consulta de precios: **2026-11-22**. Todo precio, plan o promesa de este documento es PROPUESTA (ver ADR-002 en `docs/DECISIONS.md`). Conversión referencial USD→CLP: ~950 (supuesto, no verificado; revisar el día de cotizar).

## 1. Qué es hoy el producto (según código y ARCHITECTURE.md)
App Flutter (Android + Web) + Firebase para registrar, planificar y analizar entrenamiento de fuerza.
Diferenciadores reales (hay código):
- Motor de fatiga y recuperación por músculo, con auditoría y heatmap corporal (`fatigue_*`, `muscle_recovery_service`, `muscle_catalog`).
- Planner semanal + PDF de rutina planificada (`planned_load_service`, `planned_workout_pdf_service`).
- Carga, volumen, RM y RPE con alertas de ajuste de carga (`workout_rm_service`, `rpe_factor_service`, `load_adjustment_alert_service`).
- Revisión semanal, perfil de entrenamiento, desequilibrios, correlación fatiga-rendimiento.
- Reportes de atleta/periodo en PDF y export de "story" compartible; logros.
- Sesiones en vivo y modo entrenador que elige atleta (`athlete_selection_service`, `live_session_service`).
- Catálogo de ejercicios editable con pesos musculares.

Lo que NO tiene (límite honesto para vender): agenda/reservas de clases, cobros/membresías, facturación/boleta, roles y permisos formales, portal propio del alumno ni marca blanca. Sin tests de pantallas/fatiga (riesgo, T-002 bloqueada).

## 2. Segmento objetivo (decisión)
| Opción | Encaje | Veredicto |
|---|---|---|
| **Personal trainer / coach de fuerza (online o presencial) con 10-40 alumnos** | Alto: planner, PDF, reportes, fatiga, modo entrenador | **ELEGIDO** |
| Box / gimnasio chico | Bajo hoy: lo que pagan es agenda, asistencia y cobro de mensualidades (BoxMagic, AgendaPro); no lo tenemos | Fase 2, como add-on de análisis |
| Atleta individual | Bajo ticket, mucha competencia gratis (Hevy), CAC alto | Plan de entrada barato, no foco |

Justificación: el coach paga porque ahorra horas armando planes y reportando, y retiene alumnos con evidencia (reportes, fatiga). Decide solo (una persona), ciclo de venta corto. El dolor: planillas Excel + WhatsApp, sin saber quién está sobrecargado.
Quién paga: el coach. Quién decide: el coach. Valor para él: retener 2-3 alumnos extra al mes ya paga la suscripción.

## 3. Propuesta de valor (una frase)
"Planifica a tus alumnos, mira qué músculos están fatigados y envíales un informe profesional por WhatsApp, todo en una app hecha en Chile y a precio en pesos."

## 4. Competidores (consulta 2026-11-22)
| Competidor | Precio verificado | Fuente | Estado |
|---|---|---|---|
| TrueCoach | Starter USD 26,34/mes (5 clientes), Standard USD 57,99 (20), Pro USD 136,99 (50); anual con 1-2 meses gratis | https://www.truecoach.co/pricing | Verificado |
| TrainingPeaks (atleta) | Premium USD 19,95/mes o USD 134,99/año; precios de coach no consultados | https://trainingpeaks.com/pricing/for-athletes/ | Verificado (atleta); coach no verificado |
| Trainerize | Free (1 cliente), Grow USD 9, Pro 5 USD 23 (desde); la página es inconsistente (USD 79 para 30-100 clientes, USD 135 hasta 50) | https://trainerize.com/pricing | Parcial: confirmar antes de citar |
| Hevy Coach | USD 25 (1-10 clientes), 50 (11-25), 90 (26-50), 160 (51-100); prueba gratis | https://www.capterra.com/p/10015732/Hevy-Coach/pricing/ | Verificado en Capterra (no en sitio Hevy) |
| BoxMagic (Chile/LatAm) | Desde 39.900/mes (Básico Plus Mid), 69.990/mes (Silver Mid), Gold a cotizar; la página no indica moneda | https://www.capterra.com/p/275373/Boxmagic/ | Moneda no verificada (probable CLP) |
| AgendaPro (Chile) | CLP + IVA/mes: Individual 15.900, Básico 34.900, Premium 54.900, Pro 249.900; 2 meses gratis en pago anual | https://agendapro.com/cl/planes | Verificado |
| GymMaster / Fitco / TeamUp / Mindbody | Citados en VALORACION previa; no re-verificados | — | No verificado |

Lectura: coaches en USD pagan ~USD 26-58/mes (~CLP 25.000-55.000) por 5-20 alumnos. Un precio en CLP por tramo de alumnos, más bajo y con facturación local, es competitivo. BoxMagic/AgendaPro compiten en agenda y cobros, no en análisis de carga: no pelear ahí.

## 5. Planes y precios sugeridos (CLP, netos + IVA 19%) — PROPUESTA
| Plan | Para quién | Precio/mes | Incluye |
|---|---|---|---|
| Atleta | Individuo | $6.990 | Registro, progreso, fatiga, RM/RPE, logros, story |
| Coach | Hasta 15 alumnos | $14.990 | Todo Atleta + modo entrenador, planner, PDF, reportes de atleta |
| Coach Pro | Hasta 40 alumnos | $29.990 | Coach + reportes de periodo, alertas de carga, soporte prioritario |
| Equipo / Box | Hasta 100 alumnos, varios entrenadores | desde $59.900 + instalación $150.000 | Coach Pro + onboarding y carga de ejercicios; marca blanca a cotizar ($1,5-3 M, ver VALORACION) |

Pago anual: 2 meses gratis (mismo mecanismo de AgendaPro). Prueba: 14 días sin tarjeta. Cobro inicial por transferencia/factura; medios de pago automáticos (Mercado Pago, Webpay OneClick, Flow) requieren integración = decisión crítica.
Referencia: Coach a $14.990 es ~40% bajo Hevy Coach 1-10 (USD 25 ≈ $23.750) y cubre más alumnos.

## 6. Canales de venta
1. Venta directa a coaches de Instagram/TikTok (demo de 15 min por videollamada, usando datos ficticios).
2. Comunidades de fuerza, powerlifting, calistenia y running en Chile; alianzas con 3-5 coaches influyentes (plan gratis por testimonio).
3. Story export como marketing viral: cada alumno comparte su story con marca de la app.
4. Univ./institutos de educación física y entrenadores de clubes deportivos (venta Equipo).
5. Referidos: 1 mes gratis por coach referido.

## 7. Riesgos
| Riesgo | Mitigación |
|---|---|
| Sin cobros/agenda: no sirve a boxes | Segmentar a coaches; evaluar integración a futuro |
| Calidad sin tests de pantallas/fatiga (T-002 bloqueada) | Desbloquear T-002 antes de vender a escala |
| Modelo multi-alumno basado en selección local de atleta, sin roles formales ni reglas verificadas en repo | Revisar `firestore.rules` en consola antes de onboardear clientes reales (decisión crítica) |
| Competidores globales baratos/gratis (Hevy, Trainerize Free) | Nicho: fatiga por músculo + español + CLP + factura |
| Datos de salud/entrenamiento de terceros | Política de privacidad y consentimiento (Ley 19.628/21.719) antes de comercializar |
| Precios USD de competidores cambian y Trainerize es inconsistente | Re-verificar antes de campaña |

## 8. Próximas mejoras por impacto comercial
Ver T-004, T-005, T-006 en `docs/TASKS.md`.
