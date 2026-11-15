import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/muscle_catalog.dart';

class MuscleRecoveryService {
  static final MuscleRecoveryService _instance =
      MuscleRecoveryService._internal();
  factory MuscleRecoveryService() => _instance;

  MuscleRecoveryService._internal() {
    _initStream();
  }

  Map<Muscle, double> _recoveryFactors = {
    for (var m in Muscle.values) m: m.recoveryFactor,
  };

  final Completer<void> _loaded = Completer<void>();

  /// Aplica los factores de `admin_settings/muscle_recovery`. Si el
  /// documento no existe se usan los valores por defecto del catálogo: solo
  /// un administrador lo crea al guardar desde Ajustes.
  void _apply(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data != null) {
      _recoveryFactors = {
        for (var m in Muscle.values)
          m: (data[m.name] as num?)?.toDouble() ?? m.recoveryFactor,
      };
    }
    if (!_loaded.isCompleted) _loaded.complete();
  }

  void _initStream() {
    FirebaseFirestore.instance
        .collection('admin_settings')
        .doc('muscle_recovery')
        .snapshots()
        .listen(
          _apply,
          onError: (_) {
            if (!_loaded.isCompleted) _loaded.complete();
          },
        );
  }

  /// Espera a que lleguen los factores configurados (máx. 5 s) antes de
  /// calcular fatiga, para no usar los valores por defecto por carrera.
  Future<void> ensureLoaded() =>
      _loaded.future.timeout(const Duration(seconds: 5), onTimeout: () {});

  double getRecoveryFactor(Muscle muscle) {
    return _recoveryFactors[muscle] ?? muscle.recoveryFactor;
  }

  Map<Muscle, double> get allFactors => Map.unmodifiable(_recoveryFactors);

  Future<void> updateFactors(Map<Muscle, double> newFactors) async {
    final Map<String, dynamic> data = {
      for (var entry in newFactors.entries) entry.key.name: entry.value,
    };
    await FirebaseFirestore.instance
        .collection('admin_settings')
        .doc('muscle_recovery')
        .set(data, SetOptions(merge: true));
  }
}
