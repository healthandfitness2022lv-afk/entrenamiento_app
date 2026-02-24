import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';


class AddWorkoutScreen extends StatefulWidget {
  final Map<String, dynamic>? initialBlock;

  const AddWorkoutScreen({
    super.key,
    this.initialBlock,
  });

  @override
  State<AddWorkoutScreen> createState() => _AddWorkoutScreenState();
}

class _AddWorkoutScreenState extends State<AddWorkoutScreen> {
  String? blockType;
  final List<Map<String, dynamic>> currentExercises = [];

  // ===== Bloque =====
  final workCtrl = TextEditingController();
  final restCtrl = TextEditingController();
  final roundsCtrl = TextEditingController();
  final emomTimeCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();

  // ===== Ejercicio =====
  String? exerciseName;
  List<String> availableEquipment = [];
  String? selectedEquipment;

  final seriesCtrl = TextEditingController();
  final repsCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  late TextEditingController titleController;


  String valueType = "reps"; // 👈 NUEVO
  bool perSide = false;
  int? editingExerciseIndex;

  String searchQuery = "";

  // =====================================================
  // INIT
  // =====================================================

  @override
void initState() {
  super.initState();

  final b = widget.initialBlock;
  if (b == null) return;

  blockType = b["type"];

  if (blockType == "Tabata") {
    valueType = "time"; // 🔥 fuerza tiempo
  }
  titleController = TextEditingController(
  text: widget.initialBlock?['title'] ?? '',
);
descriptionCtrl.text = widget.initialBlock?['description'] ?? '';


  final exercises =
    List<Map<String, dynamic>>.from(b["exercises"] ?? const []);

currentExercises.addAll(exercises);

  workCtrl.text = b["work"]?.toString() ?? "";
  restCtrl.text = b["rest"]?.toString() ?? "";
  roundsCtrl.text = b["rounds"]?.toString() ?? "";
  emomTimeCtrl.text = b["time"]?.toString() ?? "";
}

@override
void dispose() {
  workCtrl.dispose();
  restCtrl.dispose();
  roundsCtrl.dispose();
  emomTimeCtrl.dispose();

  seriesCtrl.dispose();
  repsCtrl.dispose();
  weightCtrl.dispose();

  titleController.dispose();
  descriptionCtrl.dispose();

  super.dispose();
}




  // =====================================================
  // GUARDAR BLOQUE
  // =====================================================

  void _saveBlock() {
  if (blockType == null || currentExercises.isEmpty) {
    _snack("Bloque incompleto");
    return;
  }

  final block = {
  "type": blockType,
  "title": titleController.text.trim(),
  "description": descriptionCtrl.text.trim(), // 👈 NUEVO
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

    exerciseName = e["name"];
    seriesCtrl.text = e["series"]?.toString() ?? "";
    repsCtrl.text = e["value"]?.toString() ?? "";
    valueType = e["valueType"] ?? "reps";
    perSide = e["perSide"] ?? false;

    selectedEquipment = e["equipment"];
    availableEquipment =
        selectedEquipment != null ? [selectedEquipment!] : [];
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



void _addExercise() {
    if (exerciseName == null) {
  _snack("Selecciona un ejercicio");
  return;
}

if (valueType == "time") {
  perSide = false; // tiempo nunca es por lado
}


if (blockType != "Tabata" && repsCtrl.text.isEmpty) {
  _snack("Ingresa reps o tiempo");
  return;
}

 final int parsedValue = int.tryParse(repsCtrl.text) ?? 0;
 final num parsedWeight = _parseWeight(weightCtrl.text);




final ex = {
  "name": exerciseName,
  "series": blockType == "Series"
      ? int.tryParse(seriesCtrl.text) ?? 1
      : null,

  // 🔁 COMPATIBILIDAD TOTAL
  if (blockType != "Tabata") ...{
    "value": parsedValue,
    "valueType": valueType,

    // 👇 CAMPO LEGACY
    if (valueType == "reps") "reps": parsedValue,
  },

  "perSide": perSide,
  "equipment": selectedEquipment,
  "weight": parsedWeight,

};



    setState(() {
      if (editingExerciseIndex != null) {
        currentExercises[editingExerciseIndex!] = ex;
        editingExerciseIndex = null;
      } else {
        currentExercises.add(ex);
      }
      _clearExerciseForm();
    });
  }

  void _clearExerciseForm() {
  exerciseName = null;
  selectedEquipment = null;
  availableEquipment.clear();
  searchQuery = "";
  seriesCtrl.clear();
  repsCtrl.clear();
  weightCtrl.text = "0"; // 👈 default SOLO nuevo

  valueType = "reps";
  perSide = false;
}


  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: _buildExerciseForm(),
        ),
      );
    },
  );
}

Widget _buildExerciseForm() {
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        editingExerciseIndex != null ? "Editar ejercicio" : "Agregar ejercicio",
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),

      _exerciseSearchAndSelector(),
      const SizedBox(height: 16),

      _executionInput(),
      const SizedBox(height: 16),

      ElevatedButton(
        onPressed: () {
          _addExercise();
          Navigator.pop(context);
        },
        child: Text(editingExerciseIndex != null ? "Guardar cambios" : "Agregar"),
      ),
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
        subtitle: Text(
          blockType == "Tabata"
              ? "Trabajo ${workCtrl.text}s"
              : "${e["series"] != null ? "${e["series"]}×" : ""}"
                "${e["value"]} "
                "${e["valueType"] == "time" ? "seg" : "reps"}",
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
              onPressed: () => setState(() {
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

  Widget _exerciseSearchAndSelector() {
    return Column(
      children: [
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("exercises")
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const CircularProgressIndicator();
            }

            final docs = snap.data!.docs
              ..sort((a, b) =>
                  (a["name"] as String).compareTo(b["name"] as String));

            final filtered = docs.where((d) {
              final name =
                  (d["name"] as String).toLowerCase();
              return name.contains(searchQuery);
            }).toList();

            final Map<String, List<QueryDocumentSnapshot>> grouped = {};
            for (final d in filtered) {
              final data = d.data() as Map<String, dynamic>;
              final type = data["exerciseType"] ?? "Otros";
              grouped.putIfAbsent(type, () => []).add(d);
            }

            final types = grouped.keys.toList();

            return DefaultTabController(
              length: types.length,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabs: types.map((t) => Tab(text: t)).toList(),
                  ),
                  SizedBox(
                    height: 200,
                    child: TabBarView(
                      children: types.map((type) {
                        return ListView(
                          children: grouped[type]!.map((d) {
                            final data =
                                d.data() as Map<String, dynamic>;
                            return InkWell(
  borderRadius: BorderRadius.circular(8),
  onTap: () {
    setState(() {
      exerciseName = data["name"];

      valueType = "reps";
      perSide = data["perSide"] == true; // ✅ FIX REAL
      weightCtrl.text = "1";
      repsCtrl.clear();

      availableEquipment =
          List<String>.from(data["equipment"] ?? []);
      selectedEquipment =
          availableEquipment.isNotEmpty
              ? availableEquipment.first
              : null;
    });
  },
  child: Padding(
    padding: const EdgeInsets.symmetric(
      vertical: 6,
      horizontal: 8,
    ),
    child: Row(
      children: [
        const Icon(Icons.arrow_right, size: 18),
        const SizedBox(width: 6),
        Expanded(child: Text(data["name"])),
      ],
    ),
  ),
);

                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _executionInput() {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Ejecución",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              // SERIES (solo si aplica)
              if (blockType == "Series") ...[
                Expanded(
                  child: TextField(
                    controller: seriesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Series",
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // REPS / TIEMPO
              Expanded(
                child: TextField(
                  controller: repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: valueType == "reps"
                        ? "Reps"
                        : "Tiempo (seg)",
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // PESO
              Expanded(
                child: TextField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+([.,]\d{0,2})?$'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: "Peso (kg)",
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Toggle debajo (compacto)
          ToggleButtons(
            isSelected: [
              valueType == "reps",
              valueType == "time",
            ],
            onPressed: (i) {
              setState(() {
                valueType = i == 0 ? "reps" : "time";
                if (valueType == "time") perSide = false;
              });
            },
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text("Reps"),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text("Tiempo"),
              ),
            ],
          ),

          if (valueType == "reps") ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Checkbox(
                  value: perSide,
                  onChanged: (v) =>
                      setState(() => perSide = v ?? false),
                ),
                const Text("Por lado"),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}


  Widget _blockConfigCard() => Card(
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // 🔥 NOMBRE DEL BLOQUE
        // 🔥 NOMBRE DEL BLOQUE
TextField(
  controller: titleController,
  decoration: const InputDecoration(
    labelText: "Nombre del bloque",
  ),
),

const SizedBox(height: 12),

// 📝 DESCRIPCIÓN DEL BLOQUE
TextField(
  controller: descriptionCtrl,
  decoration: const InputDecoration(
    labelText: "Descripción / Indicaciones",
  ),
  maxLines: 3,
),

const SizedBox(height: 12),

        const SizedBox(height: 12),

        if (blockType == "Tabata") ...[
          _num(workCtrl, "Trabajo (seg)"),
          _num(restCtrl, "Descanso (seg)"),
          _num(roundsCtrl, "Rondas"),
        ],
        if (blockType == "Circuito")
          _num(roundsCtrl, "Rondas"),
        if (blockType == "EMOM") ...[
          _num(emomTimeCtrl, "Tiempo por ronda (seg)"),
          _num(roundsCtrl, "Rondas"),
        ],
      ],
    ),
  ),
);


  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
        ),
      );
}
