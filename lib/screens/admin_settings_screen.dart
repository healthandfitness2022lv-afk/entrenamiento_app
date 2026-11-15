import 'package:flutter/material.dart';
import '../services/rpe_factor_service.dart';
import '../services/muscle_recovery_service.dart';
import '../models/muscle_catalog.dart';
import '../theme/app_theme.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // RPE Controllers
  late Map<int, TextEditingController> _rpeControllers;

  // Recovery Controllers
  late Map<Muscle, TextEditingController> _recoveryControllers;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Init RPE
    final currentRpeFactors = RpeFactorService().allFactors;
    _rpeControllers = {
      for (int i = 1; i <= 10; i++)
        i: TextEditingController(
          text: currentRpeFactors[i]?.toString() ?? '1.0',
        ),
    };

    // Init Recovery
    final currentRecoveryFactors = MuscleRecoveryService().allFactors;
    _recoveryControllers = {
      for (var m in Muscle.values)
        m: TextEditingController(
          text: currentRecoveryFactors[m]?.toString() ?? '0.7',
        ),
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _rpeControllers.values) c.dispose();
    for (final c in _recoveryControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _saveRpeFactors() async {
    setState(() => _isSaving = true);
    try {
      final newFactors = <int, double>{};
      for (int i = 1; i <= 10; i++) {
        final val = double.tryParse(
          _rpeControllers[i]!.text.replaceAll(',', '.'),
        );
        if (val != null) newFactors[i] = val;
      }
      await RpeFactorService().updateFactors(newFactors);
      _showSuccess('Factores RPE guardados');
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveRecoveryFactors() async {
    setState(() => _isSaving = true);
    try {
      final newFactors = <Muscle, double>{};
      for (var m in Muscle.values) {
        final val = double.tryParse(
          _recoveryControllers[m]!.text.replaceAll(',', '.'),
        );
        if (val != null) newFactors[m] = val;
      }
      await MuscleRecoveryService().updateFactors(newFactors);
      _showSuccess('Factores de recuperación guardados');
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.accentSoft),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $msg'), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        backgroundColor: AppColors.bg,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'RPE', icon: Icon(Icons.speed)),
            Tab(text: 'RECUPERACIÓN', icon: Icon(Icons.rebase_edit)),
          ],
        ),
      ),
      body:
          _isSaving
              ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              )
              : TabBarView(
                controller: _tabController,
                children: [_buildRpeTab(), _buildRecoveryTab()],
              ),
    );
  }

  Widget _buildRpeTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Factores Multiplicadores RPE',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.accentTint,
          ),
        ),
        const SizedBox(height: 16),
        for (int i = 1; i <= 10; i++)
          _buildFieldRow('RPE $i', _rpeControllers[i]!),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _saveRpeFactors,
          icon: const Icon(Icons.save, color: Colors.black),
          label: const Text(
            'Guardar RPE',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _buildRecoveryTab() {
    // Group muscles by anatomical group for better UX
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Factores de Recuperación (Diaria)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.accentTint,
          ),
        ),
        const Text(
          'Menor valor = Recuperación más rápida (ej: 0.6). Mayor = más lenta (ej: 0.8).',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 16),
        for (var group in AnatomicalGroup.values) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              group.label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          ...anatomicalGroups[group]!.map(
            (m) => _buildFieldRow(m.label, _recoveryControllers[m]!),
          ),
          const Divider(color: Colors.white10),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _saveRecoveryFactors,
          icon: const Icon(Icons.save, color: Colors.black),
          label: const Text(
            'Guardar Recuperación',
            style: TextStyle(color: Colors.black),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildFieldRow(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
