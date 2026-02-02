import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../core/constants.dart';

// Service client TCP pour la communication mobile → desktop
class TcpClient {
  Socket? _socket;
  final StreamController<String> _messageController = StreamController.broadcast();
  
  Stream<String> get messageStream => _messageController.stream;
  bool get isConnected => _socket != null;
  
  // Connecter au serveur
  Future<bool> connect(String ip) async {
    try {
      _socket = await Socket.connect(
        ip,
        AppConstants.serverPort,
        timeout: AppConstants.connectionTimeout,
      );
      
      // Écouter les messages du serveur
      _socket!.listen(
        (data) {
          final message = utf8.decode(data).trim();
          _messageController.add(message);
        },
        onError: (error) {
          print('❌ Erreur socket: $error');
          disconnect();
        },
        onDone: () {
          print('🔌 Connexion fermée');
          disconnect();
        },
      );
      
      // Envoyer une demande de connexion
      _socket!.write('MOBILE|CONNECT\n');
      await _socket!.flush();
      
      print('✅ Connecté à $ip');
      return true;
    } catch (e) {
      print('❌ Erreur connexion: $e');
      return false;
    }
  }
  
  // Déconnecter
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }
  
  // Envoyer un message texte
  Future<bool> sendMessage(String message) async {
    if (_socket == null) return false;
    
    try {
      _socket!.write('TEXT|$message\n');
      await _socket!.flush();
      return true;
    } catch (e) {
      print('❌ Erreur envoi: $e');
      return false;
    }
  }
  
  // Demander le partage d'écran
  Future<bool> requestScreenShare() async {
    if (_socket == null) return false;
    
    try {
      _socket!.write('SCREEN|REQUEST\n');
      await _socket!.flush();
      return true;
    } catch (e) {
      print('❌ Erreur demande écran: $e');
      return false;
    }
  }
  
  // Envoyer une alerte
  Future<bool> sendAlert(String alertType) async {
    if (_socket == null) return false;
    
    try {
      _socket!.write('ALERT|$alertType\n');
      await _socket!.flush();
      return true;
    } catch (e) {
      print('❌ Erreur alerte: $e');
      return false;
    }
  }
  
  // Nettoyer les ressources
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
