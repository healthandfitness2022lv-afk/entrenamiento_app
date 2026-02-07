import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exercise.dart';
import '../models/muscle_catalog.dart';
import '../utils/exercise_catalogs.dart';
import '../screens/muscle_weight_editor_screen.dart';



class AddExerciseScreen extends StatefulWidget {
  final Exercise? exerciseToEdit;
  final String? exerciseId;

  const AddExerciseScreen({
    super.key,
    this.exerciseToEdit,
    this.exerciseId,
  });

  @override
  State<AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<AddExerciseScreen> {
  final nameController = TextEditingController();
  final instructionsController = TextEditingController();
  final videoUrlController = TextEditingController();

  List<String> selectedEquipment = [];
  String? selectedExerciseType;
  Muscle? selectedMuscle;
  String? _originalName;



  Map<Muscle, double> muscleWeights = {};

  bool get isEditMode => widget.exerciseToEdit != null;

  // ======================================================
  // 🚀 INIT
  // ======================================================
  @override
void initState() {
  super.initState();

  if (isEditMode) {
    final e = widget.exerciseToEdit!;

    _originalName = e.name; // 🔑 CLAVE

    nameController.text = e.name;
    instructionsController.text = e.instructions;
    videoUrlController.text = e.videoUrl ?? "";

    selectedEquipment = List.from(e.equipment);

    if (exerciseTypeCatalog.contains(e.exerciseType)) {
      selectedExerciseType = e.exerciseType;
    }

    muscleWeights = Map.from(e.muscleWeights);
  }
}


  Future<void> _propagateExerciseRename({
  required String oldName,
  required String newName,
}) async {
  final firestore = FirebaseFirestore.instance;

  // ======================================================
  // 🏋️ WORKOUTS_LOGGED
  // ======================================================
  final workoutsSnap =
      await firestore.collection('workouts_logged').get();

  for (final doc in workoutsSnap.docs) {
    final data = doc.data();
    final List performed =
        List<Map<String, dynamic>>.from(data['performed'] ?? []);

    bool changed = false;

    for (int i = 0; i < performed.length; i++) {
      final p = Map<String, dynamic>.from(performed[i]);

      // =====================
      // SERIES
      // =====================
      if (p['type'] == 'Series' && p['exercise'] == oldName) {
        p['exercise'] = newName;
        changed = true;
      }

      // =====================
      // CIRCUITO
      // rounds[].exercises[].exercise
      // =====================
      if (p['type'] == 'Circuito') {
        final List rounds =
            List<Map<String, dynamic>>.from(p['rounds'] ?? []);

        for (int r = 0; r < rounds.length; r++) {
          final round =
              Map<String, dynamic>.from(rounds[r]);

          final List exercises =
              List<Map<String, dynamic>>.from(
                  round['exercises'] ?? []);

          for (int e = 0; e < exercises.length; e++) {
            final ex =
                Map<String, dynamic>.from(exercises[e]);

            if (ex['exercise'] == oldName) {
              ex['exercise'] = newName;
              exercises[e] = ex;
              changed = true;
            }
          }

          round['exercises'] = exercises;
          rounds[r] = round;
        }

        p['rounds'] = rounds;
      }

      // =====================
      // TABATA
      // exercises[].exercise
      // =====================
      if (p['type'] == 'Tabata') {
        final List exercises =
            List<Map<String, dynamic>>.from(
                p['exercises'] ?? []);

        for (int e = 0; e < exercises.length; e++) {
          final ex =
              Map<String, dynamic>.from(exercises[e]);

          if (ex['exercise'] == oldName) {
            ex['exercise'] = newName;
            exercises[e] = ex;
            changed = true;
          }
        }

        p['exercises'] = exercises;
      }

      performed[i] = p;
    }

    if (changed) {
      await doc.reference.update({
        'performed': performed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ======================================================
  // 📋 ROUTINES
  // blocks[].exercises[].name
  // ======================================================
  final routinesSnap =
      await firestore.collection('routines').get();

  for (final doc in routinesSnap.docs) {
    final data = doc.data();
    final List blocks =
        List<Map<String, dynamic>>.from(data['blocks'] ?? []);

    bool changed = false;

    for (int b = 0; b < blocks.length; b++) {
      final block =
          Map<String, dynamic>.from(blocks[b]);

      final List exercises =
          List<Map<String, dynamic>>.from(
              block['exercises'] ?? []);

      for (int e = 0; e < exercises.length; e++) {
        final ex =
            Map<String, dynamic>.from(exercises[e]);

        if (ex['name'] == oldName) {
          ex['name'] = newName;
          exercises[e] = ex;
          changed = true;
        }
      }

      block['exercises'] = exercises;
      blocks[b] = block;
    }

    if (changed) {
      await doc.reference.update({
        'blocks': blocks,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  debugPrint(
    "✅ TODAS las ocurrencias de '$oldName' fueron renombradas a '$newName'",
  );
}

  // ======================================================
  // 💾 SAVE
  // ======================================================
  Future<void> _saveExercise() async {
  // ===============================
  // 🔴 VALIDACIONES BÁSICAS
  // ===============================
  if (nameController.text.trim().isEmpty ||
      instructionsController.text.trim().isEmpty ||
      selectedExerciseType == null) {
    _snack("Completa los campos obligatorios");
    return;
  }

  final newName = nameController.text.trim();

  // ===============================
  // 🚫 VALIDACIÓN DE NOMBRE
  // ===============================
  if (_hasInvalidCharacters(newName)) {
    _snack(
      "El nombre del ejercicio no puede contener '-' ni '/'.\n"
      "Motivo: estos caracteres generan errores internos al registrar entrenamientos.",
    );
    return;
  }

  // ===============================
  // 🔥 VALIDACIÓN PONDERACIÓN MUSCULAR
  // ===============================
  final totalWeight =
      muscleWeights.values.fold(0.0, (a, b) => a + b);

  if ((totalWeight - 1.0).abs() > 0.01) {
    _snack("La ponderación muscular debe sumar 100%");
    return;
  }

  final oldName = _originalName;

  // ===============================
  // 📦 DATA A GUARDAR
  // ===============================
  final Map<String, dynamic> data = {
    'name': newName,
    'instructions': instructionsController.text.trim(),
    'equipment': selectedEquipment,
    'exerciseType': selectedExerciseType,
    'videoUrl': videoUrlController.text.trim(),
    'muscleWeights': {
      for (final e in muscleWeights.entries)
        e.key.name: e.value,
    },
    'updatedAt': FieldValue.serverTimestamp(),
  };

  final collection =
      FirebaseFirestore.instance.collection('exercises');

  // ===============================
  // ✏️ EDITAR
  // ===============================
  if (isEditMode && widget.exerciseId != null) {
    await collection.doc(widget.exerciseId).update(data);

    // 🔁 PROPAGAR CAMBIO DE NOMBRE
    if (oldName != null && oldName != newName) {
      await _propagateExerciseRename(
        oldName: oldName,
        newName: newName,
      );
    }
  }
  // ===============================
  // 🆕 CREAR
  // ===============================
  else {
    await collection.add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ===============================
  // ✅ FIN
  // ===============================
  Navigator.pop(context, true);
}


bool _hasInvalidCharacters(String name) {
  return name.contains('-') || name.contains('/');
}


  // ======================================================
  // 🖥 UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? "Editar ejercicio" : "Nuevo ejercicio"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveExercise,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: "Nombre *"),
          ),

          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: selectedExerciseType,
            decoration:
                const InputDecoration(labelText: "Tipo de ejercicio *"),
            items: exerciseTypeCatalog
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => selectedExerciseType = v),
          ), 


          /// 🔥 PONDERACIÓN MUSCULAR
const Text(
  "Ponderación muscular",
  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
),
const SizedBox(height: 8),

ElevatedButton.icon(
  icon: const Icon(Icons.fitness_center),
  label: const Text("Editar músculos"),
  onPressed: () async {
    final result = await Navigator.push<Map<Muscle, double>>(
      context,
      MaterialPageRoute(
        builder: (_) => MuscleWeightEditorScreen(
          initialWeights: muscleWeights,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        muscleWeights = result;
      });
    }
  },
),

if (muscleWeights.isNotEmpty) ...[
  const SizedBox(height: 6),
  Text(
    "${muscleWeights.length} músculos seleccionados",
    style: TextStyle(color: Colors.grey),
  ),
],


          const SizedBox(height: 16),

          const Text("Equipamiento"),
          ElevatedButton.icon(
            icon: const Icon(Icons.handyman),
            label: Text(
              selectedEquipment.isEmpty
                  ? "Seleccionar equipamiento"
                  : "Equipamiento (${selectedEquipment.length})",
            ),
            onPressed: () {
              _openMultiSelectModal(
                title: "Equipamiento",
                options: equipmentCatalog,
                selectedValues: selectedEquipment,
              );
            },
          ),

          const SizedBox(height: 12),

          TextField(
            controller: videoUrlController,
            decoration:
                const InputDecoration(labelText: "URL video (opcional)"),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: instructionsController,
            decoration:
                const InputDecoration(labelText: "Instrucciones *"),
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  // ======================================================
  // 🧩 MODAL MULTISELECT
  // ======================================================
  void _openMultiSelectModal({
    required String title,
    required List<String> options,
    required List<String> selectedValues,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((opt) {
                      final selected = selectedValues.contains(opt);
                      return FilterChip(
                        label: Text(opt),
                        selected: selected,
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selectedValues.add(opt);
                            } else {
                              selectedValues.remove(opt);
                            }
                          });
                          setState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Listo"),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
