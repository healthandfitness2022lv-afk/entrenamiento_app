import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum TabataPhase { work, rest, finished }

class TabataTimerService extends ChangeNotifier {
  late final AudioPlayer _audioPlayer;

  TabataTimerService() {
    _audioPlayer = AudioPlayer();
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayer.setVolume(1.0);
    if (!kIsWeb) {
      _audioPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.music,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
    }
  }

  // =========================================================
  // ⏱ TIMER CORE
  // =========================================================

  Timer? _timer;

  /// Fin de la fase actual según el reloj real. El tick solo refresca la UI:
  /// en web el navegador frena `Timer.periodic` con la pestaña en segundo
  /// plano, así que contar ticks atrasaría el Tabata.
  DateTime? _phaseEndsAt;

  /// Se llama cuando el bloque termina solo (no con `stop`), para pedir RPE.
  void Function(int blockIndex)? onBlockFinished;

  int _currentRound = 1;
  int _exerciseIndex = 0;
  int _secondsLeft = 0;
  int _phaseTotal = 0;

  late int _workSeconds;
  late int _restSeconds;
  late int _totalRounds;
  late List<Map<String, dynamic>> _exercises;

  TabataPhase _phase = TabataPhase.work;

  // =========================================================
  // 🧠 SESSION STATE (MULTI BLOQUE)
  // =========================================================

  final Set<int> _startedBlocks = {};
  final Set<int> _completedBlocks = {};
  final Map<int, Map<String, int>> _rpeResults = {};

  int? _activeBlockIndex;

  // =========================================================
  // 🔊 AUDIO
  // =========================================================

  Future<void> _play(String asset) async {
    try {
      // Sin awaits previos: en web (Safari iOS) el primer play debe ocurrir
      // dentro del gesto del usuario que inicia el Tabata.
      await _audioPlayer.play(AssetSource(asset));
    } catch (e) {
      debugPrint("Audio error: $e");
    }
  }

  void _soundWork() => _play('sounds/work.wav');
  void _soundRest() => _play('sounds/rest.wav');
  void _soundFinish() => _play('sounds/finish.wav');
  void _soundBeep() => _play('sounds/beep.wav');

  // =========================================================
  // 📤 GETTERS
  // =========================================================

  bool get isRunning => _timer != null;

  int get currentRound => _currentRound;

  Map<String, dynamic>? get currentExercise =>
      _exercises.isNotEmpty ? _exercises[_exerciseIndex] : null;

  int get elapsed => _phaseTotal - _secondsLeft;

  int get total => _phaseTotal;

  TabataPhase get phase => _phase;

  int? get activeBlockIndex => _activeBlockIndex;

  bool isStarted(int blockIndex) => _startedBlocks.contains(blockIndex);

  bool isCompleted(int blockIndex) => _completedBlocks.contains(blockIndex);

  Map<String, int>? getRpeResults(int blockIndex) => _rpeResults[blockIndex];

  Map<int, Map<String, int>> get allResults => _rpeResults;

  // =========================================================
  // ▶️ START BLOCK
  // =========================================================

  void startBlock({
    required int blockIndex,
    required int workSeconds,
    required int restSeconds,
    required int rounds,
    required List<Map<String, dynamic>> exercises,
  }) {
    stop(); // seguridad

    _activeBlockIndex = blockIndex;
    _startedBlocks.add(blockIndex);
    _completedBlocks.remove(blockIndex);
    _rpeResults.remove(blockIndex);

    _workSeconds = workSeconds;
    _restSeconds = restSeconds;
    _totalRounds = rounds;
    _exercises = exercises;

    _currentRound = 1;
    _exerciseIndex = 0;
    _phase = TabataPhase.work;
    _phaseTotal = _workSeconds;
    _secondsLeft = _workSeconds;
    _phaseEndsAt = DateTime.now().add(Duration(seconds: _workSeconds));

    _soundWork();

    _timer = Timer.periodic(const Duration(milliseconds: 250), _tick);

    notifyListeners();
  }

  void completeBlockWithRpe(int blockIndex, Map<String, int> rpeByExercise) {
    _completedBlocks.add(blockIndex);
    _rpeResults[blockIndex] = rpeByExercise;
    notifyListeners();
  }

  void markBlockHydrated(int blockIndex, Map<String, int> rpeByExercise) {
    _startedBlocks.add(blockIndex);
    _completedBlocks.add(blockIndex);
    _rpeResults[blockIndex] = rpeByExercise;
  }

  void resetBlock(int blockIndex) {
    _startedBlocks.remove(blockIndex);
    _completedBlocks.remove(blockIndex);
    _rpeResults.remove(blockIndex);
    notifyListeners();
  }

  // =========================================================
  // ⏱ TICK
  // =========================================================

  void _tick(Timer timer) {
    final end = _phaseEndsAt;
    if (end == null) return;

    final now = DateTime.now();
    var endsAt = end;
    var changedPhase = false;

    // Avanza todas las fases vencidas (más de una si el navegador frenó el
    // timer), sonando solo la transición final.
    while (!now.isBefore(endsAt)) {
      changedPhase = true;
      if (_phase == TabataPhase.work) {
        _phase = TabataPhase.rest;
        _phaseTotal = _restSeconds;
      } else {
        _phase = TabataPhase.work;
        _phaseTotal = _workSeconds;
        _exerciseIndex++;
        if (_exerciseIndex >= _exercises.length) {
          _exerciseIndex = 0;
          _currentRound++;
        }
        if (_currentRound > _totalRounds) {
          _currentRound = _totalRounds;
          _exerciseIndex = _exercises.length - 1;
          _finishBlock();
          return;
        }
      }
      endsAt = endsAt.add(Duration(seconds: _phaseTotal));
    }
    _phaseEndsAt = endsAt;

    final remaining = (endsAt.difference(now).inMilliseconds / 1000).ceil();

    if (changedPhase) {
      _secondsLeft = remaining;
      _phase == TabataPhase.work ? _soundWork() : _soundRest();
      notifyListeners();
      return;
    }

    if (remaining == _secondsLeft) return;
    _secondsLeft = remaining;

    // 🔔 Beep últimos 3 segundos
    if (_secondsLeft <= 3 && _secondsLeft > 0) {
      _soundBeep();
    }

    notifyListeners();
  }

  // =========================================================
  // 🏁 FIN DE BLOQUE
  // =========================================================

  void _finishBlock() {
    _timer?.cancel();
    _timer = null;
    _phaseEndsAt = null;
    _secondsLeft = 0;

    _phase = TabataPhase.finished;

    final blockIndex = _activeBlockIndex;
    if (blockIndex != null) {
      _completedBlocks.add(blockIndex);
    }

    _soundFinish();
    notifyListeners();

    if (blockIndex != null) onBlockFinished?.call(blockIndex);
  }

  // =========================================================
  // ⏹ STOP
  // =========================================================

  void stop() {
    _timer?.cancel();
    _timer = null;
    _phaseEndsAt = null;
    notifyListeners();
  }

  // =========================================================
  // 🧹 RESET TOTAL
  // =========================================================

  void resetAll() {
    stop();
    _startedBlocks.clear();
    _completedBlocks.clear();
    _rpeResults.clear();
    _activeBlockIndex = null;
    _phase = TabataPhase.work;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _audioPlayer.dispose();
    super.dispose();
  }
}
