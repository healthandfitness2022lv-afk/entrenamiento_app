import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class RpeFactorService {
  static final RpeFactorService _instance = RpeFactorService._internal();
  factory RpeFactorService() => _instance;

  RpeFactorService._internal() {
    _initStream();
  }

  Map<int, double> _factors = {
    1: 0.00,
    2: 0.15,
    3: 0.30,
    4: 0.45,
    5: 0.60,
    6: 0.85,
    7: 1.0,
    8: 1.15,
    9: 1.30,
    10: 1.5,
  };

  final Completer<void> _loaded = Completer<void>();

  /// Aplica los factores de `admin_settings/rpe_factors`. Si el documento no
  /// existe se usan los valores por defecto: solo un administrador lo crea al
  /// guardar desde Ajustes (los clientes nunca escriben aquí por su cuenta).
  void _apply(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data != null) {
      _factors = {
        for (int i = 1; i <= 10; i++)
          i: (data[i.toString()] as num?)?.toDouble() ?? _factors[i]!,
      };
    }
    if (!_loaded.isCompleted) _loaded.complete();
  }

  void _initStream() {
    FirebaseFirestore.instance
        .collection('admin_settings')
        .doc('rpe_factors')
        .snapshots()
        .listen(
          _apply,
          onError: (_) {
            if (!_loaded.isCompleted) _loaded.complete();
          },
        );
  }

  /// Espera a que lleguen los factores configurados (máx. 5 s) antes de
  /// calcular cargas, para no usar los valores por defecto por carrera.
  Future<void> ensureLoaded() =>
      _loaded.future.timeout(const Duration(seconds: 5), onTimeout: () {});

  double getFactor(double rpe) {
    final int key = rpe.round().clamp(1, 10);
    return _factors[key] ?? 1.0;
  }

  Future<void> updateFactors(Map<int, double> newFactors) async {
    final Map<String, dynamic> data = newFactors.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    await FirebaseFirestore.instance
        .collection('admin_settings')
        .doc('rpe_factors')
        .set(data, SetOptions(merge: true));
  }

  Map<int, double> get allFactors => Map.unmodifiable(_factors);
}
