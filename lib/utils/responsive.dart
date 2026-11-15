import 'package:flutter/material.dart';

/// Tamaños de pantalla de la app (se usa en celular, tablet y PC/web).
/// Cortes estilo Material 3: <600 celular, <1024 tablet, resto escritorio.
enum ScreenSize { compact, medium, expanded }

extension ScreenSizeX on BuildContext {
  ScreenSize get screenSize => screenSizeFor(MediaQuery.sizeOf(this).width);
  bool get isCompact => screenSize == ScreenSize.compact;
}

ScreenSize screenSizeFor(double width) {
  if (width < 600) return ScreenSize.compact;
  if (width < 1024) return ScreenSize.medium;
  return ScreenSize.expanded;
}

/// Padding horizontal que centra una lista con ancho máximo [maxWidth] sin
/// envolverla (útil en ListView/ListView.builder, que conviene no anidar).
EdgeInsets centeredListPadding(
  BuildContext context, {
  double maxWidth = 1100,
  double base = 16,
  double vertical = 12,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = width > maxWidth + base * 2 ? (width - maxWidth) / 2 : base;
  return EdgeInsets.symmetric(horizontal: side, vertical: vertical);
}

/// Centra el contenido con un ancho máximo para que en PC no se estire de
/// borde a borde (listas y textos largos se vuelven ilegibles a 1900 px).
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 1200,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
