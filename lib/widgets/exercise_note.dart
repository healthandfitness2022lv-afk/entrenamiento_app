import 'package:flutter/material.dart';

/// Nota del coach para un ejercicio puntual del bloque (campo `notes`).
class ExerciseNote extends StatelessWidget {
  final dynamic note;
  final EdgeInsetsGeometry padding;

  const ExerciseNote(
    this.note, {
    super.key,
    this.padding = const EdgeInsets.only(top: 6),
  });

  static bool hasNote(dynamic note) =>
      (note ?? '').toString().trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final text = (note ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.amber.withOpacity(.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.sticky_note_2_outlined,
              size: 14,
              color: Colors.amber,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
