// Modèle pour représenter un fichier/dossier distant
class RemoteFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
  
  RemoteFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.lastModified,
  });
  
  // Convertir en JSON pour l'envoi
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      'size': size,
      'lastModified': lastModified?.toIso8601String(),
    };
  }
  
  // Créer depuis JSON
  factory RemoteFile.fromJson(Map<String, dynamic> json) {
    return RemoteFile(
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['isDirectory'] as bool,
      size: json['size'] as int,
      lastModified: json['lastModified'] != null 
          ? DateTime.parse(json['lastModified'] as String)
          : null,
    );
  }
  
  // Formater la taille
  String get formattedSize {
    if (isDirectory) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
