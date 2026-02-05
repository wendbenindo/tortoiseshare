import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import '../core/constants.dart';
import '../models/file_transfer.dart';
import '../models/remote_file.dart';
import 'file_transfer_service.dart';
import 'file_browser_service.dart';

// Service client TCP pour la communication mobile → desktop
class TcpClient {
  final FileTransferService _fileService = FileTransferService();
  final FileBrowserService _browserService = FileBrowserService();
  Socket? _socket;
  final StreamController<String> _messageController = StreamController.broadcast();
  final StreamController<Uint8List> _screenFrameController = StreamController.broadcast();
  
  Stream<String> get messageStream => _messageController.stream;
  Stream<Uint8List> get screenFrameStream => _screenFrameController.stream;
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
          
          // Gérer les demandes de liste de fichiers
          if (message.startsWith('FILE|LIST|')) {
            _handleFileListRequest(message);
          } else if (message.startsWith('FILE|DOWNLOAD|')) {
            _handleFileDownloadRequest(message);
          } else {
            _messageController.add(message);
          }
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
  
  // Envoyer un message brut (sans préfixe TEXT|)
  Future<bool> sendRawMessage(String message) async {
    if (_socket == null) return false;
    
    try {
      _socket!.write('$message\n');
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
  
  // Envoyer un frame d'écran
  Future<bool> sendScreenFrame(Uint8List frameData) async {
    if (_socket == null) return false;
    
    try {
      // Créer le message complet avec métadonnées + données
      final header = utf8.encode('SCREEN|FRAME|${frameData.length}\n');
      
      // Envoyer header + frame en une seule fois
      _socket!.add(header);
      _socket!.add(frameData);
      
      // Flush une seule fois à la fin
      await _socket!.flush();
      
      return true;
    } catch (e) {
      // Ignorer les erreurs de socket fermé silencieusement
      if (!e.toString().contains('StreamSink is bound')) {
        print('❌ Erreur envoi frame: $e');
      }
      return false;
    }
  }
  
  // Nettoyer les ressources
  void dispose() {
    disconnect();
    _messageController.close();
    _fileService.dispose();
  }
  
  // Gérer une demande de liste de fichiers du PC
  Future<void> _handleFileListRequest(String message) async {
    try {
      // Format: FILE|LIST|path ou FILE|LIST|ROOT
      final parts = message.split('|');
      if (parts.length < 3) return;
      
      final path = parts[2];
      List<RemoteFile> files;
      
      if (path == 'ROOT') {
        // Demande des répertoires racines
        files = await _browserService.getRootDirectories();
      } else {
        // Demande d'un répertoire spécifique
        files = await _browserService.listDirectory(path);
      }
      
      // Convertir en JSON et envoyer
      final filesJson = files.map((f) => f.toJson()).toList();
      final response = 'FILE|LIST_RESPONSE|${jsonEncode(filesJson)}\n';
      
      _socket?.write(response);
      await _socket?.flush();
      
      print('📂 Liste envoyée: ${files.length} éléments');
      
    } catch (e) {
      print('❌ Erreur _handleFileListRequest: $e');
      _socket?.write('FILE|LIST_ERROR|$e\n');
      await _socket?.flush();
    }
  }
  
  // Gérer une demande de téléchargement de fichier du PC
  Future<void> _handleFileDownloadRequest(String message) async {
    try {
      // Format: FILE|DOWNLOAD|/path/to/file.jpg
      final parts = message.split('|');
      if (parts.length < 3) return;
      
      final filePath = parts[2];
      
      print('📤 Demande de téléchargement: $filePath');
      
      // Vérifier que le fichier existe
      final exists = await _browserService.fileExists(filePath);
      if (!exists) {
        print('❌ Fichier inexistant: $filePath');
        _socket?.write('FILE|DOWNLOAD_ERROR|Fichier inexistant\n');
        await _socket?.flush();
        return;
      }
      
      // Envoyer le fichier (sendFile gère déjà FILE|START et FILE|END)
      print('📤 Envoi du fichier...');
      await sendFile(filePath);
      print('✅ Fichier envoyé avec succès');
      
    } catch (e) {
      print('❌ Erreur _handleFileDownloadRequest: $e');
      _socket?.write('FILE|DOWNLOAD_ERROR|$e\n');
      await _socket?.flush();
    }
  }
}
