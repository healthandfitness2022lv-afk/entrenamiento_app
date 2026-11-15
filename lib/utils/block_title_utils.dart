/// Removes legacy planning coordinates (for example `M3 D5 -`) from titles.
/// The coordinates remain internal metadata; a reusable block is shown by its
/// actual training purpose instead.
String visibleBlockTitle(dynamic raw, {String fallback = 'Bloque'}) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return fallback;
  final cleaned =
      value
          .replaceFirst(
            RegExp(
              r'^\s*(?:(?:M\s*\d+)\s*)?(?:D\s*\d+)\s*(?:[-–—·|:]\s*)?',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
  return cleaned.isEmpty ? fallback : cleaned;
}
