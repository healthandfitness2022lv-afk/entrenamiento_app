import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_workout_screen.dart';

class AddRoutineScreen extends StatefulWidget {
  final String? routineId;
  final Map<String, dynamic>? initialData;

  const AddRoutineScreen({
    super.key,
    this.routineId,
    this.initialData,
  });

  @override
  State<AddRoutineScreen> createState() => _AddRoutineScreenState();
}

class _AddRoutineScreenState extends State<AddRoutineScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  final List<Map<String, dynamic>> routineBlocks = [];

  bool get isEdit => widget.routineId != null;

  // ignore: unused_field
  int? _editingIndex;

  // =========================
  // INIT
  // =========================
  @override
  void initState() {
    super.initState();

    if (widget.initialData != null) {
      nameController.text = widget.initialData!['name'] ?? '';
      descriptionController.text =
          widget.initialData!['description'] ?? '';

      final blocks =
          List<Map<String, dynamic>>.from(widget.initialData!['blocks'] ?? []);

      routineBlocks.addAll(
        blocks.map((b) => Map<String, dynamic>.from(b)),
      );
    }
  }

  // =========================
  // SAVE
  // =========================
  Future<void> _saveRoutine() async {
    if (nameController.text.trim().isEmpty || routineBlocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Completa nombre y agrega al menos un bloque"),
        ),
      );
      return;
    }

    final data = {
      'name': nameController.text.trim(),
      'description': descriptionController.text.trim(),
      'blocks': routineBlocks,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final col = FirebaseFirestore.instance.collection('routines');

    if (isEdit) {
      await col.doc(widget.routineId).update(data);
    } else {
      await col.add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (mounted) Navigator.pop(context);
  }

  // =========================
  // BLOCK SUMMARY
  // =========================
  String _blockSummary(Map<String, dynamic> b) {
    switch (b["type"]) {
      case "Tabata":
        return "Tabata ${b["work"]}/${b["rest"]} x ${b["rounds"]}";
      case "Circuito":
        return "Circuito ${b["rounds"]} rondas";
      case "EMOM":
        return "EMOM ${b["time"]}s x ${b["rounds"]}";
      case "Series":
  return "Series (${(b["exercises"] as List).length} ejercicios)";

      default:
        return b["type"] ?? "Bloque";
    }
  }

  // =========================
  // UI HELPERS
  // =========================
  Future<void> _openBlockEditor(int index) async {
  final updatedBlock = await Navigator.push<Map<String, dynamic>>(
    context,
    MaterialPageRoute(
      builder: (_) => AddWorkoutScreen(
        initialBlock: Map<String, dynamic>.from(routineBlocks[index]),
      ),
    ),
  );

  if (updatedBlock == null) return;

  setState(() {
    routineBlocks[index] = Map<String, dynamic>.from(updatedBlock);
  });
}


  void _removeBlock(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar bloque"),
        content:
            const Text("¿Seguro que deseas eliminar este bloque?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () {
              setState(() => routineBlocks.removeAt(index));
              Navigator.pop(context);
            },
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  }

  void _askBlockType() {
  showModalBottomSheet(
    context: context,
    builder: (_) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Selecciona tipo de bloque",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _blockTypeTile("Tabata"),
            _blockTypeTile("Circuito"),
            _blockTypeTile("EMOM"),
            _blockTypeTile("Series"),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

Widget _blockTypeTile(String type) {
  return ListTile(
    title: Text(type),
    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
    onTap: () {
      Navigator.pop(context);
      _openBlockEditorWithType(type);
    },
  );
}

void _openBlockEditorWithType(String type) async {
  final newBlock = await Navigator.push<Map<String, dynamic>>(
    context,
    MaterialPageRoute(
      builder: (_) => AddWorkoutScreen(
        initialBlock: {
          "type": type,
          "exercises": [],
        },
      ),
    ),
  );

  if (newBlock == null) return;

  setState(() {
    routineBlocks.add(Map<String, dynamic>.from(newBlock));
  });
}

  void _reorderBlocks(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = routineBlocks.removeAt(oldIndex);
      routineBlocks.insert(newIndex, item);
    });
  }

 Widget _blockTile(int index) {
  final block = routineBlocks[index];
  final exercises =
      List<Map<String, dynamic>>.from(block['exercises'] ?? []);

  return Card(
    key: ValueKey(block.hashCode),
    child: ExpansionTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(_blockSummary(block)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (exercises.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Sin ejercicios",
              style: TextStyle(color: Colors.grey),
            ),
          ),

        ...exercises.map((e) => _exerciseRow(e)).toList(),

        const Divider(),

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _openBlockEditor(index),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _removeBlock(index),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _exerciseRow(Map<String, dynamic> e) {
  final perSide = e['perSide'] == true;
  final weight = e['weight'];

  String valueText = "";

  if (e['valueType'] == 'time') {
    valueText = "${e['value']} s";
  } else {
    valueText =
        "${e['value']} reps${perSide ? " por lado" : ""}";
  }

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        const Icon(Icons.fitness_center, size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text(e['name'])),
        Text(
          [
            valueText,
            if (weight != null) "${weight}kg",
          ].join(" · "),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    ),
  );
}


  // =========================
  // DISPOSE
  // =========================
  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  // =========================
  // BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Editar rutina" : "Nueva rutina"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveRoutine,
          ),
        ],
      ),
      body: Column(
        children: [
          // =========================
          // HEADER
          // =========================
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Nombre de la rutina",
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: "Descripción",
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Bloques: ${routineBlocks.length}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // =========================
          // BLOCK LIST
          // =========================
          Expanded(
            child: routineBlocks.isEmpty
                ? const Center(
                    child: Text(
                      "Aún no has agregado bloques",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: routineBlocks.length,
                    onReorder: _reorderBlocks,
                    itemBuilder: (_, i) => _blockTile(i),
                  ),
          ),

          // =========================
          // ADD BLOCK BUTTON
          // =========================
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
  icon: const Icon(Icons.add),
  label: const Text("Agregar bloque"),
  onPressed: _askBlockType,
),

          ),
        ],
      ),
    );
  }
}
