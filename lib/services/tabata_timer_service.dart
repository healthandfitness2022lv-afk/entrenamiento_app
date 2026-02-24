import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum TabataPhase { work, rest, finished }

class TabataTimerService extends ChangeNotifier {
  // =========================================================
  // ⏱ TIMER CORE
  // =========================================================

  Timer? _timer;

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

  AudioPlayer _createPlayer() {
    final player = AudioPlayer();

    if (!kIsWeb) {
      player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.music,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
    }

    return player;
  }

  Future<void> _play(String asset) async {
    try {
      final player = _createPlayer();
      await player.setVolume(1.0);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(AssetSource(asset));
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

  Map<String, int>? getRpeResults(int blockIndex) =>
      _rpeResults[blockIndex];

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

    _soundWork();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      _tick,
    );

    notifyListeners();
  }


  void completeBlockWithRpe(
  int blockIndex,
  Map<String, int> rpeByExercise,
) {
  _completedBlocks.add(blockIndex);
  _rpeResults[blockIndex] = rpeByExercise;
  notifyListeners();
}


void markBlockHydrated(
  int blockIndex,
  Map<String, int> rpeByExercise,
) {
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
    _secondsLeft--;

    // 🔔 Beep últimos 3 segundos
    if (_secondsLeft <= 3 && _secondsLeft > 0) {
      _soundBeep();
    }

    notifyListeners();

    if (_secondsLeft > 0) return;

    // =====================================================
    // CAMBIO DE FASE
    // =====================================================

    if (_phase == TabataPhase.work) {
      _phase = TabataPhase.rest;
      _phaseTotal = _restSeconds;
      _secondsLeft = _restSeconds;

      _soundRest();
      notifyListeners();
      return;
    }

    // =====================================================
    // SIGUIENTE EJERCICIO / RONDA
    // =====================================================

    _phase = TabataPhase.work;
    _exerciseIndex++;

    if (_exerciseIndex >= _exercises.length) {
      _exerciseIndex = 0;
      _currentRound++;
    }

    if (_currentRound > _totalRounds) {
      _finishBlock();
      return;
    }

    _phaseTotal = _workSeconds;
    _secondsLeft = _workSeconds;

    _soundWork();
    notifyListeners();
  }

  // =========================================================
  // 🏁 FIN DE BLOQUE
  // =========================================================

  void _finishBlock() {
    _timer?.cancel();
    _timer = null;

    _phase = TabataPhase.finished;

    if (_activeBlockIndex != null) {
      _completedBlocks.add(_activeBlockIndex!);
    }

    _soundFinish();
    notifyListeners();
  }

  // =========================================================
  // ⏹ STOP
  // =========================================================

  void stop() {
    _timer?.cancel();
    _timer = null;
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
    super.dispose();
  }
}
