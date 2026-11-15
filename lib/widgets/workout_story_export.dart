import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gal/gal.dart';
// XFile (para la descarga en web) lo re-exporta share_plus.
import 'package:share_plus/share_plus.dart' show XFile;
import '../models/muscle_catalog.dart';
import '../services/workout_load_service.dart';
import '../services/workout_metrics_service.dart';
import '../utils/workout_block_order.dart';
import 'body_heatmap.dart';
import '../theme/app_theme.dart';

const _kBg = AppColors.bg;
const _kSurface = AppColors.surface;
const _kAccent = AppColors.accent;
const _kTextSecondary = AppColors.textSecondary;

/// Historia de Instagram (9:16) de un entrenamiento registrado: vista previa
/// en diálogo + exportación a PNG 1080×1920 vía share sheet nativo.
/// La usan el detalle del workout y el resumen al terminar la sesión.
class WorkoutStoryExporter {
  WorkoutStoryExporter({
    required this.workoutData,
    required this.centralizedLoad,
    String Function(Map ex)? nameOf,
  }) : performed = List<Map<String, dynamic>>.from(
         workoutData['performed'] ?? const [],
       ),
       nameOf = nameOf ?? ((ex) => visibleExerciseName(ex, null)) {
    final metrics = WorkoutMetricsService.computeFromPerformed(
      performed,
      onlyDoneSets: true,
    );
    totalSets = metrics.totalSets;
    totalVolume = metrics.totalVolumeKg;
  }

  final Map<String, dynamic> workoutData;
  final List<Map<String, dynamic>> performed;
  final Map<Muscle, double> centralizedLoad;
  final String Function(Map ex) nameOf;
  late final int totalSets;
  late final int totalVolume;
  final GlobalKey _storyExportKey = GlobalKey();

  /// Normaliza datos antiguos y evita mostrar "Original" cuando el catálogo
  /// solo tiene una variante para ese movimiento.
  static String visibleExerciseName(Map ex, Map<String, dynamic>? catalog) {
    final rawName = (ex['exercise'] ?? 'Ejercicio').toString();
    final variants = catalog?['variants'];
    if (variants is List && variants.length == 1) {
      final catalogName = (catalog?['name'] ?? '').toString().trim();
      if (catalogName.isNotEmpty) return catalogName;
      final separator = rawName.indexOf(' - ');
      if (separator > 0) return rawName.substring(0, separator);
    }
    return rawName.replaceFirst(
      RegExp(r'\s+-\s+Original$', caseSensitive: false),
      '',
    );
  }

  /// Carga el workout guardado, su carga muscular y los nombres de catálogo,
  /// y abre la vista previa de la historia.
  static Future<void> showForWorkout(
    BuildContext context,
    DocumentReference workoutRef,
  ) async {
    final snap = await workoutRef.get();
    final data = snap.data() as Map<String, dynamic>?;
    if (data == null) return;

    final load = await WorkoutLoadService.calculateLoadFromWorkout(data);

    final ids = <String>{};
    void collect(Object? raw) {
      if (raw is! Map) return;
      final id = raw['exerciseId']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }

    for (final block in (data['performed'] as List? ?? const [])) {
      if (block is! Map) continue;
      for (final ex in (block['exercises'] as List? ?? const [])) {
        collect(ex);
      }
      for (final round in (block['rounds'] as List? ?? const [])) {
        if (round is! Map) continue;
        for (final ex in (round['exercises'] as List? ?? const [])) {
          collect(ex);
        }
      }
    }
    final catalogById = <String, Map<String, dynamic>>{};
    final docs = await Future.wait(
      ids.map(
        (id) =>
            FirebaseFirestore.instance.collection('exercises').doc(id).get(),
      ),
    );
    for (final doc in docs) {
      if (doc.exists) catalogById[doc.id] = doc.data()!;
    }

    if (!context.mounted) return;
    await WorkoutStoryExporter(
      workoutData: data,
      centralizedLoad: load,
      nameOf:
          (ex) => visibleExerciseName(
            ex,
            catalogById[ex['exerciseId']?.toString() ?? ''],
          ),
    ).show(context);
  }

  Color _sourceColor(String type) {
    switch (type) {
      case 'Circuito':
        return AppColors.circuit;
      case 'Tabata':
        return AppColors.tabata;
      default:
        return _kAccent;
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Abre la vista previa de la historia con el botón de compartir.
  Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(.82),
      builder: (dialogContext) {
        // Alto de la vista previa: lo que quede libre tras título, botones
        // y márgenes del diálogo, sin pasarse del ancho disponible (9:16).
        final size = MediaQuery.of(dialogContext).size;
        final maxByHeight = size.height - 190;
        final maxByWidth = (size.width - 60) * _kStoryH / _kStoryW;
        final previewHeight = math
            .min(math.min(maxByHeight, maxByWidth), 620.0)
            .clamp(200.0, 620.0);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: _kSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: _kAccent.withOpacity(.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'VISTA PREVIA · HISTORIA',
                  style: TextStyle(
                    color: _kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: previewHeight,
                  width: previewHeight * _kStoryW / _kStoryH,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FittedBox(fit: BoxFit.contain, child: _storyCard()),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(color: _kTextSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final saved = await _downloadStoryImage(dialogContext);
                        if (saved && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      },
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text('DESCARGAR'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Guarda la historia en PNG 1080×1920 (Full HD) sin abrir el menú de
  /// compartir: en Android va directo a la galería (álbum NEXUS) y en web
  /// se descarga como archivo.
  Future<bool> _downloadStoryImage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final boundary =
          _storyExportKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return false;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;
      final safeName =
          ((workoutData['sessionName'] ??
                      workoutData['routineName'] ??
                      'entrenamiento')
                  .toString())
              .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
              .toLowerCase();
      final bytes = byteData.buffer.asUint8List();
      final fileName =
          'nexus_${safeName}_${DateTime.now().millisecondsSinceEpoch}';

      if (kIsWeb) {
        // En web, saveTo dispara la descarga del navegador.
        await XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: '$fileName.png',
        ).saveTo('$fileName.png');
      } else {
        if (!await Gal.hasAccess(toAlbum: true)) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putImageBytes(bytes, album: 'NEXUS', name: fileName);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Historia descargada'
                : 'Historia guardada en la galería (álbum NEXUS)',
          ),
        ),
      );
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo descargar la historia: $e')),
      );
      return false;
    }
  }

  // ======================================================
  // 📸 HISTORIA EXPORTABLE (lienzo 360×640 → PNG 1080×1920)
  // ======================================================
  static const double _kStoryW = 360;
  static const double _kStoryH = 640;
  static const double _kStoryPadH = 22;
  static const int _kStoryMaxItems = 1000;

  /// Cargas de ≤1 kg se registran solo para que el ejercicio sume carga en
  /// el modelo de fatiga; en la historia se tratan como peso corporal.
  static bool _isRealLoad(double w) => w > 1;

  String _fmtNum(num v) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
  }

  String _fmtThousands(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return v < 0 ? '-$buf' : buf.toString();
  }

  /// Resume las series hechas de un ejercicio en un badge corto ("4×10") y
  /// una línea de detalle con reps/pesos ("12·10·8 reps · 60–70 kg").
  _StoryExercise _summarizeSets(
    String name,
    List<_StorySet> sets, {
    required bool perSide,
    String unitSingular = 'serie',
    String unitPlural = 'series',
  }) {
    final n = sets.length;
    final reps = sets.map((s) => s.reps).toList();
    final sameReps = reps.toSet().length == 1 && reps.first > 0;
    final badge =
        sameReps
            ? '$n×${reps.first}'
            : '$n ${n == 1 ? unitSingular : unitPlural}';

    final weights = sets.map((s) => s.weight).where(_isRealLoad).toList();
    final distinctWeights = weights.toSet();
    final parts = <String>[];

    if (distinctWeights.length > 1 && weights.length == n && n <= 6) {
      // Pesos distintos por serie: mostramos la progresión completa.
      final seq = sets
          .map(
            (s) =>
                sameReps ? _fmtNum(s.weight) : '${s.reps}×${_fmtNum(s.weight)}',
          )
          .join(' · ');
      parts.add('$seq kg');
    } else {
      if (!sameReps) {
        final shown = reps.take(8).join('·');
        parts.add('$shown${reps.length > 8 ? '…' : ''} reps');
      }
      if (distinctWeights.length == 1) {
        parts.add('${_fmtNum(distinctWeights.first)} kg');
      } else if (distinctWeights.length > 1) {
        final minW = weights.reduce(math.min);
        final maxW = weights.reduce(math.max);
        parts.add('${_fmtNum(minW)}–${_fmtNum(maxW)} kg');
      }
    }
    if (perSide) parts.add('por lado');

    return _StoryExercise(name: name, badge: badge, detail: parts.join(' · '));
  }

  List<_StoryBlock> _storyBlocks() {
    final blocks = <_StoryBlock>[];
    final orderedPerformed = [...performed]..sort(comparePerformedBlocks);

    for (
      var blockIndex = 0;
      blockIndex < orderedPerformed.length;
      blockIndex++
    ) {
      final block = orderedPerformed[blockIndex];
      final type = block['type']?.toString() ?? 'Series';
      final rawTitle = block['blockTitle']?.toString().trim() ?? '';
      final title = rawTitle.isEmpty ? type : rawTitle;
      final items = <_StoryExercise>[];
      String? info;

      if (type == 'Circuito') {
        // Agrupa por ejercicio todas las rondas en que aparece.
        final order = <String>[];
        final byName = <String, List<_StorySet>>{};
        final perSideByName = <String, bool>{};
        final weightLoggedByName = <String, bool>{};
        final rounds = (block['rounds'] as List? ?? const []);
        for (final round in rounds) {
          if (round is! Map) continue;
          for (final raw in (round['exercises'] as List? ?? const [])) {
            if (raw is! Map) continue;
            final name = nameOf(raw);
            if (!byName.containsKey(name)) order.add(name);
            byName
                .putIfAbsent(name, () => [])
                .add(
                  _StorySet(
                    (raw['reps'] as num?)?.toInt() ?? 0,
                    (raw['weight'] as num?)?.toDouble() ?? 0,
                  ),
                );
            if (raw['perSide'] == true) perSideByName[name] = true;
            if (raw.containsKey('weight')) weightLoggedByName[name] = true;
          }
        }
        // Formato por ronda: "12  KTB swing americano  12 kg".
        for (final name in order) {
          final sets = byName[name]!;
          final reps = sets.map((s) => s.reps).where((r) => r > 0).toList();
          final distinctReps = reps.toSet().toList();
          final weights = sets.map((s) => s.weight).where(_isRealLoad).toList();
          final distinctWeights = weights.toSet();
          final suffix = <String>[];
          if (distinctWeights.length == 1) {
            suffix.add('${_fmtNum(distinctWeights.first)} kg');
          } else if (distinctWeights.length > 1) {
            suffix.add(
              '${_fmtNum(weights.reduce(math.min))}–'
              '${_fmtNum(weights.reduce(math.max))} kg',
            );
          } else if (weightLoggedByName[name] == true) {
            suffix.add('peso corporal');
          }
          if (perSideByName[name] == true) suffix.add('x lado');
          items.add(
            _StoryExercise(
              name: name,
              lead:
                  distinctReps.isEmpty
                      ? ''
                      : distinctReps.length == 1
                      ? '${distinctReps.first}'
                      : reps.join('/'),
              badge: '',
              detail: suffix.join(' · '),
            ),
          );
        }
        if (rounds.isNotEmpty) {
          info = '${rounds.length} ${rounds.length == 1 ? 'ronda' : 'rondas'}';
        }
      } else if (type == 'Tabata') {
        final rounds = (block['rounds'] as num?)?.toInt();
        final work = (block['work'] as num?)?.toInt();
        final rest = (block['rest'] as num?)?.toInt();
        for (final raw in (block['exercises'] as List? ?? const [])) {
          if (raw is! Map) continue;
          final rpe = (raw['rpe'] as num?)?.toDouble();
          items.add(
            _StoryExercise(
              name: nameOf(raw),
              badge:
                  (rounds != null && work != null)
                      ? '$rounds×${work}s'
                      : 'TABATA',
              detail: rpe != null ? 'RPE ${_fmtNum(rpe)}' : '',
            ),
          );
        }
        final infoParts = <String>[
          if (rounds != null) '$rounds rondas',
          if (work != null && rest != null) '${work}s / ${rest}s',
        ];
        if (infoParts.isNotEmpty) info = infoParts.join(' · ');
      } else {
        // Series, Series descendentes, Buscar RM
        for (final raw in (block['exercises'] as List? ?? const [])) {
          if (raw is! Map) continue;
          final sets = <_StorySet>[];
          var perSide = raw['perSide'] == true;
          for (final s in (raw['sets'] as List? ?? const [])) {
            if (s is! Map) continue;
            if (s.containsKey('done') && s['done'] != true) continue;
            sets.add(
              _StorySet(
                (s['reps'] as num?)?.toInt() ?? 0,
                (s['weight'] as num?)?.toDouble() ?? 0,
              ),
            );
            if (s['perSide'] == true) perSide = true;
          }
          if (sets.isEmpty) continue;
          items.add(_summarizeSets(nameOf(raw), sets, perSide: perSide));
        }
        if (title.toLowerCase() != type.toLowerCase()) info = type;
      }

      if (items.isNotEmpty) {
        blocks.add(
          _StoryBlock(
            title: title,
            info: info,
            color: _sourceColor(type),
            items: items,
          ),
        );
      }
    }
    return blocks;
  }

  int _storyReps() {
    var reps = 0;
    for (final block in performed) {
      final type = block['type']?.toString();
      if (type == 'Circuito') {
        for (final round in (block['rounds'] as List? ?? const [])) {
          if (round is! Map) continue;
          for (final ex in (round['exercises'] as List? ?? const [])) {
            if (ex is Map) reps += (ex['reps'] as num?)?.toInt() ?? 0;
          }
        }
        continue;
      }
      for (final ex in (block['exercises'] as List? ?? const [])) {
        if (ex is! Map) continue;
        for (final set in (ex['sets'] as List? ?? const [])) {
          if (set is! Map) continue;
          if (set.containsKey('done') && set['done'] != true) continue;
          reps += (set['reps'] as num?)?.toInt() ?? 0;
        }
      }
    }
    return reps;
  }

  Widget _storyCard() {
    final title =
        (workoutData['sessionName'] ??
                workoutData['routineName'] ??
                'Entrenamiento')
            .toString();
    final date = (workoutData['date'] as Timestamp?)?.toDate();
    final duration = (workoutData['durationMinutes'] as num?)?.toInt() ?? 0;
    final blocks = _storyBlocks();
    final exerciseCount = blocks.fold<int>(0, (acc, b) => acc + b.items.length);
    final rows = exerciseCount + blocks.length;
    final crowded = rows > 9;

    final metrics = <MapEntry<String, String>>[
      MapEntry(totalSets.toString(), 'SERIES'),
      MapEntry(_fmtThousands(_storyReps()), 'REPS'),
      if (totalVolume > 0) MapEntry(_fmtThousands(totalVolume), 'KG TOTALES'),
      if (duration > 0)
        MapEntry('$duration\'', 'MINUTOS')
      else
        MapEntry(exerciseCount.toString(), 'EJERCICIOS'),
    ];

    return RepaintBoundary(
      key: _storyExportKey,
      child: SizedBox(
        width: _kStoryW,
        height: _kStoryH,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _kBg,
            image: DecorationImage(
              image: const AssetImage('assets/images/training_action_2.png'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(.78),
                BlendMode.darken,
              ),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -80,
                right: -65,
                child: _storyOrb(190, _kAccent.withOpacity(.16)),
              ),
              Positioned(
                bottom: -100,
                left: -90,
                child: _storyOrb(230, AppColors.info.withOpacity(.18)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  _kStoryPadH,
                  26,
                  _kStoryPadH,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Cabecera ──
                    Row(
                      children: [
                        if (date != null)
                          Expanded(
                            child: Text(
                              _formatDate(date).toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        Image.asset(
                          'assets/logo/logo.png',
                          width: 24,
                          height: 24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Métricas ──
                    Row(
                      children: [
                        for (var i = 0; i < metrics.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _storyMetric(metrics[i].key, metrics[i].value),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Mapa muscular + músculos principales ──
                    _storyMusclePanel(height: crowded ? 92 : 118),
                    const SizedBox(height: 14),

                    // ── Detalle por bloque ──
                    Expanded(child: _storyBlockList(blocks, rows)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(width: 18, height: 2, color: _kAccent),
                        const SizedBox(width: 6),
                        const Text(
                          'NEXUS TRAINING',
                          style: TextStyle(
                            color: _kTextSecondary,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storyMusclePanel({required double height}) {
    final entries =
        centralizedLoad.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(height > 100 ? 4 : 3).toList();
    final maxValue = entries.isEmpty ? 1.0 : entries.first.value;

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: height * .9,
            child: Row(
              children: [
                Expanded(
                  child: BodyHeatmap(heatmap: centralizedLoad, showBack: false),
                ),
                Expanded(
                  child: BodyHeatmap(heatmap: centralizedLoad, showBack: true),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: Colors.white.withOpacity(.10),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MÚSCULOS MÁS TRABAJADOS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                if (top.isEmpty)
                  const Text(
                    'Sin datos musculares',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  )
                else
                  for (final entry in top)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                entry.key.label.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (entry.value / maxValue).clamp(
                                    0.05,
                                    1.0,
                                  ),
                                  minHeight: 5,
                                  backgroundColor: Colors.white.withOpacity(
                                    .08,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color.lerp(
                                      const Color(0xFFF1C40F),
                                      const Color(0xFFE74C3C),
                                      entry.value / maxValue,
                                    )!,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Lista de bloques/ejercicios. La densidad se adapta a la cantidad de
  /// filas y, como red de seguridad, un FittedBox reduce la escala si aun
  /// así no cabe — nunca desborda el lienzo exportado.
  Widget _storyBlockList(List<_StoryBlock> blocks, int rows) {
    if (blocks.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Sin series registradas',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
      );
    }

    final spacious = rows <= 6;
    final compact = rows > 11;
    final nameSize = spacious ? 13.5 : (compact ? 10.5 : 12.0);
    final detailSize = spacious ? 10.5 : (compact ? 8.5 : 9.5);
    final badgeSize = spacious ? 13.0 : (compact ? 10.0 : 11.5);
    final rowGap = spacious ? 9.0 : (compact ? 3.0 : 6.0);
    final blockGap = spacious ? 12.0 : (compact ? 6.0 : 9.0);

    var remaining = _kStoryMaxItems;
    var hidden = 0;
    final children = <Widget>[];

    for (var b = 0; b < blocks.length; b++) {
      final block = blocks[b];
      if (remaining <= 0) {
        hidden += block.items.length;
        continue;
      }
      final visible = block.items.take(remaining).toList();
      hidden += block.items.length - visible.length;
      remaining -= visible.length;

      if (b > 0) children.add(SizedBox(height: blockGap));
      children.add(
        Padding(
          padding: EdgeInsets.only(bottom: rowGap + 1),
          child: Row(
            children: [
              Container(
                width: 3,
                height: compact ? 10 : 12,
                decoration: BoxDecoration(
                  color: block.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  block.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: block.color,
                    fontSize: compact ? 8.5 : 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (block.info != null) ...[
                const SizedBox(width: 8),
                Text(
                  block.info!.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 7.5 : 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      for (final item in visible) {
        if (item.lead != null) {
          children.add(
            Padding(
              padding: EdgeInsets.only(bottom: rowGap, left: 9),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (item.lead!.isNotEmpty)
                      TextSpan(
                        text: '${item.lead}  ',
                        style: TextStyle(
                          color: block.color,
                          fontSize: badgeSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    TextSpan(
                      text: item.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: nameSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.detail.isNotEmpty)
                      TextSpan(
                        text: '  ${item.detail}',
                        style: TextStyle(
                          color: _kTextSecondary,
                          fontSize: detailSize + 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.2),
              ),
            ),
          );
          continue;
        }
        children.add(
          Padding(
            padding: EdgeInsets.only(bottom: rowGap, left: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: nameSize,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (item.detail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            item.detail,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _kTextSecondary,
                              fontSize: detailSize,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 6 : 8,
                    vertical: compact ? 2 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: block.color.withOpacity(.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: block.color.withOpacity(.35)),
                  ),
                  child: Text(
                    item.badge,
                    maxLines: 1,
                    style: TextStyle(
                      color: block.color,
                      fontSize: badgeSize,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (hidden > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 9),
          child: Text(
            '+$hidden ${hidden == 1 ? 'ejercicio más' : 'ejercicios más'}',
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _kStoryW - _kStoryPadH * 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _storyOrb(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  Widget _storyMetric(String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(.12)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextSecondary,
                fontSize: 7.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StorySet {
  final int reps;
  final double weight;
  const _StorySet(this.reps, this.weight);
}

class _StoryExercise {
  final String name;
  final String badge;
  final String detail;

  /// Si no es null, el ejercicio se pinta en una sola línea estilo circuito:
  /// "`lead` nombre detalle" (p.ej. "12 KTB swing americano 12 kg").
  final String? lead;
  const _StoryExercise({
    required this.name,
    required this.badge,
    required this.detail,
    this.lead,
  });
}

class _StoryBlock {
  final String title;
  final String? info;
  final Color color;
  final List<_StoryExercise> items;
  const _StoryBlock({
    required this.title,
    required this.info,
    required this.color,
    required this.items,
  });
}
