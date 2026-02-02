import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/colors.dart';

class PermissionsHelpScreen extends StatefulWidget {
  const PermissionsHelpScreen({super.key});

  @override
  State<PermissionsHelpScreen> createState() => _PermissionsHelpScreenState();
}

class _PermissionsHelpScreenState extends State<PermissionsHelpScreen> {
  bool _isChecking = false;
  PermissionStatus? _storageStatus;
  PermissionStatus? _manageStorageStatus;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isChecking = true);
    
    _storageStatus = await Permission.storage.status;
    _manageStorageStatus = await Permission.manageExternalStorage.status;
    
    setState(() => _isChecking = false);
  }

  Future<void> _openSettings() async {
    await openAppSettings();
    // Revérifier après retour
    await Future.delayed(const Duration(seconds: 1));
    _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Permissions requises', 
                         style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildProblemSection(),
            const SizedBox(height: 32),
            _buildSolutionSection(),
            const SizedBox(height: 32),
            _buildPermissionStatus(),
            const SizedBox(height: 32),
            _buildActionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, 
               color: AppColors.warning, size: 48),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permission manquante',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pour accéder aux fichiers du téléphone',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.info),
            const SizedBox(width: 8),
            Text(
              'Pourquoi cette permission ?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Pour que le PC puisse naviguer dans les fichiers de ton téléphone '
          '(Téléchargements, Photos, Documents, etc.), Android nécessite une '
          'permission spéciale appelée "Gérer tous les fichiers".',
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSolutionSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                'Comment activer ?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStep(1, 'Clique sur "Ouvrir les paramètres" ci-dessous'),
          _buildStep(2, 'Cherche "Fichiers et médias" ou "Autorisations"'),
          _buildStep(3, 'Sélectionne "Autoriser la gestion de tous les fichiers"'),
          _buildStep(4, 'Reviens dans l\'app et reconnecte-toi'),
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStatus() {
    if (_isChecking) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'État des permissions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildPermissionItem(
          'Stockage',
          _storageStatus,
          Icons.storage,
        ),
        const SizedBox(height: 8),
        _buildPermissionItem(
          'Gérer tous les fichiers',
          _manageStorageStatus,
          Icons.folder_open,
          isImportant: true,
        ),
      ],
    );
  }

  Widget _buildPermissionItem(
    String name,
    PermissionStatus? status,
    IconData icon, {
    bool isImportant = false,
  }) {
    final isGranted = status?.isGranted ?? false;
    final color = isGranted ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: isImportant ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isImportant ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                if (isImportant && !isGranted) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⚠️ Permission requise',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            isGranted ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    final allGranted = (_manageStorageStatus?.isGranted ?? false);

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: allGranted ? null : _openSettings,
            icon: Icon(
              allGranted ? Icons.check_circle : Icons.settings,
              color: Colors.white,
            ),
            label: Text(
              allGranted ? 'Permissions activées !' : 'Ouvrir les paramètres',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: allGranted ? AppColors.success : AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _checkPermissions,
          icon: Icon(Icons.refresh, color: AppColors.primary),
          label: Text(
            'Vérifier à nouveau',
            style: TextStyle(color: AppColors.primary),
          ),
        ),
        if (allGranted) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text(
                'Retour à l\'app',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
