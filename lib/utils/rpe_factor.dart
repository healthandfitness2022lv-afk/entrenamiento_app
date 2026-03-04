double rpeFactor(double rpe) {
  final int key = rpe.round().clamp(1, 10);

  const factors = {
    1: 0.00,
    2: 0.15,
    3: 0.30,
    4: 0.45,
    5: 0.60,
    6: 0.85,
    7: 1.0,
    8: 1.20,
    9: 1.45,   // Salto neural significativo
    10: 1.85,  // Estrés máximo del SNC
  };

  return factors[key]!;
}
