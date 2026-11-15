import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/tabata_timer_service.dart';
import 'add_workout_screen.dart';
import '../widgets/series_block_widget.dart';
import '../widgets/circuit_block_widget.dart';
import '../widgets/tabata_block_widget.dart';
import '../widgets/descending_series_block_widget.dart';
import '../widgets/buscar_rm_block_widget.dart';
import '../services/workout_save_service.dart';
import '../widgets/log_workout_dialogs.dart';
import '../screens/workout_summary_screen.dart';
import '../services/progress_summary_service.dart';
import '../services/workout_volume_service.dart';
import '../services/workout_session_service.dart';
import '../services/planned_routine_loader_service.dart';
import '../services/fatigue_recalculation_service.dart';
import '../models/exercise.dart';
import '../models/achievement.dart';
import '../utils/responsive.dart';

import '../view_models/log_workout_view_model.dart';

class LogWorkoutScreen extends StatefulWidget {
  final Map<String, dynamic>? existingWorkout;
  final DocumentReference? workoutRef;
  final DateTime? initialDate;
  final List<Map<String, dynamic>>? extraBlocks;

  const LogWorkoutScreen({
    super.key,
    this.existingWorkout,
    this.workoutRef,
    this.initialDate,
    this.extraBlocks,
  });

  @override
  State<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends State<LogWorkoutScreen>
    with TickerProviderStateMixin {
  late final LogWorkoutViewModel viewModel;

  List<Map<String, dynamic>> availableRoutines = [];
  bool get isEdit => widget.workoutRef != null;
  List<Map<String, dynamic>> availableExercisesCatalog = [];
  late final TabataTimerService tabataTimer;
  final Map<String, String> exerciseInstructionsCache = {};
  bool _saving = false;
  String _savingStep = "";
  Timer? _blockTickerTimer;
  final Set<int> _promptedBlocksForStop = {};
  DateTime _selectedDate = DateTime.now();
  int _currentBlockIndex = 0;
  bool _isPlannedSession = false;

  @override
  void dispose() {
    _blockTickerTimer?.cancel();
    viewModel.removeListener(_onViewModelChanged);
    if (tabataTimer.onBlockFinished == _onTabataFinished) {
      tabataTimer.onBlockFinished = null;
    }

    WorkoutSessionService().setViewingWorkoutScreen(false);

    // IMPORTANTE: NO disponemos viewModel ni tabataTimer aquí
    // si la sesión sigue activa en el WorkoutSessionService.
    // Solo se dispondrán cuando se llame a endWorkout().
    if (!WorkoutSessionService().isActive || isEdit) {
      // Si es edición o no hay sesión persistente, sí limpiamos
      if (isEdit) {
        tabataTimer.stop();
        viewModel.dispose();
      }
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    final session = WorkoutSessionService();

    if (session.isActive && !isEdit) {
      // Si ya hay una sesión activa (y no es edición), la retomamos
      viewModel = session.viewModel!;
      tabataTimer = session.tabataTimer!;
    } else {
      // Si no, creamos una nueva
      viewModel = LogWorkoutViewModel();
      tabataTimer = TabataTimerService();

      if (!isEdit) {
        // Solo registramos como sesión persistente si no es una edición
        session.startWorkout(viewModel, tabataTimer);
        final now = DateTime.now();
        viewModel.workoutStartedAt = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          now.hour,
          now.minute,
          now.second,
        );
        viewModel.workoutStartedAt =
            DateTime.now(); // 🔥 inicio automático (fecha ajustable via chip)
        _warnIfFatigueHigh();
      }
    }

    session.setViewingWorkoutScreen(true);
    viewModel.addListener(_onViewModelChanged);
    tabataTimer.onBlockFinished = _onTabataFinished;
    _loadExerciseCatalog();

    if (isEdit) {
      _loadWorkoutForEdit();
    } else if (widget.initialDate != null || viewModel.routine == null) {
      // Solo cargar inicial si no hay rutina (es sesión nueva)
      _loadInitialWorkout();
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    _checkBlockTimers();

    // Arrancar / detener el ticker según haya bloques corriendo
    final anyRunning = viewModel.blockStartTimes.keys.any(
      (i) => !viewModel.blockDurationSeconds.containsKey(i),
    );
    if (anyRunning && _blockTickerTimer == null) {
      _blockTickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!anyRunning) {
      _blockTickerTimer?.cancel();
      _blockTickerTimer = null;
    }
    setState(() {});
  }

  void _checkBlockTimers() {
    if (viewModel.routine == null) return;
    final blocks = viewModel.routine!['blocks'] as List;

    // 1. Preguntar por detener timers de bloques completados
    for (int i = 0; i < blocks.length; i++) {
      final isCompleted = _isSpecificBlockCompleted(i);
      if (isCompleted && viewModel.isBlockTimerRunning(i)) {
        if (!_promptedBlocksForStop.contains(i)) {
          _promptedBlocksForStop.add(i);
          _showStopTimerConfirmation(i);
        }
      } else if (!isCompleted) {
        _promptedBlocksForStop.remove(i);
      }
    }

    // 2. Iniciar timer del primer bloque no completado que no tenga timer
    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block['type'] == 'Tabata') continue; // Tabata tiene su propio timer

      if (!_isSpecificBlockCompleted(i)) {
        if (!viewModel.blockStartTimes.containsKey(i) &&
            !viewModel.blockDurationSeconds.containsKey(i) &&
            !viewModel.isBlockTimerPaused(i)) {
          viewModel.startBlockTimer(i);
          final title = blocks[i]['title'] ?? blocks[i]['type'] ?? "Bloque";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("🚀 Iniciando cronómetro: $title"),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        break; // Solo arrancamos el primero pendiente
      }
    }

    // 3. Auto-avanzar al siguiente bloque pendiente cuando el activo se completa
    if (_currentBlockIndex < blocks.length &&
        _isSpecificBlockCompleted(_currentBlockIndex)) {
      for (int i = _currentBlockIndex + 1; i < blocks.length; i++) {
        if (!_isSpecificBlockCompleted(i)) {
          _currentBlockIndex = i;
          break;
        }
      }
    }
  }

  /// Advierte (sin bloquear) si la fatiga global del atleta ya está al
  /// límite (>=85%, mismo umbral que marca `fatigue_audit_screen.dart`)
  /// antes de empezar una sesión nueva. Solo informativo: el usuario decide
  /// si continúa.
  Future<void> _warnIfFatigueHigh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final fatigue = await FatigueRecalculationService.readCurrentFatigue(
      uid: uid,
    );
    final globalFatigue = FatigueRecalculationService.calculateGlobalFatigue(
      fatigue,
    );
    if (globalFatigue < 85 || !mounted) return;

    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("⚠️ Fatiga muscular alta"),
            content: Text(
              "Tu fatiga global está en ${globalFatigue.toStringAsFixed(0)}%, "
              "al límite recomendado. Considera ajustar la intensidad o "
              "priorizar descanso.",
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Entendido, continuar"),
              ),
            ],
          ),
    );
  }

  Future<void> _showStopTimerConfirmation(int blockIndex) async {
    if (!mounted) return;
    final blocks = viewModel.routine?['blocks'] as List?;
    if (blocks == null || blockIndex >= blocks.length) return;

    final block = blocks[blockIndex];
    final title = block['title'] ?? block['type'] ?? "Bloque";

    final stop = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text("Bloque completado"),
            content: Text(
              "Has realizado todas las series del bloque \"$title\". ¿Deseas detener el temporizador?",
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                tooltip: "Cambiar variante",
                onPressed: _saving ? null : _showSessionVariantEditor,
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Mantener corriendo"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Detener"),
              ),
            ],
          ),
    );

    if (stop == true && mounted) {
      viewModel.stopBlockTimer(blockIndex);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Cronómetro de $title detenido."),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isSpecificBlockCompleted(int index) {
    if (viewModel.routine == null) return false;
    final block = viewModel.routine!['blocks'][index];
    final type = block['type'];

    if (type == 'Tabata') return tabataTimer.isCompleted(index);

    if (type == 'Circuito') {
      final completedRounds = _countCompletedCircuitRounds(index, block);
      final visibleRounds = viewModel.circuitoRound[index] ?? 1;
      return completedRounds >= visibleRounds;
    }

    // Series, Descendente, Buscar RM
    for (final ex in block['exercises']) {
      final name = viewModel.normalizeExerciseName(ex['name']);
      final key = "$index-$name";
      final sets = viewModel.seriesData[key] ?? [];
      if (sets.isEmpty) return false;
      for (final s in sets) {
        if (s['done'] != true) return false;
      }
    }
    return true;
  }

  /// Carga TODOS los bloques planificados para la fecha dada y los une en una sola
  /// estructura de "rutina" con múltiples bloques, compatible con el ViewModel.
  Future<Map<String, dynamic>?> _getPlannedRoutineForDate(DateTime date) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return PlannedRoutineLoaderService.loadRoutineForDate(
      athleteId: uid,
      date: date,
    );
  }

  void _onRepsSubmitted(String exercise, int reps) {
    viewModel.onRepsSubmitted(exercise, reps);
  }

  Widget _suggestedRepsText(String exercise, double weight) {
    final value = viewModel.getSuggestedReps(exercise, weight);

    if (value == null) {
      return const Text(
        "Sin historial para ese peso",
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Text(
      "Máx reps: $value",
      style: const TextStyle(
        fontSize: 12,
        color: Colors.blue,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _suggestedWeightText(String exercise, int reps) {
    final value = viewModel.getSuggestedWeight(exercise, reps);

    if (value == null) {
      return const Text(
        "Sin sugerencias",
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Text(
      "Sugerido: ${value.toStringAsFixed(1)} kg",
      style: const TextStyle(
        fontSize: 12,
        color: Colors.green,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Future<void> _loadExerciseCatalog() async {
    final snap =
        await FirebaseFirestore.instance
            .collection('exercises')
            .orderBy('name')
            .get();

    availableExercisesCatalog =
        snap.docs.where((d) => d.data()['mergedInto'] == null).map((d) {
          return {'id': d.id, ...d.data()};
        }).toList();
  }

  Map<String, dynamic>? _getExerciseFromCatalog(String name) {
    try {
      return availableExercisesCatalog.firstWhere((e) {
        if (viewModel.normalizeExerciseName(e['name']) == name) return true;
        final variants = e['variants'];
        if (variants is! List) return false;
        return variants.whereType<Map>().any((raw) {
          final label = (raw['label'] ?? '').toString();
          return '${e['name']} - $label' == name;
        });
      });
    } catch (_) {
      return null;
    }
  }

  void _loadWorkoutForEdit() {
    final workout = widget.existingWorkout!;

    viewModel.originalStartedAt =
        (workout['startedAt'] as Timestamp?)?.toDate();
    // Workouts legacy sin `finishedAt`: la fecha del registro es la mejor
    // referencia de cuándo terminó.
    viewModel.originalFinishedAt =
        (workout['finishedAt'] as Timestamp?)?.toDate() ??
        (workout['date'] as Timestamp?)?.toDate();
    viewModel.originalDurationMinutes =
        (workout['durationMinutes'] as num?)?.toInt();

    final performed =
        (workout['performed'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    viewModel.routine = {
      'id': workout['blockId'],
      'name':
          workout['blockTitle'] ?? workout['routineName'] ?? 'Entrenamiento',
      'blocks': _rebuildBlocksFromPerformed(performed),
    };

    viewModel.initializeRoutineState(isEdit: isEdit);
    viewModel.hydrateFromPerformed(performed, tabataTimer);

    if (mounted) setState(() => viewModel.loading = false);
  }

  List<Map<String, dynamic>> _rebuildBlocksFromPerformed(
    List<Map<String, dynamic>> performed,
  ) {
    final Map<int, Map<String, dynamic>> blocksMap = {};

    for (final e in performed) {
      final String type = (e['type'] ?? '').toString();
      final int blockIndex = (e['blockIndex'] as num?)?.toInt() ?? 0;

      blocksMap.putIfAbsent(blockIndex, () {
        return {
          'type': type,
          'title': e['blockTitle'],
          'exercises': <Map<String, dynamic>>[],
        };
      });

      // ================= SERIES Y DESCENDENTES =================
      if (type == 'Series' ||
          type == 'Series descendentes' ||
          type == 'Buscar RM') {
        final List exList = (e['exercises'] as List?) ?? const [];

        for (final ex in exList) {
          if (ex is! Map) continue;

          final String name = viewModel.normalizeExerciseName(ex['exercise']);

          final List sets = (ex['sets'] as List?) ?? const [];

          if (name.isEmpty || sets.isEmpty) continue;

          if (type == 'Series descendentes') {
            blocksMap[blockIndex]!['schema'] =
                sets.map((s) => s['reps'] as int).toList();
          }
          if (type == 'Buscar RM') {
            blocksMap[blockIndex]!['rm'] =
                sets.isNotEmpty ? sets.last['reps'] as int : 5;
          }

          blocksMap[blockIndex]!['exercises'].add({
            'name': name,
            ..._loggedIdentity(ex),
            'series': sets.length,
            'reps': (sets.first as Map)['reps'],
            'valueType': 'reps',
            'weight': (sets.first as Map)['weight'],
            'perSide': ex['perSide'] == true,
          });
        }
      }

      // ================= CIRCUITO =================
      if (type == 'Circuito') {
        blocksMap[blockIndex] = {
          'type': 'Circuito',
          'title': e['blockTitle'],
          'rounds': (e['rounds'] as List?)?.length ?? 1,
          'exercises': _extractCircuitExercises(e),
        };
      }

      // ================= TABATA =================
      if (type == 'Tabata') {
        blocksMap[blockIndex] = {
          'type': 'Tabata',
          'title': e['blockTitle'],
          'work': e['work'],
          'rest': e['rest'],
          'rounds': e['rounds'],
          'exercises':
              (e['exercises'] as List?)?.map((x) {
                final logged = x as Map;
                return {'name': logged['exercise'], ..._loggedIdentity(logged)};
              }).toList() ??
              [],
        };
      }
    }

    final sortedKeys = blocksMap.keys.toList()..sort();
    return sortedKeys.map((k) => blocksMap[k]!).toList();
  }

  List<Map<String, dynamic>> _extractCircuitExercises(Map<String, dynamic> e) {
    final List<Map<String, dynamic>> exercises = [];

    final roundsRaw = (e['rounds'] as List?) ?? const [];

    for (final r in roundsRaw) {
      final exs = (r['exercises'] as List?) ?? const [];

      for (final ex in exs) {
        final name = viewModel.normalizeExerciseName(ex['exercise']);

        if (!exercises.any((x) => x['name'] == name)) {
          exercises.add({
            'name': name,
            'reps': ex['reps'] ?? 1,
            ..._loggedIdentity(ex as Map),
          });
        }
      }
    }

    return exercises;
  }

  Map<String, dynamic> _loggedIdentity(Map source) => {
    for (final key in const [
      'exerciseId',
      'movementId',
      'movementName',
      'variantId',
      'variantLabel',
      'displayName',
      'equipment',
      'resistanceType',
      'trackRM',
      'isUnilateral',
      'muscleWeightOverrides',
    ])
      if (source[key] != null) key: source[key],
  };

  // ================= HELPERS =================

  bool _isPerSide(Map<String, dynamic> ex) {
    return ex['perSide'] == true;
  }

  String? _getEquipment(Map<String, dynamic> ex) {
    return ex['equipment'];
  }

  Future<String?> _getExerciseInstructions(String exerciseName) async {
    final snap =
        await FirebaseFirestore.instance
            .collection('exercises')
            .where('name', isEqualTo: exerciseName)
            .limit(1)
            .get();

    final canonical = snap.docs.where(
      (doc) => doc.data()['mergedInto'] == null,
    );
    if (canonical.isEmpty) return null;

    final instructions = canonical.first.data()['instructions'];
    return instructions is String ? instructions : null;
  }

  // ================= LOAD =================

  /// Carga todos los bloques disponibles en segundo plano para el selector.
  Future<void> _loadAvailableRoutinesBackground() async {
    final blocksSnap =
        await FirebaseFirestore.instance
            .collection('blocks')
            .orderBy('createdAt', descending: true)
            .get();

    availableRoutines.clear();

    for (final d in blocksSnap.docs) {
      final data = d.data();
      final title = (data['title'] ?? '').toString().trim();
      final type = (data['type'] ?? 'Bloque').toString();
      // Envolvemos el bloque individual en el formato que espera el ViewModel
      availableRoutines.add({
        'id': d.id,
        'name': title.isNotEmpty ? title : type,
        'blocks': [data],
      });
    }
  }

  Future<void> _loadInitialWorkout() async {
    if (widget.initialDate != null) {
      final now = DateTime.now();
      viewModel.workoutStartedAt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        now.hour,
        now.minute,
        now.second,
      );
    }
    final plannedRoutine = await _getPlannedRoutineForDate(_selectedDate);

    // Cargar las demás en segundo plano para el selector desplegable
    await _loadAvailableRoutinesBackground();

    final extraBlocks = widget.extraBlocks ?? const [];

    if (plannedRoutine != null) {
      _isPlannedSession = true;
      final blocks = List<Map<String, dynamic>>.from(
        plannedRoutine['blocks'] ?? const [],
      )..addAll(extraBlocks);
      _changeRoutine({
        'id': plannedRoutine['id'],
        ...plannedRoutine,
        'blocks': blocks,
      });
    } else if (extraBlocks.isNotEmpty) {
      _isPlannedSession = true;
      _changeRoutine({
        'id': null,
        'name': 'Recuperación',
        'blocks': extraBlocks,
      });
    } else {
      _startFreeWorkout();
    }
  }

  void _changeRoutine(Map<String, dynamic>? newRoutine) {
    viewModel.seriesData.clear();
    viewModel.seriesRepsCtrl.clear();
    viewModel.seriesWeightCtrl.clear();
    viewModel.expandedBlocks.clear();
    viewModel.circuitoRound.clear();
    viewModel.circuitoReps.clear();
    viewModel.circuitoWeight.clear();
    viewModel.circuitoRpePorRonda.clear();
    viewModel.circuitoDone.clear();
    viewModel.circuitoPerSide.clear();
    tabataTimer.stop();

    if (newRoutine == null) {
      viewModel.routine = {
        'id': null,
        'name': 'Entrenamiento libre',
        'blocks': <Map<String, dynamic>>[],
      };
    } else {
      viewModel.routine = newRoutine;
    }

    viewModel.initializeRoutineState(isEdit: isEdit);
    if (mounted) setState(() => viewModel.loading = false);
  }

  // ================= NAVEGACIÓN ENTRE BLOQUES =================

  String _blockTabLabel(Map<String, dynamic> block) {
    final title = (block['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) return title;
    return (block['type'] ?? 'Bloque').toString();
  }

  Widget _buildBlockTabs() {
    final blocks = viewModel.routine!['blocks'] as List;
    if (blocks.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: blocks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final block = blocks[i] as Map<String, dynamic>;
          final bool isActive = i == _currentBlockIndex;
          final bool isCompleted = _isSpecificBlockCompleted(i);

          return ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCompleted) ...[
                  const Icon(Icons.check_circle, size: 16),
                  const SizedBox(width: 4),
                ],
                Text(_blockTabLabel(block)),
              ],
            ),
            selected: isActive,
            selectedColor: theme.colorScheme.primary.withOpacity(0.25),
            onSelected: (_) => setState(() => _currentBlockIndex = i),
          );
        },
      ),
    );
  }

  List<Widget> _buildActiveBlockContent(int i) {
    final block = viewModel.routine!['blocks'][i];
    final type = block['type'];

    return [
      _blockHeader(i, block),
      if (type == 'Circuito')
        CircuitBlockWidget(
          index: i,
          block: block,
          expanded: true,
          circuitoRound: viewModel.circuitoRound,
          circuitoReps: viewModel.circuitoReps,
          circuitoWeight: viewModel.circuitoWeight,
          circuitoRpePorRonda: viewModel.circuitoRpePorRonda,
          circuitoDone: viewModel.circuitoDone,
          normalizeExerciseName: viewModel.normalizeExerciseName,
          circuitoPerSide: viewModel.circuitoPerSide,
          onStateChanged: () => setState(() {}),
          onChangeVariant: _changeVariantFor,
        ),
      if (type == 'Series')
        SeriesBlockWidget(
          index: i,
          block: block,
          expanded: true,
          seriesData: viewModel.seriesData,
          seriesRepsCtrl: viewModel.seriesRepsCtrl,
          seriesWeightCtrl: viewModel.seriesWeightCtrl,
          normalizeExerciseName: viewModel.normalizeExerciseName,
          getEquipment: _getEquipment,
          isPerSide: _isPerSide,
          onInfoPressed: _showExerciseInfo,
          onDeleteExercise: _confirmDeleteExercise,
          onAddExercise: _addExerciseToSeries,
          onRepsSubmitted: _onRepsSubmitted,
          suggestedWeightText: _suggestedWeightText,
          suggestedRepsText: _suggestedRepsText,
          onStateChanged: () => setState(() {}),
          onChangeVariant: _changeVariantFor,
        ),
      if (type == 'Series descendentes')
        DescendingSeriesBlockWidget(
          index: i,
          block: block,
          expanded: true,
          seriesData: viewModel.seriesData,
          seriesRepsCtrl: viewModel.seriesRepsCtrl,
          seriesWeightCtrl: viewModel.seriesWeightCtrl,
          normalizeExerciseName: viewModel.normalizeExerciseName,
          isPerSide: _isPerSide,
          onInfoPressed: _showExerciseInfo,
          onStateChanged: () => setState(() {}),
        ),
      if (type == 'Buscar RM')
        BuscarRmBlockWidget(
          index: i,
          block: block,
          expanded: true,
          seriesData: viewModel.seriesData,
          seriesRepsCtrl: viewModel.seriesRepsCtrl,
          seriesWeightCtrl: viewModel.seriesWeightCtrl,
          normalizeExerciseName: viewModel.normalizeExerciseName,
          isPerSide: _isPerSide,
          onInfoPressed: _showExerciseInfo,
          onStateChanged: () => setState(() {}),
        ),
      if (type == 'Tabata')
        TabataBlockWidget(
          index: i,
          block: block,
          expanded: true,
          tabataTimer: tabataTimer,
          onStartTabata:
              (blockIdx, blk) => _startTabata(blockIndex: blockIdx, block: blk),
          onSkipTabata: _skipTabata,
        ),
    ];
  }

  Widget _buildBlockNavButtons() {
    final blocks = viewModel.routine!['blocks'] as List;
    final bool hasPrev = _currentBlockIndex > 0;
    final bool hasNext = _currentBlockIndex < blocks.length - 1;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.chevron_left),
            label: const Text('Anterior'),
            onPressed:
                hasPrev ? () => setState(() => _currentBlockIndex--) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.chevron_right),
            label: const Text('Siguiente'),
            onPressed:
                hasNext ? () => setState(() => _currentBlockIndex++) : null,
          ),
        ),
      ],
    );
  }

  // ================= INFO =================

  void _showExerciseInfo(Map<String, dynamic> ex) async {
    final String name = viewModel.normalizeExerciseName(ex['name']);
    await LogWorkoutDialogs.showExerciseInfo(
      context: context,
      name: name,
      fetchInstructions: _getExerciseInstructions,
    );
  }

  // ================= HEADER BLOQUE =================

  Widget _blockHeader(int index, Map<String, dynamic> block) {
    final bool expanded = viewModel.expandedBlocks[index] ?? false;
    final theme = Theme.of(context);
    final String blockType = (block['type'] ?? 'Bloque').toString();
    final String blockTitle =
        (block['title'] as String?)?.trim().isNotEmpty == true
            ? block['title'] as String
            : blockType;
    final bool timerRunning = viewModel.isBlockTimerRunning(index);
    final bool timerStarted = viewModel.blockStartTimes.containsKey(index);
    final int elapsed = viewModel.elapsedSecondsForBlock(index);
    final bool timerFinished = timerStarted && !timerRunning;

    // Formato mm:ss
    String _fmt(int secs) {
      final m = secs ~/ 60;
      final s = secs % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return InkWell(
      onTap: () {
        setState(() {
          viewModel.expandedBlocks[index] = !expanded;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                timerRunning
                    ? theme.colorScheme.primary
                    : expanded
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primary.withOpacity(0.25),
            width: timerRunning ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(blockTitle, style: theme.textTheme.titleLarge),
                ),
                // Cronometro en vivo
                if (timerStarted || viewModel.isBlockTimerPaused(index))
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          timerRunning
                              ? theme.colorScheme.primary.withOpacity(0.15)
                              : viewModel.isBlockTimerPaused(index)
                              ? Colors.orange.withOpacity(0.15)
                              : Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          timerRunning
                              ? Icons.timer
                              : viewModel.isBlockTimerPaused(index)
                              ? Icons.pause_circle_filled
                              : Icons.timer_off,
                          size: 16,
                          color:
                              timerRunning
                                  ? theme.colorScheme.primary
                                  : viewModel.isBlockTimerPaused(index)
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _fmt(elapsed),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color:
                                timerRunning
                                    ? theme.colorScheme.primary
                                    : viewModel.isBlockTimerPaused(index)
                                    ? Colors.orange
                                    : Colors.green,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                // 🗑️ Eliminar bloque
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: "Eliminar bloque",
                  onPressed: () => _confirmDeleteBlock(index),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
            // Boton Comenzar / Detener bloque
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  if (timerRunning)
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text('Pausar'),
                        onPressed: () => viewModel.pauseBlockTimer(index),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    )
                  else if (viewModel.isBlockTimerPaused(index))
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Reanudar'),
                        onPressed: () => viewModel.startBlockTimer(index),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    )
                  else if (timerFinished)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('Reiniciar cronómetro'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(color: theme.colorScheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => viewModel.startBlockTimer(index),
                      ),
                    )
                  else
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Comenzar bloque'),
                        onPressed: () => viewModel.startBlockTimer(index),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  if (timerRunning || viewModel.isBlockTimerPaused(index)) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.stop_circle,
                        color: Colors.red,
                        size: 32,
                      ),
                      onPressed: () => viewModel.stopBlockTimer(index),
                      tooltip: "Detener bloque",
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addExerciseToSeries(int blockIndex) async {
    final block = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder:
            (_) => AddWorkoutScreen(
              initialBlock: viewModel.routine!['blocks'][blockIndex],
            ),
      ),
    );

    if (block == null) return;

    setState(() {
      viewModel.routine!['blocks'][blockIndex] = block;

      for (final ex in block['exercises']) {
        _initSeriesDataForNewExercise(blockIndex, ex);
      }
    });
  }

  void _initSeriesDataForNewExercise(int blockIndex, Map<String, dynamic> ex) {
    final name = viewModel.normalizeExerciseName(ex["name"]);
    final key = "$blockIndex-$name";

    if (viewModel.seriesData.containsKey(key)) return;

    final String valueType = ex["valueType"] ?? "reps";
    final int baseValue = ex["value"] ?? ex["reps"] ?? 0;
    final plannedSets =
        ex['sets'] is List
            ? List<Map<String, dynamic>>.from(ex['sets'])
            : const <Map<String, dynamic>>[];
    final int sets =
        plannedSets.isNotEmpty ? plannedSets.length : ex["series"] ?? 1;

    viewModel.seriesData[key] = List.generate(
      sets,
      (setIndex) => {
        'valueType': valueType,
        'value':
            plannedSets.isNotEmpty
                ? plannedSets[setIndex]['reps'] ?? baseValue
                : baseValue,
        'reps':
            valueType == "reps"
                ? plannedSets.isNotEmpty
                    ? plannedSets[setIndex]['reps'] ?? baseValue
                    : baseValue
                : null,
        'weight':
            plannedSets.isNotEmpty
                ? plannedSets[setIndex]['weight'] ?? ex["weight"]
                : ex["weight"],
        'rpe': 5,
        'done': false,
      },
    );

    viewModel.seriesRepsCtrl[key] = List.generate(
      sets,
      (setIndex) => TextEditingController(
        text:
            (plannedSets.isNotEmpty
                    ? plannedSets[setIndex]['reps'] ?? baseValue
                    : baseValue)
                .toString(),
      ),
    );

    viewModel.seriesWeightCtrl[key] = List.generate(
      sets,
      (setIndex) => TextEditingController(
        text:
            (plannedSets.isNotEmpty
                    ? plannedSets[setIndex]['weight'] ?? ex["weight"]
                    : ex["weight"])
                ?.toString() ??
            "",
      ),
    );

    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteExercise(
    int blockIndex,
    String exerciseName,
  ) async {
    final ok = await LogWorkoutDialogs.confirmDeleteExercise(
      context: context,
      exerciseName: exerciseName,
    );

    if (ok) {
      setState(() {
        viewModel.routine!['blocks'][blockIndex]['exercises'].removeWhere(
          (e) => viewModel.normalizeExerciseName(e['name']) == exerciseName,
        );

        viewModel.seriesData.remove("$blockIndex-$exerciseName");
        viewModel.seriesRepsCtrl.remove("$blockIndex-$exerciseName");
        viewModel.seriesWeightCtrl.remove("$blockIndex-$exerciseName");
      });
    }
  }

  void _startTabata({
    required int blockIndex,
    required Map<String, dynamic> block,
  }) {
    tabataTimer.startBlock(
      blockIndex: blockIndex,
      workSeconds: block['work'],
      restSeconds: block['rest'],
      rounds: block['rounds'],
      exercises: List<Map<String, dynamic>>.from(block['exercises']),
    );
  }

  void _skipTabata() async {
    tabataTimer.stop();
    final blocks = viewModel.routine!['blocks'] as List;
    final active = tabataTimer.activeBlockIndex;
    final int blockIndex =
        active != null && active < blocks.length
            ? active
            : blocks.indexWhere((b) => b['type'] == 'Tabata');
    if (blockIndex == -1) return;
    final block = blocks[blockIndex];
    await _askTabataRpe(blockIndex, block);
  }

  /// El Tabata terminó solo: sin RPE el bloque no se guarda, así que se pide.
  void _onTabataFinished(int blockIndex) {
    if (!mounted) return;
    final blocks = viewModel.routine?['blocks'] as List?;
    if (blocks == null || blockIndex >= blocks.length) return;
    final block = Map<String, dynamic>.from(blocks[blockIndex] as Map);
    _askTabataRpe(blockIndex, block);
  }

  Future<void> _askTabataRpe(int blockIndex, Map<String, dynamic> block) async {
    final Map<String, int> rpeByExercise = {};
    for (final ex in block['exercises']) {
      final rpe = await LogWorkoutDialogs.askTabataRpe(
        context: context,
        exerciseName: ex['name'],
      );
      if (rpe != null) rpeByExercise[ex['name']] = rpe;
    }
    tabataTimer.completeBlockWithRpe(blockIndex, rpeByExercise);
  }

  void _showAddBlockOptions() {
    LogWorkoutDialogs.showAddBlockOptions(
      context: context,
      onBlockAdded: (block) {
        setState(() {
          viewModel.routine!['blocks'].add(block);
          final index = viewModel.routine!['blocks'].length - 1;
          viewModel.expandedBlocks[index] = true;
          _initializeBlockState(index, block);
        });
      },
      onAddPlannedFromDate: _pickDateAndAppendBlocks,
    );
  }

  Future<void> _pickDateAndAppendBlocks() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: "Selecciona el día a importar",
    );
    if (picked == null || !mounted) return;
    await _appendBlocksFromDate(picked);
  }

  void _initializeBlockState(int index, Map<String, dynamic> block) {
    if (block['type'] == 'Series') {
      for (final ex in block['exercises']) {
        _initSeriesDataForNewExercise(index, ex);
      }
    }

    if (block['type'] == 'Circuito') {
      viewModel.circuitoRound[index] = 1;
      viewModel.circuitoReps[index] = {};
      viewModel.circuitoWeight[index] = {};
      viewModel.circuitoRpePorRonda[index] = {};
      viewModel.circuitoDone[index] = {};
    }

    if (block['type'] == 'Series descendentes') {
      final schema = List<int>.from(block['schema'] ?? []);
      for (final ex in block['exercises']) {
        final name = viewModel.normalizeExerciseName(ex['name']);
        final key = "$index-$name";

        viewModel.seriesData[key] =
            schema
                .map(
                  (reps) => {
                    'valueType': 'reps',
                    'value': reps,
                    'reps': reps,
                    'weight': ex['weight'],
                    'rpe': 5,
                    'done': false,
                  },
                )
                .toList();

        viewModel.seriesRepsCtrl[key] =
            schema
                .map((reps) => TextEditingController(text: reps.toString()))
                .toList();
        viewModel.seriesWeightCtrl[key] =
            schema
                .map(
                  (_) => TextEditingController(
                    text: ex['weight']?.toString() ?? '',
                  ),
                )
                .toList();
      }
    }

    if (block['type'] == 'Buscar RM') {
      final int rmTarget = block['rm'] ?? 5;
      for (final ex in block['exercises']) {
        final name = viewModel.normalizeExerciseName(ex['name']);
        final key = "$index-$name";
        final int targetReps = ex['reps'] ?? rmTarget;

        viewModel.seriesData[key] = [
          {
            'valueType': 'reps',
            'value': targetReps,
            'reps': targetReps,
            'weight': ex['weight'],
            'rpe': 5,
            'done': false,
          },
        ];

        viewModel.seriesRepsCtrl[key] = [
          TextEditingController(text: targetReps.toString()),
        ];
        viewModel.seriesWeightCtrl[key] = [
          TextEditingController(text: ex['weight']?.toString() ?? ''),
        ];
      }
    }
  }

  Future<void> _confirmDeleteBlock(int index) async {
    final ok = await LogWorkoutDialogs.confirmDeleteBlock(context);
    if (!ok) return;

    setState(() {
      viewModel.routine!['blocks'].removeAt(index);
      viewModel.expandedBlocks.remove(index);
      viewModel.circuitoRound.remove(index);
      viewModel.circuitoReps.remove(index);
      viewModel.circuitoWeight.remove(index);
      viewModel.circuitoRpePorRonda.remove(index);
      viewModel.circuitoDone.remove(index);
      // Limpiar cronómetros del bloque eliminado
      viewModel.blockStartTimes.remove(index);
      viewModel.blockDurationSeconds.remove(index);
      tabataTimer.resetBlock(index);
      viewModel.reindexStateAfterDeletion(index);

      final remaining = (viewModel.routine!['blocks'] as List).length;
      if (_currentBlockIndex >= remaining) {
        _currentBlockIndex = remaining == 0 ? 0 : remaining - 1;
      }
    });
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    if (viewModel.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (viewModel.routine == null) {
      return const Scaffold(
        body: Center(child: Text("Selecciona una rutina para comenzar")),
      );
    }

    if (viewModel.routine == null && availableRoutines.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("No tienes rutinas asignadas")),
      );
    }

    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          WorkoutSessionService().setViewingWorkoutScreen(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title:
              _isPlannedSession
                  ? Text(
                    viewModel.routine?['name'] ?? 'Entrenamiento libre',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                  : GestureDetector(
                    onTap: _showRoutineSelectorSheet,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            viewModel.routine?['name'] ?? 'Entrenamiento libre',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down_rounded, size: 28),
                      ],
                    ),
                  ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent),
              tooltip: "Cancelar entrenamiento",
              onPressed: _saving ? null : _confirmCancel,
            ),
            if (!_isPlannedSession)
              IconButton(
                icon: const Icon(Icons.add_box_outlined),
                tooltip: "Agregar bloque",
                onPressed: _saving ? null : _showAddBlockOptions,
              ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.2,
                child: Image.asset(
                  'assets/images/people_training_1.png',
                  fit: BoxFit.cover,
                  colorBlendMode: BlendMode.darken,
                  color: Colors.black54,
                ),
              ),
            ),
            ListView(
              // En PC/tablet las series no se estiran a 1900 px (los campos
              // de reps/kg quedaban lejísimos de su etiqueta).
              padding: centeredListPadding(
                context,
                maxWidth: 900,
                vertical: 16,
              ),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isEdit && !_isPlannedSession)
                      ActionChip(
                        avatar: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_formatDate(_selectedDate)),
                        onPressed: _saving ? null : _pickWorkoutDate,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildBlockTabs(),
                const SizedBox(height: 16),
                if (_currentBlockIndex < viewModel.routine!['blocks'].length)
                  ..._buildActiveBlockContent(_currentBlockIndex),
                const SizedBox(height: 16),
                _buildBlockNavButtons(),
                const SizedBox(height: 16),
                // Siempre visible: se puede terminar aunque falten series
                // (el diálogo avisa cuáles no se guardarán).
                ElevatedButton.icon(
                  icon:
                      _saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.check_circle),
                  label: Text(
                    _saving ? _savingStep : "Finalizar entrenamiento",
                  ),
                  onPressed: _saving ? null : _confirmFinish,
                ),
              ],
            ),
            AnimatedBuilder(
              animation: tabataTimer,
              builder: (_, __) {
                if (!tabataTimer.isRunning) return const SizedBox();
                return TabataOverlayWidget(
                  tabataTimer: tabataTimer,
                  onSkip: _skipTabata,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  int _countCompletedCircuitRounds(int blockIndex, Map<String, dynamic> block) {
    final visibleRounds = viewModel.circuitoRound[blockIndex] ?? 1;
    int completed = 0;
    for (int r = 1; r <= visibleRounds; r++) {
      if (_isCircuitRoundCompleted(blockIndex, r, block['exercises'])) {
        completed++;
      }
    }
    return completed;
  }

  void _startFreeWorkout() {
    _changeRoutine(null);
  }

  Future<void> _pickWorkoutDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: "Fecha del entrenamiento",
    );
    if (picked == null || !mounted) return;

    final hasBlocks =
        viewModel.routine != null &&
        (viewModel.routine!['blocks'] as List).isNotEmpty;

    if (!hasBlocks) {
      // No hay bloques: reemplazar con planificados de esa fecha
      setState(() => _selectedDate = picked);
      _updateWorkoutStartedAt(picked);
      final plannedRoutine = await _getPlannedRoutineForDate(picked);
      if (plannedRoutine != null) {
        _changeRoutine(plannedRoutine);
      } else {
        _changeRoutine(null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "No hay bloques planificados para ${_formatDate(picked)}. Entrenamiento libre.",
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      // Ya hay bloques: preguntar si quiere agregar bloques de esa fecha
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text("Cambiar fecha"),
              content: Text(
                "Ya tienes bloques cargados. ¿Qué deseas hacer con la fecha ${_formatDate(picked)}?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text("Cancelar"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'append'),
                  child: const Text("Agregar bloques planificados"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'replace'),
                  child: const Text("Reemplazar sesión"),
                ),
              ],
            ),
      );

      if (action == null || action == 'cancel') return;

      setState(() => _selectedDate = picked);
      _updateWorkoutStartedAt(picked);

      if (action == 'replace') {
        final plannedRoutine = await _getPlannedRoutineForDate(picked);
        if (plannedRoutine != null) {
          _changeRoutine(plannedRoutine);
        } else {
          _changeRoutine(null);
        }
      } else if (action == 'append') {
        await _appendBlocksFromDate(picked);
      }
    }
  }

  void _updateWorkoutStartedAt(DateTime date) {
    final now = DateTime.now();
    viewModel.workoutStartedAt = DateTime(
      date.year,
      date.month,
      date.day,
      now.hour,
      now.minute,
      now.second,
    );
  }

  Future<void> _appendBlocksFromDate(DateTime date) async {
    final plannedRoutine = await _getPlannedRoutineForDate(date);
    if (!mounted) return;

    if (plannedRoutine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "No hay bloques planificados para ${_formatDate(date)}.",
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final newBlocks = List<Map<String, dynamic>>.from(plannedRoutine['blocks']);
    setState(() {
      for (final block in newBlocks) {
        viewModel.routine!['blocks'].add(block);
        final index = viewModel.routine!['blocks'].length - 1;
        viewModel.expandedBlocks[index] = true;
        _initializeBlockState(index, block);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "${newBlocks.length} bloque(s) de ${_formatDate(date)} agregados.",
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return "${d.day} ${months[d.month - 1]} ${d.year}";
  }

  void _showRoutineSelectorSheet() async {
    if (availableRoutines.isEmpty) {
      await _loadAvailableRoutinesBackground();
    }
    if (!mounted) return;
    LogWorkoutDialogs.showRoutineSelectorSheet(
      context: context,
      availableRoutines: availableRoutines,
      currentRoutine: viewModel.routine,
      onConfirmChange: _confirmChangeRoutine,
      onFreeWorkoutSelected: _startFreeWorkout,
      onRoutineSelected: _changeRoutine,
    );
  }

  Future<bool> _confirmChangeRoutine() async {
    bool hasProgress =
        viewModel.routine != null &&
        (viewModel.routine!['blocks'] as List).isNotEmpty;
    if (!hasProgress) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Cambiar rutina"),
            content: const Text(
              "Si cambias de rutina, perderás el progreso de la sesión actual no guardada. ¿Continuar?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancelar"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Cambiar"),
              ),
            ],
          ),
    );
    return ok == true;
  }

  bool _isCircuitRoundCompleted(int blockIndex, int round, List exercises) {
    for (final ex in exercises) {
      final name = viewModel.normalizeExerciseName(ex['name']);
      final notifier = viewModel.circuitoDone[blockIndex]?[round]?[name];
      if (notifier == null || notifier.value != true) return false;
    }
    return true;
  }

  // ================= SAVE =================

  Future<void> _confirmFinish() async {
    if (_saving) return;
    final pendingSets = viewModel.seriesData.values.fold<int>(
      0,
      (sum, sets) => sum + sets.where((s) => s['done'] != true).length,
    );
    final notes = await LogWorkoutDialogs.confirmFinish(
      context,
      pendingSets: pendingSets,
      initialNotes: (widget.existingWorkout?['notes'] ?? '').toString(),
    );
    if (notes != null) await _saveWorkout(notes);
  }

  void _startSaving() {
    if (!mounted) return;
    setState(() {
      _saving = true;
      _savingStep = "Preparando datos…";
    });
  }

  void _setSavingStep(String step) {
    if (!mounted) return;
    setState(() => _savingStep = step);
  }

  void _finishSaving() {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savingStep = "";
    });
  }

  void _handleSaveError(Object e, StackTrace stack) {
    _finishSaving();
    _showErrorDialog("Error al guardar", e, stack);
  }

  /// Muestra el error completo en pantalla para no depender de la consola.
  void _showErrorDialog(String title, Object e, StackTrace stack) {
    debugPrint("❌ $title: $e\n$stack");
    if (!mounted) return;
    final stackLines = stack.toString().split('\n').take(12).join('\n');
    final details = "$e\n\n$stackLines";
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: SelectableText(
                details,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: details));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Error copiado")),
                  );
                },
                child: const Text("COPIAR"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("CERRAR"),
              ),
            ],
          ),
    );
  }

  Future<void> _saveWorkout(String notes) async {
    if (_saving) return;
    _startSaving();
    // Auto-detener cronómetros de bloques que sigan corriendo al guardar
    for (final idx in viewModel.blockStartTimes.keys.toList()) {
      if (viewModel.isBlockTimerRunning(idx)) {
        viewModel.stopBlockTimer(idx);
      }
    }

    try {
      await _runSaveWorkout(notes);
    } catch (e, stack) {
      _handleSaveError(e, stack);
    }
  }

  Future<void> _runSaveWorkout(String notes) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final oldStatsSnap =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('stats')
            .doc('global')
            .get();
    final Map<String, dynamic> oldStats =
        oldStatsSnap.exists ? oldStatsSnap.data()! : {};

    final service = WorkoutSaveService(
      context: context,
      isEdit: isEdit,
      workoutRef: widget.workoutRef,
      routine: viewModel.routine ?? {},
      workoutStartedAt: viewModel.workoutStartedAt,
      originalStartedAt: viewModel.originalStartedAt,
      originalFinishedAt: viewModel.originalFinishedAt,
      originalDurationMinutes: viewModel.originalDurationMinutes,
      seriesData: viewModel.seriesData,
      seriesRepsCtrl: viewModel.seriesRepsCtrl,
      seriesWeightCtrl: viewModel.seriesWeightCtrl,
      circuitoRound: viewModel.circuitoRound,
      circuitoReps: viewModel.circuitoReps,
      circuitoWeight: viewModel.circuitoWeight,
      circuitoRpePorRonda: viewModel.circuitoRpePorRonda,
      circuitoPerSide: viewModel.circuitoPerSide,
      tabataTimer: tabataTimer,
      availableExercisesCatalog: availableExercisesCatalog,
      blockDurationSeconds: viewModel.blockDurationSeconds,
      notes: notes,
      onStepChanged: _setSavingStep,
      onError: _handleSaveError,
      // El servicio no espera este callback, así que sus errores se capturan acá.
      onSuccess: (achievements, performed, savedRef) async {
        try {
          await _onSaveSuccess(
            uid: uid,
            oldStats: oldStats,
            achievements: achievements,
            performed: performed,
            savedRef: savedRef,
          );
        } catch (e, stack) {
          _handleSaveError(e, stack);
        }
      },
    );
    await service.execute();
  }

  Future<void> _onSaveSuccess({
    required String uid,
    required Map<String, dynamic> oldStats,
    required List<Achievement> achievements,
    required List<Map<String, dynamic>> performed,
    required DocumentReference savedRef,
  }) async {
    final newStatsSnap =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('stats')
            .doc('global')
            .get();
    final Map<String, dynamic> newStats =
        newStatsSnap.exists ? newStatsSnap.data()! : {};

    Map<String, dynamic> computedOldStats = Map.from(oldStats);
    if (isEdit) {
      // Para stats globales, al editar no hemos sumado un nuevo entrenamiento ni días a la racha
      // a menos que cambiaramos la fecha a un día clave. Por ende, no forzamos que racha o
      // maxWeeklySessions suban simulando restas. Solo simulamos la suma de volumen porque el
      // edit reemplaza el volumen viejo por el nuevo.
      final sessionVolume = WorkoutVolumeService.calculateWorkoutVolume(
        performed,
      );
      computedOldStats['totalVolume'] =
          (newStats['totalVolume'] ?? 0.0) - sessionVolume;
      // Max session volume respetamos el viejo
      computedOldStats['maxVolumeSession'] =
          oldStats['maxVolumeSession'] ?? 0.0;
    }

    // Alertas de progreso (PR, eficiencia, volumen) desde el resumen
    // persistido por ejercicio: un solo documento en vez de releer todo
    // el historial en cada guardado.
    final alerts = await ProgressSummaryService.alertsAfterSave(
      uid: uid,
      performed: performed,
      targetDate: viewModel.workoutStartedAt ?? DateTime.now(),
      savedWorkoutId: savedRef.id,
      isEdit: isEdit,
    );

    _finishSaving();
    if (!isEdit) {
      WorkoutSessionService().endWorkout(
        saved: true,
      ); // Limpiar sesión persistente si no es edición
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) => WorkoutSummaryScreen(
              unlockedAchievements: achievements,
              progressAlerts: alerts,
              workoutRef: savedRef,
              oldStats: computedOldStats,
              newStats: newStats,
              sessionName: viewModel.routine?['name'] ?? 'Entrenamiento libre',
              durationMinutes:
                  viewModel.originalDurationMinutes ??
                  (DateTime.now()
                      .difference(viewModel.workoutStartedAt ?? DateTime.now())
                      .inMinutes),
            ),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("¿Cancelar entrenamiento?"),
            content: const Text(
              "Se perderá todo el progreso de la sesión actual.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Continuar entrenando"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text(
                  "SÍ, CANCELAR",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (ok == true) {
      WorkoutSessionService().endWorkout();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _showSessionVariantEditor() async {
    final blocks = viewModel.routine?['blocks'] as List? ?? const [];
    final entries = <({int blockIndex, Map<String, dynamic> exercise})>[];
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = Map<String, dynamic>.from(blocks[blockIndex] as Map);
      for (final raw in List.from(block['exercises'] ?? const [])) {
        entries.add((
          blockIndex: blockIndex,
          exercise: Map<String, dynamic>.from(raw as Map),
        ));
      }
    }
    if (entries.isEmpty || !mounted) return;
    final selected = await showDialog<
      ({int blockIndex, Map<String, dynamic> exercise})
    >(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Cambiar variante ejecutada'),
            content: SizedBox(
              width: 520,
              child: ListView(
                shrinkWrap: true,
                children:
                    entries
                        .map(
                          (entry) => ListTile(
                            title: Text(
                              (entry.exercise['displayName'] ??
                                      entry.exercise['name'] ??
                                      'Ejercicio')
                                  .toString(),
                            ),
                            subtitle: Text('Bloque ${entry.blockIndex + 1}'),
                            onTap: () => Navigator.pop(dialogContext, entry),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
    );
    if (selected == null || !mounted) return;
    final exerciseId = selected.exercise['exerciseId']?.toString();
    Map<String, dynamic>? catalog;
    if (exerciseId != null) {
      catalog =
          availableExercisesCatalog
              .where((e) => e['id'] == exerciseId)
              .firstOrNull;
    }
    catalog ??= _getExerciseFromCatalog(
      (selected.exercise['movementName'] ?? selected.exercise['name'])
          .toString(),
    );
    if (catalog == null) return;
    final movement = Exercise.fromFirestore(
      catalog,
      id: catalog['id'].toString(),
    );
    final variant = await showDialog<ExerciseVariant>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('${movement.name}: variante realizada'),
            content: SizedBox(
              width: 480,
              child: ListView(
                shrinkWrap: true,
                children:
                    movement.variants
                        .map(
                          (item) => ListTile(
                            title: Text(item.label),
                            subtitle: Text(
                              '${item.group} · ${item.equipment.join(', ')}',
                            ),
                            onTap: () => Navigator.pop(dialogContext, item),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
    );
    if (variant == null || !mounted) return;
    _applyVariant(
      blockIndex: selected.blockIndex,
      exercise: selected.exercise,
      movement: movement,
      variant: variant,
    );
  }

  /// Cambia la variante ejecutada de UN ejercicio puntual, sin pasar por el
  /// selector de "elegí qué ejercicio" (ya se sabe cuál: el que el usuario
  /// tocó). Se usa desde el botón de variante junto a cada ejercicio en
  /// SeriesBlockWidget, para el caso de "el equipo planificado está
  /// ocupado" en medio del bloque, sin esperar a completarlo entero.
  Future<void> _changeVariantFor(
    int blockIndex,
    Map<String, dynamic> ex,
  ) async {
    if (!mounted) return;
    final exerciseId = ex['exerciseId']?.toString();
    Map<String, dynamic>? catalog;
    if (exerciseId != null) {
      catalog =
          availableExercisesCatalog
              .where((e) => e['id'] == exerciseId)
              .firstOrNull;
    }
    catalog ??= _getExerciseFromCatalog(
      (ex['movementName'] ?? ex['name']).toString(),
    );
    if (catalog == null || !mounted) return;
    final movement = Exercise.fromFirestore(
      catalog,
      id: catalog['id'].toString(),
    );

    final variant = await showDialog<ExerciseVariant>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('${movement.name}: variante realizada'),
            content: SizedBox(
              width: 480,
              child: ListView(
                shrinkWrap: true,
                children:
                    movement.variants
                        .map(
                          (item) => ListTile(
                            title: Text(item.label),
                            subtitle: Text(
                              '${item.group} · ${item.equipment.join(', ')}',
                            ),
                            onTap: () => Navigator.pop(dialogContext, item),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
    );
    if (variant == null || !mounted) return;
    _applyVariant(
      blockIndex: blockIndex,
      exercise: ex,
      movement: movement,
      variant: variant,
    );
  }

  void _applyVariant({
    required int blockIndex,
    required Map<String, dynamic> exercise,
    required Exercise movement,
    required ExerciseVariant variant,
  }) {
    try {
      final blocks = viewModel.routine!['blocks'] as List;
      // Copias modificables: la rutina puede venir de fuentes cuyas listas o
      // mapas no admiten escritura, y un addAll fallido no daba feedback.
      final block = Map<String, dynamic>.from(blocks[blockIndex] as Map);
      final exercises = List<dynamic>.from(block['exercises'] as List);
      final targetIndex = exercises.indexWhere(
        (item) =>
            item is Map &&
            (identical(item, exercise) ||
                (item['name'] == exercise['name'] &&
                    item['variantId'] == exercise['variantId'])),
      );
      if (targetIndex < 0) {
        _showSnack("No se encontró el ejercicio en el bloque.");
        return;
      }
      final target = exercises[targetIndex] as Map;
      final oldName = viewModel.normalizeExerciseName(target['name']);
      final newName = variant.displayName(movement.name);
      exercises[targetIndex] = <String, dynamic>{
        ...Map<String, dynamic>.from(target),
        'name': newName,
        'movementName': movement.name,
        'displayName': newName,
        'exerciseId': movement.id,
        'movementId': movement.id,
        'variantId': variant.id,
        'variantLabel': variant.label,
        'equipment': variant.equipment.join(', '),
        'resistanceType': variant.resistanceType,
        'trackRM': variant.trackRM,
        'trackProgression': variant.trackProgression,
        'isUnilateral': variant.isUnilateral,
      };
      block['exercises'] = exercises;
      final newBlocks = List<dynamic>.from(blocks)..[blockIndex] = block;
      viewModel.routine = {...viewModel.routine!, 'blocks': newBlocks};
      viewModel.renameExerciseState(blockIndex, oldName, newName);
      if (mounted) setState(() {});
      _showSnack(
        oldName == newName
            ? "Ya estabas usando esa variante."
            : "Variante cambiada a $newName",
      );
    } catch (e, stack) {
      _showErrorDialog("Error al cambiar variante", e, stack);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
