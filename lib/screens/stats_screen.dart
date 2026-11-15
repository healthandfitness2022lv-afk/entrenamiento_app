import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/workout_stats_service.dart';
import '../services/fatigue_recalculation_service.dart';
import '../models/muscle_catalog.dart';
import '../theme/app_theme.dart';

class StatsScreen extends StatefulWidget {
  final String uid;
  final String? athleteName;

  /// Heatmap ya calculado por ProfileScreen (misma lógica de fatigue_audit).
  /// Si se pasa, se usa directamente en vez de cargar fatigue_state.
  final Map<Muscle, double>? heatmap;

  const StatsScreen({
    super.key,
    required this.uid,
    this.athleteName,
    this.heatmap,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<SessionStats> _all = [];
  List<_MuscleState> _fatigueData = [];
  bool _loading = true;
  int _days = 30;

  // ── colores ────────────────────────────────────────────────────────────────
  static const _accent = AppColors.accent;
  static const _yellow = Color(0xFFF59E0B);
  static const _blue = Color(0xFF3B82F6);
  static const _purple = Color(0xFF8B5CF6);
  static const _red = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    // Si ya viene el heatmap precalculado, lo usamos directamente
    if (widget.heatmap != null) {
      _fatigueData = _heatmapToMuscleStates(widget.heatmap!);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sessions = await WorkoutStatsService.fetch(uid: widget.uid);
      // Solo recargamos fatiga desde Firestore si no se pasó heatmap externo
      final fatigue =
          widget.heatmap != null ? _fatigueData : await _loadFatigue();
      if (mounted) {
        setState(() {
          _all = sessions;
          _fatigueData = fatigue;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Convierte el Map<Muscle, double> del profile en la lista interna,
  /// usando la misma lógica que generalFatigueTopMuscles: solo músculos >= 5.
  List<_MuscleState> _heatmapToMuscleStates(Map<Muscle, double> heatmap) {
    return heatmap.entries
        .where((e) => e.value >= 0)
        .map((e) => _MuscleState(muscle: e.key.name, fatigue: e.value))
        .toList()
      ..sort((a, b) => b.fatigue.compareTo(a.fatigue));
  }

  Future<List<_MuscleState>> _loadFatigue() async {
    final fatigue = await FatigueRecalculationService.readCurrentFatigue(
      uid: widget.uid,
    );
    return fatigue.entries
        .map((e) => _MuscleState(muscle: e.key.name, fatigue: e.value))
        .toList()
      ..sort((a, b) => b.fatigue.compareTo(a.fatigue));
  }

  List<SessionStats> get _filtered {
    if (_days == 0) return _all;
    final cut = DateTime.now().subtract(Duration(days: _days));
    return _all.where((s) => s.date.isAfter(cut)).toList();
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Estadísticas', style: TextStyle(fontSize: 16)),
            if (widget.athleteName != null)
              Text(
                widget.athleteName!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  color: _accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Selector de período
                      _periodSelector(),
                      const SizedBox(height: 16),

                      if (_filtered.isEmpty)
                        _emptyState()
                      else ...[
                        // KPIs
                        _kpiRow(),
                        const SizedBox(height: 16),

                        // Volumen por sesión
                        _volumeChart(),
                        const SizedBox(height: 14),

                        // Sesiones por día de semana
                        _weekdayChart(),
                        const SizedBox(height: 14),

                        // RPE por sesión
                        _rpeChart(),
                        const SizedBox(height: 14),

                        // Carga muscular acumulada
                        _muscleLoadChart(),
                        const SizedBox(height: 14),

                        // Fatiga muscular actual
                        _fatigueSection(),
                        const SizedBox(height: 14),

                        // Tabla de últimas sesiones
                        _sessionsTable(),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }

  // ── SELECTOR DE PERÍODO ────────────────────────────────────────────────────
  Widget _periodSelector() {
    const options = [
      (7, '7 días'),
      (30, '30 días'),
      (90, '90 días'),
      (0, 'Todo'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            options.map((o) {
              final sel = _days == o.$1;
              return GestureDetector(
                onTap: () => setState(() => _days = o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? _accent.withOpacity(0.15) : Colors.transparent,
                    border: Border.all(
                      color: sel ? _accent : Colors.grey.shade700,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    o.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? _accent : Colors.grey,
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  // ── KPIs ───────────────────────────────────────────────────────────────────
  Widget _kpiRow() {
    final ss = _filtered;
    final n = ss.length;
    final totalVol = ss.fold(0.0, (s, e) => s + e.volumeKg);
    final avgVol = n > 0 ? totalVol / n : 0.0;
    final withRpe = ss.where((s) => s.avgRpe > 0).toList();
    final avgRpe =
        withRpe.isNotEmpty
            ? withRpe.fold(0.0, (s, e) => s + e.avgRpe) / withRpe.length
            : 0.0;
    final withDur = ss.where((s) => s.durationMinutes > 0).toList();
    final avgDur =
        withDur.isNotEmpty
            ? withDur.fold(0, (s, e) => s + e.durationMinutes) / withDur.length
            : 0.0;

    return Row(
      children: [
        Expanded(child: _kpi('Sesiones', '$n', '', _accent)),
        const SizedBox(width: 10),
        Expanded(
          child: _kpi(
            'Vol. prom.',
            avgVol >= 1000
                ? '${(avgVol / 1000).toStringAsFixed(1)}k'
                : avgVol.toStringAsFixed(0),
            'kg',
            _yellow,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpi(
            'Duración',
            avgDur > 0 ? avgDur.toStringAsFixed(0) : '—',
            'min',
            _blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpi(
            'RPE prom.',
            avgRpe > 0 ? avgRpe.toStringAsFixed(1) : '—',
            '/ 10',
            _purple,
          ),
        ),
      ],
    );
  }

  Widget _kpi(String label, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: color, width: 2)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── VOLUMEN POR SESIÓN ─────────────────────────────────────────────────────
  Widget _volumeChart() {
    final ss = _filtered;
    final visible = ss.length > 30 ? ss.sublist(ss.length - 30) : ss;
    final spots =
        visible
            .asMap()
            .entries
            .map((e) => FlSpot(e.key.toDouble(), e.value.volumeKg))
            .toList();
    final maxY =
        visible.isEmpty
            ? 100.0
            : visible.map((s) => s.volumeKg).reduce((a, b) => a > b ? a : b) *
                1.2;

    return _card(
      title: '📈 Volumen por sesión',
      badge: '${visible.length} sesiones',
      badgeColor: _accent,
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _accent,
              barWidth: 2,
              dotData: FlDotData(
                show: visible.length <= 15,
                getDotPainter:
                    (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 3,
                      color: _accent,
                      strokeWidth: 0,
                      strokeColor: _accent,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: _accent.withOpacity(0.07),
              ),
            ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (_) => FlLine(
                  color: Colors.grey.withOpacity(0.15),
                  strokeWidth: 1,
                ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titlesData(
            bottomLabels:
                visible
                    .asMap()
                    .entries
                    .where(
                      (e) =>
                          visible.length <= 10 ||
                          e.key % (visible.length ~/ 5).clamp(1, 99) == 0,
                    )
                    .map((e) {
                      final d = e.value.date;
                      return MapEntry(e.key.toDouble(), '${d.day}/${d.month}');
                    })
                    .toList(),
            leftUnit: 'kg',
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItems:
                  (spots) =>
                      spots
                          .map(
                            (s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(0)} kg',
                              const TextStyle(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                          .toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── SESIONES POR DÍA ──────────────────────────────────────────────────────
  Widget _weekdayChart() {
    final counts = List.filled(7, 0);
    for (final s in _filtered) counts[s.date.weekday % 7]++;
    final maxY = counts.reduce((a, b) => a > b ? a : b).toDouble();
    const labels = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

    return _card(
      title: '📅 Sesiones por día de semana',
      badge: '${_filtered.length} total',
      badgeColor: _accent,
      height: 170,
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 5 : maxY * 1.3,
          barGroups: List.generate(
            7,
            (i) => BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: counts[i].toDouble(),
                  color:
                      counts[i] == maxY && maxY > 0
                          ? _accent
                          : _accent.withOpacity(0.25),
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                  ),
                ),
              ],
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (_) => FlLine(
                  color: Colors.grey.withOpacity(0.15),
                  strokeWidth: 1,
                ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget:
                    (v, _) =>
                        v % 1 != 0
                            ? const SizedBox()
                            : Text(
                              v.toInt().toString(),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                              ),
                            ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget:
                    (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        labels[v.toInt()],
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItem:
                  (g, _, rod, __) => BarTooltipItem(
                    '${rod.toY.toInt()} sesión${rod.toY != 1 ? "es" : ""}',
                    const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  // ── RPE POR SESIÓN ─────────────────────────────────────────────────────────
  Widget _rpeChart() {
    final ss = _filtered;
    final visible = ss.length > 30 ? ss.sublist(ss.length - 30) : ss;
    final spots =
        visible
            .asMap()
            .entries
            .where((e) => e.value.avgRpe > 0)
            .map((e) => FlSpot(e.key.toDouble(), e.value.avgRpe))
            .toList();

    return _card(
      title: '⚡ RPE promedio por sesión',
      badge: '${visible.length} sesiones',
      badgeColor: _purple,
      height: 160,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 10,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _purple,
              barWidth: 2,
              dotData: FlDotData(
                show: visible.length <= 15,
                getDotPainter:
                    (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 3,
                      color: _purple,
                      strokeWidth: 0,
                      strokeColor: _purple,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: _purple.withOpacity(0.07),
              ),
            ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (_) => FlLine(
                  color: Colors.grey.withOpacity(0.15),
                  strokeWidth: 1,
                ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titlesData(
            bottomLabels:
                visible
                    .asMap()
                    .entries
                    .where(
                      (e) =>
                          visible.length <= 10 ||
                          e.key % (visible.length ~/ 5).clamp(1, 99) == 0,
                    )
                    .map((e) {
                      final d = e.value.date;
                      return MapEntry(e.key.toDouble(), '${d.day}/${d.month}');
                    })
                    .toList(),
            leftUnit: 'RPE',
            maxY: 10,
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItems:
                  (spots) =>
                      spots
                          .map(
                            (s) => LineTooltipItem(
                              'RPE ${s.y.toStringAsFixed(1)}',
                              const TextStyle(
                                color: _purple,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                          .toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── CARGA MUSCULAR ACUMULADA ───────────────────────────────────────────────
  Widget _muscleLoadChart() {
    // Usamos los datos reales de muscle load acumulada desde workouts_logged
    // Para esto traemos la suma del campo muscleLoad de cada sesión filtrada
    return FutureBuilder<Map<String, double>>(
      future: _fetchMuscleLoad(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _card(
            title: '💪 Carga muscular acumulada',
            badge: 'Top 10',
            badgeColor: _purple,
            height: 240,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data!;
        final sorted =
            data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final top = sorted.take(10).toList();

        if (top.isEmpty) {
          return const SizedBox();
        }

        final maxVal = top.first.value;
        final groups =
            top
                .asMap()
                .entries
                .map(
                  (e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        color: _purple.withOpacity(0.7),
                        width: 14,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(5),
                        ),
                      ),
                    ],
                  ),
                )
                .toList();

        return _card(
          title: '💪 Carga muscular acumulada',
          badge: 'Top 10',
          badgeColor: _purple,
          height: 280,
          child: BarChart(
            BarChartData(
              maxY: maxVal * 1.2,
              barGroups: groups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                drawHorizontalLine: false,
                getDrawingVerticalLine:
                    (_) => FlLine(
                      color: Colors.grey.withOpacity(0.15),
                      strokeWidth: 1,
                    ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= top.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _muscleLabel(top[i].key),
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget:
                        (v, _) => Text(
                          v.toStringAsFixed(0),
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.grey,
                          ),
                        ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Colors.black87,
                  getTooltipItem: (g, _, rod, __) {
                    final i = g.x;
                    if (i >= top.length) return null;
                    return BarTooltipItem(
                      '${_muscleLabel(top[i].key)}\n${rod.toY.toStringAsFixed(1)}',
                      const TextStyle(
                        color: _purple,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, double>> _fetchMuscleLoad() async {
    final cut =
        _days == 0 ? null : DateTime.now().subtract(Duration(days: _days));

    Query query = FirebaseFirestore.instance
        .collection('workouts_logged')
        .where('userId', isEqualTo: widget.uid);

    final snap = await query.get();
    final totals = <String, double>{};

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final rawDate = data['date'];
      if (rawDate == null) continue;
      final date = (rawDate as Timestamp).toDate();
      if (cut != null && date.isBefore(cut)) continue;

      final ml = data['muscleLoad'];
      if (ml is Map) {
        ml.forEach((k, v) {
          final val = (v as num?)?.toDouble() ?? 0;
          totals[k.toString()] = (totals[k.toString()] ?? 0) + val;
        });
      }
    }
    return totals;
  }

  // ── FATIGA MUSCULAR ACTUAL ─────────────────────────────────────────────────
  Widget _fatigueSection() {
    if (_fatigueData.isEmpty) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔋 Fatiga muscular actual',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'En vivo',
                    style: TextStyle(
                      fontSize: 10,
                      color: _red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._fatigueData.map((m) => _fatigueRow(m)),
          ],
        ),
      ),
    );
  }

  Widget _fatigueRow(_MuscleState m) {
    final pct = m.fatigue.clamp(0, 100).toDouble();
    final color =
        pct >= 80
            ? _red
            : pct >= 60
            ? const Color(0xFFF97316)
            : pct >= 40
            ? _yellow
            : pct >= 20
            ? const Color(0xFF84CC16)
            : _accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              _muscleLabel(m.muscle),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                backgroundColor: Colors.grey.withOpacity(0.15),
                color: color,
                minHeight: 7,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${pct.toInt()}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TABLA DE ÚLTIMAS SESIONES ──────────────────────────────────────────────
  Widget _sessionsTable() {
    final rows = _filtered.reversed.take(20).toList();
    if (rows.isEmpty) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🗒️ Últimas sesiones',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            ...rows.map((s) {
              final rpeColor =
                  s.avgRpe >= 8
                      ? _red
                      : s.avgRpe >= 6
                      ? _yellow
                      : _accent;
              final d = s.date;
              final dateStr =
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

              return Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.withOpacity(0.12)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.sessionName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (s.volumeKg > 0)
                            Text(
                              '${s.volumeKg >= 1000 ? "${(s.volumeKg / 1000).toStringAsFixed(1)}k" : s.volumeKg.toStringAsFixed(0)} kg',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _yellow,
                              ),
                            ),
                          if (s.durationMinutes > 0)
                            Text(
                              '${s.durationMinutes} min',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (s.avgRpe > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: rpeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'RPE ${s.avgRpe.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: rpeColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────
  Widget _card({
    required String title,
    required String badge,
    required Color badgeColor,
    required double height,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      color: badgeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(height: height, child: child),
          ],
        ),
      ),
    );
  }

  FlTitlesData _titlesData({
    required List<MapEntry<double, String>> bottomLabels,
    String leftUnit = '',
    double? maxY,
  }) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (val, _) {
            final match =
                bottomLabels.where((e) => (e.key - val).abs() < 0.1).toList();
            if (match.isEmpty) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                match.first.value,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          getTitlesWidget:
              (val, _) => Text(
                val >= 1000
                    ? '${(val / 1000).toStringAsFixed(1)}k'
                    : val.toInt().toString(),
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
        ),
      ),
    );
  }

  String _muscleLabel(String key) {
    const map = {
      'quads': 'Cuádriceps',
      'hamstrings': 'Isquios',
      'glutes': 'Glúteos',
      'midGlutes': 'Gl. medio',
      'adductors': 'Aductores',
      'calves': 'Gemelos',
      'chest': 'Pecho',
      'upperChest': 'Pecho sup.',
      'frontDelts': 'Delt. ant.',
      'midDelts': 'Delt. med.',
      'triceps': 'Tríceps',
      'lats': 'Dorsales',
      'rombs': 'Romboides',
      'midBack': 'Esp. media',
      'trapsUpper': 'Trap. sup.',
      'lowerTraps': 'Trap. inf.',
      'rearDelts': 'Delt. post.',
      'biceps': 'Bíceps',
      'forearms': 'Antebrazos',
      'abs': 'Abdominales',
      'lowerAbs': 'Ab. inf.',
      'obliques': 'Oblicuos',
      'psoas': 'Psoas',
      'serratus': 'Serrato',
      'lowerBack': 'Lumbar',
    };
    return map[key] ?? key;
  }

  Widget _emptyState() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Text(
        'Sin sesiones en este período.',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      ),
    ),
  );
}

class _MuscleState {
  final String muscle;
  final double fatigue;
  const _MuscleState({required this.muscle, required this.fatigue});
}
