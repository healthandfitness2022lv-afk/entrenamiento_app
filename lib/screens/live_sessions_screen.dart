import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/live_session_service.dart';
import '../theme/app_theme.dart';

/// Sesiones que los atletas están entrenando ahora (y las que terminaron en
/// las últimas horas), publicadas por [LiveSessionService].
class LiveSessionsScreen extends StatefulWidget {
  const LiveSessionsScreen({super.key});

  static const _finishedVisibleFor = Duration(hours: 3);
  static const _activeVisibleFor = Duration(hours: 6);

  /// Stream de las sesiones a mostrar; también lo usa el indicador del home.
  static Stream<List<Map<String, dynamic>>> watchSessions() {
    return FirebaseFirestore.instance
        .collection(LiveSessionService.collection)
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          final sessions =
              snap.docs.map((d) => {'id': d.id, ...d.data()}).where((s) {
                final updated = _date(s['updatedAt']);
                if (updated == null) return false;
                final limit =
                    s['status'] == 'finished'
                        ? _finishedVisibleFor
                        : _activeVisibleFor;
                return now.difference(updated) <= limit;
              }).toList();
          sessions.sort((a, b) {
            final byStatus = (a['status'] == 'active' ? 0 : 1).compareTo(
              b['status'] == 'active' ? 0 : 1,
            );
            if (byStatus != 0) return byStatus;
            return _date(b['updatedAt'])!.compareTo(_date(a['updatedAt'])!);
          });
          return sessions;
        });
  }

  @override
  State<LiveSessionsScreen> createState() => _LiveSessionsScreenState();
}

class _LiveSessionsScreenState extends State<LiveSessionsScreen> {
  final _sessions = LiveSessionsScreen.watchSessions();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('En vivo')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _sessions,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Ningún atleta está entrenando ahora.\n'
                  'Las sesiones aparecen apenas abren el registro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }
          return _Ticker(
            builder:
                (_) => ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _SessionCard(sessions[i]),
                ),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  const _SessionCard(this.session);

  @override
  Widget build(BuildContext context) {
    final status = _status(session);
    final total = (session['totalSets'] as num?)?.toInt() ?? 0;
    final done = (session['doneSets'] as num?)?.toInt() ?? 0;
    final started = _date(session['startedAt']);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) =>
                        LiveSessionDetailScreen(athleteId: session['id'] as String),
              ),
            ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session['athleteName'] ?? 'Atleta',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _StatusChip(status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                session['sessionName'] ?? '',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (status == _LiveStatus.live &&
                  session['currentExercise'] != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.fitness_center,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        session['currentExercise'],
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _Progress(done: done, total: total),
              const SizedBox(height: 8),
              Text(
                [
                  if (started != null) '${_clock(DateTime.now().difference(started))} de sesión',
                  if (_date(session['lastSetAt']) != null)
                    'última serie ${_ago(_date(session['lastSetAt'])!)}',
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalle de la sesión de un atleta, ejercicio por ejercicio y serie por serie.
class LiveSessionDetailScreen extends StatelessWidget {
  final String athleteId;
  const LiveSessionDetailScreen({super.key, required this.athleteId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection(LiveSessionService.collection)
              .doc(athleteId)
              .snapshots(),
      builder: (context, snapshot) {
        final session = snapshot.data?.data();
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            title: Text(session?['athleteName'] ?? 'En vivo'),
            actions: [
              if (session != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(child: _StatusChip(_status(session))),
                ),
            ],
          ),
          body: _body(snapshot, session),
        );
      },
    );
  }

  Widget _body(
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
    Map<String, dynamic>? session,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (session == null) {
      return const Center(
        child: Text(
          'La sesión se canceló o ya no está disponible.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    final blocks = List<Map<String, dynamic>>.from(
      (session['blocks'] as List? ?? const []).map(
        (b) => Map<String, dynamic>.from(b as Map),
      ),
    );
    final total = (session['totalSets'] as num?)?.toInt() ?? 0;
    final done = (session['doneSets'] as num?)?.toInt() ?? 0;
    final currentBlock = (session['currentBlock'] as num?)?.toInt();
    final live = _status(session) == _LiveStatus.live;

    return _Ticker(
      builder:
          (_) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                session['sessionName'] ?? '',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (_date(session['startedAt']) != null)
                    '${_clock(DateTime.now().difference(_date(session['startedAt'])!))} de sesión',
                  if (_date(session['lastSetAt']) != null)
                    'última serie ${_ago(_date(session['lastSetAt'])!)}',
                  if (_date(session['updatedAt']) != null)
                    'actualizado ${_ago(_date(session['updatedAt'])!)}',
                ].join(' · '),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _Progress(done: done, total: total),
              const SizedBox(height: 16),
              for (final block in blocks)
                _BlockCard(
                  block: block,
                  isCurrent: live && block['index'] == currentBlock,
                  currentExercise: live ? session['currentExercise'] : null,
                ),
            ],
          ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isCurrent;
  final String? currentExercise;
  const _BlockCard({
    required this.block,
    required this.isCurrent,
    required this.currentExercise,
  });

  int get _elapsedSeconds {
    final duration = (block['durationSeconds'] as num?)?.toInt();
    if (duration != null) return duration;
    var total = (block['pausedSeconds'] as num?)?.toInt() ?? 0;
    final since = _date(block['runningSince']);
    if (since != null) total += DateTime.now().difference(since).inSeconds;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final running = block['runningSince'] != null;
    final finished = block['durationSeconds'] != null;
    final elapsed = _elapsedSeconds;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? AppColors.accent : AppColors.divider,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${block['title']}',
                  style: const TextStyle(
                    color: AppColors.accentTint,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (elapsed > 0 || running)
                Row(
                  children: [
                    Icon(
                      finished
                          ? Icons.check_circle
                          : running
                          ? Icons.timer
                          : Icons.pause_circle,
                      size: 16,
                      color:
                          finished
                              ? AppColors.accentSoft
                              : running
                              ? AppColors.accent
                              : AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _clock(Duration(seconds: elapsed)),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (block['type'] == 'Circuito')
            ..._circuit()
          else if (block['type'] == 'Tabata')
            ..._tabata()
          else
            ..._series(),
        ],
      ),
    );
  }

  List<Widget> _series() {
    final exercises = List.from(block['exercises'] ?? const []);
    return [
      for (final raw in exercises)
        Builder(
          builder: (_) {
            final ex = Map<String, dynamic>.from(raw as Map);
            final sets = List.from(ex['sets'] ?? const []);
            final isNow = isCurrent && currentExercise == ex['name'];
            final isTime = ex['valueType'] == 'time';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isNow)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: _PulseDot(),
                        ),
                      Expanded(
                        child: Text(
                          ex['name'] ?? '',
                          style: TextStyle(
                            color:
                                isNow
                                    ? AppColors.textPrimary
                                    : AppColors.onSurface,
                            fontWeight:
                                isNow ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        'plan ${_target(ex['plannedReps'], ex['plannedWeight'], isTime)}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < sets.length; i++)
                        _SetChip(
                          label:
                              '${i + 1}: ${_target(sets[i]['reps'], sets[i]['weight'], isTime)}',
                          rpe: sets[i]['rpe'],
                          done: sets[i]['done'] == true,
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _circuit() {
    final rounds = List.from(block['rounds'] ?? const []);
    final planned = block['plannedRounds'];
    return [
      Text(
        'Ronda ${rounds.length}${planned != null ? ' de $planned' : ''}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 6),
      for (final rawRound in rounds)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'R${(rawRound as Map)['round']}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final raw in List.from(rawRound['exercises'] ?? const []))
                _SetChip(
                  label:
                      '${(raw as Map)['name']} ${_target(raw['reps'], raw['weight'], raw['valueType'] == 'time')}',
                  rpe: raw['rpe'],
                  done: raw['done'] == true,
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _tabata() {
    final tabata = block['tabata'] as Map?;
    final names = List.from(
      block['exercises'] ?? const [],
    ).map((e) => (e as Map)['name']).join(' · ');
    return [
      Text(names, style: const TextStyle(color: AppColors.onSurface)),
      if (tabata != null && tabata['running'] == true) ...[
        const SizedBox(height: 6),
        Text(
          'Ronda ${tabata['round']} · ${tabata['phase'] == 'work' ? 'trabajo' : 'descanso'}',
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ];
  }
}

class _SetChip extends StatelessWidget {
  final String label;
  final dynamic rpe;
  final bool done;
  const _SetChip({required this.label, required this.rpe, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            done ? AppColors.accentSoft.withOpacity(0.18) : AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: done ? AppColors.accentSoft : AppColors.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check : Icons.radio_button_unchecked,
            size: 14,
            color: done ? AppColors.accentSoft : AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            done && rpe != null ? '$label @$rpe' : label,
            style: TextStyle(
              color: done ? AppColors.textPrimary : AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final int done;
  final int total;
  const _Progress({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              backgroundColor: AppColors.surface2,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$done/$total series',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

enum _LiveStatus { live, noSignal, finished }

/// Sin latido en 2 minutos se considera que el teléfono perdió conexión o
/// la app quedó cerrada sin guardar.
_LiveStatus _status(Map<String, dynamic> session) {
  if (session['status'] == 'finished') return _LiveStatus.finished;
  final updated = _date(session['updatedAt']);
  if (updated == null ||
      DateTime.now().difference(updated) > const Duration(minutes: 2)) {
    return _LiveStatus.noSignal;
  }
  return _LiveStatus.live;
}

class _StatusChip extends StatelessWidget {
  final _LiveStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      _LiveStatus.live => ('EN VIVO', AppColors.danger),
      _LiveStatus.noSignal => ('SIN SEÑAL', AppColors.warning),
      _LiveStatus.finished => ('TERMINÓ', AppColors.accentSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == _LiveStatus.live) ...[
            const _PulseDot(),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.danger,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Reconstruye cada segundo para que cronómetros y "hace X" avancen sin
/// esperar una escritura nueva del atleta.
class _Ticker extends StatefulWidget {
  final WidgetBuilder builder;
  const _Ticker({required this.builder});

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String _ago(DateTime date) {
  final d = DateTime.now().difference(date);
  if (d.inSeconds < 60) return 'hace ${d.inSeconds.clamp(0, 59)} s';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  return 'hace ${d.inHours} h';
}

String _target(dynamic reps, dynamic weight, bool isTime) {
  final r =
      reps == null
          ? '-'
          : isTime
          ? _clock(Duration(seconds: (reps as num).toInt()))
          : '$reps';
  final w = weight is num && weight > 1 ? ' × ${_kg(weight)}' : '';
  return '$r$w';
}

String _kg(num w) =>
    '${w % 1 == 0 ? w.toInt() : w.toString().replaceAll('.', ',')} kg';
