import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ExerciseProfileTaggerScreen extends StatefulWidget {
  const ExerciseProfileTaggerScreen({super.key});

  @override
  State<ExerciseProfileTaggerScreen> createState() =>
      _ExerciseProfileTaggerScreenState();
}

class _ExerciseProfileTaggerScreenState
    extends State<ExerciseProfileTaggerScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _showAll = false;
  int _currentIndex = 0;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  String? _resistanceType;
  String? _movementClass;
  bool _isUnilateral = false;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() => _loading = true);
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('exercises')
              .orderBy('name')
              .get();

      final docs =
          snapshot.docs.where((doc) {
            if (doc.data()['mergedInto'] != null) return false;
            if (_showAll) return true;
            final data = doc.data();
            return (data['resistanceType'] ?? '').toString().trim().isEmpty ||
                (data['movementClass'] ?? '').toString().trim().isEmpty ||
                data['isUnilateral'] is! bool;
          }).toList();

      if (!mounted) return;
      setState(() {
        _docs = docs;
        _currentIndex =
            docs.isEmpty ? 0 : _currentIndex.clamp(0, docs.length - 1);
        _loading = false;
      });
      _syncCurrentValues();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando ejercicios: $error')),
      );
    }
  }

  void _syncCurrentValues() {
    if (_docs.isEmpty) return;
    final data = _docs[_currentIndex].data();
    setState(() {
      _resistanceType =
          (data['resistanceType'] ?? '').toString().trim().isEmpty
              ? null
              : (data['resistanceType'] ?? '').toString();
      _movementClass =
          (data['movementClass'] ?? '').toString().trim().isEmpty
              ? null
              : (data['movementClass'] ?? '').toString();
      _isUnilateral = data['isUnilateral'] == true;
    });
  }

  Future<void> _saveCurrent() async {
    if (_docs.isEmpty || _resistanceType == null || _movementClass == null) {
      return;
    }

    setState(() => _saving = true);
    try {
      final doc = _docs[_currentIndex];
      await doc.reference.update({
        'resistanceType': _resistanceType,
        'movementClass': _movementClass,
        'isUnilateral': _isUnilateral,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Etiquetas guardadas'),
          duration: Duration(milliseconds: 900),
        ),
      );

      if (_showAll) {
        setState(() => _saving = false);
        _next();
        return;
      }

      await _loadExercises();
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando etiquetas: $error')),
      );
    }
  }

  void _next() {
    if (_docs.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex + 1).clamp(0, _docs.length - 1);
    });
    _syncCurrentValues();
  }

  void _previous() {
    if (_docs.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex - 1).clamp(0, _docs.length - 1);
    });
    _syncCurrentValues();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = _docs.isEmpty ? null : _docs[_currentIndex];
    final data = doc?.data();
    final equipment = List<String>.from(data?['equipment'] ?? const []);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Etiquetar Perfil'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ver todos',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                Switch(
                  value: _showAll,
                  onChanged: (value) {
                    setState(() => _showAll = value);
                    _loadExercises();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _docs.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    width: 520,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: AppColors.accent,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No quedan ejercicios pendientes de etiquetar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Activa "Ver todos" para revisar el catalogo completo o recarga la lista.',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _showAll = true);
                                _loadExercises();
                              },
                              icon: const Icon(Icons.visibility),
                              label: const Text('Ver todos'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _loadExercises,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Recargar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              : LayoutBuilder(
                builder:
                    (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_currentIndex + 1} / ${_docs.length}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              (data?['name'] ?? '').toString(),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'exerciseType: ${(data?['exerciseType'] ?? '-').toString()}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'equipment: ${equipment.isEmpty ? '-' : equipment.join(', ')}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Tipo de resistencia',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                _choiceChip(
                                  'Libre',
                                  'free',
                                  _resistanceType,
                                  (value) =>
                                      setState(() => _resistanceType = value),
                                ),
                                _choiceChip(
                                  'Guiado',
                                  'guided',
                                  _resistanceType,
                                  (value) =>
                                      setState(() => _resistanceType = value),
                                ),
                                _choiceChip(
                                  'Peso corporal',
                                  'bodyweight',
                                  _resistanceType,
                                  (value) =>
                                      setState(() => _resistanceType = value),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Clase de movimiento',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                _choiceChip(
                                  'Compuesto',
                                  'compound',
                                  _movementClass,
                                  (value) =>
                                      setState(() => _movementClass = value),
                                ),
                                _choiceChip(
                                  'Aislado',
                                  'isolation',
                                  _movementClass,
                                  (value) =>
                                      setState(() => _movementClass = value),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SwitchListTile(
                              value: _isUnilateral,
                              onChanged:
                                  (value) =>
                                      setState(() => _isUnilateral = value),
                              title: const Text(
                                'Es unilateral',
                                style: TextStyle(color: Colors.white),
                              ),
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppColors.accent,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Campos actuales',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'resistanceType: ${(data?['resistanceType'] ?? '-').toString()}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    'movementClass: ${(data?['movementClass'] ?? '-').toString()}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    'isUnilateral: ${(data?['isUnilateral'] ?? '-').toString()}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                OutlinedButton(
                                  onPressed:
                                      _currentIndex > 0 ? _previous : null,
                                  child: const Text('Anterior'),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      _currentIndex < _docs.length - 1
                                          ? _next
                                          : null,
                                  child: const Text('Saltar'),
                                ),
                                ElevatedButton.icon(
                                  onPressed:
                                      _saving ||
                                              _resistanceType == null ||
                                              _movementClass == null
                                          ? null
                                          : _saveCurrent,
                                  icon:
                                      _saving
                                          ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(Icons.save),
                                  label: const Text('Guardar y seguir'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
              ),
    );
  }

  Widget _choiceChip(
    String label,
    String value,
    String? groupValue,
    ValueChanged<String> onSelected,
  ) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: groupValue == value ? Colors.black : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: groupValue == value,
      onSelected: (_) => onSelected(value),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: Colors.white24),
    );
  }
}
