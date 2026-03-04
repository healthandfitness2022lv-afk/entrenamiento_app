import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/achievement.dart';
import '../services/achievement_evaluator_service.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold();

    final achievementsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('achievements')
        .snapshots();

    final statsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('global')
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Vitrina de Logros", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF5F5F5))),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF121212),
        iconTheme: const IconThemeData(color: Color(0xFF39FF14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: "Sincronizar historial",
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Sincronizando entrenamientos... esto puede tomar unos segundos.")),
              );
              await AchievementEvaluatorService.syncHistoricalData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("¡Historial sincronizado y logros evaluados!")),
                );
              }
            },
          )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: statsStream,
        builder: (context, statsSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: achievementsStream,
            builder: (context, achSnap) {
              if (statsSnap.connectionState == ConnectionState.waiting || 
                  achSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final unlockedDocs = achSnap.data?.docs ?? [];
              final unlockedMap = <String, DateTime>{};

              for (final doc in unlockedDocs) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['unlockedAt'] != null) {
                  unlockedMap[doc.id] = (data['unlockedAt'] as Timestamp).toDate();
                } else {
                  unlockedMap[doc.id] = DateTime.now(); // Fallback
                }
              }

              final statsData = statsSnap.data?.data() as Map<String, dynamic>? ?? {};

              // Agrupar por categoría
              final Map<AchievementCategory, List<Achievement>> grouped = {
                for (var c in AchievementCategory.values) c: [],
              };

              for (final ach in achievementsCatalog) {
                grouped[ach.category]!.add(ach);
              }

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  _headerSummary(unlockedMap.length, achievementsCatalog.length),
                  const SizedBox(height: 24),
                  
                  ...AchievementCategory.values.map((category) {
                    final categoryAll = grouped[category]!;
                    if (categoryAll.isEmpty) return const SizedBox();

                    final standalones = <Achievement>[];
                    final Map<String, List<Achievement>> groupMap = {};
                    
                    for (final ach in categoryAll) {
                      if (ach.groupId.isNotEmpty) {
                        groupMap.putIfAbsent(ach.groupId, () => []).add(ach);
                      } else {
                        standalones.add(ach);
                      }
                    }

                    final List<Widget> groupWidgets = [];
                    for (final entry in groupMap.entries) {
                      final list = entry.value;
                      list.sort((a, b) => a.level.compareTo(b.level));
                      
                      Achievement? currentAim;
                      bool fullyUnlocked = true;
                      for (final ach in list) {
                        if (!unlockedMap.containsKey(ach.id)) {
                          currentAim = ach;
                          fullyUnlocked = false;
                          break;
                        }
                      }
                      currentAim ??= list.last; // Si tiene todos, mostrar el maximo nivel

                      groupWidgets.add(_buildGroupedCard(
                        context, 
                        list, 
                        currentAim, 
                        fullyUnlocked, 
                        unlockedMap, 
                        statsData
                      ));
                    }

                    final List<Widget> standaloneWidgets = standalones.map((ach) => _buildAchievementCard(
                      achievement: ach,
                      isUnlocked: unlockedMap.containsKey(ach.id),
                      unlockedDate: unlockedMap[ach.id],
                      stats: statsData,
                    )).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _categoryTitle(category),
                        ...groupWidgets,
                        ...standaloneWidgets,
                        const SizedBox(height: 24),
                      ],
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _headerSummary(int unlockedCount, int totalCount) {
    final double percent = totalCount == 0 ? 0 : unlockedCount / totalCount;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: percent,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xFF222222),
                  color: const Color(0xFF39FF14),
                ),
              ),
              const Icon(Icons.emoji_events, size: 40, color: Color(0xFF39FF14)),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tu Colección",
                  style: TextStyle(fontSize: 16, color: Color(0xFFB8B8B8), fontWeight: FontWeight.w600),
                ),
                Text(
                  "$unlockedCount / $totalCount",
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFF5F5F5)),
                ),
                Text(
                  "Has desbloqueado el ${(percent * 100).toStringAsFixed(0)}% de los logros",
                  style: const TextStyle(fontSize: 14, color: Color(0xFF8A8A8A)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _categoryTitle(AchievementCategory category) {
    String title = "";
    Color color = const Color(0xFFF5F5F5);
    IconData icon = Icons.star;

    switch (category) {
      case AchievementCategory.constancy:
        title = "Constancia y Hábitos";
        color = Colors.orange;
        icon = Icons.loop;
        break;
      case AchievementCategory.volume:
        title = "Volumen de Trabajo";
        color = Colors.purpleAccent;
        icon = Icons.fitness_center;
        break;
      case AchievementCategory.strength:
        title = "Fuerza Bruta";
        color = Colors.redAccent;
        icon = Icons.local_fire_department;
        break;
      case AchievementCategory.intelligence:
        title = "Inteligencia Táctica";
        color = Colors.teal;
        icon = Icons.psychology;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF5F5F5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedCard(
    BuildContext context,
    List<Achievement> groupList,
    Achievement currentAim,
    bool fullyUnlocked,
    Map<String, DateTime> unlockedMap,
    Map<String, dynamic> stats
  ) {
    final bool isCurrentAimUnlocked = unlockedMap.containsKey(currentAim.id);
    final Color catColor = _getColorForCategory(currentAim.category);

    return GestureDetector(
      onTap: () => _showGroupDetails(context, groupList, unlockedMap, stats),
      child: Stack(
         children: [
           _buildAchievementCard(
             achievement: currentAim,
             isUnlocked: isCurrentAimUnlocked,
             unlockedDate: unlockedMap[currentAim.id],
             stats: stats,
           ),
           Positioned(
             right: 24,
             top: 24,
             child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
               decoration: BoxDecoration(
                 color: fullyUnlocked ? catColor.withOpacity(0.2) : const Color(0xFF222222),
                 borderRadius: BorderRadius.circular(12),
               ),
               child: Text(
                 "NIVEL ${currentAim.level}/${groupList.length}",
                 style: TextStyle(
                   fontSize: 10, 
                   fontWeight: FontWeight.w900, 
                   color: fullyUnlocked ? catColor : const Color(0xFF8A8A8A)
                 ),
               ),
             ),
           ),
         ]
      )
    );
  }

  void _showGroupDetails(BuildContext context, List<Achievement> groupList, Map<String, DateTime> unlockedMap, Map<String, dynamic> stats) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
         return Container(
           height: MediaQuery.of(ctx).size.height * 0.75,
           decoration: const BoxDecoration(
             color: Color(0xFF1B1B1B),
             borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
           ),
           child: Column(
             children: [
               const SizedBox(height: 12),
               Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(2))),
               const SizedBox(height: 16),
               const Text("Línea de Progreso", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFF5F5F5))),
               const SizedBox(height: 16),
               Expanded(
                 child: ListView.builder(
                   padding: const EdgeInsets.symmetric(horizontal: 16),
                   itemCount: groupList.length,
                   itemBuilder: (ctx, i) {
                     final ach = groupList[i];
                     final isUnlocked = unlockedMap.containsKey(ach.id);
                     return _buildAchievementCard(
                       achievement: ach,
                       isUnlocked: isUnlocked,
                       unlockedDate: unlockedMap[ach.id],
                       stats: stats,
                     );
                   }
                 )
               ),
               const SizedBox(height: 16),
             ]
           )
         );
      }
    );
  }

  Widget _buildAchievementCard({
    required Achievement achievement,
    required bool isUnlocked,
    required DateTime? unlockedDate,
    required Map<String, dynamic> stats,
  }) {
    Color catColor = _getColorForCategory(achievement.category);

    final double progressPercent = isUnlocked ? 1.0 : _calculateProgress(achievement, stats);
    final String progressText = isUnlocked 
      ? "Completado" 
      : _getProgressText(achievement, stats);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnlocked ? catColor.withOpacity(0.5) : const Color(0xFF222222),
          width: isUnlocked ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Barra de progreso de fondo cuando está bloqueado
            if (!isUnlocked && progressPercent > 0)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: MediaQueryData.fromWindow(WidgetsBinding.instance.window).size.width * progressPercent,
                child: Container(
                  color: catColor.withOpacity(0.05),
                ),
              ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Ícono / Medalla
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isUnlocked ? catColor.withOpacity(0.15) : const Color(0xFF222222),
                      shape: BoxShape.circle,
                      boxShadow: isUnlocked ? [
                        BoxShadow(
                          color: catColor.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ] : [],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          isUnlocked ? Icons.workspace_premium : achievement.icon,
                          color: isUnlocked ? catColor : const Color(0xFF5A5A5A),
                          size: 32,
                        ),
                        if (!isUnlocked)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1B1B1B),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.lock, size: 12, color: Color(0xFF8A8A8A)),
                            ),
                          )
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Textos
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          achievement.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isUnlocked ? const Color(0xFFF5F5F5) : const Color(0xFFCFCFCF),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          achievement.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: isUnlocked ? const Color(0xFFEAEAEA) : const Color(0xFF8A8A8A),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Barra y fechas
                        if (isUnlocked && unlockedDate != null)
                          Row(
                            children: [
                              Icon(Icons.stars, size: 16, color: catColor),
                              const SizedBox(width: 4),
                              Text(
                                "Obtenido el ${DateFormat('dd MMM yyyy', 'es_ES').format(unlockedDate)}",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: catColor,
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    progressText,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB8B8B8)),
                                  ),
                                  Text(
                                    "${(progressPercent * 100).toStringAsFixed(0)}%",
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: catColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: progressPercent,
                                backgroundColor: const Color(0xFF222222),
                                valueColor: AlwaysStoppedAnimation<Color>(catColor),
                                borderRadius: BorderRadius.circular(4),
                                minHeight: 6,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorForCategory(AchievementCategory category) {
    if (category == AchievementCategory.strength) return Colors.redAccent;
    if (category == AchievementCategory.volume) return Colors.purpleAccent;
    if (category == AchievementCategory.intelligence) return Colors.teal;
    if (category == AchievementCategory.constancy) return Colors.orange;
    return Colors.blue;
  }

  double _calculateProgress(Achievement auth, Map<String, dynamic> stats) {
    double current = _getCurrentStatValue(auth, stats);
    if (auth.targetValue <= 0) return 0;
    return (current / auth.targetValue).clamp(0.0, 1.0);
  }

  String _getProgressText(Achievement auth, Map<String, dynamic> stats) {
    double current = _getCurrentStatValue(auth, stats);
    
    if (auth.targetValue <= 1.0) {
      return "0 / 1";
    }

    // avg_rpe usa decimales
    if (auth.groupId == 'avg_rpe') {
      return "${current.toStringAsFixed(1)} / ${auth.targetValue.toStringAsFixed(1)} ${auth.unit}";
    }

    String currentFormatted = current.toStringAsFixed(0);
    String targetFormatted = auth.targetValue.toStringAsFixed(0);

    return "$currentFormatted / $targetFormatted ${auth.unit}";
  }

  double _getCurrentStatValue(Achievement auth, Map<String, dynamic> stats) {
    if (auth.id == "first_workout" || auth.groupId == "workouts") {
      return (stats['totalWorkouts'] as num?)?.toDouble() ?? 0.0;
    }
    if (auth.groupId == "vol_session") {
      return (stats['maxVolumeSession'] as num?)?.toDouble() ?? 0.0;
    }
    if (auth.groupId == "total_vol") {
      return (stats['totalVolume'] as num?)?.toDouble() ?? 0.0;
    }
    if (auth.category == AchievementCategory.volume) {
      if (auth.id.contains("session") || auth.id == "vol_10k") {
        return (stats['maxVolumeSession'] as num?)?.toDouble() ?? 0.0;
      } else {
        return (stats['totalVolume'] as num?)?.toDouble() ?? 0.0;
      }
    }
    if (auth.groupId == "strength" || auth.id.contains("super_heavy") || auth.id.contains("elite") || auth.id.contains("heavy_lifter")) {
      return (stats['maxWeight'] as num?)?.toDouble() ?? 0.0;
    }
    if (auth.groupId == "fatigue") {
      return (stats['maxFatigue'] as num?)?.toDouble() ?? 0.0;
    }
    if (auth.groupId == "streak") {
      return (stats['maxStreak'] as num?)?.toDouble() ?? 0.0;
    }
    if (auth.groupId == "weekly") {
      return (stats['maxWeeklySessions'] as num?)?.toDouble() ?? 0.0;
    }
    if (auth.groupId == "avg_rpe") {
      return (stats['maxSessionAvgRpe'] as num?)?.toDouble() ?? 0.0;
    }
    
    return 0.0;
  }
}
