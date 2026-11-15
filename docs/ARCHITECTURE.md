# ARCHITECTURE

> Mantenido por el subagente `architect`. Refleja el código real (inspección T-001, 2026-11-15).

## Stack
- Flutter (SDK Dart ^3.7), Material con tema oscuro propio (`lib/theme/app_theme.dart`), locale `es_ES`.
- Firebase: Auth (`firebase_auth`), Firestore (`cloud_firestore`), proyecto `entrenamientoapplv`. Sin Storage ni Cloud Functions en el código.
- Plataformas: Android, iOS, Web, macOS, Windows, Linux (carpetas generadas; foco Android + Web).
- Librerías clave: `fl_chart` (gráficos), `table_calendar`, `pdf` + `printing` (PDF), `share_plus`, `gal` (guardar imágenes), `audioplayers` (sonidos de timer), `shared_preferences`, `flutter_animate`, `confetti`.
- Sin gestor de estado externo: `StatefulWidget` + `StreamBuilder`/`FutureBuilder` + un `ViewModel` (`log_workout_view_model.dart`).
- Tamaño: ~57.800 líneas Dart en 101 archivos (screens 31k, services 19k, widgets 4.6k, models 1.2k, utils 1k).

## Módulos principales (`lib/`)
- `main.dart` / `auth_gate.dart`: inicializa Firebase, splash y decide Login vs `AppShell` según `authStateChanges`.
- `screens/app_shell.dart`: navegación por pestañas (Entrenamientos, Progreso, Ejercicios, Planificación, Perfil), un `Navigator` por pestaña; `HomeScreen` en pantallas compactas.
- `screens/`: registro de entreno (`log_workout_screen`, `add_workout_screen`), rutinas, planificación semanal (`planning_screen`), progreso/estadísticas, revisión semanal unificada, carga semanal, auditoría de fatiga, logros, sesiones en vivo, alertas de ajuste de carga, administración/edición de catálogo de ejercicios.
- `services/` (lógica de negocio):
  - Persistencia de entrenos: `workout_save_service`, `workout_session_service`, `live_session_service`.
  - Fatiga y recuperación: `fatigue_service`, `fatigue_recalculation_service`, `muscle_recovery_service`, `fatigue_performance_correlation_service`.
  - Carga/volumen/RM: `workout_load_service`, `workout_volume_service`, `workout_rm_service`, `planned_load_service`, `rpe_factor_service`.
  - Análisis y reportes: `training_identity_service` (perfil de entrenamiento), `training_review_service`, `training_period_report_service`, `athlete_report_service`, `report_service`, `progress_summary_service`, `training_imbalance_service`, `progress_alert_service`, `load_adjustment_alert_service`, `workout_suggestion_service`.
  - Otros: `achievement_evaluator_service`, `planned_workout_pdf_service`, `exercise_catalog_service`, `athlete_selection_service` (entrenador que elige atleta), `tabata_timer_service`, `pending_work_service`.
- `models/`: `exercise`, `muscle_catalog` (catálogo de músculos y pesos; archivo crítico), `workout_set`, `achievement`, `routine_session_summary`.
- `widgets/`: bloques de serie/circuito/tabata/descendente/buscar-RM, heatmap corporal (SVG), overlay flotante de entreno, exportación de "story", planner (`widgets/planner/`).
- `utils/`: catálogos de ejercicios y variantes, normalización de nombres, RPE, entrada de peso, responsive.
- `scripts/` (raíz): ~56 scripts Node `.mjs` de mantenimiento/carga de datos sobre Firestore (crear planificaciones, migraciones, limpieza de duplicados). Tocan datos reales: los agentes NO deben ejecutarlos.

## Flujo de datos
Todo cuelga de `users/{uid}` en Firestore. Subcolecciones y colecciones usadas: `workouts_logged`, `planned_workouts`, `routines`, `routine_assignments`, `exercises`, `exercise_folders`, `exercise_instances`, `exercise_profile_overrides`, `blocks`, `block_folders`, `stats`, `achievements`, `fatigue_state` (doc `latest`), `fatigue_audit`, `load_adjustment_alerts`, `athlete_manual_rm`, `admin_settings`.
1. Planificación → `planned_workouts` (día/bloques).
2. Entreno: `LogWorkoutScreen` + `LogWorkoutViewModel` → `WorkoutSaveService` escribe en `workouts_logged`, y dispara cálculo de carga, alertas de ajuste, logros y recálculo de fatiga.
3. Fatiga: `FatigueRecalculationService` parte de `fatigue_state/latest`, aplica recuperación por músculo hasta la fecha (`FatigueService.recoverToNow`) y persiste el estado; las pantallas leen y recuperan "al vuelo".
4. Perfil/reportes: `TrainingIdentityService` mezcla `workouts_logged` (días realizados reemplazan lo planificado) con `planned_workouts`; los reportes se exportan a PDF/imagen.
- Reglas de dominio (PROJECT_CONTEXT.md): no duplicar logs, no recalcular fatiga sin pedirlo, preservar históricos, UI sin afectar lógica.

## Integraciones externas
- Firebase Auth + Firestore (reglas en consola; `firestore.indexes.json` versionado; no hay `firestore.rules` en el repo: cualquier cambio de reglas es decisión crítica).
- Hosting web en `build/web` (despliegue manual por el humano).
- CI: `.github/workflows/nexus-qa.yml` (revisión QA en PRs de ramas `claude/*`).

## Cómo se prueba
- `flutter pub get`, `flutter analyze`, `flutter test`.
- 5 suites en `test/` (~35 casos): catálogo de ejercicios, carga planificada, PDF planificado, equivalencia de resumen de progreso, identidad de entrenamiento. Cubren servicios puros; pantallas, guardado en Firestore y fatiga no tienen tests (riesgo, ver T-002).
- Nota: CLAUDE.md menciona "7 suites" en otros repos; aquí hay 5.
