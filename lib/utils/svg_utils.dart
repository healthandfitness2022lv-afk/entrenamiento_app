import 'package:flutter/material.dart';
import '../models/muscle_catalog.dart';

/// ------------------------------------------------------
/// Construye el SVG coloreado según el heatmap
/// ------------------------------------------------------
String buildColoredSvg(
  String rawSvg,
  Map<Muscle, double> heatmap, {
  Color? overrideColor,
  double opacityMultiplier = 1.0, // 👈 NUEVO

}) {
  String svg = rawSvg;

  for (final muscle in Muscle.values) {
    final value = heatmap[muscle] ?? 0;

    if (value <= 0) {
      svg = _applyTransparentById(svg, muscle.name);
    } else {
      final color = overrideColor ?? heatmapColor(value);


      final v = value.clamp(0, 100).toDouble();
final normalized = v / 60; // 0.0 → 1.0
double baseOpacity = 0.3 + (normalized * 0.5);

// 🔥 Aplicar multiplicador
final opacity = (baseOpacity * opacityMultiplier)
    .clamp(0.15, 0.65);


      svg = _applyColorById(svg, muscle.name, color, opacity);
    }
  }

  return svg;
}

/// ------------------------------------------------------
/// Aplica color a un path por ID
/// ------------------------------------------------------
String _applyColorById(
  String svg,
  String id,
  Color color,
  double opacity,
) {
  // 🔥 SI ES TRANSPARENTE → NO PINTAR
  if (color.alpha == 0) {
    return _applyTransparentById(svg, id);
  }

  final hex = _colorToHex(color);


  final regExp = RegExp(
    r'(<[^>]*id="' + id + r'"[^>]*)(style="[^"]*")?',
    multiLine: true,
  );

  return svg.replaceAllMapped(regExp, (match) {
    String tag = match.group(1)!;

    if (tag.contains('style=')) {
      tag = tag.replaceAll(
        RegExp(r'style="[^"]*"'),
        'style="fill:$hex;fill-opacity:$opacity;"',
      );
    } else {
      tag = '$tag fill="$hex" fill-opacity="$opacity"';
    }

    return tag;
  });
}

/// ------------------------------------------------------
/// Hace invisible un músculo no trabajado
/// ------------------------------------------------------
String _applyTransparentById(
  String svg,
  String id,
) {
  final regExp = RegExp(
    r'(<[^>]*id="' + id + r'"[^>]*)(style="[^"]*")?',
    multiLine: true,
  );

  return svg.replaceAllMapped(regExp, (match) {
    String tag = match.group(1)!;

    if (tag.contains('style=')) {
      tag = tag.replaceAll(
        RegExp(r'style="[^"]*"'),
        'style="fill:none;"',
      );
    } else {
      tag = '$tag fill="none"';
    }

    return tag;
  });
}

/// ------------------------------------------------------
/// Escala ORIGINAL (para volumen / fatiga acumulada)
/// ------------------------------------------------------
Color heatmapColor(double value) {
  final v = value.clamp(0, 100).toDouble();

  // 🔲 Transparente hasta 4
  if (v < 4) {
    return Colors.transparent;
  }

  // Reescalamos 4–100 → 0–96
  final scaled = (v - 4) / 96;

  // 🔹 0–0.25 → Celeste → Azul
  if (scaled <= 0.25) {
    final t = scaled / 0.25;
    return Color.lerp(
      const Color(0xFF4FC3F7),
      const Color(0xFF1565C0),
      t,
    )!;
  }

  // 🔹 0.25–0.5 → Azul → Morado
  if (scaled <= 0.5) {
    final t = (scaled - 0.25) / 0.25;
    return Color.lerp(
      const Color(0xFF1565C0),
      const Color(0xFF7B1FA2),
      t,
    )!;
  }

  // 🔹 0.5–0.75 → Morado → Naranjo
  if (scaled <= 0.75) {
    final t = (scaled - 0.5) / 0.25;
    return Color.lerp(
      const Color(0xFF7B1FA2),
      const Color(0xFFFF8F00),
      t,
    )!;
  }

  // 🔴 0.75–1 → Naranjo → Rojo INTENSO
  final t = (scaled - 0.75) / 0.25;
  return Color.lerp(
    const Color(0xFFFF8F00),
    const Color(0xFFB71C1C), // rojo intenso real
    t,
  )!;
}





/// ------------------------------------------------------
String _colorToHex(Color color) {
  final value = color.value;

  // 🔥 Seguridad total
  if (value == 0x00000000) {
    return '#000000'; // fallback seguro (no debería usarse)
  }

  return '#${value.toRadixString(16).padLeft(8, '0').substring(2)}';
}
