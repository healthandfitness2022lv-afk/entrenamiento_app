import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../view_models/log_workout_view_model.dart';
import '../utils/weight_input.dart';
import 'tabata_timer_service.dart';

/// Publica en `live_sessions/{uid}` el estado de la sesión en curso para que
/// el entrenador la siga en tiempo real desde [LiveSessionsScreen].
///
/// No depende de que cada widget notifique sus cambios (los checks de
/// circuito usan ValueNotifier propios): cada [_pollInterval] arma una
/// instantánea y solo escribe si cambió, más un latido cada [_heartbeat]
/// para que el entrenador sepa que el teléfono sigue conectado.
class LiveSessionService {
  static final LiveSessionService _instance = LiveSessionService._internal();
  factory LiveSessionService() => _instance;
  LiveSessionService._internal();

  static const collection = 'live_sessions';
  static const _pollInterval = Duration(seconds: 3);
  static const _heartbeat = Duration(seconds: 45);

  LogWorkoutViewModel? _viewModel;
  TabataTimerService? _tabata;
  Timer? _timer;
  String? _uid;
  String? _athleteName;
  String? _lastPayload;
  DateTime? _lastWrite;
  DateTime? _lastSetAt;
  int _lastDoneSets = 0;

  void start(LogWorkoutViewModel vm, TabataTimerService tabata) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _timer?.cancel();
    _viewModel = vm;
    _tabata = tabata;
    _uid = uid;
    _lastPayload = null;
    _lastWrite = null;
    _lastSetAt = null;
    _lastDoneSets = 0;
    _loadAthleteName(uid);
    _timer = Timer.periodic(_pollInterval, (_) => _publish());
  }

  /// [saved] marca la sesión como terminada (el entrenador ve el cierre);
  /// si se canceló, el documento se borra.
  Future<void> stop({required bool saved}) async {
    _timer?.cancel();
    _timer = null;
    final uid = _uid;
    final vm = _viewModel;
    _viewModel = null;
    _tabata = null;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance.collection(collection).doc(uid);
    try {
      if (saved && vm != null) {
        await ref.set({
          ..._snapshot(vm, null),
          'status': 'finished',
          'finishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.delete();
      }
    } catch (_) {
      // El seguimiento en vivo nunca debe bloquear el guardado.
    }
  }

  Future<void> _loadAthleteName(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _athleteName = doc.data()?['name']?.toString();
    } catch (_) {}
  }

  Future<void> _publish() async {
    final vm = _viewModel;
    final uid = _uid;
    if (vm == null || uid == null || vm.routine == null) return;

    final data = _snapshot(vm, _tabata);
    final payload = jsonEncode(data);
    final now = DateTime.now();
    final changed = payload != _lastPayload;
    final heartbeatDue =
        _lastWrite == null || now.difference(_lastWrite!) >= _heartbeat;
    if (!changed && !heartbeatDue) return;

    final doneSets = data['doneSets'] as int;
    if (doneSets > _lastDoneSets) _lastSetAt = now;
    _lastDoneSets = doneSets;

    _lastPayload = payload;
    _lastWrite = now;
    try {
      await FirebaseFirestore.instance.collection(collection).doc(uid).set({
        ...data,
        'status': 'active',
        if (_lastSetAt != null) 'lastSetAt': Timestamp.fromDate(_lastSetAt!),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _lastPayload = null; // reintentar en el próximo ciclo
    }
  }

  /// Instantánea serializable (sin Timestamps de servidor) para poder
  /// compararla entre ciclos.
  Map<String, dynamic> _snapshot(
    LogWorkoutViewModel vm,
    TabataTimerService? tabata,
  ) {
    final blocks = List.from(vm.routine?['blocks'] ?? const []);
    final liveBlocks = <Map<String, dynamic>>[];
    var totalSets = 0;
    var doneSets = 0;
    String? currentExercise;
    int? currentBlock;

    for (var i = 0; i < blocks.length; i++) {
      final block = Map<String, dynamic>.from(blocks[i] as Map);
      final type = block['type']?.toString() ?? 'Series';
      final exercises = List.from(block['exercises'] ?? const []);
      final live = <String, dynamic>{
        'index': i,
        'type': type,
        'title': block['title'] ?? block['name'] ?? type,
        'pausedSeconds': vm.blockPausedSeconds[i] ?? 0,
        if (vm.blockStartTimes[i] != null)
          'runningSince': vm.blockStartTimes[i]!.toIso8601String(),
        if (vm.blockDurationSeconds[i] != null)
          'durationSeconds': vm.blockDurationSeconds[i],
      };

      if (type == 'Circuito') {
        final rounds = vm.circuitoRound[i] ?? 0;
        final liveRounds = <Map<String, dynamic>>[];
        for (var r = 1; r <= rounds; r++) {
          final liveExercises = <Map<String, dynamic>>[];
          for (final raw in exercises) {
            final ex = Map<String, dynamic>.from(raw as Map);
            final name = vm.normalizeExerciseName(ex['name']);
            final done = vm.circuitoDone[i]?[r]?[name]?.value == true;
            totalSets++;
            if (done) doneSets++;
            liveExercises.add({
              'name': name,
              'done': done,
              'reps': int.tryParse(vm.circuitoReps[i]?[r]?[name]?.text ?? ''),
              'weight': parseWeight(vm.circuitoWeight[i]?[r]?[name]?.text ?? ''),
              'rpe': vm.circuitoRpePorRonda[i]?[r]?[name],
              if (ex['valueType'] == 'time') 'valueType': 'time',
            });
            if (!done && currentExercise == null && _isActiveBlock(vm, i)) {
              currentExercise = '$name · ronda $r';
              currentBlock = i;
            }
          }
          liveRounds.add({'round': r, 'exercises': liveExercises});
        }
        live['plannedRounds'] = block['rounds'];
        live['rounds'] = liveRounds;
      } else if (type == 'Tabata') {
        live['exercises'] = [
          for (final raw in exercises)
            {'name': vm.normalizeExerciseName((raw as Map)['name'])},
        ];
        if (tabata != null && tabata.activeBlockIndex == i) {
          live['tabata'] = {
            'running': tabata.isRunning,
            'round': tabata.currentRound,
            'phase': tabata.phase.name,
          };
          if (tabata.isRunning) {
            currentExercise = 'Tabata · ronda ${tabata.currentRound}';
            currentBlock = i;
          }
        }
      } else {
        final liveExercises = <Map<String, dynamic>>[];
        for (final raw in exercises) {
          final ex = Map<String, dynamic>.from(raw as Map);
          final name = vm.normalizeExerciseName(ex['name']);
          final key = '$i-$name';
          final sets = vm.seriesData[key] ?? const <Map<String, dynamic>>[];
          final liveSets = <Map<String, dynamic>>[];
          for (var s = 0; s < sets.length; s++) {
            final done = sets[s]['done'] == true;
            totalSets++;
            if (done) doneSets++;
            liveSets.add({
              'done': done,
              'reps': int.tryParse(vm.seriesRepsCtrl[key]?[s].text ?? ''),
              'weight': parseWeight(vm.seriesWeightCtrl[key]?[s].text ?? ''),
              'rpe': sets[s]['rpe'],
            });
          }
          if (currentExercise == null &&
              _isActiveBlock(vm, i) &&
              liveSets.any((s) => s['done'] != true)) {
            currentExercise = name;
            currentBlock = i;
          }
          liveExercises.add({
            'name': name,
            'plannedReps': ex['reps'] ?? ex['value'],
            'plannedWeight': ex['weight'],
            'perSide': ex['perSide'] == true,
            if (ex['valueType'] == 'time') 'valueType': 'time',
            'notes': ex['notes'],
            'sets': liveSets,
          });
        }
        live['exercises'] = liveExercises;
      }
      liveBlocks.add(live);
    }

    return {
      'athleteId': _uid,
      'athleteName': _athleteName,
      'sessionName': vm.routine?['name'] ?? 'Entrenamiento libre',
      'startedAt': (vm.workoutStartedAt ?? DateTime.now()).toIso8601String(),
      'totalSets': totalSets,
      'doneSets': doneSets,
      'currentExercise': currentExercise,
      'currentBlock': currentBlock,
      'blocks': liveBlocks,
    };
  }

  /// Un bloque es "el actual" si su cronómetro corre, o si ninguno corre y
  /// es el primero sin terminar.
  bool _isActiveBlock(LogWorkoutViewModel vm, int index) {
    if (vm.blockStartTimes.isNotEmpty) {
      return vm.blockStartTimes.containsKey(index);
    }
    return !vm.blockDurationSeconds.containsKey(index);
  }
}
