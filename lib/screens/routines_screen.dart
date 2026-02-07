import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_routine_screen.dart';
import 'routine_details_screen.dart';


class RoutinesScreen extends StatelessWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rutinas")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('routines')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No hay rutinas aún"));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final r = docs[i];
              return ListTile(
                title: Text(r['name']),
                subtitle: Text(r['description'] ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RoutineDetailsScreen(routine: r),
    ),
  );
},

              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddRoutineScreen()),
          );
        },
      ),
    );
  }
}
