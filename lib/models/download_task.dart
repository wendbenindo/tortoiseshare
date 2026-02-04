// Modèle pour une tâche de téléchargement
class DownloadTask {
  final String id;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String from;
  DownloadStatus status;
  double progress;
  String? error;
  
  DownloadTask({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.from,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.error,
  });
}

enum DownloadStatus {
  pending,      // En attente
  downloading,  // En cours
  completed,    // Terminé
  failed,       // Échoué
}
