// Modèle pour représenter un transfert de fichier
class FileTransfer {
  final String id;              // ID unique du transfert
  final String fileName;        // Nom du fichier (ex: "photo.jpg")
  final int fileSize;           // Taille en bytes
  final String filePath;        // Chemin local du fichier
  final FileTransferStatus status;
  final double progress;        // 0.0 à 1.0
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? error;

  FileTransfer({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.filePath,
    required this.status,
    this.progress = 0.0,
    required this.startedAt,
    this.completedAt,
    this.error,
  });

  // Créer une copie avec des modifications
  FileTransfer copyWith({
    FileTransferStatus? status,
    double? progress,
    DateTime? completedAt,
    String? error,
  }) {
    return FileTransfer(
      id: id,
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      error: error ?? this.error,
    );
  }

  // Formater la taille du fichier
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Pourcentage de progression
  int get progressPercent => (progress * 100).round();
}

// États possibles d'un transfert
enum FileTransferStatus {
  pending,      // En attente
  transferring, // En cours de transfert
  completed,    // Terminé avec succès
  failed,       // Échec
  cancelled,    // Annulé
}
