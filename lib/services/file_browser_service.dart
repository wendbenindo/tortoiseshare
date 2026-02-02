import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/remote_file.dart';

// Service pour naviguer dans les fichiers du téléphone
class FileBrowserService {
  
  // Obtenir les répertoires racines accessibles
  Future<List<RemoteFile>> getRootDirectories() async {
    final List<RemoteFile> roots = [];
    
    try {
      print('🔍 Recherche des répertoires accessibles...');
      
      // Utiliser les répertoires fournis par path_provider (toujours accessibles)
      
      // 1. Répertoire de l'application (toujours accessible)
      final appDir = await getApplicationDocumentsDirectory();
      roots.add(RemoteFile(
        name: '📱 Fichiers de l\'app',
        path: appDir.path,
        isDirectory: true,
        size: 0,
      ));
      print('✅ Dossier app trouvé: ${appDir.path}');
      
      // 2. Répertoire externe de l'application (accessible sans permission spéciale)
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          roots.add(RemoteFile(
            name: '💾 Stockage externe app',
            path: externalDir.path,
            isDirectory: true,
            size: 0,
          ));
          print('✅ Stockage externe trouvé: ${externalDir.path}');
        }
      } catch (e) {
        print('⚠️ Stockage externe non disponible: $e');
      }
      
      // 3. Répertoires publics (nécessitent des permissions mais on essaie)
      final publicDirs = [
        {'name': '📥 Téléchargements', 'path': '/storage/emulated/0/Download'},
        {'name': '📷 DCIM', 'path': '/storage/emulated/0/DCIM'},
        {'name': '📄 Documents', 'path': '/storage/emulated/0/Documents'},
        {'name': '🎵 Musique', 'path': '/storage/emulated/0/Music'},
      ];
      
      for (final dirInfo in publicDirs) {
        final path = dirInfo['path'] as String;
        final dir = Directory(path);
        
        // Vérifier si on peut y accéder
        try {
          if (await dir.exists()) {
            // Tester si on peut lister (vérification de permission)
            await dir.list(followLinks: false).first.timeout(
              const Duration(milliseconds: 500),
              onTimeout: () => throw TimeoutException('Timeout'),
            );
            
            roots.add(RemoteFile(
              name: dirInfo['name'] as String,
              path: path,
              isDirectory: true,
              size: 0,
            ));
            print('✅ Dossier public accessible: $path');
          }
        } catch (e) {
          print('⚠️ Dossier non accessible: $path - $e');
          // Ne pas ajouter ce dossier s'il n'est pas accessible
        }
      }
      
      print('📂 ${roots.length} répertoires accessibles trouvés');
      
    } catch (e) {
      print('❌ Erreur getRootDirectories: $e');
    }
    
    return roots;
  }
  
  // Lister les fichiers d'un répertoire
  Future<List<RemoteFile>> listDirectory(String path) async {
    final List<RemoteFile> files = [];
    
    try {
      print('📂 Listage du répertoire: $path');
      
      final directory = Directory(path);
      
      if (!await directory.exists()) {
        print('❌ Répertoire inexistant: $path');
        return files;
      }
      
      // Lister avec timeout pour éviter les blocages
      try {
        final stream = directory.list(followLinks: false);
        
        await for (final entity in stream) {
          try {
            final name = entity.path.split('/').last;
            
            // Ignorer les fichiers cachés
            if (name.startsWith('.')) continue;
            
            FileStat? stat;
            try {
              stat = await entity.stat();
            } catch (e) {
              stat = null;
            }
            
            files.add(RemoteFile(
              name: name,
              path: entity.path,
              isDirectory: entity is Directory,
              size: stat?.size ?? 0,
              lastModified: stat?.modified,
            ));
          } catch (e) {
            print('⚠️ Fichier ignoré: ${entity.path} - $e');
            continue;
          }
        }
      } catch (e) {
        print('❌ Erreur lors du listage: $e');
        
        // Si on a une erreur de permission, retourner un message explicite
        if (e.toString().contains('Permission denied')) {
          print('💡 Astuce: Ce dossier nécessite des permissions spéciales');
          print('💡 Va dans Paramètres → Apps → TortoiseShare → Autorisations');
          print('💡 Active "Gérer tous les fichiers"');
        }
        
        return files;
      }
      
      // Trier : dossiers d'abord, puis par nom
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      
      print('✅ ${files.length} fichiers accessibles');
      
    } catch (e) {
      print('❌ Erreur listDirectory: $e');
    }
    
    return files;
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
