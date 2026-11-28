import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:printing/printing.dart';
import '../screens/unified_weekly_review_screen.dart';
import '../widgets/planner/library_sidebar.dart';
import '../widgets/exercise_note.dart';
import '../screens/add_workout_screen.dart';
import '../screens/load_adjustment_alerts_screen.dart';
import '../models/muscle_catalog.dart';
import '../services/workout_load_service.dart';
import '../services/planned_workout_pdf_service.dart';
import '../services/training_period_report_service.dart';
import '../services/planned_load_service.dart';
import '../services/workout_rm_service.dart';
import '../utils/block_title_utils.dart';
import '../utils/exercise_name_utils.dart';
import '../theme/app_theme.dart';

/// Returns a sortable epoch value for Firestore timestamps and migrated data.
///
DateTime? _dateTimeValue(dynamic value) {
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
  }
  return null;
}

/// Una variante exacta de ejercicio (`exerciseId` + `variantId`) ya presente
/// en la planificación de un atleta, para el buscador de "progresión por
/// ejercicio".
class _ExerciseChoice {
  final String exerciseId;
  final String variantId;
  final String name;
  int sessionCount;

  _ExerciseChoice({
    required this.exerciseId,
    required this.variantId,
    required this.name,
    required this.sessionCount,
  });
}

/// Una sesión planificada (`planned_workouts`) con su bloque ya resuelto
/// (ejercicios con `exerciseInstanceId`/`sets`/`weight` calculados), para
/// el flujo de "progresión por ejercicio".
class _PlannedSessionExercises {
  final String plannedWorkoutId;
  final DateTime date;
  final String blockId;
  final String blockTitle;
  final List<Map<String, dynamic>> existingOverrides;
  final List<Map<String, dynamic>> exercises;

  _PlannedSessionExercises({
    required this.plannedWorkoutId,
    required this.date,
    required this.blockId,
    required this.blockTitle,
    required this.existingOverrides,
    required this.exercises,
  });
}

/// Una "columna de peso" dentro de la tabla de progresión: un peso dado,
/// cuántas series van a ese peso, y con cuántas repeticiones. Al guardar se
/// expande a `series` entradas individuales en `loadOverrides[].sets`, que
/// es el formato plano que usa el resto de la app.
class _WeightColumn {
  final TextEditingController weightCtrl;
  final TextEditingController seriesCtrl;
  final TextEditingController repsCtrl;

  _WeightColumn({String weight = '', String series = '1', String reps = ''})
    : weightCtrl = TextEditingController(text: weight),
      seriesCtrl = TextEditingController(text: series),
      repsCtrl = TextEditingController(text: reps);

  double get weight =>
      double.tryParse(weightCtrl.text.replaceAll(',', '.')) ?? 0;
  int get series => int.tryParse(seriesCtrl.text) ?? 0;
  int get reps => int.tryParse(repsCtrl.text) ?? 0;

  void dispose() {
    weightCtrl.dispose();
    seriesCtrl.dispose();
    repsCtrl.dispose();
  }
}

/// Métricas agregadas de una sesión, calculadas en vivo mientras se edita
/// la tabla de progresión — mismo criterio que la planilla de referencia:
/// Volumen = series totales, Tonelaje = Σ(peso×reps), PM = peso medio
/// ponderado por reps, IMR = PM / RM × 100.
class _SessionMetrics {
  final int volume;
  final double tonnage;
  final double pm;
  final double? imr;

  const _SessionMetrics({
    required this.volume,
    required this.tonnage,
    required this.pm,
    required this.imr,
  });

  static _SessionMetrics from(List<_WeightColumn> columns, double? rm) {
    int volume = 0;
    double tonnage = 0;
    double weightedRepsSum = 0; // Σ(peso × reps × series)
    int totalReps = 0;
    for (final col in columns) {
      if (col.series <= 0) continue;
      volume += col.series;
      final repsForTonnage = col.reps > 0 ? col.reps : 1;
      tonnage += col.weight * repsForTonnage * col.series;
      weightedRepsSum += col.weight * repsForTonnage * col.series;
      totalReps += repsForTonnage * col.series;
    }
    final pm = totalReps > 0 ? weightedRepsSum / totalReps : 0.0;
    final imr = (rm != null && rm > 0) ? (pm / rm) * 100 : null;
    return _SessionMetrics(volume: volume, tonnage: tonnage, pm: pm, imr: imr);
  }
}

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

/// Igual que [ReorderableDragStartListener] pero exige mantener apretado
/// [delay] (2s) antes de iniciar el arrastre, en vez del long-press corto
/// por defecto — para evitar mover bloques de planificación sin querer.
class _SlowReorderableDragStartListener extends ReorderableDragStartListener {
  const _SlowReorderableDragStartListener({
    required super.child,
    required super.index,
  });

  static const Duration delay = Duration(seconds: 2);

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this);
  }
}

class _PlanningScreenState extends State<PlanningScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  final user = FirebaseAuth.instance.currentUser;

  String? role;
  String? selectedAthleteId;
  String? selectedAthleteName;

  List<Map<String, dynamic>> _plannedWorkouts = [];
  String? _expandedWorkoutId;
  final Map<String, DocumentSnapshot> _blockCache = {};

  /// Caché del catálogo `exercises` (clave: `id:<docId>` o `name:<nombre>`).
  /// Un valor null significa "ya buscado, no existe".
  final Map<String, Map<String, dynamic>?> _catalogCache = {};

  bool _loading = true;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _plannedDocsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: selectedAthleteId)
            .get();
    return snapshot.docs.where((doc) {
      final date = _dateTimeValue(doc.data()['date']);
      return date != null && !date.isBefore(start) && date.isBefore(end);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  // ====================================================
  // INIT
  // ====================================================
  Future<void> _initialize() async {
    if (user == null) return;

    final userDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();

    role = userDoc.data()?['role']?.toString().toLowerCase();
    print("DEBUG: Current user role: $role");

    if (role == 'administrador' || role == 'admin') {
      selectedAthleteId = user!.uid;
      selectedAthleteName = userDoc.data()?['name'];
    } else {
      selectedAthleteId = user!.uid;
      selectedAthleteName = userDoc.data()?['name'];
    }

    if (selectedAthleteId != null) {
      await _loadPlannedForDay(_selectedDay!);
    }

    setState(() => _loading = false);
  }

  /// Resuelve un ejercicio planificado contra el catálogo: primero por
  /// `exerciseId`; si no hay, por nombre exacto o por su nombre base
  /// ("Sentadilla - Búlgara" → "Sentadilla"), que es donde viven las
  /// variantes.
  Future<Map<String, dynamic>?> _catalogExerciseFor(
    Map<String, dynamic> exercise,
  ) async {
    final id = exercise['exerciseId']?.toString();
    if (id != null && id.isNotEmpty) {
      final key = 'id:$id';
      if (!_catalogCache.containsKey(key)) {
        final doc =
            await FirebaseFirestore.instance
                .collection('exercises')
                .doc(id)
                .get();
        _catalogCache[key] = doc.data();
      }
      final byId = _catalogCache[key];
      if (byId != null) return byId;
    }

    final name = normalizeExerciseName(
      exercise['exercise'] ?? exercise['name'],
    );
    if (name.isEmpty) return null;
    final separator = name.indexOf(' - ');
    final candidates = [name, if (separator > 0) name.substring(0, separator)];
    for (final candidate in candidates) {
      final key = 'name:$candidate';
      if (!_catalogCache.containsKey(key)) {
        final snap =
            await FirebaseFirestore.instance
                .collection('exercises')
                .where('name', isEqualTo: candidate)
                .limit(1)
                .get();
        _catalogCache[key] = snap.docs.isEmpty ? null : snap.docs.first.data();
      }
      final byName = _catalogCache[key];
      if (byName != null) return byName;
    }
    return null;
  }

  // ====================================================
  // SELECT ATHLETE (ADMIN)
  // ====================================================
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
                      selectedAthleteId = u.id;
                      selectedAthleteName = u['name'];
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ),
    );
  }

  // ====================================================
  // LOAD AVAILABLE BLOCKS
  // ====================================================

  // ====================================================
  // LOAD PLANNED WORKOUTS
  // ====================================================
  Future<void> _loadPlannedForDay(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    print("Searching between $start and $end");

    // Algunos entrenamientos históricos fueron importados con `date` como
    // texto ISO, mientras que los nuevos usan Timestamp. No se puede hacer
    // una consulta de rango que cubra ambos tipos en Firestore, así que
    // filtramos la fecha después de traer los planes del atleta.
    final snapshot =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: selectedAthleteId)
            .get();

    print("FOUND: ${snapshot.docs.length}");

    _plannedWorkouts =
        snapshot.docs
            .where((d) {
              final value = _dateTimeValue(d.data()['date']);
              return value != null &&
                  !value.isBefore(start) &&
                  value.isBefore(end);
            })
            .map((d) => {...d.data(), 'id': d.id})
            .toList();

    // El documento de `blocks` es la fuente principal. Hidratamos los datos
    // visibles desde ese documento para que el calendario y la biblioteca no
    // puedan mostrar nombres o contenidos distintos.
    final blockIds =
        _plannedWorkouts
            .map((workout) => workout['blockId']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
    if (blockIds.isNotEmpty) {
      final blockDocs = await Future.wait(
        blockIds.map(
          (id) => FirebaseFirestore.instance.collection('blocks').doc(id).get(),
        ),
      );
      for (final blockDoc in blockDocs) {
        if (!blockDoc.exists) continue;
        _blockCache[blockDoc.id] = blockDoc;
        final block = blockDoc.data() as Map<String, dynamic>;
        final title = (block['title'] ?? '').toString().trim();
        final type = (block['type'] ?? 'Bloque').toString();
        final visibleTitle = visibleBlockTitle(title.isNotEmpty ? title : type);
        for (final workout in _plannedWorkouts) {
          if (workout['blockId']?.toString() == blockDoc.id) {
            workout['blockTitle'] = visibleTitle;
          }
        }
      }
    }

    // Sort by 'order' field if it exists, otherwise use creation time or default order
    _plannedWorkouts.sort((a, b) {
      final orderA = a['order'] as int? ?? 0;
      final orderB = b['order'] as int? ?? 0;
      return orderA.compareTo(orderB);
    });

    setState(() {});
  }

  // ====================================================
  // 📊 CALCULO DE CARGA SEMANAL PLANIFICADA
  // ====================================================

  DateTime _normalizeDayLocal(DateTime d) {
    // 🔥 mediodía local evita corrimientos por UTC/DST
    return DateTime(d.year, d.month, d.day, 12);
  }

  Future<Map<String, double>> calculateWeeklyMuscleLoad() async {
    final startOfWeek = _selectedDay!.subtract(
      Duration(days: _selectedDay!.weekday - 1),
    );

    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    final workouts = await _plannedDocsInRange(startOfWeek, endOfWeek);

    Map<String, double> weeklyLoad = {};

    for (final w in workouts) {
      if (w.data().containsKey('blockId')) {
        final blockId = w['blockId'];

        final blockDoc =
            await FirebaseFirestore.instance
                .collection('blocks')
                .doc(blockId)
                .get();

        final exercises = blockDoc.data()?['exercises'] ?? [];

        for (final ex in exercises) {
          final exerciseName = ex['name'];
          final sets = ex['series'] ?? 0;

          final exerciseSnapshot =
              await FirebaseFirestore.instance
                  .collection('exercises')
                  .where('name', isEqualTo: exerciseName)
                  .limit(1)
                  .get();

          if (exerciseSnapshot.docs.isNotEmpty) {
            final weights = Map<String, dynamic>.from(
              exerciseSnapshot.docs.first.data()['muscleWeights'] ?? {},
            );

            weights.forEach((muscle, value) {
              weeklyLoad[muscle] =
                  (weeklyLoad[muscle] ?? 0) +
                  (sets * (value as num).toDouble());
            });
          }
        }
      }
    }

    return weeklyLoad;
  }

  // ====================================================
  // CREATE PLANNED WORKOUT FROM BLOCKS (multi-select)
  // ====================================================

  // ====================================================
  // ADD SINGULAR BLOCK TO PLANNED (from Sidebar)
  // ====================================================
  Future<void> _addBlockToPlanned(Map<String, dynamic> blockData) async {
    final blockId = blockData['id'] as String?;
    if (blockId == null) return;

    final normalized = DateTime(
      _selectedDay!.year,
      _selectedDay!.month,
      _selectedDay!.day,
    );

    int maxOrder = 0;
    if (_plannedWorkouts.isNotEmpty) {
      maxOrder = _plannedWorkouts
          .map((w) => w['order'] as int? ?? 0)
          .reduce((a, b) => a > b ? a : b);
    }

    final title = (blockData['title'] ?? '').toString().trim();
    final type = (blockData['type'] ?? 'Bloque').toString();
    final blockTitle = visibleBlockTitle(title.isNotEmpty ? title : type);

    await FirebaseFirestore.instance.collection('planned_workouts').add({
      'athleteId': selectedAthleteId,
      'athleteName': selectedAthleteName,
      'blockId': blockId,
      'blockTitle': blockTitle,
      'date': Timestamp.fromDate(normalized),
      'status': 'planned',
      'createdAt': Timestamp.now(),
      'order': maxOrder + 1,
    });

    _loadPlannedForDay(_selectedDay!);
  }

  // ====================================================
  // EDIT BLOCK IN LIBRARY
  // ====================================================
  Future<void> _deleteBlockInLibrary(
    String id,
    Map<String, dynamic> block,
  ) async {
    if (role != 'administrador' && role != 'admin') return;
    final usageSnapshot =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: selectedAthleteId)
            .get();
    final used =
        usageSnapshot.docs.where((doc) {
          final data = doc.data();
          return data['blockId']?.toString() == id ||
              data['sourceBlockId']?.toString() == id;
        }).toList();
    if (!mounted) return;
    final title =
        visibleBlockTitle(block['title']) == ''
            ? (block['type'] ?? 'Bloque')
            : visibleBlockTitle(block['title']);
    if (used.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Bloque en uso'),
              content: Text(
                '“$title” tiene ${used.length} sesión(es) planificada(s). No se puede borrar para no romper esas referencias.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Borrar bloque'),
            content: Text(
              '¿Borrar “$title” de la biblioteca? Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Borrar'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection('blocks').doc(id).delete();
    _blockCache.remove(id);
    if (mounted) setState(() {});
  }

  Future<void> _editBlockInLibrary(
    String id,
    Map<String, dynamic> block,
  ) async {
    final sourceBlockId = block['sourceBlockId']?.toString();
    final canonicalBlockId =
        sourceBlockId != null && sourceBlockId.isNotEmpty ? sourceBlockId : id;
    var canonicalPreviousBlock = block;
    if (canonicalBlockId != id) {
      final sourceDoc =
          await FirebaseFirestore.instance
              .collection('blocks')
              .doc(canonicalBlockId)
              .get();
      if (sourceDoc.exists && sourceDoc.data() != null) {
        canonicalPreviousBlock = Map<String, dynamic>.from(sourceDoc.data()!);
      }
    }
    final weeklyBefore = await _estimateWeeklyProfile();
    final weeklyMusclesBefore = await _estimateWeeklyMuscles();
    if (!mounted) return;
    final updatedBlock = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddWorkoutScreen(
              initialBlock: {
                ...block,
                'id': id,
                'contextAthleteId': selectedAthleteId,
              },
            ),
      ),
    );
    if (updatedBlock == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('blocks')
          .doc(canonicalBlockId)
          .update({...updatedBlock, 'updatedAt': FieldValue.serverTimestamp()});

      final title = (updatedBlock['title'] ?? '').toString().trim();
      final type = (updatedBlock['type'] ?? 'Bloque').toString();
      final blockTitle = visibleBlockTitle(title.isNotEmpty ? title : type);
      final synchronizedPlans = await _syncPlannedBlockReferences(
        blockId: canonicalBlockId,
        blockTitle: blockTitle,
        previousBlock: canonicalPreviousBlock,
        updatedBlock: updatedBlock,
      );
      final synchronizedTemplates = await _syncLibraryTemplates(
        sourceBlockId: canonicalBlockId,
        updatedBlock: updatedBlock,
      );
      await _showBlockProfileAdjustment(
        previousBlock: canonicalPreviousBlock,
        updatedBlock: updatedBlock,
        targetBlockId: canonicalBlockId,
        beforeProfile: weeklyBefore,
        beforeMuscles: weeklyMusclesBefore,
      );

      _blockCache.remove(id);
      _blockCache.remove(canonicalBlockId);
      if (_selectedDay != null) {
        await _loadPlannedForDay(_selectedDay!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${synchronizedPlans == 1 ? 'Bloque principal actualizado y sincronizado con 1 sesión.' : 'Bloque principal actualizado y sincronizado con $synchronizedPlans sesiones.'}\n'
              '$synchronizedTemplates plantillas de biblioteca actualizadas.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el bloque: $error')),
      );
    }
  }

  Future<int> _syncLibraryTemplates({
    required String sourceBlockId,
    required Map<String, dynamic> updatedBlock,
  }) async {
    final references =
        await FirebaseFirestore.instance
            .collection('blocks')
            .where('sourceBlockId', isEqualTo: sourceBlockId)
            .get();
    if (references.docs.isEmpty) return 0;
    final fields = <String, dynamic>{
      for (final key in [
        'type',
        'title',
        'description',
        'exercises',
        'work',
        'rest',
        'rounds',
        'time',
        'schema',
        'rm',
      ])
        if (updatedBlock.containsKey(key)) key: updatedBlock[key],
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = FirebaseFirestore.instance.batch();
    for (final reference in references.docs) {
      batch.update(reference.reference, fields);
    }
    await batch.commit();
    return references.docs.length;
  }

  Map<String, double> _estimateBlockProfile(Map<String, dynamic> block) {
    final scores = <String, double>{
      'Fuerza máxima': 0,
      'Rendimiento / potencia': 0,
      'Hipertrofia': 0,
      'Acondicionamiento': 0,
      'Control y coordinación': 0,
    };
    final context =
        '${block['title'] ?? ''} ${block['type'] ?? ''}'.toLowerCase();
    for (final raw in (block['exercises'] as List? ?? const [])) {
      final exercise = Map<String, dynamic>.from(raw as Map);
      final name =
          '${exercise['name'] ?? ''} ${exercise['variantLabel'] ?? ''}'
              .toLowerCase();
      final series = (exercise['series'] as num?)?.toDouble() ?? 1;
      final reps =
          (exercise['reps'] as num?)?.toDouble() ??
          (exercise['value'] as num?)?.toDouble() ??
          1;
      final load = (series * reps).clamp(1.0, double.infinity);
      final text = '$context $name';
      if (RegExp(
        r'fuerza|max|rm|sentadilla|peso muerto|press banca|press militar',
      ).hasMatch(text)) {
        scores['Fuerza máxima'] = scores['Fuerza máxima']! + load;
      }
      if (RegExp(
        r'potencia|clean|snatch|jerk|salto|sprint|lanzamiento|balístico',
      ).hasMatch(text)) {
        scores['Rendimiento / potencia'] =
            scores['Rendimiento / potencia']! + load;
      }
      final isCorrective = RegExp(
        r'correctiv|estabilidad|coordinaci|face\s*pull|push[ -]?up\s*(plus|serrato)|flexi[oó]n\s*(plus|serrato)|elevaci[oó]n\s*w|prone\s*w|wall\s*slide|rotaci[oó]n\s*externa|scapular',
      ).hasMatch(text);
      if (!isCorrective &&
          RegExp(
            r'hipertrofia|volumen|curl|extensi|elevaci|remo|jalon|pullover',
          ).hasMatch(text)) {
        scores['Hipertrofia'] = scores['Hipertrofia']! + load;
      }
      if (RegExp(
        r'capacidad|acondicion|cardio|bike|carrera|burpee|tabata',
      ).hasMatch(text)) {
        scores['Acondicionamiento'] = scores['Acondicionamiento']! + load;
      }
      if (isCorrective ||
          RegExp(
            r'barra fija|dominada|flexion|plancha|peso corporal|calistenia',
          ).hasMatch(text)) {
        scores['Control y coordinación'] =
            scores['Control y coordinación']! + load;
      }
    }
    final total = scores.values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return scores;
    return {
      for (final entry in scores.entries) entry.key: entry.value / total * 100,
    };
  }

  double _profileVolume(Map<String, dynamic> block) {
    var volume = 0.0;
    for (final raw in (block['exercises'] as List? ?? const [])) {
      final exercise = Map<String, dynamic>.from(raw as Map);
      final series = (exercise['series'] as num?)?.toDouble() ?? 1;
      final reps =
          (exercise['reps'] as num?)?.toDouble() ??
          (exercise['value'] as num?)?.toDouble() ??
          1;
      volume += (series * reps).clamp(1.0, double.infinity);
    }
    return volume <= 0 ? 1 : volume;
  }

  Future<Map<String, double>> _estimateWeeklyProfile({
    Map<String, dynamic>? replacement,
    String? targetBlockId,
    String? targetWorkoutId,
    bool removeTarget = false,
  }) async {
    final labels = _estimateBlockProfile(const {}).keys;
    final totals = {for (final label in labels) label: 0.0};
    final start = _startOfWeekMonday(_selectedDay ?? DateTime.now());
    final end = start.add(const Duration(days: 7));
    final snapshot = await _plannedDocsInRange(start, end);
    for (final document in snapshot) {
      final data = <String, dynamic>{...document.data(), 'id': document.id};
      final isTarget =
          (targetWorkoutId != null && document.id == targetWorkoutId) ||
          (targetBlockId != null &&
              data['blockId']?.toString() == targetBlockId);
      if (isTarget && removeTarget) continue;
      Map<String, dynamic> block;
      if (isTarget && replacement != null) {
        block = replacement;
      } else {
        final id = data['blockId']?.toString();
        final cached = id == null ? null : _blockCache[id]?.data();
        if (cached is Map) {
          block = Map<String, dynamic>.from(cached);
        } else if (id != null && id.isNotEmpty) {
          final blockDoc =
              await FirebaseFirestore.instance
                  .collection('blocks')
                  .doc(id)
                  .get();
          block = blockDoc.data() ?? data;
        } else {
          block = data;
        }
      }
      final profile = _estimateBlockProfile(block);
      final volume = _profileVolume(block);
      for (final label in labels)
        totals[label] = totals[label]! + profile[label]! * volume;
    }
    final total = totals.values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return totals;
    return {
      for (final entry in totals.entries) entry.key: entry.value / total * 100,
    };
  }

  Future<Map<String, double>> _estimateWeeklyMuscles({
    Map<String, dynamic>? replacement,
    String? targetBlockId,
    String? targetWorkoutId,
    bool removeTarget = false,
  }) async {
    final totals = <String, double>{};
    final start = _startOfWeekMonday(_selectedDay ?? DateTime.now());
    final end = start.add(const Duration(days: 7));
    final snapshot = await _plannedDocsInRange(start, end);
    for (final document in snapshot) {
      final data = document.data();
      final isTarget =
          (targetWorkoutId != null && document.id == targetWorkoutId) ||
          (targetBlockId != null &&
              data['blockId']?.toString() == targetBlockId);
      if (isTarget && removeTarget) continue;
      Map<String, dynamic> block;
      if (isTarget && replacement != null) {
        block = replacement;
      } else {
        final id = data['blockId']?.toString();
        final cached = id == null ? null : _blockCache[id]?.data();
        if (cached is Map) {
          block = Map<String, dynamic>.from(cached);
        } else if (id != null && id.isNotEmpty) {
          final blockDoc =
              await FirebaseFirestore.instance
                  .collection('blocks')
                  .doc(id)
                  .get();
          block = blockDoc.data() ?? data;
        } else {
          block = data;
        }
      }
      for (final raw in (block['exercises'] as List? ?? const [])) {
        final exercise = Map<String, dynamic>.from(raw as Map);
        // Siempre se acumula por `Muscle` y se muestra por su label, sin
        // importar si los pesos vienen del bloque o del catálogo.
        final Map<Muscle, double> weights;
        final inline =
            exercise['muscleWeights'] ?? exercise['muscleWeightOverrides'];
        if (inline is Map && inline.isNotEmpty) {
          weights = WorkoutLoadService.decodeMuscleWeightsMap(inline);
        } else {
          final definition = await _catalogExerciseFor(exercise);
          if (definition == null) continue;
          weights = WorkoutLoadService.resolveMuscleWeightsFromExercise(
            definition,
            variantId: exercise['variantId']?.toString(),
            variantLabel: exercise['variantLabel']?.toString(),
          );
        }
        for (final entry in weights.entries) {
          totals[entry.key.label] =
              (totals[entry.key.label] ?? 0) + entry.value;
        }
      }
    }
    final total = totals.values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return totals;
    return {
      for (final entry in totals.entries) entry.key: entry.value / total * 100,
    };
  }

  Future<void> _showBlockProfileAdjustment({
    required Map<String, dynamic> previousBlock,
    required Map<String, dynamic> updatedBlock,
    String title = 'Perfil reajustado',
    String? targetBlockId,
    String? targetWorkoutId,
    Map<String, double>? beforeProfile,
    Map<String, double>? beforeMuscles,
  }) async {
    final before = beforeProfile ?? await _estimateWeeklyProfile();
    final after = await _estimateWeeklyProfile(
      replacement: updatedBlock,
      targetBlockId: targetBlockId,
      targetWorkoutId: targetWorkoutId,
      removeTarget: targetWorkoutId != null,
    );
    final musclesBefore = beforeMuscles ?? await _estimateWeeklyMuscles();
    final musclesAfter = await _estimateWeeklyMuscles(
      replacement: updatedBlock,
      targetBlockId: targetBlockId,
      targetWorkoutId: targetWorkoutId,
      removeTarget: targetWorkoutId != null,
    );
    final labels = before.keys.toList();
    final previousExercises =
        (previousBlock['exercises'] as List? ?? const []).length;
    final updatedExercises =
        (updatedBlock['exercises'] as List? ?? const []).length;
    final muscleLabels =
        <String>{...musclesBefore.keys, ...musclesAfter.keys}.toList()..sort(
          (a, b) => ((musclesAfter[b] ?? 0) - (musclesBefore[b] ?? 0))
              .abs()
              .compareTo(
                ((musclesAfter[a] ?? 0) - (musclesBefore[a] ?? 0)).abs(),
              ),
        );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impacto estimado sobre la carga semanal completa, considerando todas las sesiones planificadas de esta semana.',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ejercicios: $previousExercises → $updatedExercises',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    for (final label in labels)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(label)),
                            Text('${before[label]!.toStringAsFixed(1)}%'),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 14),
                            const SizedBox(width: 8),
                            Text('${after[label]!.toStringAsFixed(1)}%'),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 58,
                              child: Text(
                                '${after[label]! - before[label]! >= 0 ? '+' : ''}${(after[label]! - before[label]!).toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color:
                                      after[label]! - before[label]! >= 0
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (muscleLabels.isNotEmpty) ...[
                      const Divider(height: 20),
                      const Text(
                        'Grupos musculares implicados (carga semanal)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      for (final muscle in muscleLabels.take(10))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text(muscle)),
                              Text(
                                '${(musclesBefore[muscle] ?? 0).toStringAsFixed(1)}%',
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 14),
                              const SizedBox(width: 8),
                              Text(
                                '${(musclesAfter[muscle] ?? 0).toStringAsFixed(1)}%',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(musclesAfter[muscle] ?? 0) - (musclesBefore[muscle] ?? 0) >= 0 ? '+' : ''}${((musclesAfter[muscle] ?? 0) - (musclesBefore[muscle] ?? 0)).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color:
                                      (musclesAfter[muscle] ?? 0) -
                                                  (musclesBefore[muscle] ??
                                                      0) >=
                                              0
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    selectedAthleteId == null || _selectedDay == null
                        ? null
                        : () async {
                          Navigator.pop(dialogContext);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => UnifiedWeeklyReviewScreen(
                                    athleteId: selectedAthleteId!,
                                    athleteName:
                                        selectedAthleteName ?? 'Atleta',
                                    initialDate: _selectedDay!,
                                    onProgressionByExercise:
                                        _planProgressionByExercise,
                                  ),
                            ),
                          );
                        },
                child: const Text('Abrir revisión semanal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
  }

  Future<int> _syncPlannedBlockReferences({
    required String blockId,
    required String blockTitle,
    required Map<String, dynamic> previousBlock,
    required Map<String, dynamic> updatedBlock,
  }) async {
    final references =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('blockId', isEqualTo: blockId)
            .get();

    // Firestore admite hasta 500 operaciones por lote. Dejamos margen para
    // que un bloque reutilizado durante muchos meses siga sincronizándose.
    const chunkSize = 450;
    for (var start = 0; start < references.docs.length; start += chunkSize) {
      final end = math.min(start + chunkSize, references.docs.length);
      final batch = FirebaseFirestore.instance.batch();
      for (final reference in references.docs.sublist(start, end)) {
        final planned = reference.data();
        var rules = List<Map<String, dynamic>>.from(
          planned['loadProgression'] ?? const [],
        );
        var existing = List<Map<String, dynamic>>.from(
          planned['loadOverrides'] ?? const [],
        );
        final previousExercises = List<Map<String, dynamic>>.from(
          previousBlock['exercises'] ?? const [],
        );
        final updatedExercises = List<Map<String, dynamic>>.from(
          updatedBlock['exercises'] ?? const [],
        );
        for (
          var index = 0;
          index < math.min(previousExercises.length, updatedExercises.length);
          index++
        ) {
          final oldKey = PlannedLoadService.exerciseKey(
            previousExercises[index],
            index,
          );
          final newKey = PlannedLoadService.exerciseKey(
            updatedExercises[index],
            index,
          );
          if (oldKey == newKey) continue;
          rules = [
            for (final rule in rules)
              {
                ...rule,
                if (rule['exerciseInstanceId'] == oldKey)
                  'exerciseInstanceId': newKey,
              },
          ];
          existing = [
            for (final override in existing)
              {
                ...override,
                if (override['exerciseInstanceId'] == oldKey)
                  'exerciseInstanceId': newKey,
              },
          ];
        }
        final update = <String, dynamic>{
          'blockTitle': blockTitle,
          'blockUpdatedAt': FieldValue.serverTimestamp(),
        };
        if (rules.isNotEmpty || existing.isNotEmpty) {
          update['loadProgression'] = rules;
          update['loadOverrides'] = PlannedLoadService.generateOverrides(
            block: updatedBlock,
            progressionIndex:
                (planned['progressionIndex'] as num?)?.toInt() ?? 0,
            rules: rules,
            existing: existing,
          );
        }
        batch.update(reference.reference, update);
      }
      await batch.commit();
    }
    return references.docs.length;
  }

  Future<void> _editPlannedBlock(Map<String, dynamic> workout) async {
    final blockId = workout['blockId']?.toString();
    if (blockId == null || blockId.isEmpty) return;

    var blockDoc = _blockCache[blockId];
    if (blockDoc == null || !blockDoc.exists) {
      blockDoc =
          await FirebaseFirestore.instance
              .collection('blocks')
              .doc(blockId)
              .get();
    }
    if (!blockDoc.exists || blockDoc.data() == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El bloque principal ya no existe.')),
      );
      return;
    }

    await _editBlockInLibrary(
      blockId,
      Map<String, dynamic>.from(blockDoc.data() as Map),
    );
  }

  // ================= PROGRESIÓN POR EJERCICIO =================
  //
  // Flujo: elegir un ejercicio (con su variante exacta) → ver TODAS las
  // sesiones planificadas del atleta donde aparece → elegir cuáles entran
  // en la progresión → tabla editable (una fila por sesión) → guardar.
  //
  // A diferencia de `_planBlockMultipleDays` (que parte de un bloque), acá
  // se parte del ejercicio y se busca en toda la planificación existente,
  // sin importar bloque/semana.

  /// Trae TODOS los `planned_workouts` del atleta y resuelve cada bloque
  /// referenciado (con `_blockCache`), devolviendo una lista aplanada de
  /// "sesión + ejercicios resueltos" para poder filtrar por ejercicio en
  /// memoria.
  Future<List<_PlannedSessionExercises>> _loadAllResolvedSessions(
    String athleteId,
  ) async {
    final snap =
        await FirebaseFirestore.instance
            .collection('planned_workouts')
            .where('athleteId', isEqualTo: athleteId)
            .get();

    final sessions = <_PlannedSessionExercises>[];
    for (final doc in snap.docs) {
      final data = {...doc.data(), 'id': doc.id};
      final date = _dateTimeValue(data['date']);
      final blockId = data['blockId']?.toString();
      if (date == null || blockId == null || blockId.isEmpty) continue;

      var blockDoc = _blockCache[blockId];
      blockDoc ??=
          await FirebaseFirestore.instance
              .collection('blocks')
              .doc(blockId)
              .get();
      _blockCache[blockId] = blockDoc;
      if (!blockDoc.exists || blockDoc.data() == null) continue;

      final block = Map<String, dynamic>.from(blockDoc.data() as Map);
      final resolved = PlannedLoadService.resolveBlock(
        block: block,
        planned: data,
      );
      final exercises = List<Map<String, dynamic>>.from(
        resolved['exercises'] ?? const [],
      );

      sessions.add(
        _PlannedSessionExercises(
          plannedWorkoutId: doc.id,
          date: date,
          blockId: blockId,
          blockTitle: visibleBlockTitle(
            data['blockTitle'] ?? block['title'] ?? block['type'],
          ),
          existingOverrides: List<Map<String, dynamic>>.from(
            data['loadOverrides'] ?? const [],
          ),
          exercises: exercises,
        ),
      );
    }

    sessions.sort((a, b) => a.date.compareTo(b.date));
    return sessions;
  }

  /// Ejercicios distintos (por variante exacta: `exerciseId` + `variantId`)
  /// ya presentes en la planificación del atleta, con su nombre visible y
  /// la cantidad de sesiones donde aparece — para poblar el buscador.
  List<_ExerciseChoice> _distinctExerciseChoices(
    List<_PlannedSessionExercises> sessions,
  ) {
    final byKey = <String, _ExerciseChoice>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        final exerciseId = exercise['exerciseId']?.toString();
        final variantId = exercise['variantId']?.toString() ?? 'original';
        if (exerciseId == null || exerciseId.isEmpty) continue;
        final key = '${exerciseId}_$variantId';
        final name = (exercise['name'] ?? 'Ejercicio').toString();
        final existing = byKey[key];
        if (existing == null) {
          byKey[key] = _ExerciseChoice(
            exerciseId: exerciseId,
            variantId: variantId,
            name: name,
            sessionCount: 1,
          );
        } else {
          existing.sessionCount++;
        }
      }
    }
    final choices =
        byKey.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return choices;
  }

  Future<void> _planProgressionByExercise() async {
    if (selectedAthleteId == null) return;
    final athleteId = selectedAthleteId!;

    // No se espera (`await`) este diálogo: solo sirve de indicador visual
    // mientras se cargan los datos abajo, y se cierra explícitamente en
    // cuanto termina. Esperarlo aquí bloquearía para siempre, ya que nada
    // más lo cierra.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const AlertDialog(
              content: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 16),
                  Text('Cargando planificación…'),
                ],
              ),
            ),
      ),
    );
    final results = await Future.wait([
      _loadAllResolvedSessions(athleteId),
      _historicalRmByExercise(),
    ]);
    final sessions = results[0] as List<_PlannedSessionExercises>;
    final historicalRm = results[1] as Map<String, double>;
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final choices = _distinctExerciseChoices(sessions);
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay ejercicios planificados todavía para este atleta.',
          ),
        ),
      );
      return;
    }

    final chosen = await _showExercisePickerDialog(choices);
    if (chosen == null || !mounted) return;

    final matchingSessions =
        sessions
            .where(
              (s) => s.exercises.any(
                (e) =>
                    e['exerciseId']?.toString() == chosen.exerciseId &&
                    (e['variantId']?.toString() ?? 'original') ==
                        chosen.variantId,
              ),
            )
            .toList();

    final selectedSessions = await _showSessionPickerDialog(
      chosen,
      matchingSessions,
    );
    if (selectedSessions == null || selectedSessions.isEmpty || !mounted) {
      return;
    }

    final rmKey = WorkoutRMService.normalizeExerciseName(chosen.name);
    // El RM calculado desde entrenamientos logueados tiene prioridad; el
    // RM manual es solo respaldo para cuando todavía no hay historial.
    final rm = historicalRm[rmKey] ?? await _manualRmFor(athleteId, rmKey);
    if (!mounted) return;
    await _showProgressionTableDialog(
      chosen,
      selectedSessions,
      rm,
      athleteId: athleteId,
      rmKey: rmKey,
    );
  }

  Future<_ExerciseChoice?> _showExercisePickerDialog(
    List<_ExerciseChoice> choices,
  ) {
    final searchController = TextEditingController();
    return showDialog<_ExerciseChoice>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              final query = searchController.text.trim().toLowerCase();
              final filtered =
                  query.isEmpty
                      ? choices
                      : choices
                          .where((c) => c.name.toLowerCase().contains(query))
                          .toList();
              return AlertDialog(
                title: const Text('Elegir ejercicio'),
                content: SizedBox(
                  width: 460,
                  height: 480,
                  child: Column(
                    children: [
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Buscar ejercicio…',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            filtered.isEmpty
                                ? const Center(child: Text('Sin resultados'))
                                : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder:
                                      (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, index) {
                                    final choice = filtered[index];
                                    return ListTile(
                                      title: Text(choice.name),
                                      subtitle: Text(
                                        '${choice.sessionCount} ${choice.sessionCount == 1 ? 'sesión' : 'sesiones'} planificadas',
                                      ),
                                      onTap:
                                          () => Navigator.pop(
                                            dialogContext,
                                            choice,
                                          ),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<List<_PlannedSessionExercises>?> _showSessionPickerDialog(
    _ExerciseChoice chosen,
    List<_PlannedSessionExercises> matchingSessions,
  ) {
    final selected = <String>{
      for (final s in matchingSessions) s.plannedWorkoutId,
    };
    return showDialog<List<_PlannedSessionExercises>>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text(chosen.name),
                  content: SizedBox(
                    width: 520,
                    height: 480,
                    child:
                        matchingSessions.isEmpty
                            ? const Center(
                              child: Text(
                                'No se encontraron sesiones planificadas con este ejercicio.',
                              ),
                            )
                            : ListView.separated(
                              itemCount: matchingSessions.length,
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final session = matchingSessions[index];
                                final isSelected = selected.contains(
                                  session.plannedWorkoutId,
                                );
                                return CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selected.add(session.plannedWorkoutId);
                                      } else {
                                        selected.remove(
                                          session.plannedWorkoutId,
                                        );
                                      }
                                    });
                                  },
                                  title: Text(_formatFullDate(session.date)),
                                  subtitle: Text(session.blockTitle),
                                );
                              },
                            ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed:
                          selected.isEmpty
                              ? null
                              : () => Navigator.pop(
                                dialogContext,
                                matchingSessions
                                    .where(
                                      (s) =>
                                          selected.contains(s.plannedWorkoutId),
                                    )
                                    .toList(),
                              ),
                      child: Text('Continuar (${selected.length})'),
                    ),
                  ],
                ),
          ),
    );
  }

  String _formatFullDate(DateTime date) {
    const weekdays = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    final weekday = weekdays[date.weekday - 1];
    return '$weekday ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  /// Encuentra, dentro de una sesión ya resuelta, el ejercicio que matchea
  /// la variante elegida.
  Map<String, dynamic>? _findChosenExercise(
    _PlannedSessionExercises session,
    _ExerciseChoice chosen,
  ) {
    for (final exercise in session.exercises) {
      final exerciseId = exercise['exerciseId']?.toString();
      final variantId = exercise['variantId']?.toString() ?? 'original';
      if (exerciseId == chosen.exerciseId && variantId == chosen.variantId) {
        return exercise;
      }
    }
    return null;
  }

  /// Agrupa una lista plana de `sets` (`{weight, reps}` por serie) en
  /// columnas de peso: series consecutivas con el mismo peso y las mismas
  /// reps se colapsan en una sola columna con `series` > 1. Es la
  /// operación inversa a la expansión que se hace al guardar.
  List<_WeightColumn> _groupSetsIntoColumns(List<Map<String, dynamic>> sets) {
    if (sets.isEmpty) return [_WeightColumn()];
    final columns = <_WeightColumn>[];
    double? lastWeight;
    int? lastReps;
    for (final set in sets) {
      final weight = (set['weight'] as num?)?.toDouble() ?? 0;
      final reps = (set['reps'] as num?)?.toInt() ?? 0;
      if (columns.isNotEmpty && weight == lastWeight && reps == lastReps) {
        final col = columns.last;
        col.seriesCtrl.text = (col.series + 1).toString();
      } else {
        columns.add(
          _WeightColumn(
            weight: weight == 0 ? '' : _formatNum(weight),
            series: '1',
            reps: reps == 0 ? '' : reps.toString(),
          ),
        );
      }
      lastWeight = weight;
      lastReps = reps;
    }
    return columns;
  }

  String _formatNum(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  Future<void> _showProgressionTableDialog(
    _ExerciseChoice chosen,
    List<_PlannedSessionExercises> sessions,
    double? initialRm, {
    required String athleteId,
    required String rmKey,
  }) async {
    // Columnas de peso por sesión, precargadas agrupando los `sets` planos
    // que ya tenía guardados esa sesión.
    final columnsBySession = <String, List<_WeightColumn>>{};
    final perSideBySession = <String, bool>{};
    for (final session in sessions) {
      final exercise = _findChosenExercise(session, chosen);
      final sets = List<Map<String, dynamic>>.from(
        exercise?['sets'] ?? const [],
      );
      columnsBySession[session.plannedWorkoutId] = _groupSetsIntoColumns(sets);
      perSideBySession[session.plannedWorkoutId] =
          exercise?['perSide'] == true || exercise?['unilateral'] == true;
    }

    // Mutable: se puede fijar dentro del diálogo con "Agregar RM" sin
    // necesidad de cerrar y reabrir todo el flujo.
    double? currentRm = initialRm;
    bool editingRm = false;
    // El campo de edición del RM vive INLINE dentro de este mismo diálogo
    // (no como un segundo `showDialog` anidado): abrir un diálogo dentro
    // de otro que además se reconstruye con su propio `setState` disparaba
    // el assertion `dependents.isEmpty` de Flutter al cerrarse, porque
    // quedan referencias cruzadas entre los dos overlays del Navigator.
    final rmController = TextEditingController(
      text: currentRm != null ? _formatNum(currentRm) : '',
    );

    void disposeAll() {
      for (final columns in columnsBySession.values) {
        for (final col in columns) {
          col.dispose();
        }
      }
      rmController.dispose();
    }

    final save = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text('Progresión: ${chosen.name}'),
                  content: SizedBox(
                    width: 820,
                    height: 560,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!editingRm)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  currentRm != null
                                      ? 'RM de referencia: ${currentRm!.toStringAsFixed(1)} kg'
                                      : 'RM de referencia: sin datos — el IMR no se puede calcular',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.edit, size: 16),
                                label: Text(
                                  currentRm == null
                                      ? 'Agregar RM'
                                      : 'Editar RM',
                                ),
                                onPressed:
                                    () => setDialogState(() {
                                      rmController.text =
                                          currentRm != null
                                              ? _formatNum(currentRm!)
                                              : '';
                                      editingRm = true;
                                    }),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: rmController,
                                  autofocus: true,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'RM (kg)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.check, size: 18),
                                tooltip: 'Guardar RM',
                                onPressed: () async {
                                  final value = double.tryParse(
                                    rmController.text.replaceAll(',', '.'),
                                  );
                                  if (value == null || value <= 0) return;
                                  await _saveManualRm(
                                    athleteId,
                                    rmKey,
                                    chosen.name,
                                    value,
                                  );
                                  setDialogState(() {
                                    currentRm = value;
                                    editingRm = false;
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Cancelar',
                                onPressed:
                                    () =>
                                        setDialogState(() => editingRm = false),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        _buildProgressionChart(
                          sessions,
                          columnsBySession,
                          currentRm,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.separated(
                            itemCount: sessions.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (_, index) {
                              final session = sessions[index];
                              final columns =
                                  columnsBySession[session.plannedWorkoutId]!;
                              final metrics = _SessionMetrics.from(
                                columns,
                                currentRm,
                              );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_formatFullDate(session.date)} · ${session.blockTitle}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      _metricChip('Vol ${metrics.volume}'),
                                      const SizedBox(width: 6),
                                      _metricChip(
                                        'Ton ${metrics.tonnage.toStringAsFixed(0)}',
                                      ),
                                      const SizedBox(width: 6),
                                      _metricChip(
                                        'PM ${metrics.pm.toStringAsFixed(1)}',
                                      ),
                                      const SizedBox(width: 6),
                                      _metricChip(
                                        metrics.imr == null
                                            ? 'IMR —'
                                            : 'IMR ${metrics.imr!.toStringAsFixed(1)}%',
                                        highlight: true,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (
                                          var colIndex = 0;
                                          colIndex < columns.length;
                                          colIndex++
                                        )
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: _weightColumnEditor(
                                              columns[colIndex],
                                              onChanged:
                                                  () => setDialogState(() {}),
                                              onRemove:
                                                  columns.length > 1
                                                      ? () =>
                                                          setDialogState(() {
                                                            columns[colIndex]
                                                                .dispose();
                                                            columns.removeAt(
                                                              colIndex,
                                                            );
                                                          })
                                                      : null,
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: 'Agregar peso',
                                          icon: const Icon(
                                            Icons.add_circle_outline,
                                          ),
                                          onPressed:
                                              () => setDialogState(() {
                                                // Hereda las reps de la
                                                // última columna: al
                                                // progresar peso lo más
                                                // común es mantener las
                                                // mismas reps, y evita
                                                // dejar el campo vacío
                                                // (que se vería como "-"
                                                // en el PDF en vez de un
                                                // número real).
                                                final lastReps =
                                                    columns.isNotEmpty
                                                        ? columns.last.reps
                                                        : 0;
                                                columns.add(
                                                  _WeightColumn(
                                                    reps:
                                                        lastReps > 0
                                                            ? lastReps
                                                                .toString()
                                                            : '',
                                                  ),
                                                );
                                              }),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Guardar progresión'),
                    ),
                  ],
                ),
          ),
    );

    if (save != true) {
      disposeAll();
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final session in sessions) {
      final exercise = _findChosenExercise(session, chosen);
      if (exercise == null) continue;
      final exerciseInstanceId = exercise['exerciseInstanceId'].toString();
      final perSide = perSideBySession[session.plannedWorkoutId] ?? false;
      final columns = columnsBySession[session.plannedWorkoutId] ?? const [];

      // Si el usuario dejó el campo "reps" vacío en alguna columna, se usa
      // el reps del ejercicio ya resuelto como respaldo en vez de omitir
      // la clave del todo — sin esto, el PDF y otras vistas mostrarían un
      // "-" ambiguo en vez de un número real para esa columna.
      final existingSets = List<Map<String, dynamic>>.from(
        exercise['sets'] ?? const [],
      );
      final fallbackReps =
          existingSets.isNotEmpty
              ? (existingSets.first['reps'] as num?)?.toInt() ?? 0
              : 0;

      final expandedSets = <Map<String, dynamic>>[
        for (final col in columns)
          if (col.series > 0)
            for (var i = 0; i < col.series; i++)
              {
                'weight': col.weight,
                'reps': col.reps > 0 ? col.reps : fallbackReps,
                'source': 'manual',
              },
      ];

      final newOverride = {
        'exerciseInstanceId': exerciseInstanceId,
        'perSide': perSide,
        // Cantidad de series EXACTA que definió el usuario en la tabla:
        // sin este campo, `resolveBlock` infiere el total como el máximo
        // entre el override y el bloque original, así que reducir series
        // acá (ej. de 4 a 2) haría "resucitar" las 2 sobrantes con el
        // peso/reps original del bloque en vez de desaparecer.
        'totalSets': expandedSets.length,
        'sets': expandedSets,
      };

      // Mergear con los overrides existentes de OTROS ejercicios del mismo
      // bloque: reemplazar solo la entrada de este exerciseInstanceId,
      // conservar el resto tal cual estaba.
      final mergedOverrides = [
        for (final existing in session.existingOverrides)
          if (existing['exerciseInstanceId']?.toString() != exerciseInstanceId)
            existing,
        newOverride,
      ];

      batch.update(
        FirebaseFirestore.instance
            .collection('planned_workouts')
            .doc(session.plannedWorkoutId),
        {
          'loadOverrides': mergedOverrides,
          'loadOverridesUpdatedAt': FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
    disposeAll();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Progresión guardada en ${sessions.length} ${sessions.length == 1 ? 'sesión' : 'sesiones'}.',
        ),
      ),
    );
    if (_selectedDay != null) {
      await _loadPlannedForDay(_selectedDay!);
    }
  }

  /// Progresión en el tiempo de los 4 indicadores (volumen, tonelaje, PM,
  /// IMR) a través de las sesiones seleccionadas, ordenadas por fecha.
  /// Un mini-gráfico por indicador en vez de uno solo con 4 líneas: cada
  /// indicador tiene una escala muy distinta (volumen en unidades, tonelaje
  /// en miles, PM en kg, IMR en %), así que compartir un eje distorsionaría
  /// la lectura — un eje dual nunca es la solución correcta.
  Widget _buildProgressionChart(
    List<_PlannedSessionExercises> sessions,
    Map<String, List<_WeightColumn>> columnsBySession,
    double? rm,
  ) {
    if (sessions.length < 2) return const SizedBox.shrink();

    final ordered = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
    final metricsBySession = [
      for (final s in ordered)
        _SessionMetrics.from(columnsBySession[s.plannedWorkoutId]!, rm),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progresión en el tiempo',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _progressionSparkline('Volumen', [
                  for (final m in metricsBySession) m.volume.toDouble(),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _progressionSparkline('Tonelaje', [
                  for (final m in metricsBySession) m.tonnage,
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _progressionSparkline('PM (kg)', [
                  for (final m in metricsBySession) m.pm,
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _progressionSparkline('IMR (%)', [
                  for (final m in metricsBySession) m.imr ?? 0,
                ], showsData: metricsBySession.any((m) => m.imr != null)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressionSparkline(
    String label,
    List<double> values, {
    bool showsData = true,
  }) {
    final hasRange = values.isNotEmpty && values.any((v) => v > 0);
    final minY = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxY = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    // Padding del 15% arriba/abajo para que la línea no toque los bordes.
    final span = (maxY - minY).abs();
    final padding = span > 0 ? span * 0.15 : (maxY.abs() * 0.15 + 1);
    final chartMinY = minY - padding;
    final chartMaxY = maxY + padding;
    final last = values.isEmpty ? 0.0 : values.last;
    final first = values.isEmpty ? 0.0 : values.first;
    final delta = last - first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              showsData && hasRange ? last.toStringAsFixed(1) : '—',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            if (showsData && hasRange && delta != 0) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: delta > 0 ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child:
              !showsData || !hasRange
                  ? const Center(
                    child: Text(
                      'Sin datos',
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                  )
                  : LineChart(
                    LineChartData(
                      minY: chartMinY,
                      maxY: chartMaxY,
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems:
                              (spots) =>
                                  spots
                                      .map(
                                        (spot) => LineTooltipItem(
                                          spot.y.toStringAsFixed(1),
                                          const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      )
                                      .toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < values.length; i++)
                              FlSpot(i.toDouble(), values[i]),
                          ],
                          isCurved: false,
                          color: AppColors.accent,
                          barWidth: 2,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter:
                                (spot, percent, bar, index) =>
                                    FlDotCirclePainter(
                                      radius: 2.5,
                                      color: AppColors.accent,
                                      strokeWidth: 0,
                                    ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.accent.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _metricChip(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            highlight
                ? AppColors.accent.withOpacity(0.15)
                : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          color: highlight ? AppColors.accent : Colors.grey[300],
        ),
      ),
    );
  }

  Widget _weightColumnEditor(
    _WeightColumn column, {
    required VoidCallback onChanged,
    VoidCallback? onRemove,
  }) {
    return Container(
      width: 96,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Peso', style: TextStyle(fontSize: 10)),
              if (onRemove != null)
                InkWell(
                  onTap: onRemove,
                  child: const Icon(Icons.close, size: 14),
                ),
            ],
          ),
          TextField(
            controller: column.weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              isDense: true,
              suffixText: 'kg',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: column.seriesCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'series',
                    labelStyle: TextStyle(fontSize: 9),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: column.repsCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'reps',
                    labelStyle: TextStyle(fontSize: 9),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<Map<String, double>> _historicalRmByExercise() async {
    final output = <String, double>{};
    final snapshot =
        await FirebaseFirestore.instance
            .collection('workouts_logged')
            .where('userId', isEqualTo: selectedAthleteId)
            .get();
    for (final document in snapshot.docs) {
      final performed = List<Map<String, dynamic>>.from(
        document.data()['performed'] ?? const [],
      );
      for (final candidate in WorkoutRMService.extractAllValidRMSetCandidates(
        performed,
      )) {
        final name = candidate['exercise']?.toString() ?? '';
        final weight = (candidate['weight'] as num?)?.toDouble() ?? 0;
        final reps = (candidate['reps'] as num?)?.toInt() ?? 0;
        if (name.isEmpty || weight <= 0 || reps <= 0) continue;
        final key = WorkoutRMService.normalizeExerciseName(name);
        final rm = WorkoutRMService.estimate1RM(weight: weight, reps: reps);
        if (rm > (output[key] ?? 0)) output[key] = rm;
      }
    }
    return output;
  }

  /// RM cargado a mano por el entrenador para un atleta+ejercicio, para
  /// cuando todavía no hay historial de entrenamientos logueados que
  /// permita calcularlo automáticamente. Es solo un respaldo: en
  /// `_planProgressionByExercise` el RM calculado desde `workouts_logged`
  /// siempre tiene prioridad sobre este.
  Future<double?> _manualRmFor(String athleteId, String rmKey) async {
    final doc =
        await FirebaseFirestore.instance
            .collection('athlete_manual_rm')
            .doc('${athleteId}_$rmKey')
            .get();
    if (!doc.exists) return null;
    return (doc.data()?['rm'] as num?)?.toDouble();
  }

  Future<void> _saveManualRm(
    String athleteId,
    String rmKey,
    String exerciseName,
    double rm,
  ) async {
    await FirebaseFirestore.instance
        .collection('athlete_manual_rm')
        .doc('${athleteId}_$rmKey')
        .set({
          'athleteId': athleteId,
          'exerciseName': exerciseName,
          'rm': rm,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  // ====================================================
  // DELETE
  // ====================================================
  Future<void> _deleteWorkout(String id) async {
    final planned = _plannedWorkouts.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == id,
      orElse: () => null,
    );
    if (planned == null) return;
    final cachedBlock = _blockCache[planned['blockId']]?.data();
    Map<String, dynamic> block =
        cachedBlock is Map
            ? Map<String, dynamic>.from(cachedBlock)
            : <String, dynamic>{
              'title': planned['title'] ?? planned['name'] ?? 'Bloque',
              'type': planned['type'] ?? '',
              'exercises': planned['exercises'] ?? const [],
            };
    final blockId = planned['blockId']?.toString();
    if ((block['exercises'] as List? ?? const []).isEmpty &&
        blockId != null &&
        blockId.isNotEmpty) {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('blocks')
              .doc(blockId)
              .get();
      if (snapshot.exists) block = snapshot.data() ?? block;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Eliminar sesión planificada'),
            content: Text(
              'Se quitará “${planned['title'] ?? planned['name'] ?? 'esta sesión'}”. Podrás revisar el impacto en el perfil antes de confirmar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _showBlockProfileAdjustment(
      previousBlock: block,
      updatedBlock: <String, dynamic>{
        'title': block['title'],
        'type': block['type'],
        'exercises': const [],
      },
      title: 'Impacto al eliminar la sesión',
      targetWorkoutId: id,
    );
    await FirebaseFirestore.instance
        .collection('planned_workouts')
        .doc(id)
        .delete();

    _loadPlannedForDay(_selectedDay!);
  }

  // ====================================================
  // REORDER WORKOUTS
  // ====================================================
  Future<void> _reorderWorkouts(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    setState(() {
      final item = _plannedWorkouts.removeAt(oldIndex);
      _plannedWorkouts.insert(newIndex, item);
    });

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (int i = 0; i < _plannedWorkouts.length; i++) {
        final workoutId = _plannedWorkouts[i]['id'];
        final docRef = FirebaseFirestore.instance
            .collection('planned_workouts')
            .doc(workoutId);

        // Update local state and prepare batch update
        _plannedWorkouts[i]['order'] = i;
        batch.update(docRef, {'order': i});
      }

      await batch.commit();
    } catch (e) {
      // Revert on failure
      debugPrint("Error reordering: $e");
      await _loadPlannedForDay(_selectedDay!);
    }
  }

  Map<String, dynamic>? _resolvedPlannedBlock(Map<String, dynamic> workout) {
    final blockId = workout['blockId']?.toString();
    final snapshot = blockId == null ? null : _blockCache[blockId];
    final raw = snapshot?.data();
    if (raw is! Map) return null;
    return PlannedLoadService.resolveBlock(
      block: Map<String, dynamic>.from(raw),
      planned: workout,
    );
  }

  int _plannedExerciseCount() {
    return _plannedWorkouts.fold<int>(0, (total, workout) {
      final block = _resolvedPlannedBlock(workout);
      return total + ((block?['exercises'] as List?)?.length ?? 0);
    });
  }

  int _plannedSetCount() {
    return _plannedWorkouts.fold<int>(0, (total, workout) {
      final block = _resolvedPlannedBlock(workout);
      final exercises = block?['exercises'] as List? ?? const [];
      return total +
          exercises.fold<int>(0, (count, raw) {
            if (raw is! Map) return count;
            return count + PlannedLoadService.baseSets(raw).length;
          });
    });
  }

  String _blockStructureLabel(Map<String, dynamic> block) {
    final type = (block['type'] ?? 'Bloque').toString();
    final rounds = block['rounds'];
    switch (type) {
      case 'Circuito':
        return rounds == null ? type : '$type · $rounds rondas';
      case 'EMOM':
        return '$type · ${block['time'] ?? '?'} s · ${rounds ?? '?'} rondas';
      case 'Tabata':
        return '$type · ${block['work'] ?? '?'} / ${block['rest'] ?? '?'} · ${rounds ?? '?'} rondas';
      case 'Buscar RM':
        return '$type · objetivo ${block['rm'] ?? 5}RM';
      default:
        return type;
    }
  }

  String _exercisePrescription(Map<String, dynamic> exercise) {
    final sets = PlannedLoadService.baseSets(exercise);
    // Desglosado por grupos de series con el mismo peso y reps (ej.
    // "2x3 @ 85kg / 1x3 @ 90kg") en vez de listar reps y pesos por
    // separado, que no dejaba claro qué peso iba con qué serie.
    final setGroupsLabel = PlannedLoadService.formatSetGroups(sets);
    if (setGroupsLabel.isNotEmpty) return setGroupsLabel;
    return '${sets.length} ${sets.length == 1 ? 'serie' : 'series'}';
  }

  Widget _plannedDaySummary(DateTime date) {
    final blocks = _plannedWorkouts.length;
    final exercises = _plannedExerciseCount();
    final sets = _plannedSetCount();
    final dateLabel =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 7,
        children: [
          Text(
            'Plan de $dateLabel',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          TextButton.icon(
            onPressed:
                _plannedWorkouts.isEmpty
                    ? null
                    : () => _showSelectedDayPlanDialog(date),
            icon: const Icon(Icons.article_outlined, size: 16),
            label: const Text('Ver detalle'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: Colors.lightBlueAccent,
            ),
          ),
          _planSummaryPill(Icons.view_agenda_outlined, '$blocks bloques'),
          _planSummaryPill(
            Icons.fitness_center_outlined,
            '$exercises ejercicios',
          ),
          _planSummaryPill(Icons.repeat_outlined, '$sets series'),
        ],
      ),
    );
  }

  Future<void> _showSelectedDayPlanDialog(DateTime date) {
    final dateLabel =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    final screen = MediaQuery.sizeOf(context);
    return showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            backgroundColor: const Color(0xFF151515),
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: math.min(760, screen.width - 32),
              height: math.min(760, screen.height - 32),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          color: Colors.lightBlueAccent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Planificación del día',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                dateLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                      itemCount: _plannedWorkouts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final workout = _plannedWorkouts[index];
                        return Card(
                          color: const Color(0xFF202020),
                          margin: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  workout['blockTitle'] ??
                                      'Bloque ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              _plannedBlockDetail(workout),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _planSummaryPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.info),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _plannedBlockDetail(Map<String, dynamic> workout) {
    final block = _resolvedPlannedBlock(workout);
    if (block == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No se pudo cargar el contenido de este bloque.'),
      );
    }
    final exercises = List<Map<String, dynamic>>.from(
      block['exercises'] ?? const [],
    );
    final description =
        (block['description'] ?? block['notes'] ?? '').toString().trim();
    final blockType = (block['type'] ?? 'Series').toString();
    final isCircuit = blockType == 'Circuito';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _planSummaryPill(
                Icons.category_outlined,
                _blockStructureLabel(block),
              ),
              _planSummaryPill(
                Icons.fitness_center_outlined,
                '${exercises.length} ejercicios',
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (isCircuit) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(.28)),
              ),
              child: Text(
                'Completar en orden · ${block['rounds'] ?? '?'} rondas · una pasada por cada ejercicio',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...exercises.asMap().entries.map((entry) {
            final exercise = entry.value;
            final name = coerceExerciseName(exercise['name']);
            final variant =
                (exercise['variantName'] ?? exercise['variantLabel'] ?? '')
                    .toString()
                    .trim();
            final exerciseType =
                (exercise['exerciseType'] ?? '').toString().trim();
            final visibleVariant =
                variant.isNotEmpty &&
                variant.toLowerCase() != name.toLowerCase();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(.16),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${entry.key + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (visibleVariant || exerciseType.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (visibleVariant) variant,
                              if (exerciseType.isNotEmpty) exerciseType,
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          isCircuit
                              ? '${_exercisePrescription(exercise)} por ronda'
                              : _exercisePrescription(exercise),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.lightBlueAccent,
                          ),
                        ),
                        ExerciseNote(exercise['notes']),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String normalizeExerciseName(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is List && raw.isNotEmpty) return raw.first.toString().trim();
    return raw.toString().trim();
  }

  DateTime _startOfWeekMonday(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  Future<void> _replicateWeek() async {
    if (selectedAthleteId == null) return;

    // 1. SELECT SOURCE WEEK
    final DateTime? sourceStart = await showDatePicker(
      context: context,
      initialDate: _startOfWeekMonday(_selectedDay ?? DateTime.now()),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: "COPIAR: Selecciona el lunes de la semana origen",
      selectableDayPredicate: (day) => day.weekday == DateTime.monday,
    );
    if (sourceStart == null || !mounted) return;
    final sourceEnd = sourceStart.add(const Duration(days: 7));

    // 2. SELECT TARGET WEEK
    final DateTime? targetStart = await showDatePicker(
      context: context,
      initialDate: sourceStart.add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: "PEGAR: Selecciona el lunes de la semana destino",
      selectableDayPredicate: (day) => day.weekday == DateTime.monday,
    );
    if (targetStart == null) return;
    final targetEnd = targetStart.add(const Duration(days: 7));

    // 3. GET SOURCE WORKOUTS
    final snapshot = await _plannedDocsInRange(sourceStart, sourceEnd);

    if (snapshot.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No hay entrenamientos planificados en la semana origen",
            ),
          ),
        );
      }
      return;
    }

    // 4. CONFIRM OVERWRITE IF TARGET IS NOT EMPTY
    final existingSnapshot = await _plannedDocsInRange(targetStart, targetEnd);

    if (!mounted) return;
    bool proceed = true;
    if (existingSnapshot.isNotEmpty) {
      proceed =
          await showDialog<bool>(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text("Sobrescribir semana"),
                  content: Text(
                    "La semana del ${targetStart.day}/${targetStart.month} ya tiene entrenamientos. ¿Deseas borrarlos y replicar?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Cancelar"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        "Sobrescribir",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
          ) ??
          false;
    }

    if (!proceed) return;

    setState(() => _loading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Delete existing in target
      for (var doc in existingSnapshot) {
        batch.delete(doc.reference);
      }

      // Copy source to target
      for (var doc in snapshot) {
        final data = doc.data();
        final originalDate = _dateTimeValue(data['date']);
        if (originalDate == null) continue;
        final daysDiff = originalDate.difference(sourceStart).inDays;
        final newDate = targetStart.add(Duration(days: daysDiff));

        final newRef =
            FirebaseFirestore.instance.collection('planned_workouts').doc();
        batch.set(newRef, {
          ...data,
          'date': Timestamp.fromDate(newDate),
          'createdAt': Timestamp.now(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("¡Semana replicada con éxito!")),
        );
        _loadPlannedForDay(_selectedDay!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error al replicar: $e")));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ====================================================
  // UI
  // ====================================================
  Future<Map<String, dynamic>> _calculatePlannedPdfMetrics(
    Map<DateTime, List<Map<String, dynamic>>> days,
  ) async {
    final exerciseSnapshot =
        await FirebaseFirestore.instance.collection('exercises').get();
    final byId = <String, Map<String, dynamic>>{};
    final byName = <String, Map<String, dynamic>>{};
    for (final doc in exerciseSnapshot.docs) {
      final data = doc.data();
      byId[doc.id] = data;
      final name = (data['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty) byName[name] = data;
    }

    final muscleDistribution = <String, double>{};
    final dailyLoad = <DateTime, double>{};
    var blocksCount = 0;
    var exercisesCount = 0;
    var setsCount = 0.0;
    var volume = 0.0;
    final mesocycleIds = <String>{};

    for (final dayEntry in days.entries) {
      var dayVolume = 0.0;
      for (final item in dayEntry.value) {
        blocksCount++;
        final planned = Map<String, dynamic>.from(item['planned'] as Map);
        final block = Map<String, dynamic>.from(
          item['block'] as Map? ?? const {},
        );
        final mesocycleId = planned['mesocycleId']?.toString();
        if (mesocycleId != null && mesocycleId.isNotEmpty)
          mesocycleIds.add(mesocycleId);
        for (final rawExercise in (block['exercises'] as List? ?? const [])) {
          final exercise = Map<String, dynamic>.from(rawExercise as Map);
          exercisesCount++;
          final plannedSets =
              exercise['sets'] is List
                  ? List<Map<String, dynamic>>.from(exercise['sets'] as List)
                  : const <Map<String, dynamic>>[];
          final sets =
              plannedSets.isNotEmpty
                  ? plannedSets.length.toDouble()
                  : (exercise['series'] as num?)?.toDouble() ?? 1.0;
          final fallbackReps =
              (exercise['reps'] ??
                      exercise['value'] ??
                      exercise['targetReps'] as num?)
                  ?.toDouble() ??
              1.0;
          final fallbackWeight =
              (exercise['weight'] ??
                      exercise['referenceWeight'] ??
                      exercise['load'] as num?)
                  ?.toDouble() ??
              0.0;
          final unitLoad =
              plannedSets.isEmpty
                  ? sets *
                      fallbackReps *
                      (fallbackWeight > 0 ? fallbackWeight : 1.0) *
                      (exercise['perSide'] == true ? 2.0 : 1.0)
                  : plannedSets.fold<double>(0, (sum, set) {
                    final reps =
                        (set['reps'] as num?)?.toDouble() ?? fallbackReps;
                    final weight =
                        (set['weight'] as num?)?.toDouble() ?? fallbackWeight;
                    final sideFactor =
                        set['perSide'] == true || exercise['perSide'] == true
                            ? 2.0
                            : 1.0;
                    return sum +
                        reps * (weight > 0 ? weight : 1.0) * sideFactor;
                  });
          setsCount += sets;
          volume += unitLoad;
          dayVolume += unitLoad;

          final definition =
              byId[exercise['exerciseId']?.toString()] ??
              byName[(exercise['name'] ?? exercise['exercise'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase()];
          final weights = Map<String, dynamic>.from(
            definition?['muscleWeights'] ?? const {},
          );
          weights.forEach((muscle, rawWeight) {
            final share = (rawWeight as num).toDouble();
            muscleDistribution[muscle] =
                (muscleDistribution[muscle] ?? 0) + unitLoad * share;
          });
        }
      }
      dailyLoad[dayEntry.key] = dayVolume;
    }

    return {
      'muscleDistribution': muscleDistribution,
      'dailyLoad': dailyLoad,
      'summary': {
        'days': days.length,
        'blocks': blocksCount,
        'exercises': exercisesCount,
        'sets': setsCount.round(),
        'volume': volume,
        'mesocycleId':
            mesocycleIds.isEmpty ? 'Sin mesociclo' : mesocycleIds.join(', '),
      },
    };
  }

  /// Informe retrospectivo (planificado vs. entrenado, perfil, músculos,
  /// cumplimiento y fatiga) del atleta seleccionado. Por defecto cubre las 4
  /// semanas que terminan en la semana del día seleccionado (o hoy).
  Future<void> _exportTrainingPeriodReport() async {
    if (selectedAthleteId == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final base = _selectedDay ?? today;
    final weekStart = _startOfWeekMonday(base);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final defaultEnd = weekEnd.isAfter(today) ? today : weekEnd;
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: weekStart.subtract(const Duration(days: 21)),
        end: defaultEnd.isBefore(weekStart) ? weekStart : defaultEnd,
      ),
      helpText: 'Período del informe',
      saveText: 'Generar',
    );
    if (pickedRange == null || !mounted) return;

    await TrainingPeriodReportService.generateAndPreview(
      context: context,
      athleteId: selectedAthleteId!,
      athleteName: selectedAthleteName ?? 'Atleta',
      range: pickedRange,
    );
  }

  Future<void> _exportPlannedTrainingPdf() async {
    if (selectedAthleteId == null) return;

    final base = _selectedDay ?? DateTime.now();
    final initialStart = DateTime(base.year, base.month, base.day);
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: initialStart.add(const Duration(days: 6)),
      ),
      helpText: 'Rango del plan a exportar',
      saveText: 'Continuar',
    );
    if (pickedRange == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    var loadingDialogOpen = true;

    try {
      final start = DateTime(
        pickedRange.start.year,
        pickedRange.start.month,
        pickedRange.start.day,
      );
      final end = DateTime(
        pickedRange.end.year,
        pickedRange.end.month,
        pickedRange.end.day,
        23,
        59,
        59,
      );
      final plannedDocs = await _plannedDocsInRange(
        start,
        end.add(const Duration(seconds: 1)),
      );
      final planned =
          plannedDocs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      planned.sort((a, b) {
        final dateA = _dateTimeValue(a['date']) ?? start;
        final dateB = _dateTimeValue(b['date']) ?? start;
        final dateResult = dateA.compareTo(dateB);
        if (dateResult != 0) return dateResult;
        return ((a['order'] as num?)?.toInt() ?? 0).compareTo(
          (b['order'] as num?)?.toInt() ?? 0,
        );
      });

      final ids =
          planned
              .map((item) => item['blockId']?.toString())
              .whereType<String>()
              .toSet();
      final blockDocs = await Future.wait(
        ids.map(
          (id) => FirebaseFirestore.instance.collection('blocks').doc(id).get(),
        ),
      );
      final blocks = <String, Map<String, dynamic>>{
        for (final doc in blockDocs)
          if (doc.exists) doc.id: doc.data() ?? <String, dynamic>{},
      };
      final days = <DateTime, List<Map<String, dynamic>>>{};
      for (final item in planned) {
        final rawDate = _dateTimeValue(item['date']);
        if (rawDate == null) continue;
        final day = DateTime(rawDate.year, rawDate.month, rawDate.day);
        final baseBlock = blocks[item['blockId']];
        if (baseBlock == null) continue;
        days.putIfAbsent(day, () => []).add({
          'planned': item,
          'block': PlannedLoadService.resolveBlock(
            block: baseBlock,
            planned: item,
          ),
        });
      }

      final metrics = await _calculatePlannedPdfMetrics(days);
      final pdfRange = DateTimeRange(
        start: start,
        end: DateTime(end.year, end.month, end.day),
      );
      final muscleDistribution = Map<String, double>.from(
        metrics['muscleDistribution'] as Map,
      );
      final dailyLoad = Map<DateTime, double>.from(metrics['dailyLoad'] as Map);
      final summary = Map<String, dynamic>.from(metrics['summary'] as Map);
      final progressionVariants = await _loadProgressionVariantKeys();
      final pdfBytes = await PlannedWorkoutPdfService.buildBytes(
        athleteName: selectedAthleteName ?? 'Atleta',
        range: pdfRange,
        days: days,
        muscleDistribution: muscleDistribution,
        dailyLoad: dailyLoad,
        summary: summary,
        progressionVariants: progressionVariants,
      );
      final pageCount = PlannedWorkoutPdfService.pageCountFor(
        days,
        progressionVariants: progressionVariants,
      );
      if (mounted) {
        Navigator.pop(context);
        loadingDialogOpen = false;
      }
      if (!mounted) return;
      final confirmed = await _showActualPlannedPdfPreview(
        range: pdfRange,
        days: days,
        pdfBytes: pdfBytes,
        pageCount: pageCount,
      );
      if (confirmed != true || !mounted) return;
      await PlannedWorkoutPdfService.exportBytes(
        bytes: pdfBytes,
        athleteName: selectedAthleteName ?? 'Atleta',
        range: pdfRange,
      );
    } catch (error) {
      if (!mounted) return;
      if (loadingDialogOpen) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo preparar el PDF: $error')),
      );
    }
  }

  Future<Set<String>> _loadProgressionVariantKeys() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('exercises').get();
    final keys = <String>{};
    for (final document in snapshot.docs) {
      final variants = document.data()['variants'];
      if (variants is! List) continue;
      for (final raw in variants.whereType<Map>()) {
        final variant = Map<String, dynamic>.from(raw);
        final id = variant['id']?.toString();
        if (id != null &&
            id.isNotEmpty &&
            variant['trackProgression'] == true) {
          keys.add('${document.id}::$id');
          final movementName = document.data()['name']?.toString();
          final label = variant['label']?.toString();
          if (movementName != null && label != null && label.isNotEmpty) {
            keys.add(
              '${normalizeExerciseKey(movementName)}::${normalizeExerciseKey(label)}',
            );
          }
        }
      }
    }
    return keys;
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<bool?> _showActualPlannedPdfPreview({
    required DateTimeRange range,
    required Map<DateTime, List<Map<String, dynamic>>> days,
    required Uint8List pdfBytes,
    required int pageCount,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => _LowMemoryPdfPreviewDialog(
            bytes: pdfBytes,
            pageCount: pageCount,
            fileName: 'Plan_${_dateLabel(range.start)}.pdf',
            canExport: days.isNotEmpty,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isMobile = MediaQuery.of(context).size.width < 900;
    final d = _selectedDay!;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading:
            isMobile
                ? Builder(
                  builder:
                      (ctx) => IconButton(
                        icon: const Icon(Icons.library_books),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                )
                : null,
        title: Text(
          (role == 'administrador' || role == 'admin')
              ? (isMobile
                  ? "Admin: $selectedAthleteName"
                  : "Centro de Mando: $selectedAthleteName")
              : (isMobile ? "Plan" : "Mi planificación"),
        ),
        actions: [
          if ((role == 'administrador' || role == 'admin') &&
              selectedAthleteId != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance
                      .collection('load_adjustment_alerts')
                      .where('athleteId', isEqualTo: selectedAthleteId)
                      .snapshots(),
              builder: (context, snapshot) {
                final pending =
                    snapshot.data?.docs
                        .where((doc) => doc.data()['status'] == 'pending')
                        .length ??
                    0;
                return Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: IconButton(
                    icon: const Icon(Icons.notification_important_outlined),
                    tooltip: 'Alertas de ajuste de carga',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => LoadAdjustmentAlertsScreen(
                                athleteId: selectedAthleteId!,
                                athleteName: selectedAthleteName ?? 'Atleta',
                              ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.trending_up),
            tooltip: 'Progresión por ejercicio',
            onPressed: _planProgressionByExercise,
          ),
          // 🔁 Replicar semana
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: "Replicar semana",
            onPressed: _replicateWeek,
          ),

          // 🔁 Cambiar atleta
          if (role == 'administrador' || role == 'admin')
            IconButton(
              icon: const Icon(Icons.switch_account),
              tooltip: "Cambiar atleta",
              onPressed: () async {
                await _selectAthlete();
                if (selectedAthleteId != null) {
                  setState(() => _loading = true);
                  await _loadPlannedForDay(_selectedDay!);
                  setState(() => _loading = false);
                }
              },
            ),

          // La carga, la revisión diaria y el cumplimiento semanal están
          // consolidados en una sola pantalla con pestañas.
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: "Carga y revisión semanal",
            onPressed: () {
              if (selectedAthleteId == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => UnifiedWeeklyReviewScreen(
                        athleteId: selectedAthleteId!,
                        athleteName: selectedAthleteName ?? "Atleta",
                        initialDate: _selectedDay ?? DateTime.now(),
                        onProgressionByExercise: _planProgressionByExercise,
                      ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exportar plan a PDF',
            onPressed: _exportPlannedTrainingPdf,
          ),
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'Informe de entrenamiento',
            onPressed: _exportTrainingPeriodReport,
          ),
        ],
      ),
      drawer:
          isMobile
              ? Drawer(
                width: MediaQuery.of(context).size.width * 0.85,
                backgroundColor: AppColors.bgDeep,
                child: LibrarySidebar(
                  onBlockSelected: (block) {
                    _addBlockToPlanned(block);
                    Navigator.pop(context);
                  },
                  onEditBlock: _editBlockInLibrary,
                  onDeleteBlock: _deleteBlockInLibrary,
                  athleteId: selectedAthleteId,
                  selectedDay: _selectedDay ?? DateTime.now(),
                ),
              )
              : null,
      body: Row(
        children: [
          // ── BIBLIOTECA (IZQUIERDA) ────────────────────────
          if (!isMobile)
            Container(
              width: 450,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.surface)),
              ),
              child: LibrarySidebar(
                onBlockSelected: _addBlockToPlanned,
                onEditBlock: _editBlockInLibrary,
                onDeleteBlock: _deleteBlockInLibrary,
                athleteId: selectedAthleteId,
                selectedDay: _selectedDay ?? DateTime.now(),
              ),
            ),

          // ── PLANEADOR (DERECHA) ───────────────────────────
          Expanded(
            child: Column(
              children: [
                TableCalendar(
                  firstDay: DateTime.utc(2020),
                  lastDay: DateTime.utc(2030),
                  focusedDay: _focusedDay,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selected, focused) {
                    final normalized = _normalizeDayLocal(selected);
                    setState(() {
                      _selectedDay = normalized;
                      _focusedDay = focused;
                    });
                    _loadPlannedForDay(normalized);
                  },
                  calendarStyle: CalendarStyle(
                    selectedDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DragTarget<Map<String, dynamic>>(
                    onAccept: _addBlockToPlanned,
                    builder: (context, candidateData, rejectedData) {
                      final isOver = candidateData.isNotEmpty;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color:
                              isOver
                                  ? Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.05)
                                  : Colors.transparent,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _plannedDaySummary(d),
                            const SizedBox(height: 12),

                            if (_plannedWorkouts.isEmpty) ...[
                              Expanded(
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.calendar_today_outlined,
                                        size: 48,
                                        color: Colors.grey[800],
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        "Arrastra bloques aquí para planificar",
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ] else ...[
                              Expanded(
                                child: ReorderableListView.builder(
                                  onReorder: _reorderWorkouts,
                                  // Solo el ícono de drag_handle (leading)
                                  // dispara el arrastre; por defecto toda la
                                  // Card es arrastrable con long-press, lo
                                  // que movía bloques sin querer al tocar en
                                  // cualquier parte de la fila.
                                  buildDefaultDragHandles: false,
                                  itemCount: _plannedWorkouts.length,
                                  itemBuilder: (context, index) {
                                    final w = _plannedWorkouts[index];
                                    final isExpanded =
                                        _expandedWorkoutId == w['id'];

                                    return Card(
                                      key: ValueKey(w['id']),
                                      margin: const EdgeInsets.only(bottom: 12),
                                      color: AppColors.surface,
                                      child: Column(
                                        children: [
                                          ListTile(
                                            title: Text(
                                              w['blockTitle'] ?? 'Bloque',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            leading:
                                                role == 'administrador'
                                                    ? _SlowReorderableDragStartListener(
                                                      index: index,
                                                      child: const Icon(
                                                        Icons.drag_handle,
                                                        color: Colors.grey,
                                                      ),
                                                    )
                                                    : null,
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip:
                                                      'Editar bloque principal',
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    color: AppColors.info,
                                                    size: 20,
                                                  ),
                                                  onPressed:
                                                      () =>
                                                          _editPlannedBlock(w),
                                                ),
                                                if (role == 'administrador')
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                      color: Colors.redAccent,
                                                      size: 20,
                                                    ),
                                                    onPressed:
                                                        () => _deleteWorkout(
                                                          w['id'],
                                                        ),
                                                  ),
                                                Icon(
                                                  isExpanded
                                                      ? Icons.expand_less
                                                      : Icons.expand_more,
                                                  color: Colors.grey,
                                                ),
                                              ],
                                            ),
                                            onTap: () async {
                                              if (isExpanded) {
                                                setState(
                                                  () =>
                                                      _expandedWorkoutId = null,
                                                );
                                                return;
                                              }
                                              if (!_blockCache.containsKey(
                                                w['blockId'],
                                              )) {
                                                final blockDoc =
                                                    await FirebaseFirestore
                                                        .instance
                                                        .collection('blocks')
                                                        .doc(w['blockId'])
                                                        .get();
                                                _blockCache[w['blockId'] ??
                                                        ''] =
                                                    blockDoc;
                                              }
                                              setState(
                                                () =>
                                                    _expandedWorkoutId =
                                                        w['id'],
                                              );
                                            },
                                          ),
                                          if (isExpanded &&
                                              w['blockId'] != null &&
                                              _blockCache.containsKey(
                                                w['blockId'],
                                              ))
                                            _plannedBlockDetail(w),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LowMemoryPdfPreviewDialog extends StatefulWidget {
  const _LowMemoryPdfPreviewDialog({
    required this.bytes,
    required this.pageCount,
    required this.fileName,
    required this.canExport,
  });

  final Uint8List bytes;
  final int pageCount;
  final String fileName;
  final bool canExport;

  @override
  State<_LowMemoryPdfPreviewDialog> createState() =>
      _LowMemoryPdfPreviewDialogState();
}

class _LowMemoryPdfPreviewDialogState
    extends State<_LowMemoryPdfPreviewDialog> {
  int _page = 0;
  // La vista previa ya no expone controles ni instrucciones de zoom.
  bool _zoomed = false;

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.pageCount.clamp(1, 20);
    final screenSize = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(8),
      child: SizedBox(
        width: math.min(1400, screenSize.width - 16),
        height: screenSize.height * 0.95,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Vista previa exacta del PDF',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Página anterior',
                    onPressed:
                        _page == 0
                            ? null
                            : () => setState(() {
                              _page--;
                            }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${_page + 1} / $pageCount'),
                  IconButton(
                    tooltip: 'Página siguiente',
                    onPressed:
                        _page >= pageCount - 1
                            ? null
                            : () => setState(() {
                              _page++;
                            }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Visibility(
              visible: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                color:
                    _zoomed ? const Color(0xFFE8F5E9) : const Color(0xFFE8F0FE),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _zoomed ? Icons.zoom_out_map : Icons.zoom_in,
                      size: 18,
                      color:
                          _zoomed
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF1A73E8),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _zoomed
                            ? 'Vista ampliada: arrastra para recorrer la página. Doble toque para volver.'
                            : 'Doble toque sobre la página para ampliarla; luego puedes hacer zoom con dos dedos.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF20242B),
                child: PdfPreview(
                  key: ValueKey(_page),
                  build: (_) async => widget.bytes,
                  pages: [_page],
                  dpi: 144,
                  maxPageWidth: 1200,
                  useActions: false,
                  dynamicLayout: false,
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: widget.fileName,
                  previewPageMargin: const EdgeInsets.all(12),
                  scrollViewDecoration: const BoxDecoration(
                    color: Color(0xFF20242B),
                  ),
                  loadingWidget: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed:
                        widget.canExport
                            ? () => Navigator.pop(context, true)
                            : null,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Exportar PDF'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
