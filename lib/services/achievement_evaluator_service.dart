import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import '../models/achievement.dart';
import '../models/muscle_catalog.dart';

class AchievementEvaluatorService {
  static Future<List<Achievement>> evaluateSession(
    List<Map<String, dynamic>> performed,
    DateTime finishedAt,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final List<Achievement> newlyUnlocked = [];
    final achievementsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('achievements');

    final unlockedSnap = await achievementsRef.get();
    final unlockedIds = unlockedSnap.docs.map((d) => d.id).toSet();

    double sessionVolume = 0;
    bool hasRpe10 = false;
    bool hasAnyRpe = false;
    double maxWeightInSession = 0;
    double averageRpe = 0;
    int totalRpeRegistrations = 0;

    for (final block in performed) {
      final String type = block['type'] ?? 'Series';
      final isCircuit = type == 'Circuito';

      if (isCircuit) {
        final rounds = block['rounds'] as List? ?? [];
        for (final r in rounds) {
          final exs = r['exercises'] as List? ?? [];
          for (final ex in exs) {
            final reps = (ex['reps'] as num?)?.toInt() ?? 0;
            final weight = (ex['weight'] as num?)?.toDouble() ?? 0.0;
            final rpe = (ex['rpe'] as num?)?.toInt() ?? 0;
            final multiplier = ex['perSide'] == true ? 2 : 1;
            
            sessionVolume += reps * weight * multiplier;
            if (rpe > 0) {
              hasAnyRpe = true;
              averageRpe += rpe;
              totalRpeRegistrations++;
            }
            if (rpe >= 10) hasRpe10 = true;
            maxWeightInSession = max(maxWeightInSession, weight);
          }
        }
      } else if (type == 'Series' || type == 'Series descendentes' || type == 'Buscar RM') {
        final exs = block['exercises'] as List? ?? [];
        for (final ex in exs) {
          final sets = ex['sets'] as List? ?? [];
          for (final s in sets) {
            final reps = (s['reps'] as num?)?.toInt() ?? 0;
            final weight = (s['weight'] as num?)?.toDouble() ?? 0.0;
            final rpe = (s['rpe'] as num?)?.toInt() ?? 0;

            final bool perSide = (ex['perSide'] == true) || (s['perSide'] == true);
            final multiplier = perSide ? 2 : 1;

            sessionVolume += reps * weight * multiplier;
            if (rpe > 0) {
              hasAnyRpe = true;
              averageRpe += rpe;
              totalRpeRegistrations++;
            }
            if (rpe >= 10) hasRpe10 = true;
            maxWeightInSession = max(maxWeightInSession, weight);
          }
        }
      }
    }

    if (totalRpeRegistrations > 0) {
      averageRpe /= totalRpeRegistrations;
    }

    final statsRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('stats').doc('global');
    
    int totalWorkouts = 1;
    double totalVolume = sessionVolume;
    double runningMaxWeight = maxWeightInSession;
    double runningMaxVolumeSession = sessionVolume;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snap = await transaction.get(statsRef);
      if (snap.exists) {
        final data = snap.data()!;
        totalWorkouts = (data['totalWorkouts'] as num?)?.toInt() ?? 0;
        totalVolume = (data['totalVolume'] as num?)?.toDouble() ?? 0.0;
        double currentMaxWeight = (data['maxWeight'] as num?)?.toDouble() ?? 0.0;
        double currentMaxVolume = (data['maxVolumeSession'] as num?)?.toDouble() ?? 0.0;

        totalWorkouts += 1;
        totalVolume += sessionVolume;
        runningMaxWeight = max(currentMaxWeight, maxWeightInSession);
        runningMaxVolumeSession = max(currentMaxVolume, sessionVolume);
        
        transaction.update(statsRef, {
          'totalWorkouts': totalWorkouts,
          'totalVolume': totalVolume,
          'maxWeight': runningMaxWeight,
          'maxVolumeSession': runningMaxVolumeSession,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(statsRef, {
          'totalWorkouts': 1,
          'totalVolume': sessionVolume,
          'maxWeight': maxWeightInSession,
          'maxVolumeSession': sessionVolume,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    final muscleStateRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('muscle_state');
    final muscleSnaps = await muscleStateRef.get();

    Map<String, double> stateFatigue = {};
    for (final mSnap in muscleSnaps.docs) {
      stateFatigue[mSnap.id] = (mSnap.data()['fatigue'] as num?)?.toDouble() ?? 0.0;
    }

    double currentMaxFatigue = 0;
    for (final groupMuscles in anatomicalGroups.values) {
      double sum = 0;
      int count = 0;
      for (final muscle in groupMuscles) {
        sum += stateFatigue[muscle.name] ?? 0.0;
        count++;
      }
      if (count > 0) {
        double avg = sum / count;
        if (avg > currentMaxFatigue) {
          currentMaxFatigue = avg;
        }
      }
    }

    bool unlockedEfficiencyMaster = totalRpeRegistrations > 0 && averageRpe <= 6.0 && sessionVolume >= 2000;
    bool unlockedEarlyBird = finishedAt.hour < 8;
    bool unlockedNightOwl = finishedAt.hour >= 22;
    bool unlockedRpeMaestro = hasAnyRpe && !hasRpe10;

    await _evaluateGeneric(
       uid: uid, 
       unlockedIds: unlockedIds, 
       newlyUnlocked: newlyUnlocked,
       totalWorkouts: totalWorkouts,
       sessionVolume: sessionVolume,
       totalVolume: totalVolume,
       maxWeightInSession: runningMaxWeight,
       maxVolumeSession: runningMaxVolumeSession,
       unlockedRpeMaestro: unlockedRpeMaestro,
       unlockedEarlyBird: unlockedEarlyBird,
       unlockedNightOwl: unlockedNightOwl,
       maxFatigueReached: currentMaxFatigue,
       unlockedEfficiencyMaster: unlockedEfficiencyMaster,
       sessionAvgRpe: hasAnyRpe ? averageRpe : 0.0,
       timestampData: FieldValue.serverTimestamp(),
    );

    // ── Racha y semana (requieren leer historial) ──────────────
    await _evaluateStreakAndWeekly(
      uid: uid,
      unlockedIds: unlockedIds,
      newlyUnlocked: newlyUnlocked,
      timestampData: FieldValue.serverTimestamp(),
    );

    return newlyUnlocked;
  }

  /// Consulta workouts_logged para calcular la racha actual y el máximo de sesiones/semana,
  /// y desbloquea los logros correspondientes.
  static Future<void> _evaluateStreakAndWeekly({
    required String uid,
    required Set<String> unlockedIds,
    required List<Achievement> newlyUnlocked,
    required dynamic timestampData,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('workouts_logged')
        .where('userId', isEqualTo: uid)
        .get();

    final Set<DateTime> uniqueDays = {};
    final Map<DateTime, int> sessionsPerWeek = {};

    for (final doc in snap.docs) {
      final date = (doc.data()['date'] as Timestamp?)?.toDate();
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      uniqueDays.add(day);

      // Semana = lunes de esa semana. En local, si weekStart se descuadra por timezone puede fallar. En su lugar:
      final weekStart = DateTime(day.year, day.month, day.day).subtract(Duration(days: day.weekday - 1));
      sessionsPerWeek[weekStart] = (sessionsPerWeek[weekStart] ?? 0) + 1;
    }

    // -- Streak actual --
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));
    DateTime? startCheck;
    if (uniqueDays.contains(todayDate)) {
      startCheck = todayDate;
    } else if (uniqueDays.contains(yesterday)) {
      startCheck = yesterday;
    }
    int currentStreak = 0;
    if (startCheck != null) {
      DateTime check = startCheck;
      while (uniqueDays.contains(check)) {
        currentStreak++;
        check = check.subtract(const Duration(days: 1));
      }
    }

    // -- Máximo de sesiones en una semana --
    int maxWeeklySessions = sessionsPerWeek.values.fold(0, max);

    // -- Actualizar stats globales con estos valores --
    final statsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('global');
    await statsRef.set({
      'maxStreak': currentStreak,
      'maxWeeklySessions': maxWeeklySessions,
    }, SetOptions(merge: true));

    // -- Evaluar logros de racha --
    for (final ach in achievementsCatalog.where((a) => a.groupId == 'streak')) {
      if (unlockedIds.contains(ach.id)) continue;
      if (currentStreak >= ach.targetValue) {
        await _unlockAndAdd(uid, ach.id, newlyUnlocked, timestampData);
        unlockedIds.add(ach.id);
      }
    }

    // -- Evaluar logros de sesiones semanales --
    for (final ach in achievementsCatalog.where((a) => a.groupId == 'weekly')) {
      if (unlockedIds.contains(ach.id)) continue;
      if (maxWeeklySessions >= ach.targetValue) {
        await _unlockAndAdd(uid, ach.id, newlyUnlocked, timestampData);
        unlockedIds.add(ach.id);
      }
    }
  }

  static Future<void> _evaluateGeneric({
    required String uid,
    required Set<String> unlockedIds,
    required List<Achievement> newlyUnlocked,
    required int totalWorkouts,
    required double sessionVolume,
    required double totalVolume,
    required double maxWeightInSession,
    required double maxVolumeSession,
    required bool unlockedRpeMaestro,
    required bool unlockedEarlyBird,
    required bool unlockedNightOwl,
    required double maxFatigueReached,
    required bool unlockedEfficiencyMaster,
    required dynamic timestampData,
    double sessionAvgRpe = 0.0,
    double maxSessionAvgRpe = 0.0,
    Map<String, dynamic>? calculatedUnlocksMap,
  }) async {
    for (final ach in achievementsCatalog) {
      if (unlockedIds.contains(ach.id)) continue;
      
      bool meetsCondition = false;
      
      if (ach.id == 'first_workout') {
        meetsCondition = totalWorkouts >= 1;
      } else if (ach.id == 'early_bird') {
        meetsCondition = unlockedEarlyBird;
      } else if (ach.id == 'night_owl') {
        meetsCondition = unlockedNightOwl;
      } else if (ach.id == 'rpe_maestro') {
        meetsCondition = unlockedRpeMaestro;
      } else if (ach.id == 'efficiency_master') {
        meetsCondition = unlockedEfficiencyMaster;
      } else if (ach.groupId == 'fatigue') {
        meetsCondition = maxFatigueReached >= ach.targetValue;
      } else if (ach.groupId == 'workouts') {
        meetsCondition = totalWorkouts >= ach.targetValue;
      } else if (ach.groupId == 'strength') {
        meetsCondition = maxWeightInSession >= ach.targetValue;
      } else if (ach.groupId == 'vol_session') {
        meetsCondition = maxVolumeSession >= ach.targetValue;
      } else if (ach.groupId == 'total_vol') {
        meetsCondition = totalVolume >= ach.targetValue;
      } else if (ach.groupId == 'avg_rpe') {
        // Desbloquear si la sesión actual o el histórico máximo llegan al umbral (mín 6.5)
        final best = max(sessionAvgRpe, maxSessionAvgRpe);
        meetsCondition = best >= ach.targetValue;
      } else if (ach.category == AchievementCategory.volume) {
        if (ach.id.contains("session") || ach.id == "vol_10k") {
          meetsCondition = maxVolumeSession >= ach.targetValue;
        } else {
          meetsCondition = totalVolume >= ach.targetValue;
        }
      }
      
      if (meetsCondition) {
        if (calculatedUnlocksMap != null) {
          calculatedUnlocksMap[ach.id] = timestampData;
        } else {
          await _unlockAndAdd(uid, ach.id, newlyUnlocked, timestampData);
        }
        unlockedIds.add(ach.id);
      }
    }
  }

  static Future<void> _unlockAndAdd(String uid, String actId, List<Achievement> newlyUnlocked, dynamic timestampData) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('achievements')
        .doc(actId)
        .set({
      'unlockedAt': timestampData,
    });
    
    try {
      newlyUnlocked.add(achievementsCatalog.firstWhere((a) => a.id == actId));
    } catch (_) {}
  }

  static Future<void> syncHistoricalData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final workoutsSnap = await FirebaseFirestore.instance
        .collection('workouts_logged')
        .where('userId', isEqualTo: uid)
        .get();

    final docs = workoutsSnap.docs.toList();
    docs.sort((a, b) {
      final tA = a.data()['finishedAt'] as Timestamp?;
      final tB = b.data()['finishedAt'] as Timestamp?;
      if (tA == null && tB == null) return 0;
      if (tA == null) return 1;
      if (tB == null) return -1;
      return tA.compareTo(tB);
    });

    final achievementsRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('achievements');
    final unlockedSnap = await achievementsRef.get();

    // Mapa en memoria para el nuevo cálculo y limpieza
    final Map<String, dynamic> calculatedUnlocks = {};
    final unlockedIds = <String>{};
    final List<Achievement> dummy = [];

    int runningTotalWorkouts = 0;
    double runningTotalVolume = 0;
    double runningGlobalMaxWeight = 0;
    double runningGlobalMaxVolumeSession = 0;

    // Evaluate historically, block by block, workout by workout
    for (final doc in docs) {
      final data = doc.data();
      final performed = List<Map<String, dynamic>>.from(data['performed'] ?? []);
      
      DateTime finishedDt = DateTime.now();
      if (data['finishedAt'] != null) {
        finishedDt = (data['finishedAt'] as Timestamp).toDate();
      }
      
      double sessionVolume = 0;
      bool hasRpe10 = false;
      bool hasAnyRpe = false;
      double maxWeightInSession = 0;
      
      double averageRpe = 0;
      int totalRpeRegistrations = 0;

      for (final block in performed) {
        final String type = block['type'] ?? 'Series';
        final isCircuit = type == 'Circuito';

        if (isCircuit) {
          final rounds = block['rounds'] as List? ?? [];
          for (final r in rounds) {
            final exs = r['exercises'] as List? ?? [];
            for (final ex in exs) {
              final reps = (ex['reps'] as num?)?.toInt() ?? 0;
              final weight = (ex['weight'] as num?)?.toDouble() ?? 0.0;
              final rpe = (ex['rpe'] as num?)?.toInt() ?? 0;
              final multiplier = ex['perSide'] == true ? 2 : 1;
              
              sessionVolume += reps * weight * multiplier;
              if (rpe > 0) {
                hasAnyRpe = true;
                averageRpe += rpe;
                totalRpeRegistrations++;
              }
              if (rpe >= 10) hasRpe10 = true;
              maxWeightInSession = max(maxWeightInSession, weight);
            }
          }
        } else if (type == 'Series' || type == 'Series descendentes' || type == 'Buscar RM') {
          final exs = block['exercises'] as List? ?? [];
          for (final ex in exs) {
            final sets = ex['sets'] as List? ?? [];
            for (final s in sets) {
              final reps = (s['reps'] as num?)?.toInt() ?? 0;
              final weight = (s['weight'] as num?)?.toDouble() ?? 0.0;
              final rpe = (s['rpe'] as num?)?.toInt() ?? 0;

              final bool perSide = (ex['perSide'] == true) || (s['perSide'] == true);
              final multiplier = perSide ? 2 : 1;

              sessionVolume += reps * weight * multiplier;
              if (rpe > 0) {
                hasAnyRpe = true;
                averageRpe += rpe;
                totalRpeRegistrations++;
              }
              if (rpe >= 10) hasRpe10 = true;
              maxWeightInSession = max(maxWeightInSession, weight);
            }
          }
        }
      }

      runningTotalWorkouts++;
      runningTotalVolume += sessionVolume;
      runningGlobalMaxVolumeSession = max(runningGlobalMaxVolumeSession, sessionVolume);
      runningGlobalMaxWeight = max(runningGlobalMaxWeight, maxWeightInSession);

      double sessionAvgRpe = totalRpeRegistrations > 0 ? averageRpe / totalRpeRegistrations : 0.0;

      bool unlockedRpeMaestro = hasAnyRpe && !hasRpe10;
      bool unlockedEfficiencyMaster = totalRpeRegistrations > 0 && sessionAvgRpe <= 6.0 && sessionVolume >= 2000;
      bool unlockedEarlyBird = finishedDt.hour < 8;
      bool unlockedNightOwl = finishedDt.hour >= 22;

      await _evaluateGeneric(
        uid: uid, 
        unlockedIds: unlockedIds, 
        newlyUnlocked: dummy,
        totalWorkouts: runningTotalWorkouts,
        sessionVolume: sessionVolume,
        totalVolume: runningTotalVolume,
        maxWeightInSession: runningGlobalMaxWeight,
        maxVolumeSession: runningGlobalMaxVolumeSession,
        unlockedRpeMaestro: unlockedRpeMaestro,
        unlockedEarlyBird: unlockedEarlyBird,
        unlockedNightOwl: unlockedNightOwl,
        maxFatigueReached: 0,
        unlockedEfficiencyMaster: unlockedEfficiencyMaster,
        sessionAvgRpe: sessionAvgRpe,
        timestampData: Timestamp.fromDate(finishedDt),
        calculatedUnlocksMap: calculatedUnlocks,
      );
    }

    // Evaluate Fatigue in history 
    final auditRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('fatigue_audit');
    final auditSnaps = await auditRef.orderBy('workoutDate').get();
    
    double historicalMaxFatigue = 0;
    Map<int, DateTime> fatigueLevelDates = {};

    for (final doc in auditSnaps.docs) {
      final data = doc.data();
      final fatigueAfter = data['fatigueAfter'] as Map<String, dynamic>? ?? {};
      DateTime? currentWorkoutDate;
      if (data['workoutDate'] != null) {
        currentWorkoutDate = (data['workoutDate'] as Timestamp).toDate();
      }
      
      double currentGroupMax = 0;
      for (final groupMuscles in anatomicalGroups.values) {
        double sum = 0;
        int count = 0;
        for (final muscle in groupMuscles) {
          final val = fatigueAfter[muscle.name];
          sum += (val as num?)?.toDouble() ?? 0.0;
          count++;
        }
        if (count > 0) {
          double avg = sum / count;
          if (avg > currentGroupMax) {
            currentGroupMax = avg;
          }
        }
      }

      if (currentGroupMax > historicalMaxFatigue) {
        historicalMaxFatigue = currentGroupMax;
      }

      final targets = [35.0, 50.0, 70.0, 85.0, 100.0];
      for (int level = 1; level <= 5; level++) {
         double target = targets[level - 1];
         if (currentGroupMax >= target && !fatigueLevelDates.containsKey(level)) {
            if (currentWorkoutDate != null) {
                fatigueLevelDates[level] = currentWorkoutDate;
            }
         }
      }
    }

    // Populate calculatedUnlocks for fatigue levels
    final targets = [35.0, 50.0, 70.0, 85.0, 100.0];
    for (int level = 1; level <= 5; level++) {
        double target = targets[level - 1];
        if (fatigueLevelDates.containsKey(level)) {
            calculatedUnlocks['fatigue_l$level'] = Timestamp.fromDate(fatigueLevelDates[level]!);
        } else if (historicalMaxFatigue >= target) {
            calculatedUnlocks['fatigue_l$level'] = FieldValue.serverTimestamp();
        }
    }

    // ── Calcular fechas históricas reales de streak / weekly / avg_rpe ──
    // Los docs ya están ordenados cronológicamente (por finishedAt) desde el inicio de syncHistoricalData.

    // --- avg_rpe: primera sesión donde el promedio superó cada umbral ---
    final rpeTargets = [6.5, 7.0, 7.5, 8.0, 9.0];
    final Map<int, DateTime> avgRpeLevelDates = {}; // level → fecha
    for (final doc in docs) {
      final docDate = (doc.data()['finishedAt'] as Timestamp?)?.toDate() ??
          (doc.data()['date'] as Timestamp?)?.toDate();
      if (docDate == null) continue;
      final performed = List<Map<String, dynamic>>.from(doc.data()['performed'] ?? []);
      double rpeSum = 0; int rpeCount = 0;
      for (final block in performed) {
        final type = block['type'] ?? '';
        if (type == 'Circuito') {
          for (final r in (block['rounds'] as List? ?? [])) {
            for (final ex in (r['exercises'] as List? ?? [])) {
              final rpe = (ex['rpe'] as num?)?.toDouble() ?? 0;
              if (rpe > 0) { rpeSum += rpe; rpeCount++; }
            }
          }
        } else if (type == 'Series' || type == 'Series descendentes' || type == 'Buscar RM') {
          for (final ex in (block['exercises'] as List? ?? [])) {
            for (final s in (ex['sets'] as List? ?? [])) {
              final rpe = (s['rpe'] as num?)?.toDouble() ?? 0;
              if (rpe > 0) { rpeSum += rpe; rpeCount++; }
            }
          }
        }
      }
      if (rpeCount > 0) {
        final sessionAvg = rpeSum / rpeCount;
        for (int level = 1; level <= 5; level++) {
          if (!avgRpeLevelDates.containsKey(level) && sessionAvg >= rpeTargets[level - 1]) {
            avgRpeLevelDates[level] = docDate;
          }
        }
      }
    }
    double runningMaxAvgRpe = avgRpeLevelDates.isEmpty ? 0.0 : rpeTargets[avgRpeLevelDates.keys.reduce(max) - 1];

    // --- streak y weekly: iterar días ordenados y rastrear primera vez que se alcanzó cada nivel ---
    // Construir lista ordenada de días únicos (una entrada por día aunque haya múltiples sesiones)
    // y también sessions-per-week con su primera fecha de cierre.
    final List<DateTime> allDays = [];          // una celda por SESIÓN (para weekly)
    final Map<DateTime, DateTime> weekFirstDate = {}; // weekStart → primer día de esa semana con sesión
    final Set<DateTime> seenDays = {};

    for (final doc in docs) {
      final date = (doc.data()['date'] as Timestamp?)?.toDate() ??
          (doc.data()['finishedAt'] as Timestamp?)?.toDate();
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      allDays.add(day);                         // para weekly (counts duplicates)
      seenDays.add(day);                        // único para streak
      final weekStart = DateTime(day.year, day.month, day.day).subtract(Duration(days: day.weekday - 1));
      weekFirstDate.putIfAbsent(weekStart, () => day);
    }

    // weekly: agrupar por semana y ver cuándo se alcanzó cada nivel
    final Map<DateTime, int> sessionsPerWeekSync = {};
    final Map<DateTime, DateTime> weekLastDate = {}; // weekStart → última sesión de esa semana
    for (final doc in docs) {
      final date = (doc.data()['date'] as Timestamp?)?.toDate() ??
          (doc.data()['finishedAt'] as Timestamp?)?.toDate();
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      final weekStart = DateTime(day.year, day.month, day.day).subtract(Duration(days: day.weekday - 1));
      sessionsPerWeekSync[weekStart] = (sessionsPerWeekSync[weekStart] ?? 0) + 1;
      weekLastDate[weekStart] = day; // se sobreescribe → queda el último día de esa semana
    }
    // Para weekly: primera semana donde se alcanzó cada nivel
    final weeklyTargets = [2, 3, 4, 5, 6];
    final Map<int, DateTime> weeklyLevelDates = {};
    // iterar semanas en orden cronológico
    final sortedWeeks = sessionsPerWeekSync.keys.toList()..sort();
    for (final week in sortedWeeks) {
      final count = sessionsPerWeekSync[week]!;
      for (int level = 1; level <= 5; level++) {
        if (!weeklyLevelDates.containsKey(level) && count >= weeklyTargets[level - 1]) {
          // usar la fecha de la última sesión de esa semana (cuando "se completó")
          weeklyLevelDates[level] = weekLastDate[week]!;
        }
      }
    }
    int syncMaxWeekly = sessionsPerWeekSync.values.fold(0, max);

    // streak: para cada nivel, encontrar la primera fecha donde se alcanzó esa racha consecutiva
    final streakTargets = [2, 3, 5, 7, 10];
    final Map<int, DateTime> streakLevelDates = {};
    final sortedUniqueDays = seenDays.toList()..sort();
    // Calcular racha acumulada iterando días en orden
    int runningStrk = 0;
    for (int i = 0; i < sortedUniqueDays.length; i++) {
      if (i == 0) {
        runningStrk = 1;
      } else {
        final diff = sortedUniqueDays[i].difference(sortedUniqueDays[i - 1]).inDays;
        runningStrk = diff == 1 ? runningStrk + 1 : 1;
      }
      final dayDate = sortedUniqueDays[i];
      for (int level = 1; level <= 5; level++) {
        if (!streakLevelDates.containsKey(level) && runningStrk >= streakTargets[level - 1]) {
          streakLevelDates[level] = dayDate;
        }
      }
    }
    // Racha actual (para stats)
    final today2 = DateTime.now();
    final todayDate2 = DateTime(today2.year, today2.month, today2.day);
    final yesterday2 = todayDate2.subtract(const Duration(days: 1));
    DateTime? startCheck;
    if (seenDays.contains(todayDate2)) { startCheck = todayDate2; }
    else if (seenDays.contains(yesterday2)) { startCheck = yesterday2; }
    int syncStreak = 0;
    if (startCheck != null) {
      DateTime check = startCheck;
      while (seenDays.contains(check)) { syncStreak++; check = check.subtract(const Duration(days: 1)); }
    }

    // Poblar calculatedUnlocks con fechas históricas reales
    for (int level = 1; level <= 5; level++) {
      if (avgRpeLevelDates.containsKey(level)) {
        calculatedUnlocks['avg_rpe_l$level'] = Timestamp.fromDate(avgRpeLevelDates[level]!);
      }
      if (streakLevelDates.containsKey(level)) {
        calculatedUnlocks['streak_l$level'] = Timestamp.fromDate(streakLevelDates[level]!);
      }
      if (weeklyLevelDates.containsKey(level)) {
        calculatedUnlocks['weekly_l$level'] = Timestamp.fromDate(weeklyLevelDates[level]!);
      }
    }

    await FirebaseFirestore.instance.collection('users').doc(uid).collection('stats').doc('global').set({
      'totalWorkouts': runningTotalWorkouts,
      'totalVolume': runningTotalVolume,
      'maxWeight': runningGlobalMaxWeight,
      'maxVolumeSession': runningGlobalMaxVolumeSession,
      'maxFatigue': historicalMaxFatigue,
      'maxStreak': syncStreak,
      'maxWeeklySessions': syncMaxWeekly,
      'maxSessionAvgRpe': runningMaxAvgRpe,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Reflejar `calculatedUnlocks` en Firestore (Batch para evitar múltiples writes)
    final batch = FirebaseFirestore.instance.batch();
    
    // Obtener las llaves válidas para no borrar logs viejos a menos que esten en el catalogo
    final catalogIds = achievementsCatalog.map((a) => a.id).toSet();

    for (final doc in unlockedSnap.docs) {
      // Si el usuario tenía un logro que ahora no corresponde, se elimina
      if (catalogIds.contains(doc.id) && !calculatedUnlocks.containsKey(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    for (final entry in calculatedUnlocks.entries) {
      final docRef = achievementsRef.doc(entry.key);
      batch.set(docRef, {'unlockedAt': entry.value});
    }

    await batch.commit();
  }
}
