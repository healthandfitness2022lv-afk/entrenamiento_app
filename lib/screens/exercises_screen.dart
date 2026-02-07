import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/exercise.dart';
import '../models/muscle_catalog.dart';
import '../utils/exercise_catalogs.dart';
import 'exercise_detail_screen.dart';
import 'add_exercise_screen.dart';

class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  String _selectedEquipment = "Todos";
  Muscle? _selectedMuscle; // null = Todos

  final List<String> _types = [
    "Todos",
    ...exerciseTypeCatalog,
  ];

  Stream<QuerySnapshot> _exerciseStream() {
    return FirebaseFirestore.instance
        .collection('exercises')
        .orderBy('name')
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _types.length, vsync: this);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
  }

  Future<void> _toggleTrackRM(Exercise exercise) async {
    await FirebaseFirestore.instance
        .collection('exercises')
        .doc(exercise.id)
        .update({
      'trackRM': !exercise.trackRM,
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ===============================
            // 🏷️ TABS + FILTRO MÚSCULO
            // ===============================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabs: _types.map((t) => Tab(text: t)).toList(),
                    ),
                  ),

                  const SizedBox(width: 6),

                  PopupMenuButton<Muscle?>(
                    tooltip: "Filtrar por músculo",
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.fitness_center),
                        if (_selectedMuscle != null)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: Colors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onSelected: (m) =>
                        setState(() => _selectedMuscle = m),
                    itemBuilder: (_) => [
                      const PopupMenuItem<Muscle?>(
                        value: null,
                        child: Text("Todos"),
                      ),
                      ...Muscle.values.map(
                        (m) => PopupMenuItem<Muscle?>(
                          value: m,
                          child: Text(m.label),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ===============================
            // 🧠 CHIP MÚSCULO ACTIVO
            // ===============================
            if (_selectedMuscle != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.fitness_center, size: 18),
                    label: Text("Músculo: ${_selectedMuscle!.label}"),
                    onDeleted: () =>
                        setState(() => _selectedMuscle = null),
                  ),
                ),
              ),

            // ===============================
            // 🔍 BUSCADOR
            // ===============================
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: "Buscar ejercicio...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = "");
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),

            // ===============================
            // 📃 LISTADO
            // ===============================
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _exerciseStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData ||
                      snapshot.data!.docs.isEmpty) {
                    return const Center(
                        child: Text("No hay ejercicios"));
                  }

                  final selectedType =
                      _types[_tabController.index];

                  final exercises = snapshot.data!.docs
                      .map(
                        (doc) => Exercise.fromFirestore(
                          doc.data() as Map<String, dynamic>,
                          id: doc.id,
                        ),
                      )
                      .where((e) {
                        final matchesSearch =
                            e.name.toLowerCase().contains(_searchQuery);

                        final matchesType =
                            selectedType == "Todos" ||
                                e.exerciseType == selectedType;

                        final matchesEquipment =
                            _selectedEquipment == "Todos" ||
                                e.equipment.contains(_selectedEquipment);

                        final matchesMuscle =
    _selectedMuscle == null ||
    (e.muscleWeights[_selectedMuscle] ?? 0) > 0;


                        return matchesSearch &&
                            matchesType &&
                            matchesEquipment &&
                            matchesMuscle;
                      })
                      .toList();

                  if (exercises.isEmpty) {
                    return const Center(
                        child: Text("Sin resultados"));
                  }

                  return ListView.builder(
                    itemCount: exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = exercises[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.all(12),
                          title: Text(
                            exercise.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            exercise.exerciseType,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              exercise.trackRM
                                  ? Icons.star
                                  : Icons.star_border,
                              color: exercise.trackRM
                                  ? Colors.amber
                                  : Colors.grey,
                            ),
                            tooltip: exercise.trackRM
                                ? "Cuenta para progreso"
                                : "No cuenta para progreso",
                            onPressed: () =>
                                _toggleTrackRM(exercise),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ExerciseDetailScreen(
                                  exercise: exercise,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // ===============================
      // ➕ FAB
      // ===============================
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddExerciseScreen(),
            ),
          );
        },
      ),
    );
  }
}
