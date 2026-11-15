// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exercise.dart';
import '../models/muscle_catalog.dart';
import '../screens/add_exercise_screen.dart';
import '../widgets/body_heatmap.dart';
import '../utils/svg_utils.dart';
import '../theme/app_theme.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({super.key, required this.exercise});

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _role;
  String? _selectedVariantId;

  ExerciseVariant? get _selectedVariant {
    final id = _selectedVariantId;
    if (id == null) return null;
    for (final variant in widget.exercise.variants) {
      if (variant.id == id) return variant;
    }
    return null;
  }

  Map<Muscle, double> get _activeMuscleWeights {
    final overrides = _selectedVariant?.muscleWeightOverrides ?? const {};
    return overrides.isEmpty ? widget.exercise.muscleWeights : overrides;
  }

  Map<Muscle, double> _getHeatmapForTab() {
    final currentIndex = _tabController.index;

    // =========================
    // 0 → MUSCULAR (original)
    // =========================
    if (currentIndex == 0) {
      return _activeMuscleWeights.map((m, v) => MapEntry(m, v * 100));
    }

    // =========================
    // 1 → GRUPO
    // =========================
    if (currentIndex == 1) {
      final groupTotals = <AnatomicalGroup, double>{};

      _activeMuscleWeights.forEach((muscle, value) {
        for (final entry in anatomicalGroups.entries) {
          if (entry.value.contains(muscle)) {
            groupTotals.update(
              entry.key,
              (v) => v + value,
              ifAbsent: () => value,
            );
          }
        }
      });

      final result = <Muscle, double>{};

      for (final entry in anatomicalGroups.entries) {
        final groupValue = groupTotals[entry.key] ?? 0;
        for (final muscle in entry.value) {
          result[muscle] = groupValue * 100;
        }
      }

      return result;
    }

    // =========================
    // 2 → FUNCIONAL
    // =========================
    if (currentIndex == 2) {
      final functionalTotals = <FunctionalGroup, double>{};

      _activeMuscleWeights.forEach((muscle, value) {
        for (final entry in functionalGroups.entries) {
          if (entry.value.contains(muscle)) {
            functionalTotals.update(
              entry.key,
              (v) => v + value,
              ifAbsent: () => value,
            );
          }
        }
      });

      final result = <Muscle, double>{};

      for (final entry in functionalGroups.entries) {
        final groupValue = functionalTotals[entry.key] ?? 0;
        for (final muscle in entry.value) {
          result[muscle] = groupValue * 100;
        }
      }

      return result;
    }

    return {};
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      if (mounted) {
        setState(() {
          _role = userDoc.data()?['role']?.toString().toLowerCase();
        });
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              "¿Eliminar Ejercicio?",
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              "¿Estás seguro de que quieres eliminar '${widget.exercise.name}'? Esta acción no se puede deshacer.",
              style: const TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "CANCELAR",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _deleteExercise();
                },
                child: const Text(
                  "ELIMINAR",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteExercise() async {
    try {
      await FirebaseFirestore.instance
          .collection('exercises')
          .doc(widget.exercise.id)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ejercicio eliminado correctamente")),
        );
        Navigator.pop(context); // Volver a la biblioteca
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error al eliminar: $e")));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ======================================================
              // 🔝 HEADER
              // ======================================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.exercise.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder:
                            (_) => Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(widget.exercise.instructions),
                            ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => AddExerciseScreen(
                                exerciseToEdit: widget.exercise,
                                exerciseId: widget.exercise.id,
                              ),
                        ),
                      );
                    },
                  ),
                  if (_role == 'administrador' || _role == 'admin')
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: _confirmDelete,
                      tooltip: "Eliminar ejercicio",
                    ),
                ],
              ),

              const SizedBox(height: 8),
              _buildIdentitySummary(),
              const SizedBox(height: 10),
              _buildMuscleWeightVariantSelector(),
              const SizedBox(height: 16),

              // ======================================================
              // 🧠 MAPA + PONDERADORES
              // ======================================================
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ======================
                      // 🧍 FRONTAL
                      // ======================
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            const Text(
                              "Frontal",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            AspectRatio(
                              aspectRatio: 3 / 5,
                              child: BodyHeatmap(
                                heatmap: _getHeatmapForTab(),

                                showBack: false,
                                percentageScale: false,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // ======================
                      // 🧍 POSTERIOR
                      // ======================
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            const Text(
                              "Posterior",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            AspectRatio(
                              aspectRatio: 3 / 5,
                              child: BodyHeatmap(
                                heatmap: _getHeatmapForTab(),

                                showBack: true,
                                percentageScale: false,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      // ======================
                      // 📊 PONDERADORES CON TABS
                      // ======================
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            TabBar(
                              controller: _tabController,
                              labelColor: Theme.of(context).colorScheme.primary,
                              unselectedLabelColor: Colors.grey,
                              labelStyle: const TextStyle(fontSize: 11),
                              tabs: const [
                                Tab(text: "Músculo"),
                                Tab(text: "Grupo"),
                                Tab(text: "Función"),
                              ],
                            ),

                            const SizedBox(height: 8),

                            SizedBox(
                              height: 300,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildMuscleWeights(),
                                  _buildGroupWeights(),
                                  _buildFunctionalWeights(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ======================================================
              // 🔀 VARIANTES
              // ======================================================
              _sectionTitle('Variantes (${widget.exercise.variants.length})'),
              const SizedBox(height: 8),
              _buildVariantsSection(),
              const SizedBox(height: 24),

              // ======================================================
              // 🧰 EQUIPAMIENTO
              // ======================================================
              if (widget.exercise.equipment.isNotEmpty) ...[
                _sectionTitle("Equipamiento"),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      widget.exercise.equipment
                          .map((e) => Chip(label: Text(e)))
                          .toList(),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatPercent(double value) {
    final percent = value * 100;

    if (percent % 1 == 0) {
      return percent.toInt().toString();
    }

    return percent
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  // ======================================================
  // 🔵 MUSCULAR
  // ======================================================
  Widget _buildMuscleWeights() {
    final sorted =
        _activeMuscleWeights.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      children:
          sorted.map((e) {
            final percent = _formatPercent(e.value);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_muscleLabel(e.key))),
                      Text("$percent%"),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: e.value,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade300,
                    color: heatmapColor(e.value * 100).withOpacity(0.9),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  // ======================================================
  // 🟢 GRUPO
  // ======================================================
  Widget _buildGroupWeights() {
    final groupTotals = <AnatomicalGroup, double>{};

    _activeMuscleWeights.forEach((muscle, value) {
      for (final entry in anatomicalGroups.entries) {
        if (entry.value.contains(muscle)) {
          groupTotals.update(
            entry.key,
            (v) => v + value,
            ifAbsent: () => value,
          );
        }
      }
    });

    final sorted =
        groupTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      children:
          sorted.map((e) {
            final percent = (e.value * 100).round();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${e.key.name} $percent%"),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: e.value,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade300,
                    color: heatmapColor(e.value * 100).withOpacity(0.9),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  // ======================================================
  // 🟣 FUNCIONAL
  // ======================================================
  Widget _buildFunctionalWeights() {
    final functionalTotals = <FunctionalGroup, double>{};

    _activeMuscleWeights.forEach((muscle, value) {
      for (final entry in functionalGroups.entries) {
        if (entry.value.contains(muscle)) {
          functionalTotals.update(
            entry.key,
            (v) => v + value,
            ifAbsent: () => value,
          );
        }
      }
    });

    final sorted =
        functionalTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      children:
          sorted.map((e) {
            final percent = (e.value * 100).round();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${e.key.name} $percent%"),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: e.value,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade300,
                    color: heatmapColor(e.value * 100).withOpacity(0.9),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  String _muscleLabel(Muscle m) {
    return muscleCatalogMap.entries
        .firstWhere((e) => e.value.keys.first == m)
        .key;
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    );
  }

  String _readableId(String value) => value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Widget _identityChip({required IconData icon, required String label}) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildIdentitySummary() {
    final variants = widget.exercise.variants;
    final familyId = variants
        .map((variant) => variant.familyId)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final types =
        variants
            .map((variant) => variant.exerciseType)
            .where((value) => value.isNotEmpty)
            .toSet();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (familyId.isNotEmpty)
          _identityChip(
            icon: Icons.account_tree_outlined,
            label: 'Patrón: ${_readableId(familyId)}',
          ),
        _identityChip(
          icon: Icons.category_outlined,
          label: 'Base: ${widget.exercise.exerciseType}',
        ),
        if (types.length > 1)
          _identityChip(
            icon: Icons.tune,
            label: '${types.length} tipos según variante',
          ),
      ],
    );
  }

  Widget _buildMuscleWeightVariantSelector() {
    final selected = _selectedVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ponderación mostrada: ${selected?.label ?? 'base del movimiento'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Selecciona una variante para ver en el mapa su ponderación específica.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Base'),
                selected: _selectedVariantId == null,
                onSelected: (_) => setState(() => _selectedVariantId = null),
              ),
              ...widget.exercise.variants.map(
                (variant) => ChoiceChip(
                  label: Text(
                    variant.muscleWeightOverrides.isEmpty
                        ? '${widget.exercise.variants.length == 1 ? widget.exercise.name : variant.label} · base'
                        : '${widget.exercise.variants.length == 1 ? widget.exercise.name : variant.label} · propia',
                  ),
                  selected: _selectedVariantId == variant.id,
                  onSelected:
                      (_) => setState(() => _selectedVariantId = variant.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsSection() {
    final grouped = <String, List<ExerciseVariant>>{};
    for (final variant in widget.exercise.variants) {
      grouped.putIfAbsent(variant.group, () => []).add(variant);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final group in grouped.entries) ...[
              Text(
                group.key,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              for (final variant in group.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.tune, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.exercise.variants.length == 1
                                  ? widget.exercise.name
                                  : variant.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (variant.equipment.isNotEmpty)
                              Text(
                                variant.equipment.join(' · '),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            if (variant.techniqueLabel.isNotEmpty ||
                                variant.exerciseType.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  [
                                    if (variant.techniqueLabel.isNotEmpty)
                                      'Técnica: ${variant.techniqueLabel}',
                                    'Tipo: ${variant.exerciseType.isNotEmpty ? variant.exerciseType : widget.exercise.exerciseType}',
                                  ].join(' · '),
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            if (variant.muscleWeightOverrides.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Ponderación propia · ${variant.muscleWeightOverrides.length} músculos',
                                  style: const TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (variant.isUnilateral)
                        const Tooltip(
                          message: 'Unilateral',
                          child: Icon(
                            Icons.swap_horiz,
                            size: 17,
                            color: Colors.grey,
                          ),
                        ),
                      if (variant.trackProgression)
                        const Tooltip(
                          message: 'Incluida en progresión de sobrecarga',
                          child: Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.trending_up,
                              size: 17,
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                        ),
                      if (variant.trackRM)
                        const Tooltip(
                          message: 'Registra RM y PR',
                          child: Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.star,
                              size: 17,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (group.key != grouped.keys.last) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}
