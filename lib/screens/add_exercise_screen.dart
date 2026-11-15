import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exercise.dart';
import '../models/muscle_catalog.dart';
import '../utils/exercise_catalogs.dart';
import '../utils/exercise_name_utils.dart';
import '../utils/exercise_variant_catalog.dart';
import '../screens/muscle_weight_editor_screen.dart';

class AddExerciseScreen extends StatefulWidget {
  final Exercise? exerciseToEdit;
  final String? exerciseId;
  final String? initialType; // ⭐ Nuevo: para pre-seleccionar tipo

  const AddExerciseScreen({
    super.key,
    this.exerciseToEdit,
    this.exerciseId,
    this.initialType,
  });

  @override
  State<AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<AddExerciseScreen> {
  static const _variantExerciseTypes = [
    'Halterofilia',
    'Potencia',
    'Balístico',
    'Fuerza',
    'Hipertrofia',
    'Correctivos',
    'Acondicionamiento',
    'Peso corporal',
  ];
  static const _variantTrainingDisciplines = [
    'halterofilia',
    'balistico',
    'pliometria',
    'correctivos',
    'metabolico',
    'fuerza',
    'hipertrofia',
  ];
  final nameController = TextEditingController();
  final instructionsController = TextEditingController();
  final videoUrlController = TextEditingController();
  final customEquipmentController = TextEditingController();

  List<String> selectedEquipment = [];
  String? selectedExerciseType;
  Muscle? selectedMuscle;
  Map<Muscle, double> muscleWeights = {};
  List<ExerciseVariant> variants = [];

  bool get isEditMode => widget.exerciseToEdit != null;

  @override
  void initState() {
    super.initState();

    if (isEditMode) {
      final e = widget.exerciseToEdit!;
      nameController.text = e.name;
      instructionsController.text = e.instructions;
      videoUrlController.text = e.videoUrl ?? "";
      selectedEquipment = List.from(e.equipment);
      selectedExerciseType = e.exerciseType;
      muscleWeights = Map.from(e.muscleWeights);
      variants = List.from(e.variants);
    } else {
      selectedExerciseType = widget.initialType;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    instructionsController.dispose();
    videoUrlController.dispose();
    customEquipmentController.dispose();
    super.dispose();
  }

  // ======================================================
  // 💾 SAVE
  // ======================================================
  Future<void> _saveExercise() async {
    if (nameController.text.trim().isEmpty ||
        instructionsController.text.trim().isEmpty ||
        selectedExerciseType == null) {
      _snack("Completa los campos obligatorios");
      return;
    }

    final newName = nameController.text.trim();

    if (_hasInvalidCharacters(newName)) {
      _snack(
        "El nombre del ejercicio no puede contener '-' ni '/'.\n"
        "Motivo: estos caracteres generan errores internos al registrar entrenamientos.",
      );
      return;
    }

    final totalWeight = muscleWeights.values.fold(0.0, (a, b) => a + b);

    if ((totalWeight - 1.0).abs() > 0.01) {
      _snack("La ponderación muscular debe sumar 100%");
      return;
    }

    final Map<String, dynamic> data = {
      'name': newName,
      'instructions': instructionsController.text.trim(),
      'equipment': selectedEquipment,
      'exerciseType': selectedExerciseType,
      'videoUrl': videoUrlController.text.trim(),
      'muscleWeights': {
        for (final e in muscleWeights.entries) e.key.name: e.value,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final collection = FirebaseFirestore.instance.collection('exercises');

    final existing = await collection.get();
    final duplicate = existing.docs.any(
      (doc) =>
          doc.id != widget.exerciseId &&
          canonicalExerciseKey(doc.data()['name']) ==
              canonicalExerciseKey(newName),
    );
    if (duplicate) {
      _snack('Ya existe un movimiento con ese nombre');
      return;
    }

    if (variants.isEmpty) {
      variants = [
        ExerciseVariant(
          id: 'original',
          label: 'Original',
          group: 'Peso libre',
          equipment: List.from(selectedEquipment),
          resistanceType: 'free',
          trackRM: false,
          isUnilateral: false,
          needsReview: true,
        ),
      ];
    }

    data['variants'] = variants.map((variant) => variant.toMap()).toList();
    data['trackRM'] = variants.any((variant) => variant.trackRM);
    data['trackProgression'] = variants.any(
      (variant) => variant.trackProgression,
    );

    if (isEditMode && widget.exerciseId != null) {
      await collection.doc(widget.exerciseId).update(data);
    } else {
      await collection.add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) return;
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
          IconButton(icon: const Icon(Icons.save), onPressed: _saveExercise),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: "Nombre *"),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('exercise_folders')
                    .orderBy('name')
                    .snapshots(),
            builder: (context, snapshot) {
              final folders =
                  snapshot.data?.docs
                      .map((f) => f['name'] as String)
                      .toList() ??
                  [];

              // Incluir tipo actual si no está en carpetas (legacy)
              if (selectedExerciseType != null &&
                  !folders.contains(selectedExerciseType)) {
                folders.add(selectedExerciseType!);
              }

              return DropdownButtonFormField<String>(
                value: selectedExerciseType,
                decoration: const InputDecoration(
                  labelText: "Tipo de ejercicio *",
                ),
                items:
                    folders
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                onChanged: (v) => setState(() => selectedExerciseType = v),
              );
            },
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
                  builder:
                      (_) => MuscleWeightEditorScreen(
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

          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Variantes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _loadSuggestedVariants,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Sugeridas'),
              ),
              IconButton(
                tooltip: 'Agregar variante',
                onPressed: _addVariantDialog,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (variants.isEmpty)
            const Text(
              'Agrega al menos una variante. Si no lo haces se creará "Original".',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...variants.asMap().entries.map(
              (entry) => Card(
                child: ListTile(
                  title: Text(entry.value.label),
                  subtitle: Text(
                    '${entry.value.techniqueLabel.isNotEmpty ? '${entry.value.techniqueLabel} · ' : ''}'
                    '${entry.value.exerciseType.isNotEmpty ? '${entry.value.exerciseType} · ' : ''}'
                    '${entry.value.group} · ${entry.value.equipment.join(', ')}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed:
                        () => setState(() => variants.removeAt(entry.key)),
                  ),
                  onTap:
                      () => _addVariantDialog(
                        index: entry.key,
                        initial: entry.value,
                      ),
                ),
              ),
            ),

          const SizedBox(height: 12),

          TextField(
            controller: videoUrlController,
            decoration: const InputDecoration(
              labelText: "URL video (opcional)",
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: instructionsController,
            decoration: const InputDecoration(labelText: "Instrucciones *"),
            maxLines: 4,
          ),

          const SizedBox(height: 20),
          _buildPreview(),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final name = nameController.text.trim();
    final sortedWeights =
        muscleWeights.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.visibility_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'Vista previa',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              name.isEmpty ? 'Movimiento sin nombre' : name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              '${selectedExerciseType ?? 'Sin clasificación'} · '
              '${variants.length} ${variants.length == 1 ? 'variante' : 'variantes'}',
              style: const TextStyle(color: Colors.grey),
            ),
            if (variants.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    variants
                        .map(
                          (variant) => Chip(
                            label: Text(
                              name.isEmpty
                                  ? variant.label
                                  : variant.displayName(name),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ],
            if (sortedWeights.isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                sortedWeights
                    .map(
                      (entry) =>
                          '${entry.key.label} ${(entry.value * 100).round()}%',
                    )
                    .join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
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
                    children:
                        options.map((opt) {
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: customEquipmentController,
                          decoration: const InputDecoration(
                            labelText: 'Otro implemento o máquina',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Agregar',
                        onPressed: () {
                          final value = customEquipmentController.text.trim();
                          if (value.isEmpty) return;
                          setModalState(() {
                            if (!selectedValues.any(
                              (e) =>
                                  normalizeExerciseKey(e) ==
                                  normalizeExerciseKey(value),
                            )) {
                              selectedValues.add(value);
                            }
                            customEquipmentController.clear();
                          });
                          setState(() {});
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _loadSuggestedVariants() {
    final key = normalizeExerciseKey(nameController.text);
    List<ExerciseVariant>? suggested = commonMovementVariants[key];
    suggested ??=
        commonMovementVariants.entries
            .where(
              (entry) => key.contains(entry.key) || entry.key.contains(key),
            )
            .map((entry) => entry.value)
            .firstOrNull;
    if (suggested == null) {
      _snack('No hay variantes sugeridas para este movimiento');
      return;
    }
    setState(() {
      final byId = {for (final variant in variants) variant.id: variant};
      for (final variant in suggested!) {
        byId.putIfAbsent(variant.id, () => variant);
      }
      variants = byId.values.toList();
      selectedEquipment = variants.expand((v) => v.equipment).toSet().toList();
    });
  }

  Future<void> _addVariantDialog({int? index, ExerciseVariant? initial}) async {
    final labelController = TextEditingController(text: initial?.label ?? '');
    final equipmentController = TextEditingController(
      text: initial?.equipment.join(', ') ?? '',
    );
    final familyController = TextEditingController(
      text: initial?.familyId ?? '',
    );
    final techniqueController = TextEditingController(
      text: initial?.techniqueLabel ?? '',
    );
    var group = initial?.group ?? 'Peso libre';
    var trackRM = initial?.trackRM ?? true;
    var trackProgression = initial?.trackProgression ?? false;
    var unilateral = initial?.isUnilateral ?? false;
    var trainingDiscipline = initial?.trainingDiscipline ?? 'fuerza';
    var movementIntent = initial?.movementIntent ?? 'full';
    var variantExerciseType =
        initial?.exerciseType.isNotEmpty == true
            ? initial!.exerciseType
            : (selectedExerciseType ?? 'Fuerza');
    var techniqueId = initial?.techniqueId ?? '';
    var variantMuscleWeights = Map<Muscle, double>.from(
      initial?.muscleWeightOverrides ?? const {},
    );

    final result = await showDialog<ExerciseVariant>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text(
                    index == null ? 'Nueva variante' : 'Editar variante',
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: labelController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de la variante',
                          ),
                        ),
                        StreamBuilder<QuerySnapshot>(
                          stream:
                              FirebaseFirestore.instance
                                  .collection('exercise_folders')
                                  .orderBy('name')
                                  .snapshots(),
                          builder: (context, snapshot) {
                            final folders =
                                snapshot.data?.docs
                                    .map((f) => f['name'] as String)
                                    .toList() ??
                                _variantExerciseTypes;

                            // Incluir el tipo actual si no está en la lista
                            // (legacy) para no perderlo del dropdown.
                            if (!folders.contains(variantExerciseType)) {
                              folders.add(variantExerciseType);
                            }

                            return DropdownButtonFormField<String>(
                              value: variantExerciseType,
                              items:
                                  folders
                                      .map(
                                        (type) => DropdownMenuItem(
                                          value: type,
                                          child: Text(type),
                                        ),
                                      )
                                      .toList(),
                              onChanged:
                                  (value) => setDialogState(
                                    () =>
                                        variantExerciseType =
                                            value ?? variantExerciseType,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Tipo de entrenamiento',
                                helperText:
                                    'Depende de la técnica y el implemento.',
                              ),
                            );
                          },
                        ),
                        TextField(
                          controller: familyController,
                          decoration: const InputDecoration(
                            labelText: 'Patrón técnico',
                            hintText: 'Ej.: snatch, clean, jerk',
                          ),
                        ),
                        TextField(
                          controller: techniqueController,
                          decoration: const InputDecoration(
                            labelText: 'Técnica',
                            hintText: 'Ej.: Hang Power',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          value:
                              _variantTrainingDisciplines.contains(
                                    trainingDiscipline,
                                  )
                                  ? trainingDiscipline
                                  : 'fuerza',
                          items: const [
                            DropdownMenuItem(
                              value: 'halterofilia',
                              child: Text('Halterofilia'),
                            ),
                            DropdownMenuItem(
                              value: 'balistico',
                              child: Text('Balístico'),
                            ),
                            DropdownMenuItem(
                              value: 'pliometria',
                              child: Text('Pliometría'),
                            ),
                            DropdownMenuItem(
                              value: 'correctivos',
                              child: Text('Correctivos'),
                            ),
                            /* Legacy duplicate entry retained for old data.
                            DropdownMenuItem(
                              value: 'balistico_legacy',
                              child: Text('Balístico'),
                            ),
                            End legacy entry. */
                            DropdownMenuItem(
                              value: 'metabolico',
                              child: Text('Metabólico'),
                            ),
                            DropdownMenuItem(
                              value: 'fuerza',
                              child: Text('Fuerza'),
                            ),
                            DropdownMenuItem(
                              value: 'hipertrofia',
                              child: Text('Hipertrofia'),
                            ),
                          ],
                          onChanged:
                              (value) => setDialogState(
                                () =>
                                    trainingDiscipline =
                                        value ?? trainingDiscipline,
                              ),
                          decoration: const InputDecoration(
                            labelText: 'Disciplina',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          value: movementIntent,
                          items: const [
                            DropdownMenuItem(
                              value: 'full',
                              child: Text('Completo'),
                            ),
                            DropdownMenuItem(
                              value: 'power',
                              child: Text('Potencia'),
                            ),
                            DropdownMenuItem(
                              value: 'conditioning',
                              child: Text('Acondicionamiento'),
                            ),
                          ],
                          onChanged:
                              (value) => setDialogState(
                                () => movementIntent = value ?? movementIntent,
                              ),
                          decoration: const InputDecoration(
                            labelText: 'Intención',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: group,
                          items:
                              variantGroups
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (value) =>
                                  setDialogState(() => group = value ?? group),
                          decoration: const InputDecoration(labelText: 'Grupo'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: equipmentController,
                          decoration: const InputDecoration(
                            labelText: 'Implementos (separados por coma)',
                          ),
                        ),
                        SwitchListTile(
                          value: trackRM,
                          onChanged:
                              (value) => setDialogState(() => trackRM = value),
                          title: const Text('Registrar RM y récords'),
                        ),
                        SwitchListTile(
                          value: trackProgression,
                          onChanged:
                              (value) => setDialogState(
                                () => trackProgression = value,
                              ),
                          title: const Text(
                            'Incluir en progresión de sobrecarga',
                          ),
                          subtitle: const Text(
                            'Aparece en el mesociclo con PM, 1RM estimada e IMR.',
                          ),
                        ),
                        SwitchListTile(
                          value: unilateral,
                          onChanged:
                              (value) =>
                                  setDialogState(() => unilateral = value),
                          title: const Text('Variante unilateral'),
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.accessibility_new_outlined),
                          title: const Text(
                            'Ponderación muscular de esta variante',
                          ),
                          subtitle: Text(
                            variantMuscleWeights.isEmpty
                                ? 'Usa la ponderación base del ejercicio'
                                : '${variantMuscleWeights.length} músculos · reemplaza la ponderación base',
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () async {
                            final weights =
                                await Navigator.push<Map<Muscle, double>>(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => MuscleWeightEditorScreen(
                                          initialWeights: variantMuscleWeights,
                                        ),
                                  ),
                                );
                            if (weights != null) {
                              setDialogState(
                                () => variantMuscleWeights = weights,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final label = labelController.text.trim();
                        if (label.isEmpty) {
                          _snack('Ingresa un nombre para la variante');
                          return;
                        }
                        final id = normalizeExerciseKey(
                          label,
                        ).replaceAll(' ', '_');
                        if (variants.asMap().entries.any(
                          (entry) => entry.key != index && entry.value.id == id,
                        )) {
                          _snack('Esa variante ya existe');
                          return;
                        }
                        Navigator.pop(
                          dialogContext,
                          ExerciseVariant(
                            id: id,
                            label: label,
                            group: group,
                            equipment:
                                equipmentController.text
                                    .split(',')
                                    .map((e) => e.trim())
                                    .where((e) => e.isNotEmpty)
                                    .toList(),
                            resistanceType: switch (group) {
                              'Máquina' || 'Polea' => 'guided',
                              'Peso corporal' => 'bodyweight',
                              _ => 'free',
                            },
                            trackRM: trackRM,
                            trackProgression: trackProgression,
                            trainingDiscipline: trainingDiscipline,
                            movementIntent: movementIntent,
                            exerciseType: variantExerciseType,
                            familyId: familyController.text.trim(),
                            techniqueId:
                                techniqueId.isNotEmpty
                                    ? techniqueId
                                    : normalizeExerciseKey(
                                      techniqueController.text.trim().isEmpty
                                          ? label
                                          : techniqueController.text.trim(),
                                    ).replaceAll(' ', '_'),
                            techniqueLabel: techniqueController.text.trim(),
                            isUnilateral: unilateral,
                            muscleWeightOverrides: variantMuscleWeights,
                          ),
                        );
                      },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );
    labelController.dispose();
    equipmentController.dispose();
    familyController.dispose();
    techniqueController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        variants.add(result);
      } else {
        variants[index] = result;
      }
      selectedEquipment = variants.expand((v) => v.equipment).toSet().toList();
    });
  }
}
