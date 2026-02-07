import 'package:flutter/material.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';

/// ======================================================
/// 🧩 GRUPOS MUSCULARES
/// ======================================================
enum MuscleGroup { lower, arms, back, upper, core, stabilizers }

const Map<MuscleGroup, List<Muscle>> muscleGroups = {
  MuscleGroup.lower: [
    Muscle.quads,
    Muscle.hamstrings,
    Muscle.glutes,
    Muscle.adductors,
    Muscle.calves,
  ],
  MuscleGroup.arms: [
    Muscle.biceps,
    Muscle.triceps,
    Muscle.forearms,
  ],
  MuscleGroup.back: [
    Muscle.lats,
    Muscle.midBack,
    Muscle.traps,
  ],
  MuscleGroup.upper: [
    Muscle.chest,
    Muscle.frontDelts,
    Muscle.rearDelts,
    Muscle.midDelts
  ],
  MuscleGroup.core: [
    Muscle.abs,
    Muscle.obliques,
    Muscle.psoas,
    Muscle.lowerBack,
    Muscle.serratus,

  ],
};

/// ======================================================
/// 🖥 SCREEN
/// ======================================================
class MuscleWeightEditorScreen extends StatefulWidget {
  final Map<Muscle, double> initialWeights;

  const MuscleWeightEditorScreen({
    super.key,
    required this.initialWeights,
  });

  @override
  State<MuscleWeightEditorScreen> createState() =>
      _MuscleWeightEditorScreenState();
}

class _MuscleWeightEditorScreenState
    extends State<MuscleWeightEditorScreen> {
  /// Editable (no toca heatmap)
  late Map<Muscle, double> draftWeights;

  /// Aplicado (sí toca heatmap)
  late Map<Muscle, double> appliedWeights;

  bool hasPendingChanges = false;

  @override
  void initState() {
    super.initState();
    draftWeights = Map.from(widget.initialWeights);
    appliedWeights = Map.from(widget.initialWeights);
  }

  double get total =>
      draftWeights.values.fold(0.0, (a, b) => a + b);

  Color get totalColor {
    if (draftWeights.isEmpty) return Colors.grey;
    if ((total - 1.0).abs() < 0.01) return Colors.green;
    return Colors.red;
  }

  /// ===============================
  /// 🟢 APLICAR CAMBIOS (actualiza SVG)
  /// ===============================
  void _applyChanges() {
    final t = draftWeights.values.fold(0.0, (a, b) => a + b);

    if (draftWeights.isNotEmpty && (t - 1.0).abs() > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("La ponderación debe sumar 100%"),
        ),
      );
      return;
    }

    setState(() {
      appliedWeights = Map.from(draftWeights);
      hasPendingChanges = false;
    });
  }

  /// ===============================
  /// 💾 GUARDAR Y SALIR
  /// ===============================
  void _saveAndExit() {
    Navigator.pop(context, appliedWeights);
  }

 @override
Widget build(BuildContext context) {

  // 🔥 Heatmap con escala correcta (0–100)
  final Map<Muscle, double> heatmap = appliedWeights.map(
    (muscle, weight) => MapEntry(
      muscle,
      ((weight * 100).clamp(0.0, 100.0)).toDouble(),
    ),
  );

  return DefaultTabController(

      length: muscleGroups.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Ponderación muscular"),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: "Piernas"),
              Tab(text: "Brazos"),
              Tab(text: "Espalda"),
              Tab(text: "Pecho/Hombro"),
              Tab(text: "Core"),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  hasPendingChanges ? _applyChanges : _saveAndExit,
              child: Text(
                hasPendingChanges
                    ? "Aplicar cambios"
                    : "Guardar",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // ===============================
              // 🧍 BLOQUE 1 – CUERPOS
              // ===============================
              SizedBox(
                height: 200,
                child: Row(
                  children: [
                    Expanded(
                      child: BodyHeatmap(
                        heatmap: heatmap,
                        showBack: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BodyHeatmap(
                        heatmap: heatmap,
                        showBack: true,
                      ),
                    ),
                    
                  ],
                ),
              ),

              const Divider(),

              // ===============================
              // 🎚 BLOQUE 2 – PONDERACIONES
              // ===============================
              Align(
                alignment: Alignment.centerLeft,
                child:  Text(
                        "Total: ${(total * 100).round()}%",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: totalColor,
                        ),
                      ),
              ),

              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      ...draftWeights.entries.map((e) {
                        return MuscleSlider(
                          muscle: e.key,
                          initialValue: e.value,
                          onRemove: () {
                            setState(() {
                              draftWeights.remove(e.key);
                              hasPendingChanges = true;
                            });
                          },
                          onChangedEnd: (v) {
                            setState(() {
                              draftWeights[e.key] = v;
                              hasPendingChanges = true;
                            });
                          },
                        );
                      }),
                     
                    ],
                  ),
                ),
              ),

              // ===============================
              // 📋 BLOQUE 3–4 – SELECTOR
              // ===============================
              Expanded(
                child: TabBarView(
                  children: muscleGroups.entries.map((group) {
                    final available = group.value
                        .where(
                          (m) => !draftWeights.containsKey(m),
                        )
                        .toList();

                    return ListView(
                      padding: const EdgeInsets.all(8),
                      children: available.map((m) {
                        return ListTile(
                          dense: true,
                          title: Text(
                            m.label,
                            style:
                                const TextStyle(fontSize: 13),
                          ),
                          trailing:
                              const Icon(Icons.add, size: 18),
                          onTap: () {
                            setState(() {
                              draftWeights[m] = 0.0;
                              hasPendingChanges = true;
                            });
                          },
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ======================================================
/// 🎚 SLIDER AISLADO (CLAVE PARA FLUIDEZ)
/// ======================================================
class MuscleSlider extends StatefulWidget {
  final Muscle muscle;
  final double initialValue;
  final VoidCallback onRemove;
  final void Function(double) onChangedEnd;

  const MuscleSlider({
    super.key,
    required this.muscle,
    required this.initialValue,
    required this.onRemove,
    required this.onChangedEnd,
  });

  @override
  State<MuscleSlider> createState() => _MuscleSliderState();
}

class _MuscleSliderState extends State<MuscleSlider> {
  late double value;

  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "${widget.muscle.label} – ${(value * 100).round()}%",
                style: const TextStyle(fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onRemove,
            ),
          ],
        ),
        Slider(
          min: 0,
          max: 1,
          divisions: 20,
          value: value,
          onChanged: (v) {
            setState(() => value = v); // 🔥 SOLO ESTE WIDGET
          },
          onChangeEnd: widget.onChangedEnd,
        ),
      ],
    );
  }
}
