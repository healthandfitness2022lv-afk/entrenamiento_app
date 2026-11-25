# Diagnóstico de calidad (T-002)

- Fecha: 2026-11-25
- Fuente: check `flutter-ci` de GitHub Actions, run [45536767789](https://github.com/healthandfitness2022lv-afk/entrenamiento_app/actions/runs/45536767789) (job 138945176401), rama `claude/ci-flutter-automerge` (PR #10). Esa rama solo difiere de `main` en el workflow, hooks y docs: **el código Dart analizado es idéntico a `main`**.
- Entorno: Flutter stable 3.50.1 (ubuntu-latest). Las sesiones en la nube no pueden instalar Flutter (ADR-002).

## Resumen

| Comando | Resultado |
|---|---|
| `flutter pub get` | OK. 70 paquetes tienen versiones nuevas incompatibles con las restricciones actuales (`flutter pub outdated`). |
| `flutter analyze` | **0 errores**, 1 warning, 79 infos (80 en total). |
| `flutter test` | **35/35 en verde** (5 suites). Avisos no fatales del cargador SVG (`sodipodi:namedview`, `inkscape:perspective`, `defs`) en el test de PDF. |

### Análisis por regla

| Regla | Cant. | Gravedad real | Tarea |
|---|---|---|---|
| `use_build_context_synchronously` | 10 | **Alta**: uso de `context` tras `await` sin chequear `mounted` (p. ej. guardado del entrenamiento en `log_workout_screen.dart:1806`, asignar rutina, planner). Puede lanzar excepción o navegar con una pantalla ya cerrada. | T-007 (P1) |
| `unused_import` (warning) | 1 | Baja | T-008 |
| `avoid_print` | 3 | Baja (ruido en consola de producción, `planning_screen.dart`) | T-008 |
| `dangling_library_doc_comments` | 22 | Cosmética (todas en `lib/utils/notes.dart`) | T-008 |
| `curly_braces_in_flow_control_structures` | 20 | Cosmética | T-008 |
| `avoid_types_as_parameter_names` | 15 | Cosmética (`sum`, `count` en `fold`) | T-008 |
| Otras (`unnecessary_const`, `unnecessary_string_interpolations`, `use_super_parameters`, `prefer_final_fields`, `no_leading_underscores_for_local_identifiers`, `unnecessary_to_list_in_spreads`, `unintended_html_in_doc_comment`) | 9 | Cosmética | T-008 |

### Cobertura de tests
- 5 suites, 35 tests, todas sobre servicios de cálculo puro (identidad de entrenamiento, carga planificada, resumen de progreso, catálogo, PDF).
- ~101 archivos Dart / ~57.800 líneas en `lib/`; 31 servicios, de los cuales 5 tienen test. Sin tests para fatiga/recuperación, RM, volumen, guardado de entrenamiento, alertas ni ningún widget/pantalla. → T-009 (P2).

### Dependencias
- 70 paquetes con versiones mayores disponibles fuera de las restricciones. Actualizar versiones mayores puede romper la app: primero inventariar con `flutter pub outdated` en CI. → T-010 (P2). Cualquier salto mayor de Firebase se trata como decisión crítica.

## Salida completa de `flutter analyze`

```
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/add_workout_screen.dart:470:22 • avoid_types_as_parameter_names
info • Parameter 'key' could be a super parameter. Trying converting 'key' to a super parameter • lib/screens/admin_settings_screen.dart:8:9 • use_super_parameters
info • Statements in a for should be enclosed in a block. Try wrapping the statement in a block • lib/screens/admin_settings_screen.dart:53:45 • curly_braces_in_flow_control_structures
info • Statements in a for should be enclosed in a block. Try wrapping the statement in a block • lib/screens/admin_settings_screen.dart:54:50 • curly_braces_in_flow_control_structures
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/assign_routine_screen.dart:29:26 • use_build_context_synchronously
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/screens/exercise_rm_detail_screen.dart:875:7 • curly_braces_in_flow_control_structures
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/exercises_screen.dart:130:33 • use_build_context_synchronously
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/exercises_screen.dart:151:26 • use_build_context_synchronously
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/screens/exercises_screen.dart:410:25 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/screens/exercises_screen.dart:475:25 • curly_braces_in_flow_control_structures
info • The local variable '_fmt' starts with an underscore. Try renaming the variable to not start with an underscore • lib/screens/log_workout_screen.dart:856:12 • no_leading_underscores_for_local_identifiers
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/log_workout_screen.dart:1704:8 • avoid_types_as_parameter_names
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/log_workout_screen.dart:1806:16 • use_build_context_synchronously
info • Unnecessary use of string interpolation. Try replacing the string literal with the variable name • lib/screens/my_workout_details_screen.dart:1096:17 • unnecessary_string_interpolations
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/my_workout_details_screen.dart:1907:19 • avoid_types_as_parameter_names
info • Unnecessary 'const' keyword. Try removing the keyword • lib/screens/my_workout_details_screen.dart:2000:15 • unnecessary_const
info • Unnecessary 'const' keyword. Try removing the keyword • lib/screens/my_workout_details_screen.dart:2001:15 • unnecessary_const
info • The parameter name 'count' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/my_workouts_screen.dart:811:36 • avoid_types_as_parameter_names
info • Don't invoke 'print' in production code. Try using a logging framework • lib/screens/planning_screen.dart:216:5 • avoid_print
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/planning_screen.dart:291:16 • use_build_context_synchronously
info • Don't invoke 'print' in production code. Try using a logging framework • lib/screens/planning_screen.dart:336:5 • avoid_print
info • Don't invoke 'print' in production code. Try using a logging framework • lib/screens/planning_screen.dart:348:5 • avoid_print
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/planning_screen.dart:594:7 • use_build_context_synchronously
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/planning_screen.dart:747:50 • avoid_types_as_parameter_names
info • Statements in a for should be enclosed in a block. Try wrapping the statement in a block • lib/screens/planning_screen.dart:808:9 • curly_braces_in_flow_control_structures
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/planning_screen.dart:810:50 • avoid_types_as_parameter_names
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/planning_screen.dart:877:50 • avoid_types_as_parameter_names
info • The parameter name 'count' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/planning_screen.dart:2375:35 • avoid_types_as_parameter_names
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/planning_screen.dart:2753:16 • use_build_context_synchronously
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/planning_screen.dart:2786:22 • use_build_context_synchronously
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/screens/planning_screen.dart:2894:11 • curly_braces_in_flow_control_structures
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/planning_screen.dart:2924:50 • avoid_types_as_parameter_names
info • The private field _zoomed could be 'final'. Try making the field 'final' • lib/screens/planning_screen.dart:3576:8 • prefer_final_fields
info • Unnecessary use of string interpolation. Try replacing the string literal with the variable name • lib/screens/profile_screen.dart:677:17 • unnecessary_string_interpolations
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/screens/progress_screen.dart:730:9 • curly_braces_in_flow_control_structures
info • Angle brackets will be interpreted as HTML. Try using backticks around the content with angle brackets, or try replacing `<` with `&lt;` and `>` with `&gt;` • lib/screens/stats_screen.dart:70:23 • unintended_html_in_doc_comment
info • Statements in a for should be enclosed in a block. Try wrapping the statement in a block • lib/screens/stats_screen.dart:422:32 • curly_braces_in_flow_control_structures
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/unified_weekly_review_screen.dart:1582:34 • avoid_types_as_parameter_names
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/unified_weekly_review_screen.dart:1669:46 • avoid_types_as_parameter_names
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/screens/unified_weekly_review_screen.dart:1687:49 • avoid_types_as_parameter_names
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/screens/unified_weekly_review_screen.dart:1711:28 • use_build_context_synchronously
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/services/planned_workout_pdf_service.dart:1049:7 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/services/planned_workout_pdf_service.dart:1084:7 • curly_braces_in_flow_control_structures
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/services/progress_alert_service.dart:202:8 • avoid_types_as_parameter_names
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/services/training_review_service.dart:1554:23 • avoid_types_as_parameter_names
info • The parameter name 'sum' matches a visible type name. Try adding a name for the parameter or changing the parameter name to not match an existing type • lib/services/training_review_service.dart:1557:23 • avoid_types_as_parameter_names
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/services/workout_rm_service.dart:183:9 • curly_braces_in_flow_control_structures
warning • Unused import: 'dart:math'. Try removing the import directive • lib/services/workout_save_service.dart:5:8 • unused_import
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/services/workout_suggestion_service.dart:25:11 • curly_braces_in_flow_control_structures
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:1:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:2:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:3:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:4:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:5:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:6:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:7:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:8:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:9:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:10:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:11:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:12:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:13:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:14:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:15:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:16:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:17:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:18:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:19:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:20:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:21:1 • dangling_library_doc_comments
info • Dangling library doc comment. Add a 'library' directive after the library comment • lib/utils/notes.dart:22:1 • dangling_library_doc_comments
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/widgets/achievement_dialog.dart:45:19 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/widgets/achievement_dialog.dart:47:19 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/widgets/achievement_dialog.dart:49:19 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/widgets/achievement_dialog.dart:51:19 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/widgets/buscar_rm_block_widget.dart:238:41 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/widgets/floating_workout_overlay.dart:25:11 • curly_braces_in_flow_control_structures
info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/widgets/planner/library_sidebar.dart:100:9 • curly_braces_in_flow_control_structures
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/widgets/planner/library_sidebar.dart:159:35 • use_build_context_synchronously
info • Unnecessary use of 'toList' in a spread. Try removing the invocation of 'toList' • lib/widgets/planner/library_sidebar.dart:311:22 • unnecessary_to_list_in_spreads
80 issues found. (ran in 7.4s)
```

## Salida de `flutter test` (resumen)

```
00:00 +0: loading test/training_identity_service_test.dart
... (20 tests TrainingIdentityService, 6 planned_load_service, 3 progress_summary_equivalence, 1 planned_workout_pdf_service, 5 exercise_catalog)
unhandled element <sodipodi:namedview/>; Picture key: Svg loader
unhandled element <inkscape:perspective/>; Picture key: Svg loader
unhandled element <defs/>; Picture key: Svg loader
00:07 +35: All tests passed!
```
