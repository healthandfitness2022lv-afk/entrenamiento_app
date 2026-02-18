import 'package:flutter/material.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';

/// ======================================================
/// 🧩 GRUPOS MUSCULARES
/// ======================================================

enum MuscleViewMode { anatomical, functional }

MuscleViewMode viewMode = MuscleViewMode.anatomical;

Map<Muscle, double> expandAnatomicalGroups({
  required Map<AnatomicalGroup, double> groupWeights,
  required Map<Muscle, double> subgroupRelativeWeights,
}) {
  final result = <Muscle, double>{};

  for (final entry in groupWeights.entries) {
    final group = entry.key;
    final groupValue = entry.value;
    final muscles = anatomicalGroups[group]!;

    Map<Muscle, double> internal = {};

    final defined = muscles
        .where((m) => subgroupRelativeWeights.containsKey(m))
        .toList();

    if (defined.isEmpty) {
      final per = 1.0 / muscles.length;
      for (final m in muscles) {
        internal[m] = per;
      }
    } else {
      final totalInternal = defined.fold(
        0.0,
        (sum, m) => sum + subgroupRelativeWeights[m]!,
      );

      for (final m in muscles) {
        final rel = subgroupRelativeWeights[m] ?? 0.0;
        internal[m] = totalInternal == 0 ? 0 : rel / totalInternal;
      }
    }

    for (final m in muscles) {
      final finalValue = groupValue * (internal[m] ?? 0);

      if (finalValue > 0) {
        result[m] = finalValue;
      }
    }
  }

  return result;
}

/// ======================================================
/// 🖥 SCREEN
/// ======================================================
class MuscleWeightEditorScreen extends StatefulWidget {
  final Map<Muscle, double> initialWeights;

  const MuscleWeightEditorScreen({super.key, required this.initialWeights});

  @override
  State<MuscleWeightEditorScreen> createState() =>
      _MuscleWeightEditorScreenState();
}

class _MuscleWeightEditorScreenState extends State<MuscleWeightEditorScreen> {
  late Map<AnatomicalGroup, double> groupWeights;
  late Map<Muscle, double> subgroupRelativeWeights;
  final Map<AnatomicalGroup, TextEditingController> groupControllers = {};


  void _initializeFromInitialWeights() {
    groupWeights.clear();
    subgroupRelativeWeights.clear();

    for (final entry in anatomicalGroups.entries) {
      final group = entry.key;
      final muscles = entry.value;

      double groupTotal = 0.0;

      for (final m in muscles) {
        groupTotal += widget.initialWeights[m] ?? 0.0;
      }

      if (groupTotal > 0) {
        groupWeights[group] = groupTotal;

        for (final m in muscles) {
          final muscleValue = widget.initialWeights[m] ?? 0.0;
          const epsilon = 0.0001;

          if (muscleValue > epsilon) {
            subgroupRelativeWeights[m] = muscleValue / groupTotal;
          }
        }
      }
    }
  }

 void _openSubgroupEditor(AnatomicalGroup group) {
  final muscles = anatomicalGroups[group]!;

  

  showDialog(
    context: context,
    builder: (ctx) {
      final local = Map<Muscle, double>.from(subgroupRelativeWeights);

      // Controllers persistentes (NO crear dentro del itemBuilder)
      final controllers = <Muscle, TextEditingController>{
        for (final m in muscles)
          m: TextEditingController(
            text: (((local[m] ?? 0.0) * 100).round()).toString(),
          ),
      };

      return StatefulBuilder(
        builder: (ctx, dialogSetState) {
          final groupValue = groupWeights[group] ?? 0.0;

          double internalTotalPercent() {
  return muscles.fold<double>(
    0.0,
    (sum, m) => sum + (local[m] ?? 0.0),
  ) * 100;
}



          final w = MediaQuery.of(ctx).size.width * 0.92;
          final h = MediaQuery.of(ctx).size.height * 0.78;

          return Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                // 👇 CLAVE: ancho/alto FINITOS sí o sí
                constraints: BoxConstraints.tightFor(width: w, height: h),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // HEADER
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Detalle ${group.name.toUpperCase()}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                for (final c in controllers.values) {
                                  c.dispose();
                                }
                                Navigator.pop(ctx);
                              },
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Grupo: ${(groupValue * 100).round()}% del total",
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(
      "Suma interna: ${internalTotalPercent().round()}%",
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: (internalTotalPercent() - 100).abs() < 1
            ? Colors.green
            : Colors.red,
      ),
    ),
  ),
),
const SizedBox(height: 8),

                      const Divider(height: 1),

                      // LISTA + SCROLL
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: muscles.length,
                          itemBuilder: (_, i) {
                            final m = muscles[i];
                            final raw = (local[m] ?? 0.0).clamp(0.0, 1.0);

                            final rawPercent = ((local[m] ?? 0.0) * 100).round();
final groupPercent = rawPercent;
final totalPercent =
    ((groupWeights[group] ?? 0.0) * (local[m] ?? 0.0) * 100).round();


                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
  "${m.label}  •  $groupPercent% del grupo  •  $totalPercent% total",
  style: const TextStyle(
    fontWeight: FontWeight.w600,
  ),
),

                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Slider(
                                          value: raw,
                                          min: 0,
                                          max: 1,
                                          divisions: 100,
                                          onChanged: (v) {
                                            dialogSetState(() {
                                              final nv = v.clamp(0.0, 1.0);
                                              local[m] = nv;
                                              controllers[m]!.text =
                                                  ((nv * 100).round())
                                                      .toString();
                                            });
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 72,
                                        child: TextField(
                                          controller: controllers[m],
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            suffixText: "%",
                                            isDense: true,
                                          ),
                                          onChanged: (txt) {
                                            final n = double.tryParse(txt);
                                            if (n == null) return;
                                            final nv = (n / 100).clamp(0.0, 1.0);
                                            dialogSetState(() {
                                              local[m] = nv;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      const Divider(height: 1),

                      // FOOTER (sin Spacer / sin infinity)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 12,
                            children: [
                              TextButton(
                                onPressed: () {
  final total = muscles.fold<double>(
    0.0,
    (sum, m) => sum + (local[m] ?? 0.0),
  );

  // 🔥 tolerancia matemática correcta
  if ((total - 1.0).abs() > 0.005) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("La suma interna debe ser 100%"),
      ),
    );
    return;
  }

  setState(() {
    subgroupRelativeWeights = Map.from(local);
    hasPendingChanges = true;
  });

  Navigator.pop(ctx);
},


                                child: const Text("Listo"),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

  /// Aplicado (sí toca heatmap)
  late Map<Muscle, double> appliedWeights;

  bool hasPendingChanges = false;

  @override
  void initState() {
    super.initState();
    appliedWeights = Map.from(widget.initialWeights);
    groupWeights = {};
    subgroupRelativeWeights = {};
    _initializeFromInitialWeights();

for (final entry in anatomicalGroups.entries) {
  final group = entry.key;
  final value = groupWeights[group] ?? 0.0;
  groupControllers[group] = TextEditingController(
    text: ((value * 100).round()).toString(),
  );
}

  }

  double get total => groupWeights.values.fold(0.0, (a, b) => a + b);

  Color get totalColor {
    if ((total - 1.0).abs() < 0.01) return Colors.green;
    return Colors.red;
  }

  /// ===============================
  /// 🟢 APLICAR CAMBIOS (actualiza SVG)
  /// ===============================
  void _applyChanges() {
    final expanded = expandAnatomicalGroups(
      groupWeights: groupWeights,
      subgroupRelativeWeights: subgroupRelativeWeights,
    );

    final total = expanded.values.fold(0.0, (a, b) => a + b);

    if ((total - 1.0).abs() > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La ponderación debe sumar 100%")),
      );
      return;
    }

    setState(() {
      appliedWeights = expanded;
      hasPendingChanges = false;
    });
  }

  void _saveAndExit() {
    final expanded = expandAnatomicalGroups(
      groupWeights: groupWeights,
      subgroupRelativeWeights: subgroupRelativeWeights,
    );

    final total = expanded.values.fold(0.0, (a, b) => a + b);

    if ((total - 1.0).abs() > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La ponderación debe sumar 100%")),
      );
      return;
    }

    Navigator.pop(context, expanded);
  }

  @override
  Widget build(BuildContext context) {
    final heatmap = appliedWeights.map(
      (muscle, weight) =>
          MapEntry(muscle, ((weight * 100).clamp(0.0, 100.0)).toDouble()),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ponderación muscular"),
        actions: [
          TextButton(
            onPressed: _applyChanges,
            child: const Text(
              "Aplicar",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: _saveAndExit,
            child: const Text(
              "Guardar",
              style: TextStyle(
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
            /// 🔥 HEATMAP
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: BodyHeatmap(heatmap: heatmap, showBack: false),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BodyHeatmap(heatmap: heatmap, showBack: true),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Divider(),

            /// 🔢 TOTAL
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Total: ${(total * 100).round()}%",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: totalColor,
                ),
              ),
            ),

            const SizedBox(height: 10),
            const Divider(),

            /// 🎚 GRUPOS ANATÓMICOS
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: anatomicalGroups.entries.map((entry) {
                    final group = entry.key;
                    final value = groupWeights[group] ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// 🔹 Título + botón detallar
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "${group.name.toUpperCase()} ${(value * 100).round()}%",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _openSubgroupEditor(group),
                                  child: const Text("Detallar"),
                                ),
                              ],
                            ),

                            /// 🔹 Slider principal del grupo
                            Row(
                              children: [
                                Expanded(
                                  child: Slider(
  value: value,
  min: 0,
  max: 1,
  divisions: 100,
  onChanged: (v) {
    setState(() {
      groupWeights[group] = v;
      groupControllers[group]!.text =
          ((v * 100).round()).toString();
      hasPendingChanges = true;
    });
  },
),

                                ),
                                SizedBox(
                                  width: 60,
                                  child: TextField(
  controller: groupControllers[group],

                                    keyboardType: TextInputType.number,
                                    onChanged: (text) {
                                      final number = double.tryParse(text);
                                      if (number != null) {
                                        final normalized = (number / 100).clamp(
                                          0.0,
                                          1.0,
                                        );
                                        setState(() {
                                          groupWeights[group] = normalized;
                                          hasPendingChanges = true;
                                        });
                                      }
                                    },
                                    decoration: const InputDecoration(
                                      suffixText: "%",
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
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
          divisions: 100,
          value: value,
          onChanged: (v) {
            setState(() => value = v);
          },
          onChangeEnd: widget.onChangedEnd,
        ),
      ],
    );
  }
}
