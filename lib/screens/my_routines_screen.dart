import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyRoutinesScreen extends StatelessWidget {
  const MyRoutinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Mis Rutinas")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('routine_assignments')
            .where('athleteId', isEqualTo: uid)
            .where('status', isEqualTo: 'active')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No tienes rutinas asignadas"));
          }

          return ListView(
            children: snapshot.data!.docs.map((assignment) {
              final routineId = assignment['routineId'];

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('routines')
                    .doc(routineId)
                    .get(),
                builder: (context, routineSnapshot) {
                  if (!routineSnapshot.hasData) {
                    return const ListTile(
                        title: Text("Cargando rutina..."));
                  }

                 final routineDoc = routineSnapshot.data!;

if (!routineDoc.exists) {
  return const SizedBox(); // o un mensaje si quieres
}

final routine = routineDoc.data() as Map<String, dynamic>;

return Card(
  child: ListTile(
    title: Text(routine['name'] ?? 'Rutina sin nombre'),
    subtitle: Text(routine['description'] ?? ''),
    trailing: const Icon(Icons.fitness_center),
  ),
);

                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
