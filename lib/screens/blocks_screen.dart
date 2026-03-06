import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_workout_screen.dart';

class BlocksScreen extends StatefulWidget {
  const BlocksScreen({super.key});

  @override
  State<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends State<BlocksScreen> {
  String? selectedFolder; // null significa "Sin Carpeta" / Raíz

  void _showCreateFolderDialog() {
    final folderCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1B),
        title: const Text("Nueva Carpeta", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: folderCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Nombre de la carpeta",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A2A))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              final name = folderCtrl.text.trim();
              if (name.isNotEmpty) {
                await FirebaseFirestore.instance.collection('block_folders').add({
                  'name': name,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Crear", style: TextStyle(color: Color(0xFF39FF14))),
          ),
        ],
      ),
    );
  }

  void _askBlockType(BuildContext context, {String? defaultFolder}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B1B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Nuevo Bloque", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            _blockTypeTile(context, "Tabata", defaultFolder),
            _blockTypeTile(context, "Circuito", defaultFolder),
            _blockTypeTile(context, "EMOM", defaultFolder),
            _blockTypeTile(context, "Series", defaultFolder),
            _blockTypeTile(context, "Series descendentes", defaultFolder),
            _blockTypeTile(context, "Buscar RM", defaultFolder),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _blockTypeTile(BuildContext context, String type, String? defaultFolder) {
    return ListTile(
      title: Text(type, style: const TextStyle(color: Colors.white)),
      leading: Icon(_getIconForType(type), color: Theme.of(context).primaryColor),
      onTap: () {
        Navigator.pop(context);
        _openBlockEditorWithType(context, type, defaultFolder: defaultFolder);
      },
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case "Tabata": return Icons.timer;
      case "Circuito": return Icons.loop;
      case "EMOM": return Icons.hourglass_top;
      case "Series": return Icons.reorder;
      case "Series descendentes": return Icons.trending_down;
      case "Buscar RM": return Icons.fitness_center;
      default: return Icons.block;
    }
  }

  void _openBlockEditorWithType(BuildContext context, String type, {String? defaultFolder}) async {
    final Map<String, dynamic> base = {
      "type": type, "title": "", "folder": defaultFolder ?? "", "exercises": [],
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
    await FirebaseFirestore.instance.collection('blocks').add({
      ...newBlock, 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _editBlock(BuildContext context, String id, Map<String, dynamic> block) async {
    final updatedBlock = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => AddWorkoutScreen(initialBlock: block)),
    );
    if (updatedBlock == null) return;
    await FirebaseFirestore.instance.collection('blocks').doc(id).update({
      ...updatedBlock, 'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Explorador de Bloques"),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _showCreateFolderDialog,
            tooltip: "Nueva Carpeta",
          ),
        ],
      ),
      body: MultiStreamBuilder(
        streams: [
          FirebaseFirestore.instance.collection('block_folders').orderBy('name').snapshots(),
          FirebaseFirestore.instance.collection('blocks').orderBy('createdAt', descending: true).snapshots(),
        ],
        builder: (context, snapshots) {
          final folderDocs = snapshots[0].data?.docs ?? [];
          final blockDocs = snapshots[1].data?.docs ?? [];

          // Procesar datos
          final Set<String> allFolderNames = folderDocs.map((d) => (d.data() as Map)['name'] as String).toSet();
          final Map<String, List<QueryDocumentSnapshot>> folderToBlocks = {};
          final List<QueryDocumentSnapshot> unorganizedBlocks = [];

          for (final doc in blockDocs) {
            final folder = (doc.data() as Map<String, dynamic>)['folder']?.toString().trim() ?? '';
            if (folder.isEmpty) {
              unorganizedBlocks.add(doc);
            } else {
              folderToBlocks.putIfAbsent(folder, () => []).add(doc);
              allFolderNames.add(folder); // Asegurar que carpetas con bloques pero sin doc en block_folders existan
            }
          }

          final sortedFolders = allFolderNames.toList()..sort();

          return Row(
            children: [
              // ── SIDEBAR (Carpetas) ──────────────────────────────
              Container(
                width: 140,
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0A0A),
                  border: Border(right: BorderSide(color: Color(0xFF1B1B1B))),
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    _sidebarItem(null, "Sin carpeta", unorganizedBlocks.length),
                    const Divider(color: Color(0xFF1B1B1B), height: 20),
                    ...sortedFolders.map((f) => _sidebarItem(f, f, folderToBlocks[f]?.length ?? 0)),
                  ],
                ),
              ),

              // ── CONTENT AREA (Bloques) ──────────────────────────
              Expanded(
                child: Container(
                  color: const Color(0xFF121212),
                  child: _buildContent(selectedFolder == null ? unorganizedBlocks : (folderToBlocks[selectedFolder!] ?? [])),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _askBlockType(context, defaultFolder: selectedFolder),
      ),
    );
  }

  Widget _sidebarItem(String? id, String name, int count) {
    final isSelected = selectedFolder == id;
    return DragTarget<String>(
      onAccept: (blockId) async {
        await FirebaseFirestore.instance.collection('blocks').doc(blockId).update({'folder': id ?? ""});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Movido a ${id ?? 'Raíz'}"), duration: const Duration(milliseconds: 500)));
      },
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        return InkWell(
          onTap: () => setState(() => selectedFolder = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: isOver ? Theme.of(context).primaryColor.withOpacity(0.1) : (isSelected ? const Color(0xFF1B1B1B) : Colors.transparent),
              border: Border(left: BorderSide(color: isSelected ? Theme.of(context).primaryColor : Colors.transparent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  id == null ? Icons.folder_open : Icons.folder,
                  color: isSelected || isOver ? Theme.of(context).primaryColor : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.grey[400],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text("$count items", style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(List<QueryDocumentSnapshot> blocks) {
    if (blocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[800]),
            const SizedBox(height: 12),
            const Text("Vacío", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length,
      itemBuilder: (context, i) => _draggableBlock(blocks[i]),
    );
  }

  Widget _draggableBlock(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Sin título';
    final type = data['type'] ?? 'Bloque';

    return LongPressDraggable<String>(
      data: doc.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1B).withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).primaryColor),
          ),
          child: Text(title.isNotEmpty ? title : type, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _blockTile(doc)),
      child: _blockTile(doc),
    );
  }

  Widget _blockTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Sin título';
    final type = data['type'] ?? 'Bloque';
    final List exercises = data['exercises'] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF1B1B1B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          backgroundColor: const Color(0xFF1B1B1B),
          collapsedBackgroundColor: const Color(0xFF1B1B1B),
          leading: Icon(_getIconForType(type), color: Theme.of(context).primaryColor.withOpacity(0.7), size: 24),
          title: Text(
            title.isNotEmpty ? title : type,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
          ),
          subtitle: Text(
            "$type • ${exercises.length} ej.",
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.edit_note_rounded, size: 22, color: Theme.of(context).primaryColor),
                onPressed: () => _editBlock(context, doc.id, data),
                tooltip: "Editar bloque",
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                onPressed: () => _showDeleteConfirm(context, doc.id),
              ),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Color(0xFF2A2A2A), height: 1),
                  const SizedBox(height: 8),
                  ...exercises.map((e) {
                    final eName = e['name'] ?? 'Ejercicio';
                    final series = e['series'];
                    final reps = e['value'];
                    final valType = e['valueType'] == 'time' ? 'seg' : 'reps';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 12, color: Theme.of(context).primaryColor.withOpacity(0.5)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "$eName ${series != null ? '${series}x' : ''}$reps $valType",
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1B),
        title: const Text("Eliminar bloque", style: TextStyle(color: Colors.white)),
        content: const Text("¿Estás seguro de que quieres borrar este bloque?", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection('blocks').doc(id).delete();
              Navigator.pop(ctx);
            }, 
            child: const Text("Eliminar", style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );
  }
}

class MultiStreamBuilder extends StatelessWidget {
  final List<Stream<QuerySnapshot>> streams;
  final Widget Function(BuildContext context, List<AsyncSnapshot<QuerySnapshot>>) builder;
  const MultiStreamBuilder({super.key, required this.streams, required this.builder});

  @override
  Widget build(BuildContext context) {
    return _build(context, streams, []);
  }

  Widget _build(BuildContext context, List<Stream<QuerySnapshot>> remaining, List<AsyncSnapshot<QuerySnapshot>> snapshots) {
    if (remaining.isEmpty) return builder(context, snapshots);
    return StreamBuilder<QuerySnapshot>(
      stream: remaining.first,
      builder: (context, snapshot) => _build(context, remaining.sublist(1), [...snapshots, snapshot]),
    );
  }
}
