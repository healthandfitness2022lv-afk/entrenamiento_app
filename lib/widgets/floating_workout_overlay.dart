import 'package:flutter/material.dart';
import '../services/workout_session_service.dart';
import '../screens/log_workout_screen.dart';
import '../main.dart';

class FloatingWorkoutOverlay extends StatefulWidget {
  const FloatingWorkoutOverlay({super.key});

  @override
  State<FloatingWorkoutOverlay> createState() => _FloatingWorkoutOverlayState();
}

class _FloatingWorkoutOverlayState extends State<FloatingWorkoutOverlay> {
  Offset _position = const Offset(16, 60); // Posición inicial arriba
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final session = WorkoutSessionService();

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.isActive || session.isViewingWorkoutScreen)
          return const SizedBox.shrink();

        return Positioned(
          left: _position.dx,
          top: _position.dy,
          child: ListenableBuilder(
            listenable: session.viewModel!,
            builder: (context, _) {
              return GestureDetector(
                onPanStart: (_) => _isDragging = false,
                onPanUpdate: (details) {
                  _isDragging = true;
                  setState(() {
                    _position += details.delta;
                  });
                },
                onTap: () {
                  if (!_isDragging) {
                    navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => const LogWorkoutScreen(),
                      ),
                    );
                  }
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.fitness_center,
                            color: Colors.black,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                session.viewModel?.routine?['name'] ??
                                    "Entrenamiento",
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              StreamBuilder(
                                stream: Stream.periodic(
                                  const Duration(seconds: 1),
                                ),
                                builder: (context, _) {
                                  final duration =
                                      session.viewModel?.workoutStartedAt !=
                                              null
                                          ? DateTime.now().difference(
                                            session
                                                .viewModel!
                                                .workoutStartedAt!,
                                          )
                                          : Duration.zero;

                                  String twoDigits(int n) =>
                                      n.toString().padLeft(2, "0");
                                  final minutes = twoDigits(
                                    duration.inMinutes.remainder(60),
                                  );
                                  final seconds = twoDigits(
                                    duration.inSeconds.remainder(60),
                                  );

                                  return Text(
                                    "${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds",
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 10,
                                      height: 1,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.black,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
