import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/svg_utils.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/muscle_catalog.dart';
import '../widgets/body_heatmap.dart';
import 'my_workouts_screen.dart';
import '../services/fatigue_recalculation_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Map<Muscle, double> heatmap = {};

  bool loading = true;
  bool calculatingFatigue = false;
  DateTime? lastFatigueCalculation;
  List<FatigueRecalculationStep>? lastAuditSteps;
  late Set<Muscle> pendingChartMuscles;
  bool hasPendingChanges = false;
  bool showGlobalFatigue = true;


  Set<Muscle> chartMuscles = {};

  DateTimeRange? chartRange;

  List<FatigueRecalculationStep> _filterStepsByRange(
    List<FatigueRecalculationStep> steps,
  ) {
    final now = DateTime.now();

    final from = chartRange?.start ?? now.subtract(const Duration(days: 30));
    final to = chartRange?.end ?? now;

    return steps
    .where((s) =>
        !s.workoutDate.isBefore(from) &&
        !s.workoutDate.isAfter(to))
    .toList();

  }

  Widget _auditFatigueChart(List<FatigueRecalculationStep> steps) {
    final filtered = _filterStepsByRange(steps);

    if (filtered.length < 2) {
      return const Text(
        "No hay datos suficientes para graficar",
        style: TextStyle(color: Colors.grey),
      );
    }

    final series = <Muscle, List<FlSpot>>{};

    for (final m in chartMuscles) {
      series[m] = [];
    }

    for (int i = 0; i < filtered.length; i++) {
      final step = filtered[i];
      for (final m in chartMuscles) {
        final v = step.fatigueAfter[m];
        if (v != null) {
          series[m]!.add(FlSpot(i.toDouble(), v));
        }
      }
    }

    final globalSeries = <FlSpot>[];

    for (int i = 0; i < filtered.length; i++) {
      final g = _globalFatigueFromStep(filtered[i]);
      globalSeries.add(FlSpot(i.toDouble(), g));
    }

    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          
          minY: 0,
          maxY: 100,
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
  // ⬅️ IZQUIERDA: SE MANTIENE
  leftTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      interval: 20,
      reservedSize: 36,
      getTitlesWidget: (value, _) {
        return Text(
          value.toInt().toString(),
          style: const TextStyle(fontSize: 10),
        );
      },
    ),
  ),

  // ➡️ DERECHA: SE ELIMINA
  rightTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),

  // ⬆️ ARRIBA: SE ELIMINA
  topTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),

  // ⬇️ ABAJO: SE MANTIENE
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      interval: (filtered.length / 4).ceilToDouble(),
      getTitlesWidget: (value, _) {
        final i = value.toInt();
        if (i < 0 || i >= filtered.length) {
          return const SizedBox.shrink();
        }
        final d = filtered[i].workoutDate;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "${d.day}/${d.month}",
            style: const TextStyle(fontSize: 10),
          ),
        );
      },
    ),
  ),
),lineTouchData: LineTouchData(
  handleBuiltInTouches: true,
  touchTooltipData: LineTouchTooltipData(
    getTooltipColor: (_) => Colors.white,
    tooltipRoundedRadius: 8,
    tooltipPadding: const EdgeInsets.all(8),
    getTooltipItems: (touchedSpots) {
  if (touchedSpots.isEmpty) return [];

  final i = touchedSpots.first.x.round();
  final date = (i >= 0 && i < filtered.length)
      ? filtered[i].workoutDate
      : null;

  final fechaTxt = date == null
      ? ""
      : "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year}";

  return touchedSpots.asMap().entries.map((entry) {
    final idx = entry.key;
    final spot = entry.value;
    final barIndex = spot.barIndex;

    // 🔥 PROMEDIO GLOBAL
    if (showGlobalFatigue && barIndex == series.length) {
      return LineTooltipItem(
        "${idx == 0 ? "$fechaTxt\n" : ""}"
        "Promedio global\n"
        "${spot.y.toStringAsFixed(2)}%",
        const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    // 🔹 MÚSCULO
    final muscle = chartMuscles.elementAt(barIndex);

    return LineTooltipItem(
      "${idx == 0 ? "$fechaTxt\n" : ""}"
      "${muscle.label}\n"
      "${spot.y.toStringAsFixed(2)}%",
      TextStyle(
        color: heatmapColor(spot.y),
        fontWeight: FontWeight.bold,
      ),
    );
  }).toList();
},

  ),
),


          lineBarsData: [
  // 🔹 series por músculo
  ...series.entries.map((e) {
    return LineChartBarData(
      spots: e.value,
      isCurved: true,
      barWidth: 2,
      color: heatmapColor(40 + e.key.index * 5),
      dotData: FlDotData(show: false),
    );
  }),

  // 🔥 PROMEDIO GLOBAL (OPCIONAL)
  if (showGlobalFatigue)
    LineChartBarData(
      spots: globalSeries,
      isCurved: true,
      barWidth: 3,
      color: Colors.black,
      dashArray: [6, 4],
      dotData: FlDotData(show: false),
    ),
],

        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  String _heatmapSignature(Map<Muscle, double> heatmap) {
    final entries = heatmap.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return entries
        .map((e) => '${e.key.name}:${e.value.toStringAsFixed(2)}')
        .join('|');
  }

  // ======================================================
  // 🔄 CARGA INICIAL (estado guardado + recuperación lazy)
  // ======================================================
  Future<void> _loadInitialState() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    // 🔥 1) leer estado latest (la “última tabla” persistida)
    final latestStateSnap = await userRef
        .collection('fatigue_state')
        .doc('latest')
        .get();

    heatmap.clear();

    if (latestStateSnap.exists) {
      final data = latestStateSnap.data()!;
      final fatigueMap = Map<String, dynamic>.from(data['fatigue'] ?? {});

      for (final e in fatigueMap.entries) {
        // ✅ decodificación estricta, sin abs fallback
        final matches = Muscle.values.where((m) => m.name == e.key);
        if (matches.isEmpty) continue;
        final muscle = matches.first;

        heatmap[muscle] = (e.value as num).toDouble();
      }
    }

    // 🔥 2) leer auditoría persistida
    final auditSnap = await userRef
        .collection('fatigue_audit')
        .orderBy('workoutDate')
        .get();

    if (auditSnap.docs.isNotEmpty) {
      lastAuditSteps = auditSnap.docs
          .map((d) => FatigueRecalculationStep.fromJson(d.data()))
          .toList();
    }

    // 🔹 FECHA ÚLTIMO CÁLCULO
    final userDoc = await userRef.get();
    final userData = userDoc.data();
    if (userData?['lastFatigueCalculation'] != null) {
      lastFatigueCalculation =
          (userData!['lastFatigueCalculation'] as Timestamp).toDate();
    }

    if (!mounted) return;

    setState(() {
      pendingChartMuscles = {...chartMuscles};
      loading = false;
    });
  }

  Future<void> _recalculateFatigue() async {
    setState(() => calculatingFatigue = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;

    final result = await FatigueRecalculationService.recalculateAndPersist(
      uid: uid,
      forceRecalculateLoad: true,
    );

    if (!mounted) return;

    final now = DateTime.now(); // 👈 NUEVO

    setState(() {
      heatmap
        ..clear()
        ..addAll(result.finalFatigue);

      lastFatigueCalculation = now; // 👈 CLAVE
      calculatingFatigue = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Fatiga y tabla actualizadas"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ======================================================
  // 🖥 UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Perfil corporal"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: "Ver auditoría de fatiga",
            onPressed: lastAuditSteps == null
                ? null
                : () => _showAudit(lastAuditSteps!),
          ),
          IconButton(
            icon: calculatingFatigue
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: "Recalcular fatiga",
            onPressed: calculatingFatigue ? null : _recalculateFatigue,
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryCard(),
            const SizedBox(height: 24),
            _bodyAndMusclesSection(),
            _actions(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  double generalFatigueTopMuscles() {
    if (heatmap.isEmpty) return 0;

    // 🔹 tomamos solo músculos con carga real (evita ruido)
    final values = heatmap.values.where((v) => v >= 5).toList();

    if (values.isEmpty) return 0;

    // 🔥 orden descendente
    values.sort((a, b) => b.compareTo(a));

    // 🔥 TOP 5
    final top = values.take(5).toList();

    final avg = top.reduce((a, b) => a + b) / top.length;
    return avg.clamp(0, 100);
  }

  Widget _bodyAndMusclesSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          // 🖥️ 3 columnas
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _bodyBlock("Frontal", false)),
              const SizedBox(width: 16),
              Expanded(child: _bodyBlock("Posterior", true)),
              const SizedBox(width: 16),
              Expanded(child: _allMusclesList()),
            ],
          );
        }

        // 📱 Mobile: SVG arriba, lista abajo
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _bodyBlock("Frontal", false)),
                const SizedBox(width: 16),
                Expanded(child: _bodyBlock("Posterior", true)),
              ],
            ),
            const SizedBox(height: 24),
            _allMusclesList(),
          ],
        );
      },
    );
  }

  Widget _allMusclesList() {
    if (heatmap.isEmpty) {
      return const Text(
        "Sin datos de fatiga",
        style: TextStyle(color: Colors.grey),
      );
    }

    final entries = heatmap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Fatiga por músculo",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // 📋 LISTA DE MÚSCULOS
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: heatmapColor(e.value),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    e.key.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),

                Text(
                  e.value.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),
        const Divider(),

        // 🎨 ESCALA DE COLORES
        Wrap(spacing: 10, runSpacing: 6, children: _heatmapLegendRowsCompact()),
      ],
    );
  }

  List<Widget> _heatmapLegendRowsCompact() {
    return [
      _legendCompact(3, "Muy baja", "<5"),
      _legendCompact(10, "Baja", "5–17"),
      _legendCompact(24, "Media", "18–29"),
      _legendCompact(38, "M-alta", "30–47"),
      _legendCompact(52, "Alta", "48–55"),
      _legendCompact(65, "Muy alta", ">55"),
    ];
  }

  double _globalFatigueFromStep(FatigueRecalculationStep step) {
    final values = step.fatigueAfter.values.where((v) => v >= 5).toList();
    if (values.isEmpty) return 0;

    values.sort((a, b) => b.compareTo(a));
    final top = values.take(5).toList();

    return (top.reduce((a, b) => a + b) / top.length).clamp(0, 100);
  }

  Widget _legendCompact(double value, String label, String range) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: heatmapColor(value),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10)),
        Text(range, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  // ======================================================
  // 📊 RESUMEN GENERAL
  // ======================================================
  Widget _summaryCard() {
    final avgFatigue = generalFatigueTopMuscles();

    final status = avgFatigue < 25
        ? "Recuperado"
        : avgFatigue < 55
        ? "Carga moderada"
        : "Alta carga";

    final color = avgFatigue < 25
        ? Colors.green
        : avgFatigue < 55
        ? Colors.orange
        : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.accessibility_new, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Estado general",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${avgFatigue.toStringAsFixed(2)}% de fatiga",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 14,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                  if (lastFatigueCalculation != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        "Último cálculo: "
                        "${lastFatigueCalculation!.day.toString().padLeft(2, '0')}/"
                        "${lastFatigueCalculation!.month.toString().padLeft(2, '0')} "
                        "${lastFatigueCalculation!.hour.toString().padLeft(2, '0')}:"
                        "${lastFatigueCalculation!.minute.toString().padLeft(2, '0')}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================
  // 🧍 HEATMAPS
  // ======================================================

  Widget _bodyBlock(String title, bool showBack) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),

        AspectRatio(
          aspectRatio: 3 / 5,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: SizedBox.expand(
              // 🔥 CLAVE
              child: BodyHeatmap(
                key: ValueKey(_heatmapSignature(heatmap)),
                heatmap: heatmap,
                showBack: showBack,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ======================================================
  // ⚡ ACCIONES
  // ======================================================
  Widget _actions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Acciones", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        ListTile(
          leading: const Icon(Icons.history),
          title: const Text("Ver entrenamientos"),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyWorkoutsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _auditMuscleSelectorModal(
    void Function(void Function()) setModalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: Muscle.values.map((m) {
            final selected = pendingChartMuscles.contains(m);

            return FilterChip(
              label: Text(m.label, style: const TextStyle(fontSize: 11)),
              selected: selected,
              onSelected: (v) {
                setModalState(() {
                  v
                      ? pendingChartMuscles.add(m)
                      : pendingChartMuscles.remove(m);
                  hasPendingChanges = true;
                });
              },
            );
          }).toList(),
        ),

        if (hasPendingChanges)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ElevatedButton.icon(
              onPressed: () {
                setModalState(() {
                  chartMuscles = {...pendingChartMuscles};
                  hasPendingChanges = false;
                });
              },
              icon: const Icon(Icons.check),
              label: const Text("Aplicar"),
            ),
          ),
      ],
    );
  }

  void _showAudit(List<FatigueRecalculationStep> steps) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              minChildSize: 0.4,
              builder: (_, controller) {
                return SingleChildScrollView(
                  controller: controller,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Evolución de fatiga",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                final now = DateTime.now();

                                final range = await showDateRangePicker(
                                  context: context,
                                  firstDate: now.subtract(
                                    const Duration(days: 365),
                                  ),
                                  lastDate: now,
                                  initialDateRange:
                                      chartRange ??
                                      DateTimeRange(
                                        start: now.subtract(
                                          const Duration(days: 30),
                                        ),
                                        end: now,
                                      ),
                                );

                                if (range != null) {
                                  setModalState(() {
                                    chartRange = range;
                                  });
                                }
                              },
                              icon: const Icon(Icons.date_range),
                              label: const Text("Rango"),
                            ),
                            const Spacer(),
                            Text(
                              chartRange == null
                                  ? "Últimos 30 días"
                                  : "${chartRange!.start.day}/${chartRange!.start.month} - "
                                        "${chartRange!.end.day}/${chartRange!.end.month}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),Switch(
      value: showGlobalFatigue,
      onChanged: (v) {
        setModalState(() {
          showGlobalFatigue = v;
        });
      },
    ),
    const Text("promedio"),
                          ],
                        ),

                        _auditFatigueChart(steps),

                        const SizedBox(height: 8),

                        _auditMuscleSelectorModal(setModalState),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
