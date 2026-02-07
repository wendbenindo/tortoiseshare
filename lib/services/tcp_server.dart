import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import '../core/constants.dart';
import '../models/device.dart';
import '../models/file_transfer.dart';
import '../models/remote_file.dart';
import 'file_transfer_service.dart';

// Service serveur TCP pour la communication desktop
class TcpServer {
  final FileTransferService _fileService = FileTransferService();
  ServerSocket? _server;
  final List<Socket> _clients = [];
  final StreamController<ServerMessage> _messageController = 
      StreamController.broadcast();
  
  // Pour gérer la réception de fichiers
  final Map<String, FileReceptionState> _fileReceptions = {};
  
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
    
    // Buffer pour accumuler les données
    List<int> buffer = [];
    bool receivingFile = false;
    bool receivingFrame = false;
    int frameSize = 0;
    int frameBytesNeeded = 0;
    
    // Écouter les messages du client
    client.listen(
      (List<int> data) {
        // Toujours accumuler dans le buffer
        buffer.addAll(data);
        
        if (receivingFile) {
          // Mode réception de fichier - chercher FILE|END
          _checkFileEnd(buffer, ip, () {
            // Callback quand le fichier est terminé
            receivingFile = false;
            buffer.clear();
          });
        } else if (receivingFrame) {
          // Mode réception de frame d'écran
          if (buffer.length >= frameBytesNeeded) {
            // On a reçu tout le frame
            final frameData = Uint8List.fromList(buffer.sublist(0, frameBytesNeeded));
            buffer.removeRange(0, frameBytesNeeded);
            
            // Envoyer le frame au viewer
            _messageController.add(ServerMessage(
              type: ServerMessageType.screenFrame,
              data: {'from': ip, 'frameData': frameData},
            ));
            
            receivingFrame = false;
            frameBytesNeeded = 0;
          }
          // Sinon, attendre plus de données
        } else {
          // Mode réception de messages texte
          // Chercher les lignes complètes (terminées par \n)
          while (true) {
            final newlineIndex = buffer.indexOf(10); // 10 = '\n'
            if (newlineIndex == -1) break; // Pas de ligne complète
            
            // Extraire la ligne
            final lineBytes = buffer.sublist(0, newlineIndex);
            buffer.removeRange(0, newlineIndex + 1);
            
            // Vérifier si c'est un message texte valide
            if (lineBytes.isEmpty) continue;
            
            // Essayer de décoder en UTF-8
            try {
              final message = utf8.decode(lineBytes, allowMalformed: false).trim();
              
              if (message.startsWith('FILE|START|')) {
                // Début de réception de fichier
                receivingFile = true;
                _handleFileStart(message, ip);
                break; // Sortir de la boucle while
              } else if (message.startsWith('SCREEN|FRAME|')) {
                // Début de réception de frame d'écran
                final parts = message.split('|');
                if (parts.length >= 3) {
                  frameSize = int.tryParse(parts[2]) ?? 0;
                  if (frameSize > 0) {
                    receivingFrame = true;
                    frameBytesNeeded = frameSize;
                    break; // Sortir de la boucle while pour passer en mode frame
                  }
                }
              } else if (message.isNotEmpty) {
                // Message normal
                _handleClientMessage(message, ip);
              }
            } catch (e) {
              // Ignorer silencieusement les erreurs de décodage UTF-8
              // (données binaires mélangées)
            }
          }
        }
      },
      onDone: () {
        _clients.remove(client);
        _fileReceptions.remove(client.remoteAddress.address);
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
  
  // Gérer le début de réception d'un fichier
  void _handleFileStart(String message, String clientIP) {
    // Format: FILE|START|filename.jpg|12345
    final parts = message.split('|');
    if (parts.length < 4) return;
    
    final fileName = parts[2];
    final fileSize = int.tryParse(parts[3]) ?? 0;
    
    print('📥 Début réception: $fileName (${_formatBytes(fileSize)}) de $clientIP');
    
    // Créer l'état de réception
    _fileReceptions[clientIP] = FileReceptionState(
      fileName: fileName,
      fileSize: fileSize,
      receivedBytes: [],
    );
    
    _messageController.add(ServerMessage(
      type: ServerMessageType.fileStart,
      data: {
        'from': clientIP,
        'fileName': fileName,
        'fileSize': fileSize,
      },
    ));
  }
  
  // Vérifier si on a reçu la fin du fichier
  void _checkFileEnd(List<int> buffer, String clientIP, Function onComplete) {
    final state = _fileReceptions[clientIP];
    if (state == null) return;
    
    // Chercher le marqueur de fin "FILE|END\n"
    final endMarker = utf8.encode('FILE|END\n');
    final endIndex = _findSequence(buffer, endMarker);
    
    if (endIndex != -1) {
      // On a trouvé la fin !
      final fileData = buffer.sublist(0, endIndex);
      state.receivedBytes.addAll(fileData);
      
      print('✅ Fichier reçu: ${state.fileName} (${_formatBytes(state.receivedBytes.length)})');
      
      // Sauvegarder le fichier
      _saveReceivedFile(state, clientIP);
      
      // Nettoyer
      _fileReceptions.remove(clientIP);
      
      // Retirer FILE|END\n du buffer
      buffer.removeRange(0, endIndex + endMarker.length);
      
      // Appeler le callback pour revenir en mode texte
      onComplete();
    } else {
      // Pas encore fini, continuer à accumuler
      state.receivedBytes.addAll(buffer);
      buffer.clear();
      
      // Mettre à jour la progression
      final progress = state.receivedBytes.length / state.fileSize;
      _messageController.add(ServerMessage(
        type: ServerMessageType.fileProgress,
        data: {
          'from': clientIP,
          'fileName': state.fileName,
          'progress': progress,
        },
      ));
    }
  }
  
  // Trouver une séquence dans un buffer
  int _findSequence(List<int> buffer, List<int> sequence) {
    for (int i = 0; i <= buffer.length - sequence.length; i++) {
      bool found = true;
      for (int j = 0; j < sequence.length; j++) {
        if (buffer[i + j] != sequence[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }
  
  // Sauvegarder le fichier reçu
  Future<void> _saveReceivedFile(FileReceptionState state, String clientIP) async {
    // Dossier de sauvegarde (Downloads par défaut)
    final savePath = Platform.isWindows
        ? '${Platform.environment['USERPROFILE']}\\Downloads\\TortoiseShare'
        : '${Platform.environment['HOME']}/Downloads/TortoiseShare';
    
    final success = await _fileService.saveReceivedFile(
      state.fileName,
      state.receivedBytes,
      savePath,
    );
    
    if (success) {
      _messageController.add(ServerMessage(
        type: ServerMessageType.fileComplete,
        data: {
          'from': clientIP,
          'fileName': state.fileName,
          'filePath': '$savePath/${state.fileName}',
        },
      ));
    } else {
      _messageController.add(ServerMessage(
        type: ServerMessageType.fileError,
        data: {
          'from': clientIP,
          'fileName': state.fileName,
          'error': 'Erreur de sauvegarde',
        },
      ));
    }
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    } else if (message.startsWith('LINK|')) {
      final link = message.substring(5);
      _messageController.add(ServerMessage(
        type: ServerMessageType.linkMessage,
        data: {'from': clientIP, 'link': link},
      ));
    } else if (message.startsWith('SCREEN|REQUEST')) {
      _messageController.add(ServerMessage(
        type: ServerMessageType.screenRequest,
        data: {'from': clientIP},
      ));
    } else if (message == 'SCREEN|START') {
      // Le mobile commence à partager son écran
      print('📱 Début partage écran mobile de $clientIP');
      _messageController.add(ServerMessage(
        type: ServerMessageType.screenShareStart,
        data: {'from': clientIP},
      ));
    } else if (message == 'SCREEN|STOP') {
      // Le mobile arrête de partager son écran
      print('🛑 Fin partage écran mobile de $clientIP');
      _messageController.add(ServerMessage(
        type: ServerMessageType.screenShareStop,
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
    } else if (message.startsWith('FILE|LIST_RESPONSE|')) {
      // Réponse avec la liste des fichiers
      final jsonData = message.substring(19);
      try {
        final List<dynamic> filesJson = jsonDecode(jsonData);
        final files = filesJson.map((json) => RemoteFile.fromJson(json)).toList();
        
        _messageController.add(ServerMessage(
          type: ServerMessageType.fileListResponse,
          data: {'from': clientIP, 'files': files},
        ));
      } catch (e) {
        print('❌ Erreur parsing FILE|LIST_RESPONSE: $e');
        _messageController.add(ServerMessage(
          type: ServerMessageType.fileListError,
          data: {'from': clientIP, 'error': e.toString()},
        ));
      }
    } else if (message.startsWith('FILE|LIST_ERROR|')) {
      final error = message.substring(16);
      _messageController.add(ServerMessage(
        type: ServerMessageType.fileListError,
        data: {'from': clientIP, 'error': error},
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
  
  // Demander la liste des fichiers racines au mobile
  Future<void> requestRootDirectories(String clientIP) async {
    await sendToClient(clientIP, 'FILE|LIST|ROOT');
  }
  
  // Demander la liste des fichiers d'un répertoire au mobile
  Future<void> requestDirectoryList(String clientIP, String path) async {
    await sendToClient(clientIP, 'FILE|LIST|$path');
  }
  
  // Demander le téléchargement d'un fichier depuis le mobile
  Future<void> requestFileDownload(String clientIP, String filePath) async {
    await sendToClient(clientIP, 'FILE|DOWNLOAD|$filePath');
  }
  
  // Demander une miniature d'image depuis le mobile
  Future<void> requestThumbnail(String clientIP, String filePath) async {
    await sendToClient(clientIP, 'FILE|THUMBNAIL|$filePath');
  }
  
  // Envoyer un frame de partage d'écran
  Future<void> sendScreenFrame(String clientIP, Uint8List frameData) async {
    try {
      for (final client in _clients) {
        if (client.remoteAddress.address == clientIP) {
          // Envoyer les métadonnées
          client.write('SCREEN|FRAME|${frameData.length}\n');
          await client.flush();
          
          // Envoyer les données
          client.add(frameData);
          await client.flush();
          
          return;
        }
      }
    } catch (e) {
      print('❌ Erreur envoi frame: $e');
    }
  }
  
  // Notifier le début du partage d'écran
  Future<void> notifyScreenShareStart(String clientIP) async {
    await sendToClient(clientIP, 'SCREEN|START');
  }
  
  // Notifier la fin du partage d'écran
  Future<void> notifyScreenShareStop(String clientIP) async {
    await sendToClient(clientIP, 'SCREEN|STOP');
  }
  
  // Nettoyer les ressources
  void dispose() {
    stopServer();
    _messageController.close();
    _fileService.dispose();
  }
}

// État de réception d'un fichier
class FileReceptionState {
  final String fileName;
  final int fileSize;
  final List<int> receivedBytes;
  
  FileReceptionState({
    required this.fileName,
    required this.fileSize,
    required this.receivedBytes,
  });
}

// Types de messages du serveur
enum ServerMessageType {
  serverStarted,
  serverStopped,
  clientConnected,
  clientDisconnected,
  textMessage,
  linkMessage,       // Nouveau type pour les liens
  screenRequest,
  screenShareStart,  // Début du partage d'écran
  screenShareStop,   // Fin du partage d'écran
  screenFrame,       // Frame d'écran reçu
  mobileConnected,
  alert,
  fileStart,
  fileProgress,
  fileComplete,
  fileError,
  fileListResponse,  // Réponse avec la liste des fichiers
  fileListError,     // Erreur lors de la liste
  thumbnailReceived, // Miniature d'image reçue
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
