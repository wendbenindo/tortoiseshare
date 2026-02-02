import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import '../core/constants.dart';
import '../models/file_transfer.dart';
import 'file_transfer_service.dart';

// Service client TCP pour la communication mobile → desktop
class TcpClient {
  final FileTransferService _fileService = FileTransferService();
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
  
  // Envoyer un fichier
  Future<bool> sendFile(String filePath, {
    Function(double progress)? onProgress,
  }) async {
    if (_socket == null) return false;
    
    try {
      // 1. Préparer le fichier
      final transfer = await _fileService.prepareFile(filePath);
      if (transfer == null) return false;
      
      print('📤 Envoi du fichier: ${transfer.fileName}');
      
      // 2. Envoyer les métadonnées du fichier
      final metadata = 'FILE|START|${transfer.fileName}|${transfer.fileSize}\n';
      _socket!.write(metadata);
      await _socket!.flush();
      
      print('📋 Métadonnées envoyées');
      
      // 3. Lire et envoyer le fichier par chunks
      int bytesSent = 0;
      
      await for (final chunk in _fileService.readFileChunks(filePath)) {
        // Envoyer le chunk
        _socket!.add(chunk);
        await _socket!.flush();
        
        // Mettre à jour la progression
        bytesSent += chunk.length;
        final progress = bytesSent / transfer.fileSize;
        onProgress?.call(progress);
        
        // Petit délai pour ne pas surcharger
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      // 4. Envoyer le signal de fin
      await Future.delayed(const Duration(milliseconds: 100));
      _socket!.write('FILE|END\n');
      await _socket!.flush();
      
      print('✅ Fichier envoyé: ${transfer.fileName}');
      return true;
      
    } catch (e) {
      print('❌ Erreur envoi fichier: $e');
      return false;
    }
  }
  
  // Nettoyer les ressources
  void dispose() {
    disconnect();
    _messageController.close();
    _fileService.dispose();
  }
}
