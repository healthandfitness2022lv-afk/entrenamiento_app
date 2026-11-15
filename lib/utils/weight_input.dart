/// Interpreta el peso escrito por el usuario. Acepta coma decimal ("62,5",
/// habitual en teclados en español) además de punto. Null si está vacío o
/// no es un número.
double? parseWeight(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}
