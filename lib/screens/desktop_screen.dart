import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../core/network_helper.dart';
import '../services/tcp_server.dart';
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
        break;
        
      case ServerMessageType.fileListError:
        setState(() {
          _loadingFiles = false;
        });
        _addLog('❌ Erreur liste fichiers: ${message.data['error']}', 
                LogType.error, Icons.error,
                sender: message.data['from']);
        break;
    }
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
    });
    
    _server.requestDirectoryList(_connectedClientIP!, path);
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
  
  @override
  void dispose() {
    _server.dispose();
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
      width: 320,
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildServerStatusCard(),
            const SizedBox(height: 24),
            _buildNetworkInfoCard(),
            const SizedBox(height: 24),
            if (_connectedClientIP != null) ...[
              _buildFileBrowserButton(),
              const SizedBox(height: 24),
            ],
            _buildInstructionsCard(),
            const SizedBox(height: 32),
            _buildVersion(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
          ),
          child: Icon(Icons.desktop_windows, size: 40, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text('TortoiseShare', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text('Desktop', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
      ],
    );
  }
  
  Widget _buildServerStatusCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _isRunning ? AppColors.success.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
        ),
      ),
      color: _isRunning ? AppColors.success.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _isRunning ? AppColors.success : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isRunning ? '✅ Communication autorisée' : 'Communication désactivée',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isRunning ? AppColors.success : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleServer,
                icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow, color: Colors.white),
                label: Text(
                  _isRunning ? 'DÉSACTIVER' : 'AUTORISER LA COMMUNICATION',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRunning ? AppColors.error : AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNetworkInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.info.withOpacity(0.2)),
      ),
      color: AppColors.info.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: AppColors.info, size: 20),
                const SizedBox(width: 8),
                Text('INFORMATIONS RÉSEAU', 
                     style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, 
                                    color: AppColors.info, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 12),
            if (_serverIP != null) ...[
              _buildInfoRow('Adresse IP', _serverIP!, Icons.network_check),
              const SizedBox(height: 8),
            ],
            _buildInfoRow('Port', '8081', Icons.adjust),
            const SizedBox(height: 8),
            _buildInfoRow('Appareils connectés', '${_server.connectedDevices.length}', Icons.device_hub),
            
            // Afficher la file d'attente de téléchargements
            if (_downloadQueue.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: AppColors.primary.withOpacity(0.3)),
              const SizedBox(height: 12),
              Text(
                'TÉLÉCHARGEMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              ..._downloadQueue.map((task) => _buildDownloadTaskItem(task)).toList(),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildDownloadTaskItem(DownloadTask task) {
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (task.status == DownloadStatus.downloading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: statusColor,
                  ),
                )
              else
                Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.fileName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (task.status == DownloadStatus.downloading)
                Text(
                  '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
            ],
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.progress,
              backgroundColor: AppColors.background,
              color: statusColor,
              minHeight: 3,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
  
  Widget _buildInstructionsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accent.withOpacity(0.2)),
      ),
      color: AppColors.accent.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Text('INSTRUCTIONS', 
                     style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, 
                                    color: AppColors.accent, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '1. Cliquez sur "Autoriser la communication"\n'
              '2. Ouvrez l\'app mobile sur le même réseau WiFi\n'
              '3. L\'app mobile détectera automatiquement ce PC\n'
              '4. Les connexions apparaîtront ici',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildVersion() {
    return Text(
      'Version 1.0.0 • TortoiseShare',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withOpacity(0.6)),
    );
  }
  
  Widget _buildMainPanel() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ACTIVITÉ EN TEMPS RÉEL', 
                   style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, 
                                  color: AppColors.textSecondary, letterSpacing: 1)),
              if (_logs.isNotEmpty)
                Text('${_logs.length} événements', 
                     style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _logs.isEmpty ? _buildEmptyState() : _buildLogsList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 20),
          Text('Aucune activité', 
               style: TextStyle(fontSize: 18, color: AppColors.textSecondary.withOpacity(0.6), 
                              fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text('Les connexions et messages\napparaîtront ici', 
               textAlign: TextAlign.center,
               style: TextStyle(fontSize: 14, color: AppColors.textSecondary.withOpacity(0.5))),
        ],
      ),
    );
  }
  
  Widget _buildLogsList() {
    return ListView.builder(
      reverse: true,
      itemCount: _logs.length,
      itemBuilder: (context, index) => _buildLogItem(_logs[index]),
    );
  }
  
  Widget _buildLogItem(LogEntry log) {
    final color = _getLogColor(log.type);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, spreadRadius: 1),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(log.icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(log.message, style: TextStyle(fontSize: 14))),
                      Text(_formatTime(log.timestamp), 
                           style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.6))),
                    ],
                  ),
                  if (log.sender != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('De: ${log.sender}', 
                                 style: TextStyle(fontSize: 12, color: AppColors.textSecondary, 
                                                fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            ),
          ],
        ),
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
  
  // Bouton pour ouvrir l'explorateur de fichiers
  Widget _buildFileBrowserButton() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.withOpacity(0.3)),
      ),
      color: Colors.blue.withOpacity(0.05),
      child: InkWell(
        onTap: _openFileBrowser,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.folder_open, color: Colors.blue, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explorateur',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Parcourir les fichiers du mobile',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue),
            ],
          ),
        ),
      ),
    );
  }
  
  // Explorateur de fichiers
  Widget _buildFileBrowser() {
    return Column(
      children: [
        _buildFileBrowserHeader(),
        Expanded(
          child: _loadingFiles
              ? Center(child: CircularProgressIndicator())
              : _currentFiles.isEmpty
                  ? _buildEmptyFilesState()
                  : _buildFilesList(),
        ),
      ],
    );
  }
  
  Widget _buildFileBrowserHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.primary),
            onPressed: _navigateBack,
            tooltip: 'Retour',
          ),
          const SizedBox(width: 12),
          Icon(Icons.folder, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentPath == 'ROOT' ? 'Stockage' : _currentPath.split('/').last,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.error),
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
          Icon(Icons.folder_off, size: 80, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 20),
          Text(
            'Dossier vide',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _currentFiles.length,
      itemBuilder: (context, index) {
        final file = _currentFiles[index];
        return _buildFileItem(file);
      },
    );
  }
  
  Widget _buildFileItem(RemoteFile file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          if (file.isDirectory) {
            _navigateToDirectory(file.path);
          } else {
            _downloadFile(file);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: file.isDirectory
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                  size: 24,
                  color: file.isDirectory ? Colors.orange : Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!file.isDirectory && file.formattedSize.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        file.formattedSize,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                file.isDirectory ? Icons.arrow_forward_ios : Icons.download,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
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
