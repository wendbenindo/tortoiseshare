// lib/pc_server.dart - Version améliorée
import 'dart:io';
import 'core/services/tcp_server.dart';
import 'core/services/auto_discovery.dart';

void main() async {
  print('''
  🐢 TORTOISESHARE SERVEUR (PC)
  ============================
  Mode: Découverte automatique
  Port: 8081
  ============================
  ''');
  
  final server = TcpServer();
  final discovery = AutoDiscovery();
  
  // Obtenir le nom du PC
  final pcName = Platform.localHostname.split('.')[0];
  print('💻 Nom du PC: $pcName');
  
  // Démarrer le serveur TCP
  await server.startServer(port: 8081);
  
  // Annoncer notre service sur le réseau
  await discovery.startAdvertising(pcName);
  
  // Gérer les connexions entrantes
  server.messageStream.listen((message) {
    final type = message['type'];
    final client = message['client'];
    
    switch (type) {
      case 'file_start':
        print('📥 [${DateTime.now().toString().split(' ')[1]}] '
              'Réception: ${message['filename']} '
              '(${_formatBytes(message['size'])}) de $client');
        break;
        
      case 'file_end':
        print('✅ [${DateTime.now().toString().split(' ')[1]}] '
              'Fichier reçu: ${message['filename']}');
        break;
        
      case 'text':
        print('📝 [${DateTime.now().toString().split(' ')[1]}] '
              'Message de $client: ${message['text']}');
        break;
        
      case 'screen_request':
        print('🖥️  [${DateTime.now().toString().split(' ')[1]}] '
              '$client demande le partage d\'écran');
        // Répondre
        server.sendToClient(client, 'SERVER|SCREEN|READY');
        break;
    }
  });
  
  // Afficher les IPs disponibles
  print('\n🌐 IPs disponibles pour connexion:');
  final interfaces = await NetworkInterface.list();
  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (addr.type == InternetAddressType.IPv4 && 
          !addr.address.startsWith('127.')) {
        print('   • ${addr.address}:8081');
      }
    }
  }
  
  print('\n📢 Service annoncé sur le réseau local');
  print('📱 Les mobiles peuvent vous découvrir automatiquement');
  print('\n🛑 Pour arrêter: Ctrl+C');
  
  // Attendre indéfiniment
  await ProcessSignal.sigint.watch().first;
  await server.stopServer();
  await discovery.stop();
  print('\n👋 Serveur arrêté');
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}