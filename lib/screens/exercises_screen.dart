import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/exercise.dart';
import '../models/muscle_catalog.dart';
import 'exercise_detail_screen.dart';
import 'add_exercise_screen.dart';
import '../utils/responsive.dart';
import '../theme/app_theme.dart';

class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _folderCtrl = TextEditingController();
  final TextEditingController _multiplierCtrl = TextEditingController();
  String _searchQuery = "";
  String? _selectedType; // null = Todos
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Muscle? _selectedMuscle;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _folderCtrl.dispose();
    _multiplierCtrl.dispose();
    super.dispose();
  }

  void _showCreateFolderDialog({
    String? initialName,
    double? initialMult,
    String? docId,
  }) {
    _folderCtrl.text = initialName ?? "";
    _multiplierCtrl.text = (initialMult ?? 1.0).toString();

    // Si no tenemos ID pero el nombre ya existe en Firestore, intentar recuperar el ID
    // (Esto evita duplicados si el usuario usa el botón '+' pero escribe un nombre que ya existe)
    String? effectiveDocId = docId;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              docId != null ? "Editar Categoría" : "Nueva Categoría",
              style: const TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _folderCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Nombre (ej: Balísticos)",
                    hintStyle: TextStyle(color: Colors.grey),
                    labelText: "Nombre",
                  ),
                  autofocus: docId == null,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _multiplierCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Ponderador (ej: 1.3)",
                    hintStyle: TextStyle(color: Colors.grey),
                    labelText: "Ponderador de Carga",
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cancelar",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final name = _folderCtrl.text.trim();
                  final mult = double.tryParse(_multiplierCtrl.text) ?? 1.0;
                  if (name.isEmpty) return;

                  // Si es una creación pero el nombre ya tiene un documento, lo convertimos en edición silenciosa
                  if (effectiveDocId == null) {
                    final existing =
                        await FirebaseFirestore.instance
                            .collection('exercise_folders')
                            .where('name', isEqualTo: name)
                            .limit(1)
                            .get();
                    if (existing.docs.isNotEmpty) {
                      effectiveDocId = existing.docs.first.id;
                    }
                  }

                  if (effectiveDocId != null) {
                    await FirebaseFirestore.instance
                        .collection('exercise_folders')
                        .doc(effectiveDocId)
                        .update({
                          'name': name,
                          'multiplier': mult,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                  } else {
                    await FirebaseFirestore.instance
                        .collection('exercise_folders')
                        .add({
                          'name': name,
                          'multiplier': mult,
                          'createdAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() => _selectedType = name);
                },
                child: Text(
                  docId != null ? "Guardar" : "Crear",
                  style: const TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _moveExerciseToType(String exerciseId, String newType) async {
    await FirebaseFirestore.instance
        .collection('exercises')
        .doc(exerciseId)
        .update({
          'exerciseType': newType,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Ejercicio movido a $newType"),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _catalogTitle() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('exercises').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Text('EJERCICIOS');

        final movements =
            snapshot.data!.docs
                .where(
                  (doc) =>
                      (doc.data() as Map<String, dynamic>)['mergedInto'] ==
                      null,
                )
                .map(
                  (doc) => Exercise.fromFirestore(
                    doc.data() as Map<String, dynamic>,
                    id: doc.id,
                  ),
                )
                .toList();
        final variantCount = movements.fold<int>(
          0,
          (total, movement) => total + movement.variants.length,
        );

        return Tooltip(
          message:
              '${movements.length} movimientos activos · $variantCount variantes',
          child: Text(
            'EJERCICIOS · ${movements.length} M · $variantCount V',
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  /// Categorías (tipos). Fija a la izquierda en tablet/PC; en celular va en
  /// un panel lateral (170 px fijos se comían media pantalla en 360 px).
  Widget _typesSidebar({double width = 170}) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(right: BorderSide(color: AppColors.surface)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "TIPOS",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  onPressed: () => _showCreateFolderDialog(),
                  tooltip: "Nueva categoría",
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('exercise_folders')
                      .snapshots(),
              builder: (context, folderSnap) {
                final customFolders = folderSnap.data?.docs ?? [];
                final Map<String, dynamic> folderMapping = {};
                for (var doc in customFolders) {
                  final data = doc.data() as Map<String, dynamic>;
                  folderMapping[data['name']] = {
                    'id': doc.id,
                    'multiplier': (data['multiplier'] ?? 1.0).toDouble(),
                  };
                }

                return StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('exercises')
                          .snapshots(),
                  builder: (context, exSnap) {
                    // 1. Tipos únicos desde Firestore (Folders + Ejercicios en uso)
                    final Set<String> allTypeNames = {};
                    final Set<String> usedTypeNames = {};

                    if (exSnap.hasData) {
                      for (var doc in exSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        if (data['mergedInto'] != null) continue;
                        final type = (data['exerciseType'] ?? '').toString();
                        if (type.isNotEmpty) {
                          allTypeNames.add(type);
                          usedTypeNames.add(type);
                        }
                        final variants = data['variants'];
                        if (variants is List) {
                          for (final raw in variants.whereType<Map>()) {
                            final variantType =
                                (raw['exerciseType'] ?? '').toString();
                            if (variantType.isEmpty) continue;
                            allTypeNames.add(variantType);
                            usedTypeNames.add(variantType);
                          }
                        }
                      }
                    }

                    // Solo mostrar carpetas que realmente tienen un movimiento o variante activa.
                    for (var name in folderMapping.keys) {
                      if (usedTypeNames.contains(name)) allTypeNames.add(name);
                    }

                    final sortedNames = allTypeNames.toList()..sort();

                    return ListView(
                      children: [
                        _folderItem(null, "Todos", null),
                        const Divider(color: Colors.white10),
                        ...sortedNames.map((name) {
                          final data = folderMapping[name];
                          return _folderItem(
                            name,
                            name,
                            data != null ? data['multiplier'] : 1.0,
                            docId: data?['id'],
                          );
                        }),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Scaffold(
      key: _scaffoldKey,
      endDrawer:
          compact
              ? Drawer(
                width: 260,
                child: SafeArea(child: _typesSidebar(width: double.infinity)),
              )
              : null,
      appBar: AppBar(
        title: _catalogTitle(),
        actions: [
          if (compact)
            IconButton(
              tooltip: "Tipos de ejercicio",
              icon: Badge(
                isLabelVisible: _selectedType != null,
                smallSize: 9,
                backgroundColor: Colors.amber,
                child: const Icon(Icons.folder_open_outlined),
              ),
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
          PopupMenuButton<Muscle?>(
            tooltip: "Filtrar por músculo",
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.fitness_center),
                if (_selectedMuscle != null)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onSelected: (m) => setState(() => _selectedMuscle = m),
            itemBuilder:
                (_) => [
                  const PopupMenuItem<Muscle?>(
                    value: null,
                    child: Text("Todos los músculos"),
                  ),
                  ...Muscle.values.map(
                    (m) =>
                        PopupMenuItem<Muscle?>(value: m, child: Text(m.label)),
                  ),
                ],
          ),
        ],
      ),
      body: Row(
        children: [
          if (!compact) _typesSidebar(),

          // ===============================
          // 📃 LISTADO DE EJERCICIOS
          // ===============================
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: "Buscar ejercicio...",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged:
                        (v) => setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream:
                        FirebaseFirestore.instance
                            .collection('exercises')
                            .orderBy('name')
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());

                      var exercises =
                          snapshot.data!.docs
                              .where(
                                (doc) =>
                                    (doc.data()
                                        as Map<
                                          String,
                                          dynamic
                                        >)['mergedInto'] ==
                                    null,
                              )
                              .map(
                                (doc) => Exercise.fromFirestore(
                                  doc.data() as Map<String, dynamic>,
                                  id: doc.id,
                                ),
                              )
                              .where((e) {
                                final matchesSearch =
                                    e.name.toLowerCase().contains(
                                      _searchQuery,
                                    ) ||
                                    e.variants.any(
                                      (variant) =>
                                          variant.label.toLowerCase().contains(
                                            _searchQuery,
                                          ) ||
                                          variant.equipment.any(
                                            (equipment) => equipment
                                                .toLowerCase()
                                                .contains(_searchQuery),
                                          ),
                                    );
                                final matchesType =
                                    _selectedType == null ||
                                    e.exerciseType == _selectedType ||
                                    e.variants.any(
                                      (variant) =>
                                          variant.exerciseType == _selectedType,
                                    );
                                final matchesMuscle =
                                    _selectedMuscle == null ||
                                    (e.muscleWeights[_selectedMuscle] ?? 0) > 0;
                                return matchesSearch &&
                                    matchesType &&
                                    matchesMuscle;
                              })
                              .toList();

                      if (_selectedMuscle != null) {
                        exercises.sort((a, b) {
                          final weightA =
                              a.muscleWeights[_selectedMuscle!] ?? 0.0;
                          final weightB =
                              b.muscleWeights[_selectedMuscle!] ?? 0.0;
                          if (weightA != weightB) {
                            return weightB.compareTo(weightA);
                          }
                          return a.name.compareTo(b.name);
                        });
                      }

                      if (exercises.isEmpty)
                        return const Center(child: Text("Sin ejercicios"));

                      return ListView.builder(
                        itemCount: exercises.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          return _exerciseCard(exercises[index], const {});
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddExerciseScreen(initialType: _selectedType),
              ),
            ),
      ),
    );
  }

  Widget _exerciseCard(Exercise ex, Map<String, dynamic> folderMapping) {
    String weightText = "";
    if (_selectedMuscle != null) {
      final weight = ex.muscleWeights[_selectedMuscle] ?? 0.0;
      if (weight > 0) {
        weightText =
            "  •  ${(weight * 100).toStringAsFixed(0)}% ${_selectedMuscle!.label}";
      }
    }
    final variantCount = ex.variants.length;
    final variantLabels = ex.variants
        .where((variant) => variant.label.toLowerCase() != 'original')
        .map((variant) => '${variant.label} · ${variant.trainingDiscipline}')
        .take(3)
        .join(' · ');
    final variantText =
        '$variantCount ${variantCount == 1 ? 'variante' : 'variantes'}';
    final variantTypes = ex.variants
        .where((variant) => variant.label.toLowerCase() != 'original')
        .map((variant) {
          final folder = folderMapping[variant.exerciseType];
          final multiplier =
              folder is Map ? (folder['multiplier'] as num?)?.toDouble() : null;
          final factor =
              multiplier == null ? '' : ' · x${multiplier.toStringAsFixed(2)}';
          return '${variant.label} · ${variant.exerciseType.isEmpty ? 'Sin tipo' : variant.exerciseType}$factor';
        })
        .take(3)
        .join(' · ');

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Draggable<String>(
          data: ex.id,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).primaryColor),
              ),
              child: Text(
                ex.name,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          childWhenDragging: const Opacity(
            opacity: 0.3,
            child: Icon(Icons.drag_indicator, color: Colors.grey),
          ),
          child: const MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Icon(Icons.drag_indicator, color: Colors.grey),
          ),
        ),
        title: Text(
          ex.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${ex.exerciseType}$weightText · $variantText",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (variantLabels.isNotEmpty)
              Text(
                '$variantLabels${variantTypes.isNotEmpty ? ' · $variantTypes' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
        trailing: Icon(
          ex.trackRM ? Icons.star : Icons.star_border,
          color: ex.trackRM ? Colors.amber : Colors.white12,
          size: 18,
        ),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExerciseDetailScreen(exercise: ex),
              ),
            ),
      ),
    );
  }

  Widget _folderItem(
    String? typeName,
    String label,
    double? multiplier, {
    String? docId,
  }) {
    final isSelected = _selectedType == typeName;

    return DragTarget<String>(
      onWillAccept:
          (data) =>
              data != null && typeName != null && typeName != _selectedType,
      onAccept: (exId) => _moveExerciseToType(exId, typeName!),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return InkWell(
          onTap: () {
            setState(() => _selectedType = typeName);
            // En celular la lista está en un panel: cerrarlo al elegir.
            if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
              _scaffoldKey.currentState!.closeEndDrawer();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  isHovering
                      ? Theme.of(context).primaryColor.withOpacity(0.1)
                      : (isSelected ? AppColors.surface : Colors.transparent),
              border: Border(
                left: BorderSide(
                  color:
                      isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  typeName == null
                      ? Icons.category_outlined
                      : Icons.folder_open,
                  color:
                      isHovering
                          ? Theme.of(context).primaryColor
                          : (isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (multiplier != null)
                        Text(
                          "x${multiplier.toStringAsFixed(2)}",
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey.withOpacity(0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                if (typeName != null)
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: Colors.grey,
                    ),
                    onPressed:
                        () => _showCreateFolderDialog(
                          initialName: typeName,
                          initialMult: multiplier,
                          docId: docId,
                        ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
