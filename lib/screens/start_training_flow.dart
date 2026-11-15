import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/planned_routine_loader_service.dart';
import 'log_workout_screen.dart';
import 'planned_day_preview_screen.dart';

/// Flujo del botón "Entrenar" (FAB del inicio en celular y botón del menú
/// lateral en tablet/PC): si el atleta tiene días planificados abre la vista
/// previa del día (hoy, o el primero disponible); si no, un entrenamiento
/// libre. Completa cuando el usuario vuelve de esa pantalla.
///
/// [navigator] permite abrirlo en el navegador raíz para que la sesión ocupe
/// toda la pantalla (sin el menú lateral) aunque se llame desde una pestaña.
Future<void> startTrainingFlow(
  BuildContext context, {
  NavigatorState? navigator,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final nav = navigator ?? Navigator.of(context);

  final snapshot = await FirebaseFirestore.instance
      .collection('planned_workouts')
      .where('athleteId', isEqualTo: uid)
      .get(const GetOptions(source: Source.server));
  if (!nav.mounted) return;

  DateTime dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  final daysByKey = <String, DateTime>{};
  for (final doc in snapshot.docs) {
    final date = PlannedRoutineLoaderService.dateTimeValue(doc.data()['date']);
    if (date == null) continue;
    final day = dayOnly(date);
    daysByKey['${day.year}-${day.month}-${day.day}'] = day;
  }
  final days = daysByKey.values.toList()..sort();

  if (days.isEmpty) {
    await nav.push(
      MaterialPageRoute(
        builder: (_) => const LogWorkoutScreen(initialDate: null),
      ),
    );
    return;
  }

  final today = dayOnly(DateTime.now());
  await nav.push(
    MaterialPageRoute(
      builder:
          (_) => PlannedDayPreviewScreen(
            availableDays: days,
            initialDay: days.contains(today) ? today : days.first,
          ),
    ),
  );
}
