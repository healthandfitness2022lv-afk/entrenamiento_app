import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/workout_rpe_utils.dart';
import '../utils/workout_block_order.dart';
import 'my_workout_details_screen.dart';
import '../services/workout_volume_service.dart';
import 'log_workout_screen.dart';

import '../models/achievement.dart';
import '../services/progress_alert_service.dart';
import '../services/workout_rm_service.dart';
import '../services/athlete_selection_service.dart';
import '../theme/app_theme.dart';

class MyWorkoutsScreen extends StatefulWidget {
  final String? initialAthleteId;
  final String? initialAthleteName;

  const MyWorkoutsScreen({
    super.key,
    this.initialAthleteId,
    this.initialAthleteName,
  });

  @override
  State<MyWorkoutsScreen> createState() => _MyWorkoutsScreenState();
}

class _MyWorkoutsScreenState extends State<MyWorkoutsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final user = FirebaseAuth.instance.currentUser;

  String? role;
  String? selectedAthleteId;
  String? selectedAthleteName;
  bool _loading = true;

  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: 0);
    _initialize();
  }

  Future<void> _initialize() async {
    if (user == null) return;

    final userDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();

    role = userDoc.data()?['role'];

    selectedAthleteId = widget.initialAthleteId;
    selectedAthleteName = widget.initialAthleteName;

    if (selectedAthleteId == null && role == 'administrador') {
      final saved = await AthleteSelectionService.load();
      if (saved != null) {
        selectedAthleteId = saved['id'];
        selectedAthleteName = saved['name'];
      }
    }

    selectedAthleteId ??= user!.uid;
    selectedAthleteName ??= userDoc.data()?['name'];

    setState(() => _loading = false);
  }

  Future<void> _selectAthlete() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('users')
            .where('role', whereIn: ['atleta', 'administrador'])
            .get();

    final users = snapshot.docs;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: const Text("Seleccionar atleta"),
            content: SizedBox(
              width: 300,
              height: 400,
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final u = users[index];
                  final isMe = u.id == user!.uid;

                  return ListTile(
                    leading:
                        isMe
                            ? const Icon(Icons.person, color: Colors.blue)
                            : const Icon(Icons.fitness_center),
                    title: Text(isMe ? "${u['name']} (Yo)" : u['name']),
                    onTap: () {
                      setState(() {
                        selectedAthleteId = u.id;
                        selectedAthleteName = u['name'];
                      });
                      AthleteSelectionService.save(u.id, u['name']);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  void _sortPerformedBlocks(List<Map<String, dynamic>> performed) {
    performed.sort(comparePerformedBlocks);
  }

  // ======================================================
  // 🔹 Helpers fechas (America/Santiago -> usamos local)
  // ======================================================
  DateTime _startOfWeek(DateTime now) {
    // Lunes como inicio
    final int diff = now.weekday - DateTime.monday;
    final d = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: diff));
    return d; // 00:00
  }

  DateTime _endOfToday(DateTime now) {
    // fin del día 23:59:59.999
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  Widget _buildAchievementBadge(String text, IconData icon, Color color) {
    // El subtítulo del tile puede ser muy angosto (el trailing ocupa mucho),
    // así que el texto se corta con "…" y el tooltip muestra el completo.
    return Tooltip(
      message: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _performedWorkoutView(
    List<Map<String, dynamic>> performed,
    List<ProgressAlert> alerts,
    List<Achievement> sessionVitrina,
  ) {
    final List<Widget> children = [];

    for (final p in performed) {
      String type = p['type'] ?? 'Series';
      String blockTitle = (p['blockTitle']?.toString() ?? '').trim();

      // Fix if backend saved a default generic name or it is empty
      if (blockTitle.isEmpty ||
          blockTitle == 'Series' ||
          blockTitle == 'Circuito' ||
          blockTitle == 'Tabata') {
        blockTitle = type;
      }

      if (type == 'Circuito') {
        final rounds = p['rounds'] as List? ?? [];
        blockTitle = "$blockTitle · ${rounds.length} rondas";
      } else if (type == 'Tabata') {
        blockTitle =
            "$blockTitle · ${p['work']}/${p['rest']} · ${p['rounds']} rondas";
      }

      children.add(
        Padding(
          padding: EdgeInsets.only(bottom: 6, top: children.isEmpty ? 0 : 8),
          child: Text(
            blockTitle.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.info,
            ),
          ),
        ),
      );

      if (type == 'Circuito') {
        children.add(_circuitBlockView(p, alerts));
      } else if (type == 'Tabata') {
        children.add(_tabataBlockView(p));
      } else if (type == 'Series descendentes') {
        children.add(_descendingSeriesBlockView(p, alerts));
      } else if (type == 'Series' || type == 'Buscar RM') {
        final List exs = p['exercises'] ?? [];
        for (final ex in exs) {
          children.add(
            _seriesExerciseRow(Map<String, dynamic>.from(ex), type, alerts),
          );
        }
      }
    }

    // General achievements (that do not specify a single exercise, like 'bestWeekEver' or Vitrina achievements)
    final generalAlerts =
        alerts.where((a) => a.evidence['exercise'] == null).toList();
    if (generalAlerts.isNotEmpty || sessionVitrina.isNotEmpty) {
      children.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🏆 LOGROS GENERALES DE LA SESIÓN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(height: 6),
              ...sessionVitrina.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• Desbloqueaste: ${a.title}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ...generalAlerts.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• ${a.title}${a.explanation.isNotEmpty ? ' - ${a.explanation}' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _descendingSeriesBlockView(
    Map<String, dynamic> p,
    List<ProgressAlert> alerts,
  ) {
    final List exs = p['exercises'] ?? [];
    if (exs.isEmpty) return const SizedBox();

    int maxSets = 0;
    for (final ex in exs) {
      if (ex is! Map) continue;
      final sets = ex['sets'] as List? ?? [];
      if (sets.length > maxSets) {
        maxSets = sets.length;
      }
    }

    if (maxSets == 0) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(maxSets, (i) {
            int? roundReps;
            for (final ex in exs) {
              if (ex is! Map) continue;
              final sets = ex['sets'] as List? ?? [];
              if (i < sets.length) {
                roundReps = _parseInt(sets[i]['reps']);
                if (roundReps > 0) break;
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${roundReps ?? '-'} reps",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ...exs.map((ex) {
                    if (ex is! Map) return const SizedBox();
                    final String name = ex['exercise'] ?? 'Ejercicio';
                    final sets = ex['sets'] as List? ?? [];
                    if (i >= sets.length) return const SizedBox();

                    final s = sets[i];
                    final weight = s['weight'] ?? 0;
                    final rpe = s['rpe'] ?? '-';

                    final bool exPerSide = ex['perSide'] == true;
                    final bool sPerSide = s['perSide'] == true;
                    final bool perSide = exPerSide || sPerSide;
                    final sideLabel = perSide ? " · por lado" : "";

                    final exAlerts =
                        alerts
                            .where((a) => a.evidence['exercise'] == name)
                            .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "• $name$sideLabel · $weight kg · RPE $rpe",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        if (exAlerts.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 10,
                              top: 2,
                              bottom: 2,
                            ),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children:
                                  exAlerts
                                      .map(
                                        (a) => Text(
                                          '🔥 ${a.title}${a.explanation.isNotEmpty ? ': ${a.explanation}' : ''}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _seriesExerciseRow(
    Map<String, dynamic> p,
    String blockType,
    List<ProgressAlert> alerts,
  ) {
    final String name = p['exercise'];
    final List sets = p['sets'] ?? [];

    if (sets.isEmpty) return const SizedBox();

    final bool perSide =
        (p['perSide'] == true) || sets.any((s) => s['perSide'] == true);

    final int sideMultiplier = perSide ? 2 : 1;

    double totalWeight = 0;

    for (final s in sets) {
      final int reps = _parseInt(s['reps']);
      final double weight = _parseDouble(s['weight']);

      totalWeight += reps * weight * sideMultiplier;
    }

    final String sideLabel = perSide ? " · por lado ×2" : "";

    String headerText =
        "$name$sideLabel · ${totalWeight.toStringAsFixed(0)} kg";
    if (blockType == 'Series descendentes') {
      headerText =
          "$name (Descendentes)$sideLabel · ${totalWeight.toStringAsFixed(0)} kg";
    } else if (blockType == 'Buscar RM') {
      headerText =
          "$name (RM)$sideLabel · ${totalWeight.toStringAsFixed(0)} kg";
    }

    final exAlerts =
        alerts.where((a) => a.evidence['exercise'] == name).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headerText,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (exAlerts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children:
                    exAlerts
                        .map(
                          (a) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.emoji_events,
                                size: 12,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${a.title}${a.explanation.isNotEmpty ? ': ${a.explanation}' : ''}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
              ),
            ),
          const SizedBox(height: 2),
          ...List.generate(sets.length, (i) {
            final s = sets[i];
            final repCount = _parseInt(s['reps']);
            final wCount = _parseDouble(s['weight']);

            bool isRecordSet = false;
            for (final a in exAlerts) {
              if (a.type == ProgressAlertType.newPR) {
                final currentSet = a.evidence['currentSet'];
                if (currentSet != null) {
                  if (currentSet['reps'] == repCount &&
                      currentSet['weight'] == wCount) {
                    isRecordSet = true;
                  }
                }
              }
            }

            final textStyle = TextStyle(
              fontSize: 12,
              color: isRecordSet ? Colors.amber : Colors.grey,
              fontWeight: isRecordSet ? FontWeight.bold : FontWeight.normal,
            );

            String lineText = "";
            if (blockType == 'Series descendentes') {
              lineText =
                  "• Escalón ${i + 1}: ${s['reps']} reps · ${s['weight'] ?? 0} kg · RPE ${s['rpe']}";
            } else if (blockType == 'Buscar RM') {
              lineText =
                  "• Intento ${i + 1}: ${s['reps']} reps · ${s['weight'] ?? 0} kg · RPE ${s['rpe']}";
            } else {
              lineText =
                  "• ${i + 1}: ${s['reps']} reps · ${s['weight'] ?? 0} kg · RPE ${s['rpe']}";
            }

            if (isRecordSet) {
              return Row(
                children: [
                  Text(lineText, style: textStyle),
                  const SizedBox(width: 4),
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                ],
              );
            }

            return Text(lineText, style: textStyle);
          }),
        ],
      ),
    );
  }

  Widget _circuitBlockView(Map<String, dynamic> p, List<ProgressAlert> alerts) {
    final List rounds = p['rounds'] ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rounds.map((r) {
            final List exs = r['exercises'] ?? [];

            double roundTotal = 0;
            bool anyPerSide = false;

            for (final e in exs) {
              final int reps = _parseInt(e['reps']);
              final double weight = _parseDouble(e['weight']);

              final bool perSide = e['perSide'] == true;
              if (perSide) anyPerSide = true;

              roundTotal += reps * weight * (perSide ? 2 : 1);
            }

            final String sideLabel = anyPerSide ? "" : "";

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Ronda ${r['round']} · ${roundTotal.toStringAsFixed(0)} kg$sideLabel",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ...exs.map((e) {
                    final String name = e['exercise'] ?? '';
                    final bool perSide = e['perSide'] == true;
                    final String sideText = perSide ? " · por lado" : "";

                    final exAlerts =
                        alerts
                            .where((a) => a.evidence['exercise'] == name)
                            .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "• $name$sideText · ${e['reps']} reps · ${e['weight'] ?? 0} kg · RPE ${e['rpe']}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        if (exAlerts.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 10,
                              top: 2,
                              bottom: 2,
                            ),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children:
                                  exAlerts
                                      .map(
                                        (a) => Text(
                                          '🔥 ${a.title}${a.explanation.isNotEmpty ? ': ${a.explanation}' : ''}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _tabataBlockView(Map<String, dynamic> p) {
    final List exs = p['exercises'] ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...exs.map(
            (e) => Text(
              "• ${e['exercise']} · RPE ${e['rpe']}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // Historial de RM de todos los workouts, calculado una vez por snapshot de
  // Firestore (antes se recalculaba por cada tarjeta en cada rebuild: O(N²)).
  QuerySnapshot? _rmHistorySnapshot;
  Map<String, List<Map<String, dynamic>>> _rmHistoryCache = {};

  Map<String, List<Map<String, dynamic>>> _rmHistoryFor(QuerySnapshot snap) {
    if (identical(snap, _rmHistorySnapshot)) return _rmHistoryCache;
    final history = <String, List<Map<String, dynamic>>>{};
    for (final ad in snap.docs) {
      final data = ad.data() as Map<String, dynamic>;
      final ts = data['date'];
      if (ts is! Timestamp) continue;
      WorkoutRMService.addSessionToRmHistory(
        history,
        List<Map<String, dynamic>>.from(data['performed'] ?? const []),
        ts.toDate(),
      );
    }
    _rmHistorySnapshot = snap;
    _rmHistoryCache = history;
    return history;
  }

  // ======================================================
  // 🔹 Listado reutilizable según rango
  // ======================================================
  Widget _buildList({
    required Map<String, List<Map<String, dynamic>>> fullRmHistory,
    required List<QueryDocumentSnapshot> docs,
    required DateFormat dateFmt,
    required DateTime start,
    required DateTime end,
    required List<Map<String, dynamic>> userAchievements,
  }) {
    // Filtrar por rango (inclusive)
    final filtered =
        docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final ts = data['date'];
          if (ts == null) return false;
          final date = (ts as Timestamp).toDate();
          return !date.isBefore(start) && !date.isAfter(end);
        }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          "No hay entrenamientos en este período",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      // En PC las tarjetas no se estiran a todo el ancho (quedan centradas);
      // en celular no agrega margen extra (las tarjetas ya traen el suyo).
      padding: centeredListPadding(
        context,
        maxWidth: 900,
        base: 0,
        vertical: 8,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final d = filtered[i];
        final data = d.data() as Map<String, dynamic>;

        final date = (data['date'] as Timestamp).toDate();
        final finishedTs =
            data['finishedAt'] as Timestamp? ?? data['date'] as Timestamp;
        final finishedDt = finishedTs.toDate();

        final performed = List<Map<String, dynamic>>.from(
          data['performed'] ?? [],
        );
        _sortPerformedBlocks(performed);

        // 🔥 CÁLCULOS (AQUÍ, ANTES DE USARLOS)
        final double volume = WorkoutVolumeService.calculateWorkoutVolume(
          performed,
        );

        final double avgRpe = calculateAverageWorkoutRPE(performed);

        final int duration = (data['durationMinutes'] as num?)?.toInt() ?? 0;

        // 🔥 LOGROS VITRINA
        final List<Achievement> sessionVitrina = [];
        for (var u in userAchievements) {
          if (u['unlockedAt'] == null) continue;
          final DateTime unlocked = (u['unlockedAt'] as Timestamp).toDate();
          if (unlocked.difference(finishedDt).inMinutes.abs() <= 5) {
            try {
              sessionVitrina.add(
                achievementsCatalog.firstWhere((a) => a.id == u['id']),
              );
            } catch (_) {}
          }
        }

        // 🔥 LOGROS OTROS (PRs)
        final alerts = ProgressAlertService.analyzeSessionImpact(
          rmHistory: WorkoutRMService.rmHistoryUpTo(fullRmHistory, date),
          targetDate: date,
        );

        final List<Widget> badgeWidgets = [];
        for (final ach in sessionVitrina) {
          badgeWidgets.add(
            _buildAchievementBadge(ach.title, ach.icon, Colors.amber),
          );
        }

        final Map<ProgressAlertType, int> alertCounts = {};
        for (final a in alerts) {
          if (a.type != ProgressAlertType.rpeWithoutProgress &&
              a.type != ProgressAlertType.stagnation) {
            alertCounts[a.type] = (alertCounts[a.type] ?? 0) + 1;
          }
        }

        alertCounts.forEach((type, count) {
          String title = "";
          IconData id;
          Color c;
          switch (type) {
            case ProgressAlertType.newPR:
              title = "Nuevo PR";
              id = Icons.emoji_events;
              c = Colors.amber;
              break;
            case ProgressAlertType.heaviestSet:
              title = "Serie Pesada";
              id = Icons.fitness_center;
              c = Colors.deepPurpleAccent;
              break;
            case ProgressAlertType.sessionVolumePR:
              title = "Récord Volumen";
              id = Icons.bar_chart;
              c = AppColors.info;
              break;
            case ProgressAlertType.bestWeekEver:
              title = "Mejor Sem.";
              id = Icons.calendar_today;
              c = Colors.green;
              break;
            case ProgressAlertType.improvedEfficiency:
              title = "Más Eficacia";
              id = Icons.psychology;
              c = Colors.teal;
              break;
            default:
              title = "Logro";
              id = Icons.star;
              c = Colors.orange;
              break;
          }
          if (count > 1) title = "$count $title";
          badgeWidgets.add(_buildAchievementBadge(title, id, c));
        });

        return Card(
          elevation: 4,
          shadowColor:
              badgeWidgets.isNotEmpty
                  ? Colors.amber.withOpacity(0.2)
                  : Colors.black26,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
                  badgeWidgets.isNotEmpty
                      ? Colors.amber.withOpacity(0.4)
                      : Colors.grey.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: ExpansionTile(
            shape: const Border(),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.fitness_center,
                color: AppColors.accent,
                size: 24,
              ),
            ),
            title: Text(
              data['sessionName'] ?? data['routineName'] ?? 'Entrenamiento',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  dateFmt.format(date),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (badgeWidgets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children:
                        badgeWidgets.take(4).toList()..addAll(
                          badgeWidgets.length > 4
                              ? [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '+${badgeWidgets.length - 4}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ]
                              : [],
                        ),
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dos líneas como máximo: el trailing del ListTile tiene alto
                // fijo y con tres líneas (min / kg / RPE) se desbordaba.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 🏋 VOLUMEN
                    Text(
                      "${volume.toStringAsFixed(0)} kg",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.info,
                      ),
                    ),

                    // 🕒 DURACIÓN · 🔥 RPE
                    if (duration > 0 || avgRpe > 0)
                      Text.rich(
                        TextSpan(
                          children: [
                            if (duration > 0)
                              TextSpan(
                                text: "$duration min",
                                style: const TextStyle(color: Colors.grey),
                              ),
                            if (duration > 0 && avgRpe > 0)
                              const TextSpan(
                                text: " · ",
                                style: TextStyle(color: Colors.grey),
                              ),
                            if (avgRpe > 0)
                              TextSpan(
                                text: "RPE ${avgRpe.toStringAsFixed(1)}",
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                ),
                              ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: "Editar entrenamiento",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => LogWorkoutScreen(
                              existingWorkout: {
                                'id': d.id,
                                ...d.data() as Map<String, dynamic>,
                              },
                              workoutRef: d.reference,
                            ),
                      ),
                    );
                  },
                ),
              ],
            ),
            children: [
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _performedWorkoutView(performed, alerts, sessionVitrina),
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text("Ver detalle completo"),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MyWorkoutDetailsScreen(workout: d),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ======================================================
  // 🔹 Rango picker
  // ======================================================
  Future<void> _pickRange() async {
    final now = DateTime.now();

    final initialStart = _rangeStart ?? now.subtract(const Duration(days: 6));
    final initialEnd = _rangeEnd ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: "Elegir rango de fechas",
      confirmText: "Aplicar",
      cancelText: "Cancelar",
      locale: const Locale('es', 'ES'),
    );

    if (picked == null) return;

    setState(() {
      _rangeStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeEnd = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
        999,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dateFmt = DateFormat('dd MMM yyyy · HH:mm', 'es_ES');
    final now = DateTime.now();

    final weekStart = _startOfWeek(now);
    final weekEnd = _endOfToday(now);

    final last10Start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 9));
    final last10End = _endOfToday(now);

    final rangeStart =
        _rangeStart ?? weekStart; // por defecto, mismo que semana
    final rangeEnd = _rangeEnd ?? weekEnd;

    final targetUid = selectedAthleteId ?? user!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selectedAthleteId == user?.uid
              ? "Mis entrenamientos"
              : "Entrenamientos de $selectedAthleteName",
        ),
        centerTitle: true,
        actions: [
          if (role == 'administrador')
            IconButton(
              icon: const Icon(Icons.switch_account),
              tooltip: "Cambiar atleta",
              onPressed: _selectAthlete,
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: "Esta semana"),
            Tab(text: "Últimos 10 días"),
            Tab(text: "Rango"),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/training_action_2.png'),
            fit: BoxFit.cover,
            opacity: 0.15,
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(targetUid)
                  .collection('achievements')
                  .snapshots(),
          builder: (context, achSnapshot) {
            final userAchievements =
                achSnapshot.hasData
                    ? achSnapshot.data!.docs
                        .map(
                          (d) => {
                            'id': d.id,
                            'unlockedAt':
                                (d.data()
                                    as Map<String, dynamic>)['unlockedAt'],
                          },
                        )
                        .toList()
                    : <Map<String, dynamic>>[];

            return StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('workouts_logged')
                      .where('userId', isEqualTo: targetUid)
                      .orderBy('date', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs.cast<QueryDocumentSnapshot>();
                final rmHistory = _rmHistoryFor(snapshot.data!);

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "Aún no tienes entrenamientos registrados",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return TabBarView(
                  controller: _tabCtrl,
                  children: [
                    // ✅ Esta semana (default)
                    _buildList(
                      fullRmHistory: rmHistory,
                      docs: docs,
                      dateFmt: dateFmt,
                      start: weekStart,
                      end: weekEnd,
                      userAchievements: userAchievements,
                    ),

                    // ✅ Últimos 10 días
                    _buildList(
                      fullRmHistory: rmHistory,
                      docs: docs,
                      dateFmt: dateFmt,
                      start: last10Start,
                      end: last10End,
                      userAchievements: userAchievements,
                    ),

                    // ✅ Rango
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.date_range),
                                  label: Text(
                                    _rangeStart == null && _rangeEnd == null
                                        ? "Elegir rango"
                                        : "${DateFormat('dd MMM', 'es_ES').format(rangeStart)} → ${DateFormat('dd MMM', 'es_ES').format(rangeEnd)}",
                                  ),
                                  onPressed: _pickRange,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: "Limpiar",
                                onPressed: () {
                                  setState(() {
                                    _rangeStart = null;
                                    _rangeEnd = null;
                                  });
                                },
                                icon: const Icon(Icons.clear),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: _buildList(
                            fullRmHistory: rmHistory,
                            docs: docs,
                            dateFmt: dateFmt,
                            start: rangeStart,
                            end: rangeEnd,
                            userAchievements: userAchievements,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
