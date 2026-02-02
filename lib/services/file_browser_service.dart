import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/remote_file.dart';

// Service pour naviguer dans les fichiers du téléphone
class FileBrowserService {
  
  // Obtenir les répertoires racines (stockage interne, carte SD, etc.)
  Future<List<RemoteFile>> getRootDirectories() async {
    final List<RemoteFile> roots = [];
    
    try {
      // Stockage interne
      final internalStorage = await getExternalStorageDirectory();
      if (internalStorage != null) {
        // Remonter au répertoire racine du stockage
        final storagePath = _getStorageRoot(internalStorage.path);
        roots.add(RemoteFile(
          name: '📱 Stockage interne',
          path: storagePath,
          isDirectory: true,
          size: 0,
        ));
      }
      
      // Dossiers communs
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        roots.add(RemoteFile(
          name: '📥 Téléchargements',
          path: downloads.path,
          isDirectory: true,
          size: 0,
        ));
      }
      
      final dcim = Directory('/storage/emulated/0/DCIM');
      if (await dcim.exists()) {
        roots.add(RemoteFile(
          name: '📷 Photos',
          path: dcim.path,
          isDirectory: true,
          size: 0,
        ));
      }
      
      final documents = Directory('/storage/emulated/0/Documents');
      if (await documents.exists()) {
        roots.add(RemoteFile(
          name: '📄 Documents',
          path: documents.path,
          isDirectory: true,
          size: 0,
        ));
      }
      
    } catch (e) {
      print('❌ Erreur getRootDirectories: $e');
    }
    
    return roots;
  }
  
  // Lister les fichiers d'un répertoire
  Future<List<RemoteFile>> listDirectory(String path) async {
    final List<RemoteFile> files = [];
    
    try {
      final directory = Directory(path);
      
      if (!await directory.exists()) {
        print('❌ Répertoire inexistant: $path');
        return files;
      }
      
      final entities = await directory.list().toList();
      
      for (final entity in entities) {
        try {
          final stat = await entity.stat();
          final name = entity.path.split('/').last;
          
          // Ignorer les fichiers cachés
          if (name.startsWith('.')) continue;
          
          files.add(RemoteFile(
            name: name,
            path: entity.path,
            isDirectory: entity is Directory,
            size: stat.size,
            lastModified: stat.modified,
          ));
        } catch (e) {
          // Ignorer les fichiers inaccessibles
          continue;
        }
      }
      
      // Trier : dossiers d'abord, puis par nom
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      
    } catch (e) {
      print('❌ Erreur listDirectory: $e');
    }
    
    return files;
  }
  
  // Obtenir le chemin racine du stockage
  String _getStorageRoot(String path) {
    // Exemple: /storage/emulated/0/Android/data/... -> /storage/emulated/0
    if (path.contains('/storage/emulated/0')) {
      return '/storage/emulated/0';
    }
    return path;
  }
  
  // Vérifier si un fichier existe
  Future<bool> fileExists(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
}
