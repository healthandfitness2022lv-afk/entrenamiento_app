import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // ===== Ejercicio =====
  String? exerciseName;
  List<String> availableEquipment = [];
  String? selectedEquipment;

  final seriesCtrl = TextEditingController();
  final repsCtrl = TextEditingController();
  final weightCtrl = TextEditingController();

  String valueType = "reps"; // 👈 NUEVO
  bool weightNA = false;
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

  final exercises =
    List<Map<String, dynamic>>.from(b["exercises"] ?? const []);

currentExercises.addAll(exercises);

  workCtrl.text = b["work"]?.toString() ?? "";
  restCtrl.text = b["rest"]?.toString() ?? "";
  roundsCtrl.text = b["rounds"]?.toString() ?? "";
  emomTimeCtrl.text = b["time"]?.toString() ?? "";
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

  // 🔥 SOLO EL BLOQUE
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

    // 👇 CLAVE
    if (e["weight"] == null) {
      weightNA = true;
      weightCtrl.clear();
    } else {
      weightNA = false;
      weightCtrl.text = e["weight"].toString();
    }

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
 final double? parsedWeight = weightNA
    ? null
    : double.tryParse(
        weightCtrl.text.replaceAll(',', '.').trim(),
      );



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

  weightNA = false;
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

      // 🔍 BUSCADOR (EXPANDIDO)
      Expanded(
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: "Buscar ejercicio",
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) =>
              setState(() => searchQuery = v.toLowerCase()),
        ),
      ),

      const SizedBox(width: 8),

      // 💾 GUARDAR BLOQUE
      IconButton(
        icon: const Icon(Icons.save),
        tooltip: "Guardar bloque",
        onPressed: _saveBlock,
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

      body: ListView(
        padding: const EdgeInsets.all(12),
        
        children: [
            const SizedBox(height: 25),

  _topHeader(),
  _blockConfigCard(),

  const SizedBox(height: 12),


          const SizedBox(height: 12),

          // ===== SELECCIÓN EJERCICIO =====
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: exerciseName == null
                  ? _exerciseSearchAndSelector()
                  : _selectedExerciseRow(),
            ),
          ),

          if (availableEquipment.isNotEmpty)
            DropdownButtonFormField<String>(
              value: selectedEquipment,
              decoration:
                  const InputDecoration(labelText: "Equipamiento"),
              items: availableEquipment
                  .map((e) =>
                      DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => selectedEquipment = v),
            ),

          if (blockType == "Series")
  _num(seriesCtrl, "Series"),

            const SizedBox(height: 8),

          ElevatedButton.icon(
  icon: Icon(
    editingExerciseIndex != null ? Icons.save : Icons.add,
  ),
  onPressed: () {
    _addExercise(); // reutilizamos la lógica
  },
  label: Text(
    editingExerciseIndex != null
        ? "Guardar cambios"
        : "Agregar ejercicio",
  ),
),
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
  if (exerciseName != null && blockType != "Tabata") ...[
  const SizedBox(height: 8),
  _executionInput(),
  const SizedBox(height: 8),
  _weightInput(),
],


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
              onPressed: () => _editExercise(index),
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

  Widget _selectedExerciseRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            exerciseName!,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(_clearExerciseForm),
        ),
      ],
    );
  }

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
      perSide = false;
      weightNA = false;
      weightCtrl.text = "0";
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
          const SizedBox(height: 8),

          // 🔁 REPS / TIEMPO
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

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        valueType == "reps" ? "Repeticiones" : "Tiempo (seg)",
                  ),
                ),
              ),

              if (valueType == "reps") ...[
                const SizedBox(width: 12),
                Column(
                  children: [
                    Checkbox(
                      value: perSide,
                      onChanged: (v) =>
                          setState(() => perSide = v ?? false),
                    ),
                    const Text(
                      "Por lado",
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}


Widget _weightInput() {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Carga",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: weightCtrl,
                  enabled: !weightNA,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: "Peso (kg)"),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  Checkbox(
                    value: weightNA,
                    onChanged: (v) {
                      setState(() {
                        weightNA = v ?? false;
                        if (weightNA) weightCtrl.clear();
                      });
                    },
                  ),
                  const Text(
                    "Sin peso",
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}


  Widget _blockConfigCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
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
