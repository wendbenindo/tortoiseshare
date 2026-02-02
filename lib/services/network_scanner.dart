import 'dart:io';
import '../core/constants.dart';
import '../models/device.dart';

// Service pour scanner le réseau et trouver des appareils
class NetworkScanner {
  bool _isScanning = false;
  
  // Callback pour la progression du scan
  Function(int current, int total)? onProgress;
  
  // Détecter le réseau local de l'appareil
  Future<String?> detectOwnNetwork() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.address.startsWith('127.')) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              print('📱 Mon IP: ${addr.address}');
              print('📱 Réseau détecté: ${parts[0]}.${parts[1]}.${parts[2]}');
              return '${parts[0]}.${parts[1]}.${parts[2]}';
            }
          }
        }
      }
    } catch (e) {
      print('❌ Erreur détection réseau: $e');
    }
    return null;
  }
  
  // Scanner un réseau complet
  Stream<Device> scanNetwork() async* {
    _isScanning = true;
    
    // D'abord détecter notre propre réseau
    final networkBase = await detectOwnNetwork();
    
    if (networkBase != null) {
      // Scanner les adresses prioritaires d'abord
      yield* _scanPriorityAddresses(networkBase);
      
      // Puis scanner toutes les autres adresses
      yield* _scanAllAddresses(networkBase);
    } else {
      // Fallback : scanner les réseaux communs
      yield* _scanCommonNetworks();
    }
    
    _isScanning = false;
  }
  
  // Scanner les adresses prioritaires
  Stream<Device> _scanPriorityAddresses(String networkBase) async* {
    int progress = 0;
    final total = AppConstants.priorityAddresses.length;
    
    for (final i in AppConstants.priorityAddresses) {
      if (!_isScanning) break;
      
      final ip = '$networkBase.$i';
      progress++;
      onProgress?.call(progress, total);
      
      if (await _testConnection(ip)) {
        yield Device(
          id: ip,
          name: 'PC-${ip.split('.').last}',
          ipAddress: ip,
          type: DeviceType.desktop,
          connectedAt: DateTime.now(),
        );
      }
      
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
  
  // Scanner toutes les adresses
  Stream<Device> _scanAllAddresses(String networkBase) async* {
    int progress = 0;
    const total = 254;
    
    for (int i = 1; i <= 254; i++) {
      if (!_isScanning) break;
      
      // Ignorer les adresses déjà scannées
      if (AppConstants.priorityAddresses.contains(i)) continue;
      
      final ip = '$networkBase.$i';
      progress++;
      
      if (i % 10 == 0) {
        onProgress?.call(progress, total);
      }
      
      if (await _testConnection(ip)) {
        yield Device(
          id: ip,
          name: 'PC-${ip.split('.').last}',
          ipAddress: ip,
          type: DeviceType.desktop,
          connectedAt: DateTime.now(),
        );
      }
      
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }
  
  // Scanner les réseaux communs
  Stream<Device> _scanCommonNetworks() async* {
    int progress = 0;
    final total = AppConstants.commonNetworks.length * 
                  AppConstants.commonAddresses.length;
    
    for (final network in AppConstants.commonNetworks) {
      for (final i in AppConstants.commonAddresses) {
        if (!_isScanning) break;
        
        final ip = '$network.$i';
        progress++;
        onProgress?.call(progress, total);
        
        if (await _testConnection(ip)) {
          yield Device(
            id: ip,
            name: 'PC-${ip.split('.').last}',
            ipAddress: ip,
            type: DeviceType.desktop,
            connectedAt: DateTime.now(),
          );
        }
        
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }
  
  // Tester si une IP a un serveur TortoiseShare
  Future<bool> _testConnection(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        AppConstants.serverPort,
        timeout: AppConstants.scanTimeout,
      );
      
      socket.write('MOBILE|HELLO\n');
      await socket.flush();
      socket.destroy();
      
      print('✅ Serveur trouvé: $ip');
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Arrêter le scan
  void stopScan() {
    _isScanning = false;
  }
}
