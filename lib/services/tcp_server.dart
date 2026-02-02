import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../core/constants.dart';
import '../models/device.dart';

// Service serveur TCP pour la communication desktop
class TcpServer {
  ServerSocket? _server;
  final List<Socket> _clients = [];
  final StreamController<ServerMessage> _messageController = 
      StreamController.broadcast();
  
  Stream<ServerMessage> get messageStream => _messageController.stream;
  bool get isRunning => _server != null;
  List<Device> get connectedDevices => _clients.map((client) {
    return Device(
      id: client.remoteAddress.address,
      name: 'Mobile-${client.remoteAddress.address.split('.').last}',
      ipAddress: client.remoteAddress.address,
      type: DeviceType.mobile,
      connectedAt: DateTime.now(),
    );
  }).toList();
  
  // Démarrer le serveur
  Future<bool> startServer() async {
    try {
      _server = await ServerSocket.bind('0.0.0.0', AppConstants.serverPort);
      
      _server!.listen((Socket client) {
        _handleNewClient(client);
      });
      
      _messageController.add(ServerMessage(
        type: ServerMessageType.serverStarted,
        data: {'port': AppConstants.serverPort},
      ));
      
      print('✅ Serveur démarré sur le port ${AppConstants.serverPort}');
      return true;
    } catch (e) {
      print('❌ Erreur démarrage serveur: $e');
      return false;
    }
  }
  
  // Arrêter le serveur
  Future<void> stopServer() async {
    for (final client in _clients) {
      client.destroy();
    }
    _clients.clear();
    
    await _server?.close();
    _server = null;
    
    _messageController.add(ServerMessage(
      type: ServerMessageType.serverStopped,
      data: {},
    ));
    
    print('🛑 Serveur arrêté');
  }
  
  // Gérer un nouveau client
  void _handleNewClient(Socket client) {
    final ip = client.remoteAddress.address;
    
    _clients.add(client);
    
    _messageController.add(ServerMessage(
      type: ServerMessageType.clientConnected,
      data: {'ip': ip},
    ));
    
    // Envoyer le nom du serveur
    client.write('SERVER|NAME|PC-TortoiseShare\n');
    
    // Écouter les messages du client
    client.listen(
      (List<int> data) {
        final message = utf8.decode(data).trim();
        _handleClientMessage(message, ip);
      },
      onDone: () {
        _clients.remove(client);
        _messageController.add(ServerMessage(
          type: ServerMessageType.clientDisconnected,
          data: {'ip': ip},
        ));
        client.destroy();
      },
      onError: (error) {
        print('❌ Erreur client: $error');
        _clients.remove(client);
        client.destroy();
      },
    );
    
    print('📱 Client connecté: $ip');
  }
  
  // Gérer un message d'un client
  void _handleClientMessage(String message, String clientIP) {
    print('📨 Message de $clientIP: $message');
    
    if (message.startsWith('TEXT|')) {
      final text = message.substring(5);
      _messageController.add(ServerMessage(
        type: ServerMessageType.textMessage,
        data: {'from': clientIP, 'text': text},
      ));
    } else if (message.startsWith('SCREEN|REQUEST')) {
      _messageController.add(ServerMessage(
        type: ServerMessageType.screenRequest,
        data: {'from': clientIP},
      ));
    } else if (message.startsWith('MOBILE|')) {
      _messageController.add(ServerMessage(
        type: ServerMessageType.mobileConnected,
        data: {'from': clientIP},
      ));
    } else if (message.startsWith('ALERT|')) {
      final alertType = message.substring(6);
      _messageController.add(ServerMessage(
        type: ServerMessageType.alert,
        data: {'from': clientIP, 'alertType': alertType},
      ));
    }
  }
  
  // Envoyer un message à un client spécifique
  Future<bool> sendToClient(String clientIP, String message) async {
    try {
      for (final client in _clients) {
        if (client.remoteAddress.address == clientIP) {
          client.write('$message\n');
          await client.flush();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('❌ Erreur envoi: $e');
      return false;
    }
  }
  
  // Nettoyer les ressources
  void dispose() {
    stopServer();
    _messageController.close();
  }
}

// Types de messages du serveur
enum ServerMessageType {
  serverStarted,
  serverStopped,
  clientConnected,
  clientDisconnected,
  textMessage,
  screenRequest,
  mobileConnected,
  alert,
}

// Message du serveur
class ServerMessage {
  final ServerMessageType type;
  final Map<String, dynamic> data;
  
  ServerMessage({
    required this.type,
    required this.data,
  });
}
