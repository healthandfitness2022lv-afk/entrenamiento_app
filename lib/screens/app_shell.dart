import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'exercises_screen.dart';
import 'home_screen.dart';
import 'my_workouts_screen.dart';
import 'planning_screen.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import 'start_training_flow.dart';

/// Contenedor principal tras iniciar sesión.
///
/// - Celular: el inicio de siempre (hub con accesos + botón Entrenar).
/// - Tablet/PC: menú lateral fijo con las secciones. Cada sección tiene su
///   propio `Navigator`, así que al abrir un detalle el menú sigue visible y
///   al volver a la sección se conserva dónde estabas.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _Section {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;

  const _Section(this.label, this.icon, this.selectedIcon, this.builder);
}

class _AppShellState extends State<AppShell> {
  static final _sections = <_Section>[
    _Section(
      'Inicio',
      Icons.home_outlined,
      Icons.home_rounded,
      (_) => const HomeScreen(showNavigationShortcuts: false),
    ),
    _Section(
      'Historial',
      Icons.history_outlined,
      Icons.history_rounded,
      (_) => const MyWorkoutsScreen(),
    ),
    _Section(
      'Progreso',
      Icons.bar_chart_outlined,
      Icons.bar_chart_rounded,
      (_) => const ProgressScreen(),
    ),
    _Section(
      'Ejercicios',
      Icons.monitor_weight_outlined,
      Icons.monitor_weight_rounded,
      (_) => const ExercisesScreen(),
    ),
    _Section(
      'Planificación',
      Icons.calendar_month_outlined,
      Icons.calendar_month_rounded,
      (_) => const PlanningScreen(),
    ),
    _Section(
      'Perfil',
      Icons.person_outline_rounded,
      Icons.person_rounded,
      (_) => const ProfileScreen(),
    ),
  ];

  final _navigatorKeys = List.generate(
    _sections.length,
    (_) => GlobalKey<NavigatorState>(),
  );

  /// Uno por sección y creado una sola vez (no en cada build).
  final _heroControllers = List.generate(
    _sections.length,
    (_) => MaterialApp.createMaterialHeroController(),
  );

  @override
  void dispose() {
    for (final c in _heroControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Secciones ya abiertas: se construyen recién al visitarlas (Planificación
  /// y otras hacen consultas pesadas al montarse).
  final Set<int> _visited = {0};
  int _index = 0;

  void _select(int index) {
    if (index == _index) {
      // Tocar la sección activa vuelve a su pantalla inicial.
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  Future<void> _startTraining() async {
    // En el navegador raíz: la sesión ocupa toda la pantalla (sin menú).
    await startTrainingFlow(context, navigator: Navigator.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final size = context.screenSize;
    if (size == ScreenSize.compact) return const HomeScreen();

    final extended = size == ScreenSize.expanded;

    return PopScope(
      // Atrás (Android / navegador) retrocede dentro de la sección activa
      // antes de salir de la app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _navigatorKeys[_index].currentState;
        if (nav != null && await nav.maybePop()) return;
        if (_index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: extended,
              minExtendedWidth: 200,
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType:
                  extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child:
                    extended
                        ? FloatingActionButton.extended(
                          heroTag: 'shell-train',
                          onPressed: _startTraining,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text(
                            'Entrenar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        )
                        : FloatingActionButton(
                          heroTag: 'shell-train',
                          tooltip: 'Entrenar',
                          onPressed: _startTraining,
                          child: const Icon(Icons.play_arrow_rounded),
                        ),
              ),
              destinations: [
                for (final s in _sections)
                  NavigationRailDestination(
                    icon: Icon(s.icon),
                    selectedIcon: Icon(s.selectedIcon),
                    label: Text(s.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.divider),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    _visited.contains(i)
                        ? HeroControllerScope(
                          controller: _heroControllers[i],
                          child: Navigator(
                            key: _navigatorKeys[i],
                            onGenerateRoute:
                                (settings) => MaterialPageRoute(
                                  settings: settings,
                                  builder: _sections[i].builder,
                                ),
                          ),
                        )
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
