import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../models/file_transfer.dart';

// Service pour gérer le transfert de fichiers
class FileTransferService {
  // Taille des chunks (morceaux) à envoyer
  static const int chunkSize = 8192; // 8 KB par chunk
  
  final StreamController<FileTransfer> _progressController = 
      StreamController.broadcast();
  
  Stream<FileTransfer> get progressStream => _progressController.stream;
  
  // Préparer un fichier pour l'envoi
  Future<FileTransfer?> prepareFile(String filePath) async {
    try {
      final file = File(filePath);
      
      // Vérifier que le fichier existe
      if (!await file.exists()) {
        print('❌ Fichier introuvable: $filePath');
        return null;
      }
      
      // Obtenir les infos du fichier
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      
      // Créer l'objet FileTransfer
      final transfer = FileTransfer(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fileName: fileName,
        fileSize: fileSize,
        filePath: filePath,
        status: FileTransferStatus.pending,
        startedAt: DateTime.now(),
      );
      
      print('✅ Fichier préparé: $fileName (${transfer.formattedSize})');
      return transfer;
      
    } catch (e) {
      print('❌ Erreur préparation fichier: $e');
      return null;
    }
  }
  
  // Lire le fichier par chunks (morceaux)
  Stream<Uint8List> readFileChunks(String filePath) async* {
    final file = File(filePath);
    final fileStream = file.openRead();
    
    await for (final chunk in fileStream) {
      yield Uint8List.fromList(chunk);
    }
  }
  
  // Sauvegarder un fichier reçu
  Future<bool> saveReceivedFile(
    String fileName,
    List<int> fileData,
    String savePath,
  ) async {
    try {
      // Créer le dossier si nécessaire
      final directory = Directory(savePath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // Créer le fichier
      final filePath = '$savePath/$fileName';
      final file = File(filePath);
      
      // Écrire les données
      await file.writeAsBytes(fileData);
      
      print('✅ Fichier sauvegardé: $filePath');
      return true;
      
    } catch (e) {
      print('❌ Erreur sauvegarde fichier: $e');
      return false;
    }
  }
  
  // Mettre à jour la progression
  void updateProgress(FileTransfer transfer) {
    _progressController.add(transfer);
  }
  
  // Nettoyer
  void dispose() {
    _progressController.close();
  }
}
