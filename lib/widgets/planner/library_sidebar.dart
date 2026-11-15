import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../screens/add_workout_screen.dart';
import '../../utils/block_title_utils.dart';
import '../../theme/app_theme.dart';
import '../../utils/responsive.dart';

/// Accepts both native Firestore timestamps and ISO strings written by older
/// migration/import scripts when ordering library folders.
int _libraryTimestampMillis(dynamic value) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is num) return value.toInt();
  if (value is String) {
    return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}

DateTime? _libraryDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

class LibrarySidebar extends StatefulWidget {
  final Function(Map<String, dynamic> block) onBlockSelected;
  final Function(String blockId, Map<String, dynamic> blockData) onEditBlock;
  final Future<void> Function(String blockId, Map<String, dynamic> blockData)
  onDeleteBlock;
  final String? athleteId;
  final DateTime selectedDay;

  const LibrarySidebar({
    super.key,
    required this.onBlockSelected,
    required this.onEditBlock,
    required this.onDeleteBlock,
    this.athleteId,
    required this.selectedDay,
  });

  @override
  State<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends State<LibrarySidebar> {
  String? selectedFolder; // null = Raíz / Sin carpeta
  String searchQuery = "";
  final Set<String> _duplicateCleanupKeys = <String>{};

  String _fingerprint(Map<String, dynamic> data) {
    dynamic clean(dynamic value) {
      if (value is Map) {
        const ignored = {
          'id',
          'instanceId',
          'exerciseId',
          'createdAt',
          'updatedAt',
          'libraryOrder',
          'sourceBlockId',
          'sourceMesocycleId',
        };
        final entries =
            value.entries
                .where((entry) => !ignored.contains(entry.key.toString()))
                .map(
                  (entry) => MapEntry(entry.key.toString(), clean(entry.value)),
                )
                .toList()
              ..sort((a, b) => a.key.compareTo(b.key));
        return Map.fromEntries(entries);
      }
      if (value is List) return value.map(clean).toList();
      return value;
    }

    return jsonEncode(clean(data));
  }

  void _cleanupDuplicateBlocks(
    List<QueryDocumentSnapshot> docs,
    Map<String, int> usage,
  ) {
    final groups = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      groups
          .putIfAbsent(
            _fingerprint(doc.data() as Map<String, dynamic>),
            () => [],
          )
          .add(doc);
    }
    for (final entry in groups.entries) {
      if (entry.value.length < 2 || _duplicateCleanupKeys.contains(entry.key))
        continue;
      _duplicateCleanupKeys.add(entry.key);
      final sorted = [...entry.value]..sort((a, b) {
        final usageDiff = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
        return usageDiff != 0 ? usageDiff : b.id.compareTo(a.id);
      });
      for (final duplicate in sorted.skip(1)) {
        if ((usage[duplicate.id] ?? 0) == 0) {
          FirebaseFirestore.instance
              .collection('blocks')
              .doc(duplicate.id)
              .delete();
        }
      }
    }
  }

  void _showCreateFolderDialog() {
    final folderCtrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              "Nueva Carpeta",
              style: TextStyle(color: Colors.white),
            ),
            content: TextField(
              controller: folderCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Nombre de la carpeta",
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.divider),
                ),
              ),
              autofocus: true,
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
                  final name = folderCtrl.text.trim();
                  if (name.isNotEmpty) {
                    await FirebaseFirestore.instance
                        .collection('block_folders')
                        .add({
                          'name': name,
                          'order': DateTime.now().millisecondsSinceEpoch,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                    Navigator.pop(ctx);
                  }
                },
                child: const Text(
                  "Crear",
                  style: TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
    );
  }

  void _askBlockType(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "Nuevo Bloque",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                _blockTypeTile(context, "Tabata"),
                _blockTypeTile(context, "Circuito"),
                _blockTypeTile(context, "EMOM"),
                _blockTypeTile(context, "Series"),
                _blockTypeTile(context, "Series descendentes"),
                _blockTypeTile(context, "Buscar RM"),
                const SizedBox(height: 12),
              ],
            ),
          ),
    );
  }

  Widget _blockTypeTile(BuildContext context, String type) {
    return ListTile(
      title: Text(type, style: const TextStyle(color: Colors.white)),
      leading: Icon(
        _getIconForType(type),
        color: Theme.of(context).primaryColor,
      ),
      onTap: () {
        Navigator.pop(context);
        _openBlockEditorWithType(context, type);
      },
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case "Tabata":
        return Icons.timer;
      case "Circuito":
        return Icons.loop;
      case "EMOM":
        return Icons.hourglass_top;
      case "Series":
        return Icons.reorder;
      case "Series descendentes":
        return Icons.trending_down;
      case "Buscar RM":
        return Icons.fitness_center;
      default:
        return Icons.block;
    }
  }

  void _openBlockEditorWithType(BuildContext context, String type) async {
    final Map<String, dynamic> base = {
      "type": type,
      "title": "",
      "folder": selectedFolder ?? "",
      "exercises": [],
      "athleteId": widget.athleteId, // Pasar el atleta actual como sugerencia
    };
    if (type == "Series descendentes") base["schema"] = [21, 15, 9];
    if (type == "Buscar RM") base["rm"] = 5;
    if (type == "Circuito") base["rounds"] = 3;
    if (type == "Tabata") base.addAll({"work": 20, "rest": 10, "rounds": 8});

    final newBlock = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => AddWorkoutScreen(initialBlock: base)),
    );
    if (newBlock == null) return;

    // Si estamos en la vista de un atleta específico, guardamos el bloque para él por defecto,
    // a menos que el editor permita marcarlo como general (se implementará en AddWorkoutScreen).
    await FirebaseFirestore.instance.collection('blocks').add({
      ...newBlock,
      'athleteId': newBlock['athleteId'], // Mantiene lo que venga del editor
      'isLibraryTemplate': true,
      'libraryOrder': DateTime.now().millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _showBlockPreview(Map<String, dynamic> data) {
    final title = visibleBlockTitle(data['title']);
    final type = data['type'] ?? "Bloque";
    final List exercises = data['exercises'] ?? [];

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              title.isNotEmpty ? title : type,
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Tipo: $type",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const Divider(color: AppColors.divider, height: 20),
                  ...exercises.map((e) {
                    final name = e['name'] ?? 'Ejercicio';
                    final sets = e['series'];
                    final val = e['value'];
                    final unit = e['valueType'] == 'time' ? 'seg' : 'reps';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        "• $name ${sets != null ? '${sets}x' : ''}$val $unit",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onBlockSelected(data);
                },
                // Muestra el día destino: en celular la biblioteca tapa el
                // calendario y no se veía a qué día iba el bloque.
                child: Text(
                  "Planificar el ${DateFormat('EEE d MMM', 'es_ES').format(widget.selectedDay)}",
                  style: const TextStyle(color: AppColors.accent),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cerrar",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.bgDeep),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "BIBLIOTECA",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.create_new_folder_outlined,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: _showCreateFolderDialog,
                  tooltip: "Nueva carpeta",
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_box_outlined,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  onPressed: () => _askBlockType(context),
                  tooltip: "Nuevo bloque",
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Buscar bloque o ejercicio...",
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.grey,
                  size: 16,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged:
                  (val) => setState(() => searchQuery = val.toLowerCase()),
            ),
          ),

          const SizedBox(height: 8),

          // Folders & Blocks List (Horizontal Split)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('block_folders')
                      .snapshots(),
              builder: (context, folderSnap) {
                final startOfWeek = widget.selectedDay.subtract(
                  Duration(days: widget.selectedDay.weekday - 1),
                );
                final endOfWeek = startOfWeek.add(const Duration(days: 7));

                return StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('planned_workouts')
                          .snapshots(),
                  builder: (context, plannedSnap) {
                    final plannedBlockCounts = <String, int>{};
                    for (final document in plannedSnap.data?.docs ?? const []) {
                      final data = document.data() as Map<String, dynamic>;
                      final plannedDate = _libraryDateTime(data['date']);
                      final weekStart = DateTime(
                        startOfWeek.year,
                        startOfWeek.month,
                        startOfWeek.day,
                      );
                      final weekEnd = DateTime(
                        endOfWeek.year,
                        endOfWeek.month,
                        endOfWeek.day,
                      );
                      if (plannedDate == null ||
                          plannedDate.isBefore(weekStart) ||
                          !plannedDate.isBefore(weekEnd)) {
                        continue;
                      }
                      final owner =
                          (data['athleteId'] ??
                                  data['userId'] ??
                                  data['contextAthleteId'])
                              ?.toString();
                      if (widget.athleteId != null &&
                          owner != null &&
                          owner != widget.athleteId) {
                        continue;
                      }
                      final ids = <String>{
                        data['blockId']?.toString() ?? '',
                        data['sourceBlockId']?.toString() ?? '',
                        data['libraryBlockId']?.toString() ?? '',
                        data['templateId']?.toString() ?? '',
                      }..removeWhere((id) => id.isEmpty);
                      for (final id in ids) {
                        plannedBlockCounts[id] =
                            (plannedBlockCounts[id] ?? 0) + 1;
                      }
                    }

                    return StreamBuilder<QuerySnapshot>(
                      stream:
                          FirebaseFirestore.instance
                              .collection('blocks')
                              .snapshots(),
                      builder: (context, blockSnap) {
                        final folderDocs = [
                          ...(folderSnap.data?.docs ?? const []),
                        ]..sort((a, b) {
                          final ad = a.data() as Map<String, dynamic>;
                          final bd = b.data() as Map<String, dynamic>;
                          final ao =
                              (ad['order'] as num?)?.toInt() ??
                              _libraryTimestampMillis(ad['createdAt']);
                          final bo =
                              (bd['order'] as num?)?.toInt() ??
                              _libraryTimestampMillis(bd['createdAt']);
                          return ao.compareTo(bo);
                        });
                        final rawBlockDocs = blockSnap.data?.docs ?? [];

                        // La biblioteca contiene solo plantillas explícitas.
                        // Los bloques de un mesociclo permanecen en Firestore
                        // para que las planificaciones existentes no pierdan
                        // sus referencias, pero no se muestran como plantillas.
                        final blockDocs =
                            rawBlockDocs.where((doc) {
                              final d = doc.data() as Map<String, dynamic>;
                              final bAthleteId = d['athleteId'];
                              final isPlanned = plannedBlockCounts.containsKey(
                                doc.id,
                              );
                              return (d['isLibraryTemplate'] != false ||
                                      isPlanned) &&
                                  (bAthleteId == null ||
                                      bAthleteId == widget.athleteId);
                            }).toList();
                        _cleanupDuplicateBlocks(blockDocs, plannedBlockCounts);

                        // Filter logic
                        final filteredBlocks =
                            blockDocs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final title =
                                    (data['title'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                final type =
                                    (data['type'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                final folder = data['folder'] ?? "";
                                final List exercises = data['exercises'] ?? [];

                                final matchesSearch =
                                    title.contains(searchQuery) ||
                                    type.contains(searchQuery) ||
                                    exercises.any(
                                      (e) => (e['name'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .contains(searchQuery),
                                    );

                                final matchesFolder =
                                    selectedFolder == null
                                        ? folder == ""
                                        : folder == selectedFolder;

                                return matchesSearch && matchesFolder;
                              }).toList()
                              ..sort((a, b) {
                                final aData = a.data() as Map<String, dynamic>;
                                final bData = b.data() as Map<String, dynamic>;
                                final aOrder =
                                    (aData['libraryOrder'] as num?)?.toInt() ??
                                    9999;
                                final bOrder =
                                    (bData['libraryOrder'] as num?)?.toInt() ??
                                    9999;
                                return aOrder.compareTo(bOrder);
                              });

                        final blockList = ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: filteredBlocks.length,
                          itemBuilder: (_, i) {
                            final doc = filteredBlocks[i];
                            final data = doc.data() as Map<String, dynamic>;
                            final plannedCount =
                                plannedBlockCounts[doc.id] ?? 0;

                            return _LibraryBlockTile(
                              docId: doc.id,
                              data: data,
                              plannedCount: plannedCount,
                              onTap: () => _showBlockPreview(data),
                              onEdit: () => widget.onEditBlock(doc.id, data),
                              onDelete:
                                  () => widget.onDeleteBlock(doc.id, data),
                              icon: _getIconForType(data['type'] ?? ""),
                            );
                          },
                        );
                        final folderItems = [
                          _folderItem(null, "Raíz"),
                          ...folderDocs.map(
                            (f) => _folderItem(f['name'], f['name']),
                          ),
                        ];

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            // Angosto (celular): carpetas en una tira
                            // horizontal arriba. Con la columna fija de 120 px
                            // a los bloques les quedaba tan poco ancho que el
                            // título medía 11 px y el candado se desbordaba.
                            if (constraints.maxWidth < 420) {
                              return Column(
                                children: [
                                  SizedBox(
                                    height: 64,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      children: [
                                        for (final item in folderItems)
                                          SizedBox(width: 104, child: item),
                                      ],
                                    ),
                                  ),
                                  const Divider(
                                    height: 1,
                                    color: AppColors.surface,
                                  ),
                                  Expanded(child: blockList),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                // Sidebar de Carpetas
                                Container(
                                  width: 120,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                        color: AppColors.surface,
                                      ),
                                    ),
                                  ),
                                  child: ListView(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    children: [
                                      folderItems.first,
                                      const Divider(color: AppColors.surface),
                                      ...folderItems.skip(1),
                                    ],
                                  ),
                                ),

                                // Lista de Bloques
                                Expanded(child: blockList),
                              ],
                            );
                          },
                        );
                      },
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

  Widget _folderItem(String? id, String name) {
    final isSelected = selectedFolder == id;
    return DragTarget<Map<String, dynamic>>(
      onWillAccept: (data) => data != null && data['id'] != null,
      onAccept: (data) async {
        final blockId = data['id'];
        final newFolderName = id ?? ""; // null = Raíz (sin carpeta)

        await FirebaseFirestore.instance
            .collection('blocks')
            .doc(blockId)
            .update({'folder': newFolderName});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Bloque movido a $name"),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return InkWell(
          onTap: () => setState(() => selectedFolder = id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color:
                  isHovering
                      ? AppColors.info.withOpacity(0.1)
                      : (isSelected ? AppColors.surface : Colors.transparent),
              border: Border(
                left: BorderSide(
                  color:
                      isHovering
                          ? AppColors.info
                          : (isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.transparent),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  id == null ? Icons.folder_open : Icons.folder,
                  color:
                      isHovering
                          ? AppColors.info
                          : (isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey[600]),
                  size: 18,
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected || isHovering
                            ? FontWeight.bold
                            : FontWeight.normal,
                    color:
                        isSelected || isHovering
                            ? Colors.white
                            : Colors.grey[400],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LibraryBlockTile extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final int plannedCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final IconData icon;

  const _LibraryBlockTile({
    required this.docId,
    required this.data,
    required this.plannedCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.icon,
  });

  /// Editar/borrar: dos íconos en pantallas anchas; en celular un solo menú ⋮
  /// para dejarle ancho al título.
  Widget _actions(BuildContext context) {
    if (context.isCompact) {
      return PopupMenuButton<String>(
        tooltip: 'Opciones del bloque',
        icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
        onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
        itemBuilder:
            (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Editar'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Borrar'),
                ),
              ),
            ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Editar bloque',
          icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
          onPressed: onEdit,
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Borrar bloque',
          icon: const Icon(
            Icons.delete_outline,
            size: 18,
            color: Colors.redAccent,
          ),
          onPressed: onDelete,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPlanned = plannedCount > 0;
    final title = visibleBlockTitle(data['title']);
    final type = data['type'] ?? "Bloque";
    final List exercises = data['exercises'] ?? [];

    return Draggable<Map<String, dynamic>>(
      data: {...data, 'id': docId},
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).primaryColor),
          ),
          child: Text(
            title.isNotEmpty ? title : type,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
      child: Stack(
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: const Color(0xFF141414),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color:
                    isPlanned
                        ? Theme.of(context).primaryColor.withOpacity(0.5)
                        : AppColors.surface,
                width: isPlanned ? 1.5 : 1,
              ),
            ),
            child: ListTile(
              onTap: onTap,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              leading: Icon(
                icon,
                color: Theme.of(context).primaryColor.withOpacity(0.5),
                size: 18,
              ),
              // Candado dentro del texto (no en un Row): así nunca desborda,
              // aunque el título quede muy angosto.
              title: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: title.isNotEmpty ? title : type),
                    if (data['athleteId'] != null)
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.lock,
                            size: 10,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                "$type • ${exercises.length} ej.",
                style: const TextStyle(color: Colors.grey, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _actions(context),
            ),
          ),
          if (isPlanned)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: Text(
                  plannedCount > 1 ? "USADO · $plannedCount" : "USADO",
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
