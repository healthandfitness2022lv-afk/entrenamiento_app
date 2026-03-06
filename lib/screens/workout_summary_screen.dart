import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../models/achievement.dart';
import '../services/progress_alert_service.dart';

class WorkoutSummaryScreen extends StatefulWidget {
  final List<Achievement> unlockedAchievements;
  final List<ProgressAlert> progressAlerts;
  final Map<String, dynamic> oldStats;
  final Map<String, dynamic> newStats;
  final String sessionName;
  final int durationMinutes;

  const WorkoutSummaryScreen({
    super.key,
    required this.unlockedAchievements,
    this.progressAlerts = const [],
    required this.oldStats,
    required this.newStats,
    required this.sessionName,
    required this.durationMinutes,
  });

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  late ConfettiController _confettiController;
  final ScrollController _scrollController = ScrollController();
  
  bool _showAnimations = false;

  final Map<String, String> _statToGroup = {
    'totalWorkouts': 'workouts',
    'totalVolume': 'total_vol',
    'maxVolumeSession': 'vol_session',
    'maxStreak': 'streak',
    'maxWeeklySessions': 'weekly',
  };

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    
    // Iniciar animaciones de barras despues de que se monte la vista
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _showAnimations = true;
        });
        if (widget.unlockedAchievements.isNotEmpty) {
           _confettiController.play();
        }
      }
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Achievement? _getNextTarget(String groupId, num currentValue) {
    final groupAch = achievementsCatalog.where((a) => a.groupId == groupId).toList();
    groupAch.sort((a, b) => a.level.compareTo(b.level));
    
    for (final ach in groupAch) {
      if (ach.targetValue > currentValue) {
        return ach;
      }
    }
    return null; // Si ya los completo todos
  }
  
  Achievement? _getJustUnlocked(String groupId, num oldValue, num newValue) {
     final groupAch = achievementsCatalog.where((a) => a.groupId == groupId).toList();
     groupAch.sort((a, b) => a.level.compareTo(b.level));
     
     // Buscar el logro de mayor nivel que se acaba de pasar con newValue,
     // y que ants con oldValue NO se pasaba.
     Achievement? unlocked;
     for (final ach in groupAch) {
       if (oldValue < ach.targetValue && newValue >= ach.targetValue) {
          unlocked = ach;
       }
     }
     return unlocked;
  }

  Widget _buildSummaryHeader(ThemeData theme) {
    return Column(
      children: [
        const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
        const SizedBox(height: 16),
        Text(
          "¡Entrenamiento Finalizado!",
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          "${widget.sessionName} - ${widget.durationMinutes} min",
          style: theme.textTheme.titleMedium?.copyWith(color: theme.textTheme.bodySmall?.color),
        ),
      ],
    );
  }

  Widget _buildProgressBar(
      ThemeData theme,
      String label, 
      num oldValue, 
      num newValue, 
      Achievement nextAch, 
      Achievement? unlockedThisSession
  ) {
    final target = unlockedThisSession != null ? unlockedThisSession.targetValue : nextAch.targetValue;
    final maxTarget = target > 0 ? target : 1.0;
    
    // Usar Tween animation para interpolar valor inicial -> valor final
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (unlockedThisSession != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: const Text("¡Subiste de Nivel!", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: (oldValue / maxTarget).clamp(0.0, 1.0).toDouble(),
              end: _showAnimations ? (newValue / maxTarget).clamp(0.0, 1.0).toDouble() : (oldValue / maxTarget).clamp(0.0, 1.0).toDouble(),
            ),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              // Interpolacion inversa para mostrar el numero animado
              final animatedValue = oldValue + (newValue - oldValue) * (_showAnimations ? (value - (oldValue/maxTarget)) / ((newValue/maxTarget) - (oldValue/maxTarget) == 0 ? 1 : (newValue/maxTarget) - (oldValue/maxTarget)) : 0);
              
              final isUnlocked = value >= 1.0 && unlockedThisSession != null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                         unlockedThisSession != null ? unlockedThisSession.icon : nextAch.icon, 
                         size: 20, 
                         color: isUnlocked ? Colors.amber : theme.colorScheme.primary
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 12,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                               isUnlocked ? Colors.amber : theme.colorScheme.primary
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${animatedValue.toStringAsFixed(animatedValue == animatedValue.toInt() ? 0 : 1)} / ${target.toInt()} ${nextAch.unit}",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isUnlocked ? Colors.amber : null,
                        ),
                      ),
                    ],
                  ),
                  if (isUnlocked) ...[
                     const SizedBox(height: 4),
                     Text(
                        unlockedThisSession.title, 
                        style: const TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
                     ),
                  ] else ...[
                     const SizedBox(height: 4),
                     Text(
                        "Próximo: ${nextAch.title}", 
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                     ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(ThemeData theme) {
    List<Widget> bars = [];
    
    // Evaluate progress bars
    _statToGroup.forEach((statKey, groupId) {
       final oldVal = widget.oldStats[statKey] ?? 0;
       final newVal = widget.newStats[statKey] ?? 0;
       
       if (newVal > oldVal) {
          final nextAch = _getNextTarget(groupId, oldVal);
          final unlocked = _getJustUnlocked(groupId, oldVal, newVal);
          
          if (nextAch != null || unlocked != null) {
              String label = "";
              switch(statKey) {
                 case 'totalWorkouts': label = "Entrenamientos Totales"; break;
                 case 'totalVolume': label = "Volumen Total Movido"; break;
                 case 'maxVolumeSession': label = "Volumen en Sesión"; break;
                 case 'maxStreak': label = "Racha Actual"; break;
                 case 'maxWeeklySessions': label = "Sesiones en la Semana"; break;
              }

              bars.add(_buildProgressBar(
                  theme, 
                  label, 
                  oldVal, 
                  newVal, 
                  nextAch ?? unlocked!, 
                  unlocked
              ));
              bars.add(const Divider(height: 1, color: Colors.white10));
          }
       }
    });

    if (bars.isEmpty) return const SizedBox();

    return Card(
      color: theme.colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
               "Tu Progreso", 
               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...bars,
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockedAchievementsSection(ThemeData theme) {
    if (widget.unlockedAchievements.isEmpty) return const SizedBox();

    List<Widget> achievementWidgets = widget.unlockedAchievements.map((a) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(a.icon, color: Colors.amber, size: 24),
        ),
        title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(a.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }).toList();

    return Card(
      color: theme.colorScheme.surface,
      elevation: 4,
      shadowColor: Colors.amber.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.amber.withOpacity(0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.emoji_events, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                   "¡Logros Desbloqueados!", 
                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...achievementWidgets,
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsSection(ThemeData theme) {
    if (widget.progressAlerts.isEmpty) return const SizedBox();

    List<Widget> alertWidgets = widget.progressAlerts.map((a) {
      IconData id; Color c;
      switch (a.type) {
        case ProgressAlertType.newPR: id = Icons.emoji_events; c = Colors.amber; break;
        case ProgressAlertType.heaviestSet: id = Icons.fitness_center; c = Colors.deepPurpleAccent; break;
        case ProgressAlertType.sessionVolumePR: id = Icons.bar_chart; c = Colors.blueAccent; break;
        case ProgressAlertType.bestWeekEver: id = Icons.calendar_today; c = Colors.green; break;
        case ProgressAlertType.improvedEfficiency: id = Icons.psychology; c = Colors.teal; break;
        default: id = Icons.star; c = Colors.orange; break;
      }

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(id, color: c, size: 24),
        ),
        title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: a.explanation.isNotEmpty 
            ? Text(a.explanation, style: const TextStyle(fontSize: 12, color: Colors.grey))
            : null,
      );
    }).toList();

    return Card(
      color: theme.colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
               "¡Récords de la Sesión!", 
               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...alertWidgets,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background Gradient effect
          Positioned.fill(
             child: Container(
                decoration: BoxDecoration(
                   gradient: LinearGradient(
                      colors: [
                         theme.colorScheme.primary.withOpacity(0.1),
                         theme.scaffoldBackgroundColor,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                   ),
                ),
             )
          ),
          SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        _buildSummaryHeader(theme),
                        if (widget.unlockedAchievements.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildUnlockedAchievementsSection(theme),
                        ],
                        if (widget.progressAlerts.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildAlertsSection(theme),
                        ],
                        const SizedBox(height: 24),
                        _buildProgressSection(theme),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: () {
                             if (Navigator.canPop(context)) {
                                Navigator.pop(context); // Pop summary
                                Navigator.pop(context); // Pop log workout screen
                             }
                          },
                          style: ElevatedButton.styleFrom(
                             padding: const EdgeInsets.symmetric(vertical: 16),
                             backgroundColor: theme.colorScheme.primary,
                             foregroundColor: theme.colorScheme.onPrimary,
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Continuar", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Confetti Overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple
              ],
            ),
          ),
        ],
      ),
    );
  }
}
