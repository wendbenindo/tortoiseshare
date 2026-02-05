import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../core/colors.dart';
import '../core/network_helper.dart';
import '../services/tcp_server.dart';
import '../services/screen_share_service.dart';
import '../screens/mobile_screen_viewer.dart';
import '../models/remote_file.dart';
import '../models/download_task.dart';

class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  // Service
  final TcpServer _server = TcpServer();
  final ScreenShareService _screenShare = ScreenShareService();
  
  // État
  bool _isRunning = false;
  String? _serverIP;
  final List<LogEntry> _logs = [];
  int _messagesReceived = 0;
  
  // Pour les demandes de fichiers en attente
  final List<FileRequest> _pendingFileRequests = [];
  
  // Pour l'explorateur de fichiers
  bool _showFileBrowser = false;
  List<RemoteFile> _currentFiles = [];
  String _currentPath = 'ROOT';
  bool _loadingFiles = false;
  String? _connectedClientIP;
  
  // Pour la file d'attente de téléchargements
  final List<DownloadTask> _downloadQueue = [];
  bool _isProcessingDownload = false;
  
  // Cache pour les miniatures d'images
  final Map<String, Uint8List> _thumbnailCache = {};
  
  // Pour le partage d'écran
  bool _isSharingScreen = false;
  bool _isViewingMobileScreen = false;
  GlobalKey<MobileScreenViewerState>? _viewerKey;
  
  @override
  void initState() {
    super.initState();
    _init();
  }
  
  Future<void> _init() async {
    _serverIP = await NetworkHelper.getLocalIP();
    
    // Écouter les messages du serveur
    _server.messageStream.listen((message) {
      _handleServerMessage(message);
    });
    
    setState(() {});
  }
  
  void _handleServerMessage(ServerMessage message) {
    switch (message.type) {
      case ServerMessageType.serverStarted:
        _addLog('Serveur démarré sur le port ${message.data['port']}', 
                LogType.system, Icons.check_circle);
        break;
        
      case ServerMessageType.serverStopped:
        _addLog('Serveur arrêté', LogType.system, Icons.stop_circle);
        break;
        
      case ServerMessageType.clientConnected:
        // Pas de log pour éviter le spam
        _connectedClientIP = message.data['ip'];
        break;
        
      case ServerMessageType.clientDisconnected:
        _addLog('Appareil déconnecté: ${message.data['ip']}', 
                LogType.disconnect, Icons.link_off);
        if (_connectedClientIP == message.data['ip']) {
          _connectedClientIP = null;
          _showFileBrowser = false;
        }
        break;
        
      case ServerMessageType.textMessage:
        // Pas de log pour les messages texte
        _messagesReceived++;
        break;
        
      case ServerMessageType.screenRequest:
        _addLog('Demande de partage d\'écran', LogType.screen, Icons.screen_share,
                sender: message.data['from']);
        break;
        
      case ServerMessageType.mobileConnected:
        _addLog('Connexion mobile établie', LogType.mobile, Icons.smartphone,
                sender: message.data['from']);
        break;
        
      case ServerMessageType.alert:
        _addLog('Alerte: ${message.data['alertType']}', LogType.alert, Icons.notifications,
                sender: message.data['from']);
        break;
        
      case ServerMessageType.fileStart:
        // Un fichier commence à être reçu
        final fileName = message.data['fileName'];
        final fileSize = message.data['fileSize'];
        final from = message.data['from'];
        
        // Chercher une tâche existante (peu importe le statut)
        final existingTask = _downloadQueue.firstWhere(
          (t) => t.fileName == fileName,
          orElse: () => DownloadTask(id: '', fileName: '', filePath: '', fileSize: 0, from: ''),
        );
        
        if (existingTask.id.isNotEmpty) {
          // Tâche trouvée - mettre à jour le statut
          setState(() {
            existingTask.status = DownloadStatus.downloading;
          });
        } else {
          // Tâche non trouvée - créer une nouvelle (cas rare)
          final newTask = DownloadTask(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            fileName: fileName,
            filePath: '',
            fileSize: fileSize,
            from: from,
            status: DownloadStatus.downloading,
          );
          setState(() {
            _downloadQueue.add(newTask);
          });
        }
        break;
        
      case ServerMessageType.fileProgress:
        // Mettre à jour la progression
        final fileName = message.data['fileName'];
        final progress = message.data['progress'] ?? 0.0;
        
        // Chercher la tâche en cours de téléchargement
        final task = _downloadQueue.firstWhere(
          (t) => t.fileName == fileName && t.status == DownloadStatus.downloading,
          orElse: () => DownloadTask(id: '', fileName: '', filePath: '', fileSize: 0, from: ''),
        );
        
        if (task.id.isNotEmpty) {
          setState(() {
            task.progress = progress;
          });
        }
        break;
        
      case ServerMessageType.fileComplete:
        final fileName = message.data['fileName'];
        
        final task = _downloadQueue.firstWhere(
          (t) => t.fileName == fileName,
          orElse: () => DownloadTask(id: '', fileName: '', filePath: '', fileSize: 0, from: ''),
        );
        
        if (task.id.isNotEmpty) {
          setState(() {
            task.status = DownloadStatus.completed;
            task.progress = 1.0;
          });
          
          // Retirer de la file après 2 secondes
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _downloadQueue.remove(task);
              });
            }
          });
        }
        
        _addLog('✅ Fichier reçu: ${message.data['fileName']}', 
                LogType.file, Icons.check_circle,
                sender: message.data['from']);
        
        // Traiter le prochain téléchargement
        _isProcessingDownload = false;
        _processNextDownload();
        break;
        
      case ServerMessageType.fileError:
        final fileName = message.data['fileName'];
        
        final task = _downloadQueue.firstWhere(
          (t) => t.fileName == fileName,
          orElse: () => DownloadTask(id: '', fileName: '', filePath: '', fileSize: 0, from: ''),
        );
        
        if (task.id.isNotEmpty) {
          setState(() {
            task.status = DownloadStatus.failed;
            task.error = 'Erreur de téléchargement';
          });
          
          // Retirer de la file après 3 secondes
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _downloadQueue.remove(task);
              });
            }
          });
        }
        
        _addLog('❌ Erreur fichier: ${message.data['fileName']}', 
                LogType.error, Icons.error,
                sender: message.data['from']);
        
        // Traiter le prochain téléchargement
        _isProcessingDownload = false;
        _processNextDownload();
        break;
        
      case ServerMessageType.fileListResponse:
        // Réponse avec la liste des fichiers (pas de log)
        final files = message.data['files'] as List<RemoteFile>;
        setState(() {
          _currentFiles = files;
          _loadingFiles = false;
        });
        
        // Charger les miniatures pour les images
        _loadThumbnailsForImages();
        break;
        
      case ServerMessageType.fileListError:
        setState(() {
          _loadingFiles = false;
        });
        _addLog('❌ Erreur liste fichiers: ${message.data['error']}', 
                LogType.error, Icons.error,
                sender: message.data['from']);
        break;
        
      case ServerMessageType.thumbnailReceived:
        // Miniature d'image reçue
        final filePath = message.data['filePath'] as String;
        final thumbnailData = message.data['data'] as Uint8List;
        
        setState(() {
          _thumbnailCache[filePath] = thumbnailData;
        });
        break;
        
      case ServerMessageType.screenShareStart:
        // Début du partage d'écran mobile
        print('🖥️ Desktop: Réception SCREEN|START, ouverture du viewer...');
        _openMobileScreenViewer();
        break;
        
      case ServerMessageType.screenShareStop:
        // Fin du partage d'écran mobile
        print('🖥️ Desktop: Réception SCREEN|STOP, fermeture du viewer...');
        if (_isViewingMobileScreen && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        setState(() {
          _isViewingMobileScreen = false;
        });
        break;
        
      case ServerMessageType.screenFrame:
        // Frame d'écran reçu
        if (_isViewingMobileScreen && _viewerKey?.currentState != null) {
          final frameData = message.data['frameData'] as Uint8List;
          _viewerKey!.currentState!.updateFrame(frameData);
        }
        break;
    }
  }
  
  // Ouvrir la visualisation de l'écran mobile
  void _openMobileScreenViewer() {
    if (_isViewingMobileScreen) return;
    
    setState(() {
      _isViewingMobileScreen = true;
    });
    
    _viewerKey = GlobalKey<MobileScreenViewerState>();
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MobileScreenViewer(
          key: _viewerKey,
          onClose: () {
            Navigator.pop(context);
            setState(() {
              _isViewingMobileScreen = false;
            });
          },
        ),
      ),
    );
  }
  
  // Mettre à jour le frame de l'écran mobile
  void _updateMobileScreenFrame(Uint8List frameData) {
    _viewerKey?.currentState?.updateFrame(frameData);
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  void _showNotification(String message) {
    // TODO: Ajouter une vraie notification système
    print('🔔 Notification: $message');
  }
  
  // Afficher une demande d'acceptation de fichier
  void _showFileRequestDialog(String fileName, int fileSize, String from) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.file_download, color: AppColors.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Fichier entrant', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Un appareil souhaite vous envoyer un fichier :',
                 style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.insert_drive_file, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Taille: ${_formatBytes(fileSize)}',
                       style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('De: $from',
                       style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Le fichier sera sauvegardé dans :',
                 style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Downloads/TortoiseShare/',
                 style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _rejectFile(fileName, from);
            },
            child: Text('Refuser', style: TextStyle(color: AppColors.error)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptFile(fileName, fileSize, from);
            },
            icon: Icon(Icons.check, color: Colors.white),
            label: Text('Accepter', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
  
  void _acceptFile(String fileName, int fileSize, String from) {
    _addLog('✅ Accepté: $fileName', LogType.file, Icons.check_circle, sender: from);
    _addLog('📥 Réception en cours...', LogType.file, Icons.downloading, sender: from);
    // Le serveur continue automatiquement la réception
  }
  
  void _rejectFile(String fileName, String from) {
    _addLog('❌ Refusé: $fileName', LogType.file, Icons.cancel, sender: from);
    // TODO: Envoyer un message au client pour annuler
    _server.sendToClient(from, 'FILE|REJECTED\n');
  }
  
  void _addLog(String message, LogType type, IconData icon, {String? sender}) {
    setState(() {
      _logs.insert(0, LogEntry(
        message: message,
        type: type,
        icon: icon,
        sender: sender,
        timestamp: DateTime.now(),
      ));
      
      if (_logs.length > 50) {
        _logs.removeLast();
      }
    });
  }
  
  Future<void> _toggleServer() async {
    if (_isRunning) {
      await _server.stopServer();
      setState(() => _isRunning = false);
    } else {
      final success = await _server.startServer();
      setState(() => _isRunning = success);
    }
  }
  
  void _clearLogs() {
    setState(() => _logs.clear());
  }
  
  // Ouvrir l'explorateur de fichiers
  void _openFileBrowser() {
    if (_connectedClientIP == null) {
      _addLog('❌ Aucun appareil connecté', LogType.error, Icons.error);
      return;
    }
    
    setState(() {
      _showFileBrowser = true;
      _currentPath = 'ROOT';
      _loadingFiles = true;
    });
    
    _server.requestRootDirectories(_connectedClientIP!);
  }
  
  // Naviguer dans un dossier
  void _navigateToDirectory(String path) {
    if (_connectedClientIP == null) return;
    
    setState(() {
      _currentPath = path;
      _loadingFiles = true;
      _thumbnailCache.clear(); // Vider le cache des miniatures
    });
    
    _server.requestDirectoryList(_connectedClientIP!, path);
  }
  
  // Charger les miniatures pour les images
  void _loadThumbnailsForImages() {
    if (_connectedClientIP == null) return;
    
    for (final file in _currentFiles) {
      if (!file.isDirectory && _isImageFile(file.name)) {
        // Demander la miniature au mobile
        _server.requestThumbnail(_connectedClientIP!, file.path);
      }
    }
  }
  
  // Retour au dossier parent
  void _navigateBack() {
    if (_currentPath == 'ROOT') {
      setState(() {
        _showFileBrowser = false;
      });
      return;
    }
    
    // Extraire le chemin parent
    final parts = _currentPath.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      final parentPath = parts.join('/');
      _navigateToDirectory(parentPath.isEmpty ? 'ROOT' : parentPath);
    } else {
      _navigateToDirectory('ROOT');
    }
  }
  
  // Télécharger un fichier (ajouter à la file d'attente)
  void _downloadFile(RemoteFile file) {
    if (_connectedClientIP == null) return;
    
    // Créer une nouvelle tâche
    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: file.name,
      filePath: file.path,
      fileSize: file.size,
      from: _connectedClientIP!,
      status: DownloadStatus.pending,
    );
    
    setState(() {
      _downloadQueue.add(task);
    });
    
    // Traiter la file d'attente
    _processNextDownload();
  }
  
  // Traiter le prochain téléchargement dans la file
  void _processNextDownload() {
    if (_isProcessingDownload) return;
    
    // Trouver la prochaine tâche en attente
    final nextTask = _downloadQueue.firstWhere(
      (t) => t.status == DownloadStatus.pending,
      orElse: () => DownloadTask(id: '', fileName: '', filePath: '', fileSize: 0, from: ''),
    );
    
    if (nextTask.id.isEmpty) return;
    
    // Marquer comme en cours de traitement
    _isProcessingDownload = true;
    
    setState(() {
      nextTask.status = DownloadStatus.downloading;
    });
    
    // Demander le fichier au mobile
    _server.requestFileDownload(nextTask.from, nextTask.filePath);
  }
  
  // Démarrer/arrêter le partage d'écran
  Future<void> _toggleScreenShare() async {
    if (_connectedClientIP == null) {
      _showSnackBar('Aucun appareil connecté');
      return;
    }
    
    if (_isSharingScreen) {
      // Arrêter le partage
      _screenShare.stopSharing();
      await _server.notifyScreenShareStop(_connectedClientIP!);
      
      setState(() {
        _isSharingScreen = false;
      });
      
      _addLog('🛑 Partage d\'écran arrêté', LogType.screen, Icons.stop_screen_share);
    } else {
      // Démarrer le partage
      _screenShare.onFrameCaptured = (frameData) {
        _server.sendScreenFrame(_connectedClientIP!, frameData);
      };
      
      final success = await _screenShare.startSharing();
      
      if (success) {
        await _server.notifyScreenShareStart(_connectedClientIP!);
        
        setState(() {
          _isSharingScreen = true;
        });
        
        _addLog('🖥️ Partage d\'écran démarré', LogType.screen, Icons.screen_share);
      } else {
        _showSnackBar('Erreur: Impossible de capturer l\'écran');
      }
    }
  }
  
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: Duration(seconds: 2)),
      );
    }
  }
  
  @override
  void dispose() {
    _server.dispose();
    _screenShare.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: _showFileBrowser 
                ? _buildFileBrowser() 
                : _buildMainPanel(),
          ),
        ],
      ),
    );
  }
  
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Icon(Icons.sensors, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Text(
            'TortoiseShare Desktop',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.primary,
      elevation: 2,
      actions: [
        if (_logs.isNotEmpty)
          IconButton(
            icon: Icon(Icons.delete_sweep, color: Colors.white),
            onPressed: _clearLogs,
            tooltip: 'Effacer les logs',
          ),
      ],
    );
  }
  
  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header compact
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.desktop_windows, size: 48, color: AppColors.primary),
                const SizedBox(height: 12),
                Text('TortoiseShare', 
                     style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Desktop', 
                     style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
          ),
          
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          
          // Toggle simple pour activer/désactiver
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isRunning ? 'Détection active' : 'Détection désactivée',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _isRunning ? AppColors.success : Colors.grey,
                    ),
                  ),
                ),
                Switch(
                  value: _isRunning,
                  onChanged: (value) => _toggleServer(),
                  activeColor: AppColors.success,
                ),
              ],
            ),
          ),
          
          // Infos réseau compactes
          if (_isRunning) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_serverIP != null)
                      _buildCompactInfo(Icons.wifi, _serverIP!),
                    const SizedBox(height: 8),
                    _buildCompactInfo(Icons.device_hub, 
                        '${_server.connectedDevices.length} appareil(s)'),
                  ],
                ),
              ),
            ),
          ],
          
          // Bouton explorateur (si connecté)
          if (_connectedClientIP != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton.icon(
                onPressed: _openFileBrowser,
                icon: Icon(Icons.folder_open, color: Colors.white),
                label: Text('Explorateur', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton.icon(
                onPressed: _toggleScreenShare,
                icon: Icon(
                  _isSharingScreen ? Icons.stop_screen_share : Icons.screen_share,
                  color: Colors.white,
                ),
                label: Text(
                  _isSharingScreen ? 'Arrêter partage' : 'Partager l\'écran',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSharingScreen ? AppColors.error : Colors.purple,
                  minimumSize: Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
          
          // Téléchargements en cours
          if (_downloadQueue.isNotEmpty) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TÉLÉCHARGEMENTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._downloadQueue.map((task) => _buildCompactDownloadItem(task)).toList(),
                ],
              ),
            ),
          ],
          
          Spacer(),
          
          // Version en bas
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'v1.0.0',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCompactInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
  
  Widget _buildCompactDownloadItem(DownloadTask task) {
    Color statusColor;
    IconData statusIcon;
    
    switch (task.status) {
      case DownloadStatus.pending:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule;
        break;
      case DownloadStatus.downloading:
        statusColor = AppColors.primary;
        statusIcon = Icons.downloading;
        break;
      case DownloadStatus.completed:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        break;
      case DownloadStatus.failed:
        statusColor = AppColors.error;
        statusIcon = Icons.error;
        break;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (task.status == DownloadStatus.downloading)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: statusColor,
                  ),
                )
              else
                Icon(statusIcon, size: 12, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.fileName,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (task.status == DownloadStatus.downloading)
                Text(
                  '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
            ],
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: task.progress,
              backgroundColor: Colors.grey.withOpacity(0.2),
              color: statusColor,
              minHeight: 2,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildMainPanel() {
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'Aucune activité',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Header simple
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activité récente',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton.icon(
                onPressed: _clearLogs,
                icon: Icon(Icons.clear_all, size: 18),
                label: Text('Effacer'),
              ),
            ],
          ),
        ),
        Divider(height: 1),
        // Liste des logs
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            reverse: true,
            itemCount: _logs.length,
            itemBuilder: (context, index) => _buildCompactLogItem(_logs[index]),
          ),
        ),
      ],
    );
  }
  
  Widget _buildCompactLogItem(LogEntry log) {
    final color = _getLogColor(log.type);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(log.icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              log.message,
              style: TextStyle(fontSize: 13),
            ),
          ),
          Text(
            _formatTime(log.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getLogColor(LogType type) {
    switch (type) {
      case LogType.system: return AppColors.info;
      case LogType.connect: return AppColors.success;
      case LogType.disconnect: return AppColors.warning;
      case LogType.message: return AppColors.primary;
      case LogType.screen: return Colors.purple;
      case LogType.mobile: return Colors.cyan;
      case LogType.alert: return AppColors.warning;
      case LogType.file: return Colors.orange;
      case LogType.error: return AppColors.error;
    }
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }
  
  // Explorateur de fichiers
  Widget _buildFileBrowser() {
    return Column(
      children: [
        _buildFileBrowserHeader(),
        Expanded(
          child: _loadingFiles
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Chargement...', 
                           style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : _currentFiles.isEmpty
                  ? _buildEmptyFilesState()
                  : _buildFilesGrid(),
        ),
      ],
    );
  }
  
  Widget _buildFileBrowserHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.primary),
            onPressed: _navigateBack,
            tooltip: 'Retour',
          ),
          const SizedBox(width: 12),
          Icon(Icons.folder, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentPath == 'ROOT' ? 'Stockage' : _currentPath.split('/').last,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: () {
              setState(() {
                _showFileBrowser = false;
              });
            },
            tooltip: 'Fermer',
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyFilesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off, size: 64, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'Dossier vide',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  // Affichage en grille pour les fichiers
  Widget _buildFilesGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6, // 6 colonnes au lieu de 4
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75, // Ratio ajusté pour des cartes plus compactes
      ),
      itemCount: _currentFiles.length,
      itemBuilder: (context, index) {
        final file = _currentFiles[index];
        return _buildFileCard(file);
      },
    );
  }
  
  Widget _buildFileCard(RemoteFile file) {
    final isImage = _isImageFile(file.name);
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.withOpacity(0.15)),
      ),
      child: InkWell(
        onTap: () {
          if (file.isDirectory) {
            _navigateToDirectory(file.path);
          } else {
            _downloadFile(file);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail ou icône
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: file.isDirectory
                      ? Colors.orange.withOpacity(0.08)
                      : isImage
                          ? Colors.black.withOpacity(0.02)
                          : Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: isImage && !file.isDirectory
                    ? _buildImageThumbnail(file)
                    : Center(
                        child: Icon(
                          file.isDirectory ? Icons.folder : _getFileIcon(file.name),
                          size: 40,
                          color: file.isDirectory 
                              ? Colors.orange 
                              : Colors.blue.withOpacity(0.7),
                        ),
                      ),
              ),
            ),
            // Nom et taille
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!file.isDirectory && file.formattedSize.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      file.formattedSize,
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Vérifier si c'est une image
  bool _isImageFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }
  
  // Obtenir l'icône selon le type de fichier
  IconData _getFileIcon(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      return Icons.image;
    } else if (['mp4', 'avi', 'mkv', 'mov'].contains(ext)) {
      return Icons.video_file;
    } else if (['mp3', 'wav', 'flac', 'm4a'].contains(ext)) {
      return Icons.audio_file;
    } else if (['pdf'].contains(ext)) {
      return Icons.picture_as_pdf;
    } else if (['doc', 'docx', 'txt'].contains(ext)) {
      return Icons.description;
    } else if (['zip', 'rar', '7z'].contains(ext)) {
      return Icons.folder_zip;
    } else {
      return Icons.insert_drive_file;
    }
  }
  
  // Afficher une miniature de l'image
  Widget _buildImageThumbnail(RemoteFile file) {
    // Vérifier si on a la miniature en cache
    final thumbnail = _thumbnailCache[file.path];
    
    if (thumbnail != null) {
      // Afficher la vraie miniature
      return ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        child: Image.memory(
          thumbnail,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    
    // Sinon, afficher une icône en attendant
    return Stack(
      children: [
        Center(
          child: Icon(
            Icons.image,
            size: 48,
            color: Colors.blue.withOpacity(0.2),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.8),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              file.name.split('.').last.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Entrée de log
class LogEntry {
  final String message;
  final LogType type;
  final IconData icon;
  final String? sender;
  final DateTime timestamp;
  
  LogEntry({
    required this.message,
    required this.type,
    required this.icon,
    this.sender,
    required this.timestamp,
  });
}

enum LogType {
  system,
  connect,
  disconnect,
  message,
  screen,
  mobile,
  alert,
  file,
  error,
}

// Demande de fichier en attente
class FileRequest {
  final String fileName;
  final int fileSize;
  final String from;
  
  FileRequest({
    required this.fileName,
    required this.fileSize,
    required this.from,
  });
}
