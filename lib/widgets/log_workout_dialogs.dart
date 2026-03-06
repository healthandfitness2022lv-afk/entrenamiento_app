import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/add_workout_screen.dart';

class LogWorkoutDialogs {
  static Future<void> showExerciseInfo({
    required BuildContext context,
    required String name,
    required Future<String?> Function(String) fetchInstructions,
  }) async {
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    final instructions = await fetchInstructions(name);
    if (!context.mounted) return;
    Navigator.pop(context); // Close loading

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(name),
        content: instructions != null
            ? Text(instructions)
            : const Text("No hay instrucciones disponibles"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  static Future<bool> confirmDeleteExercise({
    required BuildContext context,
    required String exerciseName,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar ejercicio"),
        content: Text("¿Eliminar $exerciseName del bloque?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static Future<bool> confirmDeleteBlock(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar bloque"),
        content: const Text("¿Seguro que deseas eliminar este bloque?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static Future<bool> confirmFinish(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Finalizar entrenamiento"),
        content: const Text("¿Estás seguro?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Finalizar"),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static Future<int?> askTabataRpe({
    required BuildContext context,
    required String exerciseName,
  }) async {
    return await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        int selected = 7;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("RPE — $exerciseName"),
              content: DropdownButton<int>(
                value: selected,
                items: List.generate(
                  10,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text("RPE ${i + 1}"),
                  ),
                ),
                onChanged: (v) {
                  setState(() {
                    selected = v!;
                  });
                },
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text("Confirmar"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Shows a bottom sheet with two tabs:
  /// 1) Create a new block (by type)
  /// 2) Pick from the saved 'blocks' collection
  static void showAddBlockOptions({
    required BuildContext context,
    required Function(Map<String, dynamic>) onBlockAdded,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40, height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Agregar bloque",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.add_circle_outline), text: "Nuevo"),
                  Tab(icon: Icon(Icons.library_books_outlined), text: "Guardados"),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // ---- TAB 1: Crear nuevo bloque ----
                    ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        _addBlockTile(context, "Series", Icons.repeat, onBlockAdded),
                        _addBlockTile(context, "Circuito", Icons.loop, onBlockAdded),
                        _addBlockTile(context, "Tabata", Icons.timer, onBlockAdded),
                        _addBlockTile(context, "EMOM", Icons.av_timer, onBlockAdded),
                        _addBlockTile(context, "Series descendentes", Icons.trending_down, onBlockAdded),
                        _addBlockTile(context, "Buscar RM", Icons.track_changes, onBlockAdded),
                      ],
                    ),

                    // ---- TAB 2: Bloques guardados ----
                    _SavedBlocksList(onBlockAdded: onBlockAdded),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _addBlockTile(
    BuildContext context, 
    String type, 
    IconData icon,
    Function(Map<String, dynamic>) onBlockAdded,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(type),
      onTap: () async {
        Navigator.pop(context); // Close bottom sheet
        final block = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => AddWorkoutScreen(
              initialBlock: _emptyBlockForType(type),
            ),
          ),
        );
        if (block != null) {
          onBlockAdded(block);
        }
      },
    );
  }

  static Map<String, dynamic> _emptyBlockForType(String type) {
    switch (type) {
      case "Series":
        return {
          "type": "Series",
          "exercises": <Map<String, dynamic>>[],
        };
      case "Circuito":
        return {
          "type": "Circuito",
          "rounds": 3,
          "exercises": <Map<String, dynamic>>[],
        };
      case "Tabata":
        return {
          "type": "Tabata",
          "work": 20,
          "rest": 10,
          "rounds": 8,
          "exercises": <Map<String, dynamic>>[],
        };
      case "Series descendentes":
        return {
          "type": "Series descendentes",
          "schema": [21, 15, 9],
          "exercises": <Map<String, dynamic>>[],
        };
      case "Buscar RM":
        return {
          "type": "Buscar RM",
          "rm": 5,
          "exercises": <Map<String, dynamic>>[],
        };
      default:
        return {
          "type": type,
          "exercises": <Map<String, dynamic>>[],
        };
    }
  }

  static void showRoutineSelectorSheet({
    required BuildContext context,
    required List<Map<String, dynamic>> availableRoutines,
    required Map<String, dynamic>? currentRoutine,
    required Future<bool> Function() onConfirmChange,
    required VoidCallback onFreeWorkoutSelected,
    required Function(Map<String, dynamic>) onRoutineSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "Cambiar entrenamiento",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.fitness_center, color: Colors.tealAccent),
                          ),
                          title: const Text("Entrenamiento libre", style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text("Añade bloques manualmente"),
                          onTap: () async {
                            final ok = await onConfirmChange();
                            if (ok && bottomSheetContext.mounted) {
                              Navigator.pop(bottomSheetContext);
                              onFreeWorkoutSelected();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        if (availableRoutines.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Text(
                              "Mis bloques",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ...availableRoutines.map((r) {
                          final isCurrent = currentRoutine != null && currentRoutine['id'] == r['id'];
                          return ListTile(
                            leading: Icon(
                              Icons.list_alt_rounded,
                              color: isCurrent ? Colors.tealAccent : Colors.grey,
                            ),
                            title: Text(
                              r['name'] ?? 'Rutina',
                              style: TextStyle(
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent ? Colors.tealAccent : null,
                              ),
                            ),
                            onTap: () async {
                              if (isCurrent) {
                                Navigator.pop(bottomSheetContext);
                                return;
                              }
                              final ok = await onConfirmChange();
                              if (ok && bottomSheetContext.mounted) {
                                Navigator.pop(bottomSheetContext);
                                onRoutineSelected(r);
                              }
                            },
                          );
                        }),
                      ],
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
}

// ====================================================
// Widget interno: lista de bloques guardados en Firestore
// ====================================================
class _SavedBlocksList extends StatefulWidget {
  final Function(Map<String, dynamic>) onBlockAdded;
  const _SavedBlocksList({required this.onBlockAdded});

  @override
  State<_SavedBlocksList> createState() => _SavedBlocksListState();
}

class _SavedBlocksListState extends State<_SavedBlocksList> {
  List<Map<String, dynamic>> _blocks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await FirebaseFirestore.instance
        .collection('blocks')
        .orderBy('createdAt', descending: true)
        .get();

    if (mounted) {
      setState(() {
        _blocks = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_blocks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "No tienes bloques guardados.\nCrea uno en la sección Bloques.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _blocks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final b = _blocks[i];
        final title = (b['title'] ?? '').toString().trim();
        final type = (b['type'] ?? 'Bloque').toString();
        final exCount = (b['exercises'] as List?)?.length ?? 0;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.tealAccent.withOpacity(0.15),
            child: const Icon(Icons.fitness_center, color: Colors.tealAccent, size: 20),
          ),
          title: Text(title.isNotEmpty ? title : type),
          subtitle: Text("$type  •  $exCount ejercicios"),
          trailing: const Icon(Icons.add_circle, color: Colors.tealAccent),
          onTap: () {
            Navigator.pop(ctx); // cerrar sheet
            // Pasar una copia del bloque (sin el id de Firestore)
            final blockCopy = Map<String, dynamic>.from(b)
              ..remove('id')
              ..remove('createdAt')
              ..remove('updatedAt')
              ..remove('sourceRoutineId')
              ..remove('sourceRoutineName');
            widget.onBlockAdded(blockCopy);
          },
        );
      },
    );
  }
}
