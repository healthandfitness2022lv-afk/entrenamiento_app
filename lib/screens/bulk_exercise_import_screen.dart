import 'package:flutter/material.dart';

import '../services/exercise_catalog_service.dart';

class BulkExerciseImportScreen extends StatefulWidget {
  const BulkExerciseImportScreen({super.key});

  @override
  State<BulkExerciseImportScreen> createState() =>
      _BulkExerciseImportScreenState();
}

class _BulkExerciseImportScreenState extends State<BulkExerciseImportScreen> {
  final _controller = TextEditingController(
    text:
        'Movimiento\tVariante\tGrupo\tImplementos\n'
        'Sentadilla\tMáquina Smith\tMáquina\tMáquina Smith\n'
        'Sentadilla\tGoblet con kettlebell\tPeso libre\tKettlebell',
  );
  DuplicateExercisePolicy _policy = DuplicateExercisePolicy.merge;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ExerciseCatalogService.parseTabular(_controller.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Importar movimientos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Pega una fila por variante: Movimiento | Variante | Grupo | Implementos separados por coma.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 9,
            maxLines: 18,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Datos tabulados'),
          ),
          const SizedBox(height: 16),
          SegmentedButton<DuplicateExercisePolicy>(
            segments: const [
              ButtonSegment(
                value: DuplicateExercisePolicy.merge,
                label: Text('Fusionar'),
              ),
              ButtonSegment(
                value: DuplicateExercisePolicy.skip,
                label: Text('Omitir'),
              ),
              ButtonSegment(
                value: DuplicateExercisePolicy.review,
                label: Text('Revisar'),
              ),
            ],
            selected: {_policy},
            onSelectionChanged:
                (value) => setState(() => _policy = value.first),
          ),
          const SizedBox(height: 16),
          Text('Vista previa: ${rows.length} variantes'),
          ...rows
              .take(20)
              .map(
                (row) => ListTile(
                  dense: true,
                  title: Text('${row.movement} - ${row.variant}'),
                  subtitle: Text('${row.group} · ${row.equipment.join(', ')}'),
                ),
              ),
          if (rows.length > 20) Text('y ${rows.length - 20} más...'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _saving || rows.isEmpty ? null : () => _import(rows),
            icon:
                _saving
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.upload_file),
            label: const Text('Importar'),
          ),
        ],
      ),
    );
  }

  Future<void> _import(List<ExerciseImportRow> rows) async {
    setState(() => _saving = true);
    final result = await ExerciseCatalogService().importRows(
      rows,
      duplicatePolicy: _policy,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    final message =
        'Creados: ${result.created} · Fusionados: ${result.merged} '
        '· Omitidos: ${result.skipped}'
        '${result.errors.isEmpty ? '' : ' · Errores: ${result.errors.length}'}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
