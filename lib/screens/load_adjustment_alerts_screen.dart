import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/load_adjustment_alert_service.dart';

class LoadAdjustmentAlertsScreen extends StatelessWidget {
  const LoadAdjustmentAlertsScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
  });

  final String athleteId;
  final String athleteName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ajustes de carga · $athleteName')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('load_adjustment_alerts')
                .where('athleteId', isEqualTo: athleteId)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final documents =
              snapshot.data!.docs.toList()..sort((a, b) {
                final ad =
                    (a.data()['workoutDate'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
                final bd =
                    (b.data()['workoutDate'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
                return bd.compareTo(ad);
              });
          if (documents.isEmpty) {
            return const Center(
              child: Text('No hay ajustes de carga para revisar.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: documents.length,
            itemBuilder: (_, index) => _AlertCard(document: documents[index]),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatefulWidget {
  const _AlertCard({required this.document});

  final QueryDocumentSnapshot<Map<String, dynamic>> document;

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _saving = false;

  Future<void> _dismiss(String resolution) async {
    setState(() => _saving = true);
    await widget.document.reference.update({
      'status': 'dismissed',
      'resolution': resolution,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _apply({double? kg, double? percent}) async {
    setState(() => _saving = true);
    final changed = await LoadAdjustmentAlertService.applyToFuture(
      alertRef: widget.document.reference,
      customDeltaKg: kg,
      customDeltaPercent: percent == null ? null : percent / 100,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$changed sesiones futuras actualizadas.')),
    );
  }

  Future<void> _customAdjustment() async {
    final controller = TextEditingController();
    var unit = 'kg';
    final result = await showDialog<(double, String)>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (_, setDialogState) => AlertDialog(
                  title: const Text('Ajuste personalizado'),
                  content: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Diferencia desde la próxima sesión',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: unit,
                        items: const [
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
                          DropdownMenuItem(value: '%', child: Text('%')),
                        ],
                        onChanged:
                            (value) =>
                                setDialogState(() => unit = value ?? 'kg'),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final value = double.tryParse(
                          controller.text.replaceAll(',', '.'),
                        );
                        if (value != null) {
                          Navigator.pop(dialogContext, (value, unit));
                        }
                      },
                      child: const Text('Aplicar'),
                    ),
                  ],
                ),
          ),
    );
    controller.dispose();
    if (result == null) return;
    await _apply(
      kg: result.$2 == 'kg' ? result.$1 : null,
      percent: result.$2 == '%' ? result.$1 : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.document.data();
    final status = data['status']?.toString() ?? 'pending';
    final direction = data['direction']?.toString();
    final comparisons = List<Map<String, dynamic>>.from(
      data['comparisons'] ?? const [],
    );
    final suggested =
        ((data['suggestedDeltaRatio'] as num?)?.toDouble() ?? 0) * 100;
    final date = (data['workoutDate'] as Timestamp?)?.toDate();
    final pending = status == 'pending';
    final highPriority = data['priority'] == 'high';
    final statusLabel = switch (status) {
      'applied' => 'APLICADA',
      'dismissed' => 'DESCARTADA',
      _ => 'PENDIENTE',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          direction == 'lower'
              ? Icons.trending_down
              : direction == 'higher'
              ? Icons.trending_up
              : Icons.swap_vert,
          color: direction == 'lower' ? Colors.orange : Colors.teal,
        ),
        title: Text(data['exerciseName']?.toString() ?? 'Ejercicio'),
        subtitle: Text(
          '${data['blockTitle'] ?? 'Bloque'} · ${date == null ? '' : '${date.day}/${date.month}/${date.year}'}'
          '${data['isTrend'] == true ? ' · TENDENCIA' : ''}',
        ),
        trailing: Chip(label: Text(statusLabel)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          for (final comparison in comparisons)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Serie ${(comparison['setIndex'] as num).toInt() + 1}',
              ),
              subtitle: Text(
                '${comparison['plannedWeight']} kg planificados → '
                '${comparison['actualWeight']} kg realizados · '
                'RPE ${comparison['rpe'] ?? '—'}',
              ),
              trailing: Text(
                '${(comparison['deltaKg'] as num).toDouble().toStringAsFixed(1)} kg',
              ),
            ),
          if (data['reason'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Motivo: ${_reasonLabel(data['reason'].toString())}',
                  style: TextStyle(
                    color: highPriority ? Colors.redAccent : Colors.grey,
                    fontWeight:
                        highPriority ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          if (pending) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!highPriority)
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _apply(),
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(
                      'Aplicar sugerencia ${suggested >= 0 ? '+' : ''}${suggested.toStringAsFixed(1)}%',
                    ),
                  ),
                OutlinedButton(
                  onPressed: _saving ? null : _customAdjustment,
                  child: const Text('Ajuste personalizado'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _dismiss('cambio_puntual'),
                  child: const Text('Descartar'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _dismiss('intencional'),
                  child: const Text('Marcar intencional'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _reasonLabel(String reason) {
    return switch (reason) {
      'muy_pesado' => 'Estaba muy pesado',
      'muy_liviano' => 'Estaba muy liviano',
      'equipo_distinto' => 'Máquina o discos diferentes',
      'dolor_molestia' => 'Dolor o molestia',
      _ => 'Otro motivo',
    };
  }
}
