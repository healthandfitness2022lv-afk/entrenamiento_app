import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../models/exercise.dart';
import '../utils/block_title_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/exercise_note.dart';

class AddWorkoutScreen extends StatefulWidget {
  final Map<String, dynamic>? initialBlock;

  const AddWorkoutScreen({super.key, this.initialBlock});

  @override
  State<AddWorkoutScreen> createState() => _AddWorkoutScreenState();
}

class _AddWorkoutScreenState extends State<AddWorkoutScreen> {
  String? blockType;
  final List<Map<String, dynamic>> currentExercises = [];

  static const _blockTypes = <String>[
    "Series",
    "Circuito",
    "EMOM",
    "Tabata",
    "Series descendentes",
    "Buscar RM",
  ];

  // ===== Bloque =====
  final workCtrl = TextEditingController();
  final restCtrl = TextEditingController();
  final roundsCtrl = TextEditingController();
  final emomTimeCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final schemaCtrl = TextEditingController();
  final rmCtrl = TextEditingController();
  String _folder = "";
  String? _athleteId; // null = General, ID = Atleta específico
  List<QueryDocumentSnapshot> _allExercises = [];
  bool _loadedExercises = false;

  // ===== Ejercicio =====
  // Multi-selection: tracks all exercises chosen before hitting "Agregar"
  final Set<String> pendingExercises = {};
  final Map<String, ExerciseVariant> selectedVariantsByExercise = {};
  // For single-edit mode we still need the original exerciseName reference
  String? exerciseName;
  List<String> availableEquipment = [];
  String? selectedEquipment;

  final seriesCtrl = TextEditingController();
  final repsCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  final setWeightsCtrl = TextEditingController();
  final exerciseNotesCtrl = TextEditingController();
  late TextEditingController titleController;

  String valueType = "reps";
  bool perSide = false;
  int? editingExerciseIndex;

  String searchQuery = "";
  String? selectedTypeFilter; // filter chip for exerciseType

  // =====================================================
  // INIT
  // =====================================================

  @override
  void initState() {
    super.initState();
    _loadExercises();

    titleController = TextEditingController(
      text:
          widget.initialBlock?['title'] == null
              ? ''
              : visibleBlockTitle(widget.initialBlock?['title']),
    );
    descriptionCtrl.text = widget.initialBlock?['description'] ?? '';
    _folder = (widget.initialBlock?['folder'] ?? '').toString();
    _athleteId = widget.initialBlock?['athleteId'];

    final b = widget.initialBlock;
    blockType = (b?['type'] ?? "Series").toString();
    if (!_blockTypes.contains(blockType)) blockType = "Series";
    if (b == null) return;

    if (blockType == "Tabata") {
      valueType = "time"; // 🔥 fuerza tiempo
    }
    if (blockType == "Series descendentes") {
      final schema = List<int>.from(b["schema"] ?? [21, 15, 9]);
      schemaCtrl.text = schema.join("-");
    }
    if (blockType == "Buscar RM") {
      rmCtrl.text = b["rm"]?.toString() ?? "5";
    }

    final exercises = List<Map<String, dynamic>>.from(
      b["exercises"] ?? const [],
    );

    currentExercises.addAll(exercises);

    workCtrl.text = b["work"]?.toString() ?? "";
    restCtrl.text = b["rest"]?.toString() ?? "";
    roundsCtrl.text = b["rounds"]?.toString() ?? "";
    emomTimeCtrl.text = b["time"]?.toString() ?? "";
  }

  void _changeBlockType(String type) {
    setState(() {
      blockType = type;

      // Give each system a usable starting point without touching the
      // exercises already added to the block.
      if (type == "Tabata") {
        valueType = "time";
        if (workCtrl.text.trim().isEmpty) workCtrl.text = "20";
        if (restCtrl.text.trim().isEmpty) restCtrl.text = "10";
        if (roundsCtrl.text.trim().isEmpty) roundsCtrl.text = "8";
      } else {
        if (type == "Circuito" && roundsCtrl.text.trim().isEmpty) {
          roundsCtrl.text = "3";
        }
        if (type == "EMOM") {
          if (emomTimeCtrl.text.trim().isEmpty) emomTimeCtrl.text = "60";
          if (roundsCtrl.text.trim().isEmpty) roundsCtrl.text = "5";
        }
        if (type == "Series descendentes" && schemaCtrl.text.trim().isEmpty) {
          schemaCtrl.text = "21-15-9";
        }
        if (type == "Buscar RM" && rmCtrl.text.trim().isEmpty) {
          rmCtrl.text = "5";
        }
        if (valueType == "time") valueType = "reps";
      }
    });
  }

  @override
  void dispose() {
    workCtrl.dispose();
    restCtrl.dispose();
    roundsCtrl.dispose();
    emomTimeCtrl.dispose();
    schemaCtrl.dispose();
    rmCtrl.dispose();

    seriesCtrl.dispose();
    repsCtrl.dispose();
    weightCtrl.dispose();
    setWeightsCtrl.dispose();
    exerciseNotesCtrl.dispose();

    titleController.dispose();
    descriptionCtrl.dispose();

    super.dispose();
  }

  Future<void> _loadExercises() async {
    // Ejercicios
    final snap = await FirebaseFirestore.instance.collection("exercises").get();
    _allExercises =
        snap.docs.where((doc) => doc.data()['mergedInto'] == null).toList();
    _allExercises.sort(
      (a, b) => (a["name"] as String).compareTo(b["name"] as String),
    );

    setState(() {
      _loadedExercises = true;
    });
  }

  // =====================================================
  // GUARDAR BLOQUE
  // =====================================================

  void _saveBlock() {
    if (blockType == null || currentExercises.isEmpty) {
      _snack("Bloque incompleto");
      return;
    }

    for (final exercise in currentExercises) {
      final current = exercise['instanceId']?.toString().trim();
      if (current == null || current.isEmpty) {
        exercise['instanceId'] =
            FirebaseFirestore.instance
                .collection('exercise_instances')
                .doc()
                .id;
      }
    }
    final block = {
      "type": blockType,
      "title": titleController.text.trim(),
      "description": descriptionCtrl.text.trim(),
      "folder": _folder,
      "athleteId": _athleteId,
      "exercises": List<Map<String, dynamic>>.from(currentExercises),
    };

    if (blockType == "Tabata") {
      block.addAll({
        "work": int.tryParse(workCtrl.text) ?? 0,
        "rest": int.tryParse(restCtrl.text) ?? 0,
        "rounds": int.tryParse(roundsCtrl.text) ?? 0,
      });
    }

    if (blockType == "Circuito") {
      block["rounds"] = int.tryParse(roundsCtrl.text) ?? 1;
    }

    if (blockType == "Series descendentes") {
      final schema = _parseSchema(schemaCtrl.text);

      if (schema.isEmpty) {
        _snack("Esquema inválido");
        return;
      }

      block["schema"] = schema;
    }

    if (blockType == "Buscar RM") {
      block["rm"] = int.tryParse(rmCtrl.text) ?? 5;
    }

    if (blockType == "EMOM") {
      block.addAll({
        "time": int.tryParse(emomTimeCtrl.text) ?? 60,
        "rounds": int.tryParse(roundsCtrl.text) ?? 1,
      });
    }

    editingExerciseIndex = null;
    Navigator.pop(context, block);
  }

  // =====================================================
  // AGREGAR / EDITAR EJERCICIO
  // =====================================================

  void _editExercise(int index) {
    final e = currentExercises[index];

    setState(() {
      editingExerciseIndex = index;

      final movementName =
          (e['movementName'] ?? e['name'] ?? '').toString().split(' - ').first;
      exerciseName = movementName;
      seriesCtrl.text = e["series"]?.toString() ?? "";
      repsCtrl.text = e["value"]?.toString() ?? "";
      weightCtrl.text = e["weight"]?.toString() ?? "";
      final plannedSets =
          e['sets'] is List
              ? List<Map<String, dynamic>>.from(e['sets'] as List)
              : const <Map<String, dynamic>>[];
      setWeightsCtrl.text = plannedSets
          .map((set) => set['weight'])
          .where((weight) => weight != null)
          .map(_formatNumber)
          .join(' / ');
      valueType = e["valueType"] ?? "reps";
      perSide = e["perSide"] ?? false;
      exerciseNotesCtrl.text = (e['notes'] ?? '').toString();

      selectedEquipment = e["equipment"];
      availableEquipment =
          selectedEquipment != null ? [selectedEquipment!] : [];
      final variantId = e['variantId']?.toString();
      final exerciseId = e['exerciseId']?.toString();
      if (variantId != null && exerciseId != null) {
        final doc =
            _allExercises.where((d) => d.id == exerciseId).firstOrNull ??
            _allExercises
                .where(
                  (d) => ((d.data() as Map?)?['name'] ?? '') == movementName,
                )
                .firstOrNull;
        if (doc != null) {
          final movement = Exercise.fromFirestore(
            Map<String, dynamic>.from(doc.data() as Map),
            id: doc.id,
          );
          final variant =
              movement.variants.where((v) => v.id == variantId).firstOrNull ??
              movement.variants
                  .where((v) => v.label == e['variantLabel'])
                  .firstOrNull;
          if (variant != null) {
            selectedVariantsByExercise[movementName] = variant;
          }
        }
      }
    });
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = currentExercises.removeAt(oldIndex);
      currentExercises.insert(newIndex, item);
    });
  }

  num _parseWeight(String raw) {
    final cleaned = raw.replaceAll(',', '.').trim();

    if (cleaned.isEmpty) return 1;

    final parsed = double.tryParse(cleaned) ?? 1;

    if (parsed % 1 == 0) {
      return parsed.toInt();
    }

    return double.parse(parsed.toStringAsFixed(2));
  }

  String _formatNumber(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return '$value';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  }

  List<num> _parseSetWeights() {
    final raw = setWeightsCtrl.text.trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'\s*(?:/|;)\s*'))
        .where((part) => part.trim().isNotEmpty)
        .map(_parseWeight)
        .toList();
  }

  void _addExercise() {
    if (blockType == 'Series' && setWeightsCtrl.text.trim().isNotEmpty) {
      final series = int.tryParse(seriesCtrl.text) ?? 1;
      if (_parseSetWeights().length != series) {
        _snack('Ingresa un peso por cada una de las $series series');
        return;
      }
    }

    // In editing mode, behave as before (single exercise)
    if (editingExerciseIndex != null) {
      if (exerciseName == null) {
        _snack("Selecciona un ejercicio");
        return;
      }
      _commitSingleExercise(exerciseName!);
      setState(() {
        editingExerciseIndex = null;
        _clearExerciseForm();
      });
      return;
    }

    // Multi-select mode
    if (pendingExercises.isEmpty) {
      _snack("Selecciona al menos un ejercicio");
      return;
    }

    if (blockType != "Tabata" &&
        blockType != "Series descendentes" &&
        blockType != "Buscar RM" &&
        repsCtrl.text.isEmpty) {
      _snack("Ingresa reps o tiempo");
      return;
    }

    setState(() {
      for (final name in pendingExercises) {
        _commitSingleExercise(name);
      }
      _clearExerciseForm();
    });
  }

  void _commitSingleExercise(String name) {
    final int parsedValue = int.tryParse(repsCtrl.text) ?? 0;
    final num parsedWeight = _parseWeight(weightCtrl.text);

    final existingInstanceId =
        editingExerciseIndex == null
            ? null
            : currentExercises[editingExerciseIndex!]['instanceId']?.toString();
    final instanceId =
        existingInstanceId ??
        FirebaseFirestore.instance.collection('exercise_instances').doc().id;
    Map<String, dynamic> ex = {
      "name": name,
      "instanceId": instanceId,
      "perSide": perSide,
      "equipment": selectedEquipment,
      "weight": parsedWeight,
    };

    final catalogDoc =
        _allExercises.where((doc) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          return data['name'] == name;
        }).firstOrNull;
    if (catalogDoc != null) {
      final movement = Exercise.fromFirestore(
        Map<String, dynamic>.from(catalogDoc.data() as Map),
        id: catalogDoc.id,
      );
      final variant =
          selectedVariantsByExercise[name] ??
          (movement.variants.length == 1 ? movement.variants.first : null);
      if (variant != null) {
        final displayName = variant.displayName(
          movement.name,
          hideSingleVariantLabel: movement.variants.length == 1,
        );
        ex.addAll({
          'name': displayName,
          'movementName': movement.name,
          'exerciseId': movement.id,
          'movementId': movement.id,
          'variantId': variant.id,
          'variantLabel': variant.label,
          'familyId': variant.familyId,
          'exerciseType':
              variant.exerciseType.isNotEmpty
                  ? variant.exerciseType
                  : movement.exerciseType,
          'techniqueId': variant.techniqueId,
          'techniqueLabel': variant.techniqueLabel,
          'trainingDiscipline': variant.trainingDiscipline,
          'movementIntent': variant.movementIntent,
          'displayName': displayName,
          'equipment': variant.equipment.join(', '),
          'resistanceType': variant.resistanceType,
          'trackRM': variant.trackRM,
          'trackProgression': variant.trackProgression,
          'isUnilateral': variant.isUnilateral,
          if (variant.muscleWeightOverrides.isNotEmpty)
            'muscleWeightOverrides': {
              for (final entry in variant.muscleWeightOverrides.entries)
                entry.key.name: entry.value,
            },
        });
      }
    }

    if (blockType == "Series") {
      final series = int.tryParse(seriesCtrl.text) ?? 1;
      final plannedWeights = _parseSetWeights();
      final representativeWeight =
          plannedWeights.isEmpty
              ? parsedWeight
              : plannedWeights.fold<double>(
                    0,
                    (sum, value) => sum + value.toDouble(),
                  ) /
                  plannedWeights.length;
      ex['weight'] = representativeWeight;
      ex.addAll({
        "series": series,
        "value": parsedValue,
        "valueType": valueType,
        if (valueType == "reps") "reps": parsedValue,
        if (plannedWeights.isNotEmpty)
          'sets': [
            for (final weight in plannedWeights)
              {'reps': parsedValue, 'weight': weight, 'perSide': perSide},
          ],
      });
    }

    if (blockType == "Circuito" || blockType == "EMOM") {
      ex.addAll({
        "value": parsedValue,
        "valueType": valueType,
        if (valueType == "reps") "reps": parsedValue,
      });
    }

    // Series descendentes / Buscar RM: solo peso y nombre

    final notes = exerciseNotesCtrl.text.trim();
    if (notes.isNotEmpty) ex['notes'] = notes;

    if (editingExerciseIndex != null) {
      currentExercises[editingExerciseIndex!] = ex;
    } else {
      currentExercises.add(ex);
    }
  }

  void _clearExerciseForm() {
    exerciseName = null;
    pendingExercises.clear();
    selectedVariantsByExercise.clear();
    selectedEquipment = null;
    availableEquipment.clear();
    searchQuery = "";
    selectedTypeFilter = null;
    seriesCtrl.clear();
    repsCtrl.clear();
    weightCtrl.text = "1";
    setWeightsCtrl.clear();
    exerciseNotesCtrl.clear();
    valueType = "reps";
    perSide = false;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _topHeader() {
    return Row(
      children: [
        // ⬅️ VOLVER
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),

        const Spacer(), // 👈 empuja el resto hacia la derecha
        // 💾 GUARDAR BLOQUE
        IconButton(
          icon: const Icon(Icons.save),
          tooltip: "Guardar bloque",
          onPressed: _saveBlock,
        ),
      ],
    );
  }

  void _openAddExerciseSheet() {
    searchQuery = "";
    selectedTypeFilter = null;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final screenW = MediaQuery.of(context).size.width;
            final isWide = screenW > 600;
            final dialogW = (screenW * 0.95).clamp(300.0, 900.0);
            final dialogH = MediaQuery.of(context).size.height * 0.88;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                width: dialogW,
                height: dialogH,
                child: Column(
                  children: [
                    // ── HEADER ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                      child: Row(
                        children: [
                          Text(
                            editingExerciseIndex != null
                                ? "Editar ejercicio"
                                : "Agregar ejercicios",
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // ── BODY ────────────────────────────────────
                    Expanded(
                      child:
                          isWide
                              // Two-column layout for tablet / wide screen
                              ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left: search + list
                                  Expanded(
                                    flex: 6,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        8,
                                        0,
                                      ),
                                      child: _exerciseSearchAndSelector(
                                        setSheetState: setSheetState,
                                      ),
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  // Right: selected chips + execution
                                  Expanded(
                                    flex: 5,
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        16,
                                        0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _selectedExercisesPanel(
                                            setSheetState: setSheetState,
                                          ),
                                          const SizedBox(height: 12),
                                          _executionInput(
                                            setSheetState: setSheetState,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                              // Single-column layout for phones
                              : SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: Column(
                                  children: [
                                    _selectedExercisesPanel(
                                      setSheetState: setSheetState,
                                    ),
                                    const SizedBox(height: 8),
                                    _exerciseSearchAndSelector(
                                      setSheetState: setSheetState,
                                    ),
                                    const SizedBox(height: 12),
                                    _executionInput(
                                      setSheetState: setSheetState,
                                    ),
                                  ],
                                ),
                              ),
                    ),

                    // ── STICKY FOOTER ────────────────────────────
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(
                            editingExerciseIndex != null
                                ? Icons.save
                                : Icons.add,
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            _addExercise();
                            Navigator.pop(context);
                          },
                          label: Text(
                            editingExerciseIndex != null
                                ? "Guardar cambios"
                                : pendingExercises.isEmpty
                                ? "Agregar ejercicio"
                                : "Agregar ${pendingExercises.length} ejercicio${pendingExercises.length > 1 ? 's' : ''}",
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Panel showing currently selected exercise chips (used in right column)
  Widget _selectedExercisesPanel({required StateSetter setSheetState}) {
    if (pendingExercises.isEmpty &&
        !(editingExerciseIndex != null && exerciseName != null)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Seleccionados",
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ...pendingExercises.map(
              (name) => Chip(
                label: Text(
                  selectedVariantsByExercise[name]?.displayName(name) ?? name,
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 13),
                onDeleted:
                    () => setSheetState(() {
                      pendingExercises.remove(name);
                      selectedVariantsByExercise.remove(name);
                    }),
                backgroundColor: Colors.green.withOpacity(0.12),
                side: const BorderSide(color: Colors.green, width: 0.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (editingExerciseIndex != null && exerciseName != null)
              Chip(
                label: Text(
                  exerciseName!,
                  style: const TextStyle(fontSize: 12),
                ),
                avatar: const Icon(Icons.edit, size: 13),
                backgroundColor: Colors.blue.withOpacity(0.12),
              ),
          ],
        ),
        const Divider(height: 20),
      ],
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          setState(() {
            editingExerciseIndex = null;
            _clearExerciseForm();
          });
          _openAddExerciseSheet();
        },
      ),

      body: ListView(
        padding: const EdgeInsets.all(12),

        children: [
          const SizedBox(height: 25),

          _topHeader(),
          _blockConfigCard(),

          if (editingExerciseIndex != null)
            TextButton(
              onPressed: () {
                setState(() {
                  editingExerciseIndex = null;
                  _clearExerciseForm();
                });
              },
              child: const Text("Cancelar edición"),
            ),
          const SizedBox(height: 16),

          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: currentExercises.length,
            onReorder: _reorderExercises,
            itemBuilder: (_, index) {
              final e = currentExercises[index];

              return Card(
                key: ValueKey(e.hashCode),
                child: ListTile(
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text(e["name"]),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        blockType == "Tabata"
                            ? "Trabajo ${workCtrl.text}s"
                            : blockType == "Series descendentes"
                            ? "Esquema ${schemaCtrl.text}"
                            : blockType == "Buscar RM"
                            ? "Buscar ${rmCtrl.text} RM"
                            : "${e["series"] != null ? "${e["series"]}×" : ""}"
                                "${e["value"] ?? ""} "
                                "${e["valueType"] == "time" ? "seg" : "reps"}",
                      ),
                      ExerciseNote(
                        e['notes'],
                        padding: const EdgeInsets.only(top: 4),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          _editExercise(index);
                          _openAddExerciseSheet();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed:
                            () => setState(() {
                              currentExercises.removeAt(index);
                            }),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // =====================================================
  // UI HELPERS
  // =====================================================

  Widget _exerciseSearchAndSelector({required StateSetter setSheetState}) {
    if (!_loadedExercises) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      );
    }

    // Extract all unique exercise types dynamically
    final allTypes =
        _allExercises
            .map((d) => (d['exerciseType'] ?? 'Otros').toString())
            .toSet()
            .toList()
          ..sort();

    final query = searchQuery.trim().toLowerCase();

    final filtered =
        _allExercises.where((d) {
          final name = (d['name'] as String).toLowerCase().trim();
          final type = (d['exerciseType'] ?? 'Otros').toString();
          final matchesQuery = query.isEmpty || name.contains(query);
          final matchesType =
              selectedTypeFilter == null || type == selectedTypeFilter;
          return matchesQuery && matchesType;
        }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // ── Search field ─────────────────────────────────────
        TextField(
          decoration: const InputDecoration(
            hintText: "Buscar ejercicio...",
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setSheetState(() => searchQuery = v),
        ),

        const SizedBox(height: 10),

        // ── Category filter chips ────────────────────────────
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // "Todos" chip
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text("Todos"),
                  selected: selectedTypeFilter == null,
                  onSelected:
                      (_) => setSheetState(() => selectedTypeFilter = null),
                  selectedColor: Colors.blue.withOpacity(0.2),
                ),
              ),
              ...allTypes.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(t),
                    selected: selectedTypeFilter == t,
                    onSelected:
                        (_) => setSheetState(() {
                          selectedTypeFilter =
                              selectedTypeFilter == t ? null : t;
                        }),
                    selectedColor: Colors.blue.withOpacity(0.2),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── Results count ────────────────────────────────────
        Text(
          "${filtered.length} ejercicios${pendingExercises.isNotEmpty ? ' · ${pendingExercises.length} seleccionados' : ''}",
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),

        const SizedBox(height: 6),

        // ── Exercise list ────────────────────────────────────
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text("Sin resultados"),
          )
        else
          SizedBox(
            height: 240,
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final data = filtered[i].data() as Map<String, dynamic>;
                final name = data['name'] as String;
                final isSelected =
                    pendingExercises.contains(name) ||
                    (editingExerciseIndex != null && exerciseName == name);
                final typeLabel = (data['exerciseType'] ?? '').toString();

                return InkWell(
                  onTap: () async {
                    if (pendingExercises.contains(name) &&
                        editingExerciseIndex == null) {
                      setSheetState(() {
                        pendingExercises.remove(name);
                        selectedVariantsByExercise.remove(name);
                      });
                      return;
                    }
                    final movement = Exercise.fromFirestore(
                      data,
                      id: filtered[i].id,
                    );
                    final variant = await _chooseVariant(movement);
                    if (variant == null || !mounted) return;
                    setSheetState(() {
                      if (editingExerciseIndex != null) {
                        exerciseName = name;
                        selectedVariantsByExercise[name] = variant;
                      } else {
                        pendingExercises.add(name);
                        selectedVariantsByExercise[name] = variant;
                        if (pendingExercises.length == 1) {
                          availableEquipment = variant.equipment;
                          selectedEquipment =
                              variant.equipment.isEmpty
                                  ? null
                                  : variant.equipment.join(', ');
                        }
                      }
                    });
                  },
                  child: Container(
                    color: isSelected ? Colors.green.withOpacity(0.08) : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    child: Row(
                      children: [
                        // Checkbox-style indicator
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isSelected ? Colors.green : Colors.transparent,
                            border: Border.all(
                              color: isSelected ? Colors.green : Colors.grey,
                              width: 1.5,
                            ),
                          ),
                          child:
                              isSelected
                                  ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 13,
                                  )
                                  : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 14)),
                              if (typeLabel.isNotEmpty)
                                Text(
                                  selectedVariantsByExercise[name] == null
                                      ? typeLabel
                                      : '$typeLabel · ${selectedVariantsByExercise[name]!.label}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<ExerciseVariant?> _chooseVariant(Exercise exercise) async {
    if (exercise.variants.length == 1) return exercise.variants.first;
    return showDialog<ExerciseVariant>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('${exercise.name}: elegir variante'),
            content: SizedBox(
              width: 520,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group
                      in exercise.variants
                          .map(
                            (v) =>
                                v.techniqueLabel.isEmpty
                                    ? v.group
                                    : v.techniqueLabel,
                          )
                          .toSet()) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        group.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...exercise.variants
                        .where(
                          (v) =>
                              (v.techniqueLabel.isEmpty
                                  ? v.group
                                  : v.techniqueLabel) ==
                              group,
                        )
                        .map(
                          (variant) => ListTile(
                            title: Text(variant.label),
                            subtitle: Text(
                              '${variant.equipment.join(', ')} · ${variant.trainingDiscipline}',
                            ),
                            trailing:
                                variant.needsReview
                                    ? const Icon(
                                      Icons.warning_amber,
                                      color: Colors.amber,
                                    )
                                    : null,
                            onTap: () => Navigator.pop(dialogContext, variant),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  Widget _executionInput({required StateSetter setSheetState}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Ejecución",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 10),

        // ── Toggle Reps / Tiempo ────────────────────────────
        if (blockType != "Series descendentes" && blockType != "Buscar RM") ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: "reps",
                label: Text("Reps"),
                icon: Icon(Icons.repeat, size: 14),
              ),
              ButtonSegment(
                value: "time",
                label: Text("Tiempo"),
                icon: Icon(Icons.timer_outlined, size: 14),
              ),
            ],
            selected: {valueType},
            onSelectionChanged:
                (s) => setSheetState(() {
                  valueType = s.first;
                }),
          ),
          const SizedBox(height: 12),
        ],

        // ── Number fields in a row ──────────────────────────
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (blockType == "Series")
              SizedBox(
                width: 90,
                child: TextField(
                  controller: seriesCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: "Series",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

            if (blockType != "Series descendentes" && blockType != "Buscar RM")
              SizedBox(
                width: 100,
                child: TextField(
                  controller: repsCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: valueType == "reps" ? "Reps" : "Seg",
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),

            SizedBox(
              width: 110,
              child: TextField(
                controller: weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+([.,]\d{0,2})?$'),
                  ),
                ],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: "Peso (kg)",
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),

        // ── Per side checkbox ────────────────────────────────
        if (blockType == 'Series') ...[
          const SizedBox(height: 10),
          TextField(
            controller: setWeightsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Pesos por serie (opcional)',
              hintText: 'Ejemplo: 60 / 65 / 70 / 70',
              helperText: 'Separa cada carga con / o ;',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],

        if (blockType != "Series descendentes" && blockType != "Buscar RM") ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setSheetState(() => perSide = !perSide),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: perSide,
                    onChanged: (v) => setSheetState(() => perSide = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const Text("Por lado", style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 10),
        TextField(
          controller: exerciseNotesCtrl,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nota del ejercicio (opcional)',
            hintText: 'Ejemplo: de rodillas si cuesta mantener la zona lumbar',
            prefixIcon: Icon(Icons.sticky_note_2_outlined),
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _blockConfigCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔥 NOMBRE DEL BLOQUE
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: "Nombre del bloque",
              prefixIcon: Icon(Icons.title),
            ),
          ),

          const SizedBox(height: 12),

          // 📝 DESCRIPCIÓN DEL BLOQUE
          TextField(
            controller: descriptionCtrl,
            decoration: const InputDecoration(
              labelText: "Descripción / Indicaciones",
              prefixIcon: Icon(Icons.notes),
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _blockTypes.contains(blockType) ? blockType : "Series",
            decoration: const InputDecoration(
              labelText: "Sistema de entrenamiento",
              helperText:
                  "Puedes cambiarlo al editar y conservar los ejercicios",
              prefixIcon: Icon(Icons.account_tree_outlined),
              border: OutlineInputBorder(),
            ),
            items:
                _blockTypes
                    .map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      ),
                    )
                    .toList(),
            onChanged: (type) {
              if (type != null) _changeBlockType(type);
            },
          ),

          const SizedBox(height: 12),
          if (blockType == "Series descendentes") _schemaInput(),
          if (blockType == "Buscar RM")
            _num(rmCtrl, "RM a buscar (por defecto: 5)"),

          if (blockType == "Tabata") ...[
            _num(workCtrl, "Trabajo (seg)"),
            _num(restCtrl, "Descanso (seg)"),
            _num(roundsCtrl, "Rondas"),
          ],
          if (blockType == "Circuito") _num(roundsCtrl, "Rondas"),
          if (blockType == "EMOM") ...[
            _num(emomTimeCtrl, "Tiempo por ronda (seg)"),
            _num(roundsCtrl, "Rondas"),
          ],

          const Divider(height: 32),

          // 🔒 ASIGNACIÓN (PÚBLICO / PRIVADO)
          const Text(
            "Visibilidad y Asignación",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _athleteId = null),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          _athleteId == null
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            _athleteId == null
                                ? Colors.blue
                                : Colors.grey.shade800,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.public,
                          color: _athleteId == null ? Colors.blue : Colors.grey,
                        ),
                        const Text("General", style: TextStyle(fontSize: 12)),
                        const Text(
                          "(Ver todos)",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {
                    final targetId =
                        widget.initialBlock?['athleteId'] ??
                        widget.initialBlock?['contextAthleteId'];
                    if (targetId != null) {
                      setState(() => _athleteId = targetId);
                    } else {
                      _snack(
                        "No se puede asignar: Abre el editor desde la vista de un atleta",
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          _athleteId != null
                              ? Colors.orange.withOpacity(0.1)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            _athleteId != null
                                ? Colors.orange
                                : Colors.grey.shade800,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.person,
                          color:
                              _athleteId != null ? Colors.orange : Colors.grey,
                        ),
                        const Text("Privado", style: TextStyle(fontSize: 12)),
                        const Text(
                          "(Solo este atleta)",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _schemaInput() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: schemaCtrl,
        decoration: const InputDecoration(labelText: "Esquema (ej: 21-15-9)"),
        keyboardType: TextInputType.text,
      ),
    );
  }

  List<int> _parseSchema(String raw) {
    return raw
        .split('-')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e > 0)
        .toList();
  }

  Widget _num(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
    ),
  );
}
