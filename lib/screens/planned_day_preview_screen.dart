import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';
import '../services/planned_routine_loader_service.dart';
import '../services/workout_load_service.dart';
import '../services/pending_work_service.dart';
import 'log_workout_screen.dart';

class _PlannedDayData {
  final Map<String, dynamic> routine;
  final Map<Muscle, double> heatmap;

  _PlannedDayData({required this.routine, required this.heatmap});
}

class PlannedDayPreviewScreen extends StatefulWidget {
  final List<DateTime> availableDays;
  final DateTime initialDay;

  const PlannedDayPreviewScreen({
    super.key,
    required this.availableDays,
    required this.initialDay,
  });

  @override
  State<PlannedDayPreviewScreen> createState() =>
      _PlannedDayPreviewScreenState();
}

class _PlannedDayPreviewScreenState extends State<PlannedDayPreviewScreen> {
  late DateTime _selectedDay;
  final Map<DateTime, Future<_PlannedDayData?>> _cache = {};
  late Future<List<PendingExercise>> _pendingFuture;
  final Set<int> _selectedPendingIndexes = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay;
    _pendingFuture = _loadPending();
  }

  Future<List<PendingExercise>> _loadPending() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final pending = await PendingWorkService.loadPendingExercises(
      athleteId: uid,
    );
    // Por defecto se ofrecen todos seleccionados: el atleta puede
    // destildar los que no quiera recuperar hoy.
    if (mounted) {
      setState(() {
        _selectedPendingIndexes
          ..clear()
          ..addAll(List.generate(pending.length, (i) => i));
      });
    }
    return pending;
  }

  DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _dayLabel(DateTime day) {
    if (day == _dayOnly(DateTime.now())) return 'Hoy';
    return '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
  }

  Future<_PlannedDayData?> _loadDayData(DateTime day) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final routine = await PlannedRoutineLoaderService.loadRoutineForDate(
      athleteId: uid,
      date: day,
    );
    if (routine == null) return null;

    final blocks = List<Map<String, dynamic>>.from(routine['blocks'] ?? []);
    final heatmap = await WorkoutLoadService.calculateLoadFromPlannedBlocks(
      blocks,
    );
    return _PlannedDayData(routine: routine, heatmap: heatmap);
  }

  Future<_PlannedDayData?> _dataFor(DateTime day) {
    return _cache.putIfAbsent(day, () => _loadDayData(day));
  }

  void _retry(DateTime day) {
    setState(() => _cache.remove(day));
  }

  Future<void> _startTraining() async {
    final pending = await _pendingFuture;
    final chosen = [
      for (final i in _selectedPendingIndexes)
        if (i < pending.length) pending[i],
    ];
    final extraBlocks =
        chosen.isEmpty ? null : [PendingWorkService.buildRecoveryBlock(chosen)];

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) => LogWorkoutScreen(
              initialDate: _selectedDay,
              extraBlocks: extraBlocks,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vista previa del entrenamiento')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildDayTabs(),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<_PlannedDayData?>(
                key: ValueKey(_selectedDay),
                future: _dataFor(_selectedDay),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _buildError(_selectedDay);
                  }
                  final data = snapshot.data;
                  if (data == null ||
                      (data.routine['blocks'] as List).isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No hay ejercicios planificados para este día.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        _buildPendingSection(),
                      ],
                    );
                  }
                  return _buildDayContent(data);
                },
              ),
            ),
            _buildStartButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildDayTabs() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: widget.availableDays.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = widget.availableDays[i];
          final bool isActive = day == _selectedDay;
          return ChoiceChip(
            label: Text(_dayLabel(day)),
            selected: isActive,
            selectedColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.25),
            onSelected: (_) => setState(() => _selectedDay = day),
          );
        },
      ),
    );
  }

  Widget _buildError(DateTime day) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
          const SizedBox(height: 12),
          const Text('No se pudo cargar la planificación de este día.'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _retry(day),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDayContent(_PlannedDayData data) {
    final blocks = List<Map<String, dynamic>>.from(
      data.routine['blocks'] ?? [],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _buildHeatmapSection(data.heatmap),
        const SizedBox(height: 20),
        for (final block in blocks) _buildBlockExercises(block),
        _buildPendingSection(),
      ],
    );
  }

  Widget _buildPendingSection() {
    return FutureBuilder<List<PendingExercise>>(
      future: _pendingFuture,
      builder: (context, snapshot) {
        final pending = snapshot.data;
        if (pending == null || pending.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 8, bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.tertiary.withOpacity(0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_toggle_off_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Pendientes por recuperar',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'No completaste estos ejercicios en su día planificado. '
                'Elegí cuáles agregar a la sesión de hoy.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < pending.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selectedPendingIndexes.contains(i),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedPendingIndexes.add(i);
                      } else {
                        _selectedPendingIndexes.remove(i);
                      }
                    });
                  },
                  title: Text(pending[i].name),
                  subtitle: Text(
                    '${pending[i].blockTitle} · '
                    '${_dayLabel(pending[i].originalDate)} · '
                    '${pending[i].missingVol.ceil()} '
                    '${pending[i].blockType == "Series" ? "series" : "rondas"} pendientes',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeatmapSection(Map<Muscle, double> heatmap) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'FRONTAL',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 240,
                      child: BodyHeatmap(heatmap: heatmap, showBack: false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'POSTERIOR',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 240,
                      child: BodyHeatmap(heatmap: heatmap, showBack: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (heatmap.isEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Sin datos musculares suficientes para estimar la carga.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlockExercises(Map<String, dynamic> block) {
    final String blockType = (block['type'] ?? 'Bloque').toString();
    final String blockTitle =
        (block['title'] as String?)?.trim().isNotEmpty == true
            ? block['title'] as String
            : blockType;
    final exercises = List<Map<String, dynamic>>.from(block['exercises'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            blockTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(blockType),
          children: [
            for (final ex in exercises) _buildExerciseTile(ex),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseTile(Map<String, dynamic> ex) {
    final String name = (ex['name'] ?? 'Ejercicio').toString();
    final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < sets.length; i++)
                Chip(
                  label: Text(
                    '${sets[i]['reps'] ?? '-'} reps × ${sets[i]['weight'] ?? 0} kg',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Comenzar entrenamiento'),
          onPressed: _startTraining,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}
