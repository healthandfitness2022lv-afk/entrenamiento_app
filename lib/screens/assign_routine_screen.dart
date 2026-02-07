import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AssignRoutineScreen extends StatefulWidget {
  const AssignRoutineScreen({super.key});

  @override
  State<AssignRoutineScreen> createState() => _AssignRoutineScreenState();
}

class _AssignRoutineScreenState extends State<AssignRoutineScreen> {
  String? selectedRoutineId;
  String? selectedAthleteId;

  Future<void> _assignRoutine() async {
    if (selectedRoutineId == null || selectedAthleteId == null) return;

    final adminUid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection('routine_assignments')
        .add({
      'routineId': selectedRoutineId,
      'athleteId': selectedAthleteId,
      'assignedBy': adminUid,
      'startDate': Timestamp.now(),
      'status': 'active',
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Rutina asignada correctamente")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Asignar Rutina")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// 🔹 Rutinas
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('routines')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                return DropdownButtonFormField<String>(
                  decoration:
                      const InputDecoration(labelText: "Seleccionar rutina"),
                  items: snapshot.data!.docs.map((doc) {
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(doc['name']),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedRoutineId = value);
                  },
                );
              },
            ),

            const SizedBox(height: 20),

            /// 🔹 Atletas
            StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection('users')
      .where(
        'role',
        whereIn: ['atleta', 'administrador'],
      )
      .snapshots(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) {
      return const CircularProgressIndicator();
    }

    return DropdownButtonFormField<String>(
      decoration:
          const InputDecoration(labelText: "Seleccionar atleta"),
      items: snapshot.data!.docs.map((doc) {
        return DropdownMenuItem(
          value: doc.id,
          child: Text(
            doc.id == FirebaseAuth.instance.currentUser!.uid
                ? "${doc['name']} (Yo)"
                : doc['name'],
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() => selectedAthleteId = value);
      },
    );
  },
),


            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _assignRoutine,
              child: const Text("Asignar Rutina"),
            ),
          ],
        ),
      ),
    );
  }
}
