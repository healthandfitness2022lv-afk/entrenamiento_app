import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'web_audio.dart';


enum TabataPhase { work, rest, finished }

class TabataTimerService {
  Timer? _timer;

  int _currentRound = 1;
  int _exerciseIndex = 0;
  int _secondsLeft = 0;
  int _phaseTotal = 0;

  late int workSeconds;
  late int restSeconds;
  late int totalRounds;
  late List<Map<String, dynamic>> exercises;

  TabataPhase phase = TabataPhase.work;

  // ============================
  // 🔊 AUDIO CONFIG
  // ============================

  static bool _audioUnlocked = false;

  AudioPlayer _createPlayer() {
  final player = AudioPlayer();

  if (!kIsWeb) {
    player.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.alarm, // 🔥 CLAVE
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
    await player.setVolume(1.0); // 🔊 CLAVE
    await player.setReleaseMode(ReleaseMode.stop);
    await player.play(AssetSource(asset));
  } catch (e) {
    debugPrint("Audio error: $e");
  }
}


  /// 🔓 Llamar UNA VEZ desde un botón (obligatorio en Web)
  static Future<void> unlockAudio() async {
    if (_audioUnlocked) return;

    try {
      final player = AudioPlayer();
      await player.play(
        AssetSource('sounds/beep.wav'),
        volume: 0, // inaudible
      );
      _audioUnlocked = true;
    } catch (_) {}
  }

 void _soundWork() {
  if (kIsWeb) {
    WebAudio.play('assets/sounds/work.wav');
  } else {
    _play('sounds/work.wav');
  }
}

void _soundRest() {
  if (kIsWeb) {
    WebAudio.play('assets/sounds/rest.wav');
  } else {
    _play('sounds/rest.wav');
  }
}

void _soundFinish() {
  if (kIsWeb) {
    WebAudio.play('assets/sounds/finish.wav');
  } else {
    _play('sounds/finish.wav');
  }
}

void _soundBeep() {
  if (kIsWeb) {
    WebAudio.play('assets/sounds/beep.wav');
  } else {
    _play('sounds/beep.wav');
  }
}


  // ============================
  // CALLBACKS
  // ============================
  void Function(
    int round,
    Map<String, dynamic> exercise,
    TabataPhase phase,
    int elapsed,
    int total,
  )? onTick;

  void Function()? onFinish;

  bool get isRunning => _timer != null;

  // ============================
  // ▶️ START
  // ============================
  void start({
    required int workSeconds,
    required int restSeconds,
    required int rounds,
    required List<Map<String, dynamic>> exercises,
    void Function(
      int round,
      Map<String, dynamic> exercise,
      TabataPhase phase,
      int elapsed,
      int total,
    )? onTick,
    void Function()? onFinish,
  }) {
    stop();

    this.workSeconds = workSeconds;
    this.restSeconds = restSeconds;
    totalRounds = rounds;
    this.exercises = exercises;
    this.onTick = onTick;
    this.onFinish = onFinish;

    _currentRound = 1;
    _exerciseIndex = 0;
    phase = TabataPhase.work;
    _phaseTotal = workSeconds;
    _secondsLeft = workSeconds;

    _soundWork(); // 🔊 inicio

    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  // ============================
  // ⏱️ TICK
  // ============================
  void _tick(Timer timer) {
    _secondsLeft--;

    final elapsed = _phaseTotal - _secondsLeft;

    // 🔔 beep últimos 3 segundos
    if (_secondsLeft <= 3 && _secondsLeft > 0) {
      _soundBeep();
    }

    onTick?.call(
      _currentRound,
      exercises[_exerciseIndex],
      phase,
      elapsed,
      _phaseTotal,
    );

    if (_secondsLeft > 0) return;

    // ============================
    // CAMBIO DE FASE
    // ============================
    if (phase == TabataPhase.work) {
      phase = TabataPhase.rest;
      _phaseTotal = restSeconds;
      _secondsLeft = restSeconds;

      _soundRest();
      return;
    }

    // ============================
    // SIGUIENTE EJERCICIO / RONDA
    // ============================
    phase = TabataPhase.work;
    _exerciseIndex++;

    if (_exerciseIndex >= exercises.length) {
      _exerciseIndex = 0;
      _currentRound++;
    }

    if (_currentRound > totalRounds) {
      stop();
      _soundFinish();
      onFinish?.call();
      return;
    }

    _phaseTotal = workSeconds;
    _secondsLeft = workSeconds;

    _soundWork();
  }

  // ============================
  // ⏹️ STOP
  // ============================
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
