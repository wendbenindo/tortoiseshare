// Constantes globales de l'application TortoiseShare
class AppConstants {
  // Réseau
  static const int serverPort = 8081;
  static const Duration connectionTimeout = Duration(seconds: 3);
  static const Duration scanTimeout = Duration(milliseconds: 300);
  
  // App
  static const String appName = 'TortoiseShare';
  static const String appVersion = '1.0.0';
  
  // Réseaux communs à scanner
  static const List<String> commonNetworks = [
    '192.168.1',
    '192.168.0',
    '192.168.43',  // Hotspot mobile
    '192.168.86',  // Google WiFi
    '10.0.0',
  ];
  
  // Adresses prioritaires à scanner en premier
  static const List<int> priorityAddresses = [1, 2, 10, 20, 50, 100, 150, 200, 254];
  static const List<int> commonAddresses = [1, 2, 10, 20, 50, 100, 254];
}
