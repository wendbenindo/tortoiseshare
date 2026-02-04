import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/colors.dart';
import '../services/network_scanner.dart';
import '../services/tcp_client.dart';
import '../models/device.dart';
import '../models/connection_status.dart';
import 'permissions_help_screen.dart';

class MobileScreen extends StatefulWidget {
  const MobileScreen({super.key});

  @override
  State<MobileScreen> createState() => _MobileScreenState();
}

class _MobileScreenState extends State<MobileScreen> {
  // Services
  final NetworkScanner _scanner = NetworkScanner();
  final TcpClient _client = TcpClient();
  
  // État
  AppConnectionState _connectionState = AppConnectionState.idle();
  final List<Device> _foundDevices = [];
  Device? _connectedDevice;
  String _pcName = 'PC TortoiseShare';
  int _scanProgress = 0;
  int _totalScans = 0;
  bool _hasPermission = false;
  
  // Pour le transfert de fichiers
  bool _isTransferring = false;
  double _transferProgress = 0.0;
  String? _currentFileName;
  
  // Controllers
  final TextEditingController _messageController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    
    // Vérifier les permissions au démarrage
    if (Platform.isAndroid) {
      _checkPermissions();
    }
    
    // Charger le dernier PC connu
    _loadLastKnownPC();
    
    // Écouter les messages du serveur
    _client.messageStream.listen((message) {
      _handleServerMessage(message);
    });
    
    // Écouter la progression du scan
    _scanner.onProgress = (current, total) {
      if (mounted) {
        setState(() {
          _scanProgress = current;
          _totalScans = total;
        });
      }
    };
  }
  
  // Charger le dernier PC connu
  Future<void> _loadLastKnownPC() async {
    final prefs = await SharedPreferences.getInstance();
    final lastIP = prefs.getString('last_pc_ip');
    final lastName = prefs.getString('last_pc_name');
    
    if (lastIP != null) {
      // Ajouter le PC connu à la liste
      final knownDevice = Device(
        id: lastIP,
        name: lastName ?? 'PC TortoiseShare',
        ipAddress: lastIP,
        type: DeviceType.desktop,
        connectedAt: DateTime.now(),
      );
      
      if (mounted) {
        setState(() {
          _foundDevices.add(knownDevice);
        });
      }
    }
  }
  
  // Sauvegarder le PC trouvé
  Future<void> _saveLastKnownPC(String ip, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_pc_ip', ip);
    await prefs.setString('last_pc_name', name);
  }

  // Vérifier et demander les permissions
  Future<void> _checkPermissions() async {
    bool hasPermission = false;
    
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      
      if (androidInfo.version.sdkInt >= 30) {
        // Android 11+ : Utiliser MANAGE_EXTERNAL_STORAGE
        hasPermission = await Permission.manageExternalStorage.isGranted;
      } else {
        // Android 10 et moins : Utiliser STORAGE normal
        hasPermission = await Permission.storage.isGranted;
      }
    } else {
      // iOS ou autre
      hasPermission = true;
    }
    
    if (mounted) {
      setState(() {
        _hasPermission = hasPermission;
      });
    }
    
    if (!hasPermission && Platform.isAndroid) {
      // Demander la permission
      await _requestPermission();
    }
  }
  
  // Demander la permission
  Future<void> _requestPermission() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    PermissionStatus status;
    
    if (androidInfo.version.sdkInt >= 30) {
      status = await Permission.manageExternalStorage.request();
    } else {
      status = await Permission.storage.request();
    }
    
    if (mounted) {
      setState(() {
        _hasPermission = status.isGranted;
      });
      
      if (!status.isGranted) {
        // Si refusé, montrer l'écran d'aide
        _showPermissionDialog();
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permission requise'),
        content: const Text(
          'Pour que le PC puisse voir tes fichiers, tu dois autoriser '
          'l\'accès à tous les fichiers. C\'est obligatoire pour cette fonctionnalité.'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // L'utilisateur refuse, on le prévient
              _showSnackBar('Fonctionnalité limitée sans permission', AppColors.warning);
            },
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Ouvrir les paramètres', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  // Démarrer le scan
  Future<void> _startScan() async {
    if (_connectionState.isScanning || _connectionState.isConnected) return;
    
    setState(() {
      _connectionState = AppConnectionState.scanning('🔍 Recherche en cours...');
      _foundDevices.clear();
      _scanProgress = 0;
      _totalScans = 0;
    });
    
    await for (final device in _scanner.scanNetwork()) {
      if (mounted && !_foundDevices.any((d) => d.id == device.id)) {
        setState(() {
          _foundDevices.add(device);
        });
      }
    }
    
    if (mounted) {
      setState(() {
        _connectionState = _foundDevices.isEmpty
            ? AppConnectionState.error('Aucun PC trouvé')
            : AppConnectionState(
                status: ConnectionStatus.idle,
                message: '✅ ${_foundDevices.length} PC trouvé(s)',
              );
      });
    }
  }
  
  // Connecter à un appareil
  Future<void> _connectToDevice(Device device) async {
    setState(() {
      _connectionState = AppConnectionState(
        status: ConnectionStatus.connecting,
        message: '🔄 Connexion en cours...',
      );
    });
    
    final success = await _client.connect(device.ipAddress);
    
    if (mounted) {
      setState(() {
        if (success) {
          _connectedDevice = device;
          _connectionState = AppConnectionState.connected(device.name);
          
          // Sauvegarder le PC pour la prochaine fois
          _saveLastKnownPC(device.ipAddress, device.name);
        } else {
          _connectionState = AppConnectionState.error('Connexion échouée');
        }
      });
      
      if (success) {
        _showSnackBar('Connexion établie', AppColors.success);
      } else {
        _showSnackBar('Erreur de connexion', AppColors.error);
      }
    }
  }
  
  // Gérer les messages du serveur
  void _handleServerMessage(String message) {
    print('📨 Serveur: $message');
    
    if (message.startsWith('SERVER|NAME|')) {
      final name = message.substring(12);
      setState(() {
        _pcName = name.isNotEmpty ? name : 'PC TortoiseShare';
      });
      _showSnackBar('Connecté à $_pcName', AppColors.success);
    } else if (message == 'FILE|REJECTED') {
      // Le fichier a été refusé par le PC
      setState(() {
        _isTransferring = false;
      });
      _showSnackBar('❌ Fichier refusé par le PC', AppColors.error);
    }
  }
  
  // Envoyer un message
  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) return;
    
    final message = _messageController.text;
    final success = await _client.sendMessage(message);
    
    if (success) {
      _messageController.clear();
      _showSnackBar('Message envoyé', AppColors.primary);
      FocusScope.of(context).unfocus();
    } else {
      _showSnackBar('Erreur d\'envoi', AppColors.error);
    }
  }
  
  // Déconnecter
  Future<void> _disconnect() async {
    await _client.disconnect();
    setState(() {
      _connectedDevice = null;
      _connectionState = AppConnectionState.idle();
      _foundDevices.clear();
    });
    _showSnackBar('Déconnecté', AppColors.warning);
  }
  
  // Choisir et envoyer un fichier
  Future<void> _pickAndSendFile() async {
    try {
      // 1. Choisir un fichier
      final result = await FilePicker.platform.pickFiles();
      
      if (result == null || result.files.isEmpty) {
        _showSnackBar('Aucun fichier sélectionné', AppColors.warning);
        return;
      }
      
      final file = result.files.first;
      final filePath = file.path;
      
      if (filePath == null) {
        _showSnackBar('Erreur: chemin du fichier invalide', AppColors.error);
        return;
      }
      
      // 2. Afficher la progression
      setState(() {
        _isTransferring = true;
        _transferProgress = 0.0;
        _currentFileName = file.name;
      });
      
      _showSnackBar('Envoi de ${file.name}...', AppColors.info);
      
      // 3. Envoyer le fichier
      final success = await _client.sendFile(
        filePath,
        onProgress: (progress) {
          setState(() {
            _transferProgress = progress;
          });
        },
      );
      
      // 4. Afficher le résultat
      setState(() {
        _isTransferring = false;
      });
      
      if (success) {
        _showSnackBar('✅ Fichier envoyé avec succès !', AppColors.success);
      } else {
        _showSnackBar('❌ Erreur lors de l\'envoi', AppColors.error);
      }
      
    } catch (e) {
      setState(() {
        _isTransferring = false;
      });
      _showSnackBar('Erreur: $e', AppColors.error);
      print('❌ Erreur sélection fichier: $e');
    }
  }
  
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  @override
  void dispose() {
    _scanner.stopScan();
    _client.dispose();
    _messageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _connectionState.isConnected 
          ? _buildConnectedView() 
          : _buildScanView(),
    );
  }
  
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Icon(Icons.sensors, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Text(
            'TortoiseShare',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.primary,
      elevation: 0,
      actions: [
        if (_connectionState.isScanning)
          IconButton(
            icon: Icon(Icons.stop, color: Colors.white),
            onPressed: () {
              _scanner.stopScan();
              setState(() {
                _connectionState = AppConnectionState(
                  status: ConnectionStatus.idle,
                  message: 'Scan annulé',
                );
              });
            },
            tooltip: 'Arrêter',
          ),
        if (_foundDevices.isNotEmpty && !_connectionState.isConnected)
          IconButton(
            icon: Icon(Icons.clear_all, color: Colors.white),
            onPressed: () {
              setState(() {
                _foundDevices.clear();
                _connectionState = AppConnectionState.idle();
              });
            },
            tooltip: 'Effacer',
          ),
      ],
    );
  }
  
  Widget _buildScanView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildScanButton(),
          const SizedBox(height: 20),
          if (_connectionState.isScanning || _foundDevices.isNotEmpty)
            _buildStatusCard(),
          const SizedBox(height: 20),
          if (_foundDevices.isNotEmpty) _buildDeviceList(),
        ],
      ),
    );
  }
  
  Widget _buildHeader() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sensors, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'TortoiseShare Mobile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connexion PC simplifiée',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildScanButton() {
    return ElevatedButton.icon(
      onPressed: _connectionState.isScanning ? null : _startScan,
      icon: Icon(
        _connectionState.isScanning ? Icons.hourglass_top : Icons.search,
        color: Colors.white,
      ),
      label: Text(
        _connectionState.isScanning ? 'Recherche...' : 'Rechercher un PC',
        style: TextStyle(fontSize: 16, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
  
  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statut', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (_connectionState.isScanning) ...[
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_connectionState.message),
                  ),
                ],
              ),
              if (_totalScans > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _scanProgress / _totalScans,
                  color: AppColors.primary,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                ),
              ],
            ] else
              Text(_connectionState.message, style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDeviceList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PC DISPONIBLES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('${_foundDevices.length} trouvé(s)', 
                     style: TextStyle(fontSize: 12, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 16),
            ..._foundDevices.map((device) => _buildDeviceItem(device)).toList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDeviceItem(Device device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.desktop_windows, color: AppColors.primary, size: 20),
        ),
        title: Text(device.name, style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('IP: ${device.ipAddress}', style: TextStyle(fontSize: 12)),
        trailing: Icon(Icons.arrow_forward_ios, color: AppColors.primary, size: 16),
        onTap: () => _connectToDevice(device),
      ),
    );
  }
  
  Widget _buildConnectedView() {
    return Column(
      children: [
        _buildConnectionHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildMessageCard(),
                const SizedBox(height: 20),
                _buildActionsSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildConnectionHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.desktop_windows, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connecté à', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      Text(_pcName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(_connectedDevice?.ipAddress ?? '', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.link_off, color: Colors.white),
                  onPressed: _disconnect,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMessageCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            
            // Afficher la progression du transfert si en cours
            if (_isTransferring) ...[
              Text('📤 Envoi: $_currentFileName', 
                   style: TextStyle(fontSize: 14, color: AppColors.primary)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _transferProgress,
                backgroundColor: AppColors.background,
                color: AppColors.primary,
                minHeight: 8,
              ),
              const SizedBox(height: 4),
              Text('${(_transferProgress * 100).toStringAsFixed(0)}%',
                   style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
            ],
            
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Tapez votre message...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppColors.background,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sendMessage,
              icon: Icon(Icons.send, size: 20),
              label: Text('Envoyer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        
        // Bouton d'aide pour les permissions
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.info, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explorateur de fichiers',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Le PC peut voir tes fichiers',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PermissionsHelpScreen(),
                    ),
                  );
                },
                child: Text('Aide', style: TextStyle(color: AppColors.info)),
              ),
            ],
          ),
        ),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(Icons.screen_share, 'Écran', () async {
              await _client.requestScreenShare();
              _showSnackBar('Demande envoyée', AppColors.info);
            }),
            _buildActionButton(Icons.file_upload, 'Fichier', () {
              _pickAndSendFile();
            }),
            _buildActionButton(Icons.notifications, 'Alerte', () async {
              await _client.sendAlert('PING');
              _showSnackBar('Alerte envoyée', AppColors.warning);
            }),
          ],
        ),
      ],
    );
  }
  
  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: IconButton(
            icon: Icon(icon, color: AppColors.primary, size: 28),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
