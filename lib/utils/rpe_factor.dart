double rpeFactor(double rpe) {
  final int key = rpe.round().clamp(1, 10);

  const factors = {
  1: 0.00,
  2: 0.15,
  3: 0.30,
  4: 0.45,
  5: 0.65,
  6: 0.85,
  7: 1.0,
  8: 1.1,
  9: 1.15,
  10: 1.3,
};


  return factors[key]!;
}
