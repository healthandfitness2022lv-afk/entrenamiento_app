import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/exercise.dart';

/// Central configuration for the movements that receive a planned overload
/// progression in the mesocycle PDF.
class OverloadProgressionConfigScreen extends StatefulWidget {
  const OverloadProgressionConfigScreen({super.key});

  @override
  State<OverloadProgressionConfigScreen> createState() =>
      _OverloadProgressionConfigScreenState();
}

class _OverloadProgressionConfigScreenState
    extends State<OverloadProgressionConfigScreen> {
  String _query = '';
  final Set<String> _saving = {};

  Future<void> _setTracked(
    Exercise exercise,
    ExerciseVariant target,
    bool enabled,
  ) async {
    final key = '${exercise.id}:${target.id}';
    setState(() => _saving.add(key));
    try {
      final variants =
          exercise.variants.map((variant) {
            final data = variant.toMap();
            if (variant.id == target.id) data['trackProgression'] = enabled;
            return data;
          }).toList();
      await FirebaseFirestore.instance
          .collection('exercises')
          .doc(exercise.id)
          .update({
            'variants': variants,
            'trackProgression': variants.any(
              (variant) => variant['trackProgression'] == true,
            ),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar la configuración: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Compatibilidad de progresión')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar movimiento o variante',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'La progresión se decide dentro de Planificación según el objetivo del atleta. '
              'Esta marca se conserva únicamente para compatibilidad con planes antiguos.',
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance
                      .collection('exercises')
                      .orderBy('name')
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = <(Exercise, ExerciseVariant)>[];
                for (final document in snapshot.data!.docs) {
                  if (document.data()['mergedInto'] != null) continue;
                  final exercise = Exercise.fromFirestore(
                    document.data(),
                    id: document.id,
                  );
                  for (final variant in exercise.variants) {
                    final searchable =
                        '${exercise.name} ${variant.label} '
                                '${variant.equipment.join(' ')}'
                            .toLowerCase();
                    if (normalizedQuery.isEmpty ||
                        searchable.contains(normalizedQuery)) {
                      entries.add((exercise, variant));
                    }
                  }
                }
                if (entries.isEmpty) {
                  return const Center(
                    child: Text('Sin variantes coincidentes.'),
                  );
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final (exercise, variant) = entries[index];
                    final key = '${exercise.id}:${variant.id}';
                    final saving = _saving.contains(key);
                    return SwitchListTile(
                      value: variant.trackProgression,
                      onChanged:
                          saving
                              ? null
                              : (value) =>
                                  _setTracked(exercise, variant, value),
                      title: Text(variant.displayName(exercise.name)),
                      subtitle: Text(
                        [variant.group, ...variant.equipment].join(' · '),
                      ),
                      secondary:
                          saving
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : Icon(
                                Icons.trending_up,
                                color:
                                    variant.trackProgression
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey,
                              ),
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
}
