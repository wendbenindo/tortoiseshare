import 'dart:io';

// Helper pour les opérations réseau
class NetworkHelper {
  // Obtenir l'IP locale de l'appareil
  static Future<String?> getLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.address.startsWith('127.')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('❌ Erreur getLocalIP: $e');
    }
    return null;
  }
  
  // Extraire la base du réseau (ex: "192.168.1" depuis "192.168.1.100")
  static String? getNetworkBase(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return null;
  }
  
  // Formater les octets en format lisible
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  // Valider une adresse IP
  static bool isValidIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    
    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }
}
