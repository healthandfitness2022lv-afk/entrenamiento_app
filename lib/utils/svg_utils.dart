import 'package:flutter/material.dart';
import '../models/muscle_catalog.dart';

/// ------------------------------------------------------
/// Construye el SVG coloreado según el heatmap
/// ------------------------------------------------------
String buildColoredSvg(
  String rawSvg,
  Map<Muscle, double> heatmap, {
  Color? overrideColor,
  bool percentageScale = false, // 👈 NUEVO (seguro)
}) {
  String svg = rawSvg;

  for (final muscle in Muscle.values) {
    final value = heatmap[muscle] ?? 0;

    if (value <= 0) {
      svg = _applyTransparentById(svg, muscle.name);
    } else {
      final color = overrideColor ??
          (percentageScale
              ? heatmapColorPercent(value)
              : heatmapColor(value));

      final opacity = 0.65; // 👈 AJUSTABLE (0.5–0.8 recomendado)
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
  // clamp de seguridad
  final v = value.clamp(0, 65);

  // 🔹 MUY BAJO = INVISIBLE
  if (v < 5) {
    return Colors.transparent;
  } 
  // 🔵 BAJO
  else if (v < 18) {
    return const Color(0xFF26C6DA); // cian
  } 
  // 🔵 MEDIA
  else if (v < 30) {
    return const Color(0xFF1E88E5); // azul
  } 
  // 🟣 MEDIA-ALTA
  else if (v < 48) {
    return const Color(0xFF5C6BC0); // azul-violeta
  } 
  // 🟪 ALTA
  else if (v < 65) {
    return const Color(0xFF3949AB); // índigo
  } 
  // 🟪 MUY ALTA (tope)
  else {
    return const Color(0xFF311B92); // morado profundo
  }
}




/// ------------------------------------------------------
/// Escala PORCENTUAL (0.0 – 1.0) 👉 para ejercicios
/// ------------------------------------------------------
Color heatmapColorPercent(double value) {
  final percent = (value * 100).clamp(0, 100);

  if (percent <= 10) {
    return const Color(0xFFE3F2FD); // celeste cielo
  } else if (percent <= 25) {
    return const Color(0xFFBBDEFB); // celeste claro
  } else if (percent <= 40) {
    return const Color(0xFF64B5F6); // azul claro
  } else if (percent <= 60) {
    return const Color(0xFF42A5F5); // azul medio
  } else if (percent <= 80) {
    return const Color(0xFF1E88E5); // azul fuerte
  } else {
    return const Color(0xFF0D47A1); // azul intenso
  }
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
