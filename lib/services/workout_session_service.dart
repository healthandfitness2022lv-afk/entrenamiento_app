import 'package:flutter/material.dart';
import '../view_models/log_workout_view_model.dart';
import '../services/tabata_timer_service.dart';
import 'live_session_service.dart';

class WorkoutSessionService extends ChangeNotifier {
  static final WorkoutSessionService _instance =
      WorkoutSessionService._internal();
  factory WorkoutSessionService() => _instance;
  WorkoutSessionService._internal();

  LogWorkoutViewModel? viewModel;
  TabataTimerService? tabataTimer;
  bool get isActive => viewModel != null;
  bool isViewingWorkoutScreen = false;

  void startWorkout(LogWorkoutViewModel vm, TabataTimerService timer) {
    viewModel = vm;
    tabataTimer = timer;
    LiveSessionService().start(vm, timer);
    notifyListeners();
  }

  void setViewingWorkoutScreen(bool value) {
    isViewingWorkoutScreen = value;
    notifyListeners();
  }

  /// [saved] distingue un entrenamiento guardado de uno cancelado para el
  /// seguimiento en vivo del entrenador.
  void endWorkout({bool saved = false}) {
    LiveSessionService().stop(saved: saved);
    viewModel = null;
    tabataTimer = null;
    isViewingWorkoutScreen = false;
    notifyListeners();
  }

  void notify() {
    notifyListeners();
  }
}
