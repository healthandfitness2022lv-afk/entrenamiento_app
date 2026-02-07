import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/muscle_catalog.dart';
import '../utils/svg_utils.dart';

class BodyHeatmap extends StatefulWidget {
  final Map<Muscle, double> heatmap;
  final bool showBack;
  final Color? overrideColor;
  final bool percentageScale; // 👈 NUEVO

  const BodyHeatmap({
    super.key,
    required this.heatmap,
    this.showBack = false,
    this.overrideColor,
    this.percentageScale = false, // 👈 default seguro
  });

  @override
  State<BodyHeatmap> createState() => _BodyHeatmapState();
}

class _BodyHeatmapState extends State<BodyHeatmap> {
  String? _svgData;

  /// 🔥 Cache global de SVG procesados
  static final Map<String, String> _svgCache = {};

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  @override
void didUpdateWidget(covariant BodyHeatmap oldWidget) {
  super.didUpdateWidget(oldWidget);
  _loadSvg(); // 🔥 siempre recalcula si el widget cambia
}


  /// ======================================================
  /// 🔑 Cache key estable (NO depende del orden del Map)
  /// ======================================================
  String _cacheKey() {
    final entries = widget.heatmap.entries
        .map(
          (e) => '${e.key.name}:${e.value.toStringAsFixed(3)}',
        )
        .toList()
      ..sort();

    return [
      widget.showBack ? 'back' : 'front',
      widget.percentageScale ? 'percent' : 'raw',
      entries.join('|'),
      widget.overrideColor?.value.toString() ?? 'default',
    ].join('::');
  }

  /// ======================================================
  /// ⚡ Carga + cache del SVG
  /// ======================================================
  Future<void> _loadSvg() async {
    final key = _cacheKey();

    if (_svgCache.containsKey(key)) {
      setState(() => _svgData = _svgCache[key]);
      return;
    }

    final path = widget.showBack
        ? 'assets/svg/body_back.svg'
        : 'assets/svg/body_front.svg';

    final rawSvg = await rootBundle.loadString(path);

    final coloredSvg = buildColoredSvg(
      rawSvg,
      widget.heatmap,
      overrideColor: widget.overrideColor,
      percentageScale: widget.percentageScale, // 👈 PASAMOS EL FLAG
    );

    _svgCache[key] = coloredSvg;

    if (!mounted) return;
    setState(() => _svgData = coloredSvg);
  }

  @override
  Widget build(BuildContext context) {
    if (_svgData == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return RepaintBoundary(
      child: SvgPicture.string(
        _svgData!,
        fit: BoxFit.contain,
      ),
    );
  }
}
