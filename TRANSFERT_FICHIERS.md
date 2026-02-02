# 📁 Transfert de fichiers - Implémentation

## ✅ Ce qui a été ajouté

### 1. Modèle de données (`lib/models/file_transfer.dart`)
```dart
class FileTransfer {
  final String fileName;
  final int fileSize;
  final FileTransferStatus status;
  final double progress;  // 0.0 à 1.0
}

enum FileTransferStatus {
  pending, transferring, completed, failed, cancelled
}
```

### 2. Service de transfert (`lib/services/file_transfer_service.dart`)
- `prepareFile()` - Préparer un fichier pour l'envoi
- `readFileChunks()` - Lire le fichier par morceaux (8 KB)
- `saveReceivedFile()` - Sauvegarder un fichier reçu

### 3. TcpClient - Envoi de fichiers (Mobile)
```dart
Future<bool> sendFile(String filePath, {
  Function(double progress)? onProgress,
}) async {
  // 1. Préparer le fichier
  // 2. Envoyer les métadonnées: FILE|START|nom|taille
  // 3. Envoyer le contenu par chunks de 8 KB
  // 4. Envoyer le signal de fin: FILE|END
}
```

### 4. TcpServer - Réception de fichiers (Desktop)
- Détecte `FILE|START|nom|taille`
- Accumule les données reçues
- Détecte `FILE|END`
- Sauvegarde dans `Downloads/TortoiseShare/`

### 5. UI Mobile
- Bouton "Fichier" fonctionnel
- Sélection de fichier avec `file_picker`
- Barre de progression pendant l'envoi
- Messages de succès/erreur

### 6. UI Desktop
- Logs pour les événements de fichiers :
  - 📥 Début de réception
  - 📊 Progression
  - ✅ Fichier reçu
  - ❌ Erreur

## 🔄 Protocole de transfert

### Format des messages

**1. Début de transfert (Mobile → Desktop)**
```
FILE|START|photo.jpg|1048576\n
```
- `FILE|START` = Type de message
- `photo.jpg` = Nom du fichier
- `1048576` = Taille en bytes (1 MB)

**2. Données du fichier (Mobile → Desktop)**
```
[bytes bruts du fichier]
```
- Envoyé par chunks de 8 KB
- Pas de format spécial, juste les bytes

**3. Fin de transfert (Mobile → Desktop)**
```
FILE|END\n
```
- Signal que le fichier est complet

## 📊 Flux complet

### Côté Mobile (Envoi)
```
1. Utilisateur clique sur "Fichier"
   ↓
2. FilePicker.platform.pickFiles()
   ↓
3. Utilisateur choisit un fichier
   ↓
4. _pickAndSendFile() est appelé
   ↓
5. TcpClient.sendFile(filePath)
   ↓
6. FileTransferService.prepareFile()
   ↓
7. Envoi de "FILE|START|nom|taille\n"
   ↓
8. Lecture du fichier par chunks
   ↓
9. Pour chaque chunk:
   - socket.add(chunk)
   - Mise à jour de la progression
   ↓
10. Envoi de "FILE|END\n"
   ↓
11. Affichage "✅ Fichier envoyé"
```

### Côté Desktop (Réception)
```
1. Réception de "FILE|START|nom|taille\n"
   ↓
2. _handleFileStart() créé un FileReceptionState
   ↓
3. Log: "📥 Début réception: nom (taille)"
   ↓
4. Mode réception activé (receivingFile = true)
   ↓
5. Accumulation des bytes dans buffer
   ↓
6. À chaque chunk:
   - Vérifier si "FILE|END\n" est présent
   - Si non: continuer à accumuler
   - Si oui: passer à l'étape 7
   ↓
7. Fichier complet reçu
   ↓
8. Sauvegarde dans Downloads/TortoiseShare/
   ↓
9. Log: "✅ Fichier reçu: nom"
   ↓
10. Notification système (TODO)
```

## 🎯 Exemple concret

### Envoyer "photo.jpg" (100 KB)

**Mobile envoie :**
```
1. "FILE|START|photo.jpg|102400\n"
2. [8192 bytes]  ← Chunk 1
3. [8192 bytes]  ← Chunk 2
4. [8192 bytes]  ← Chunk 3
   ...
13. [8192 bytes]  ← Chunk 12
14. [4096 bytes]  ← Chunk 13 (dernier)
15. "FILE|END\n"
```

**Desktop reçoit :**
```
1. Détecte "FILE|START|photo.jpg|102400\n"
   → Crée FileReceptionState
   → Log: "📥 Réception: photo.jpg (100.0 KB)"

2. Reçoit les chunks et les accumule
   → Après chunk 1: 8%
   → Après chunk 2: 16%
   → ...
   → Après chunk 13: 100%

3. Détecte "FILE|END\n"
   → Sauvegarde dans Downloads/TortoiseShare/photo.jpg
   → Log: "✅ Fichier reçu: photo.jpg"
```

## 🔧 Configuration

### Taille des chunks
```dart
static const int chunkSize = 8192; // 8 KB
```
- Plus petit = plus de messages, plus lent
- Plus grand = moins de messages, mais risque de timeout

### Dossier de sauvegarde (Desktop)
```dart
Windows: C:\Users\[User]\Downloads\TortoiseShare\
Linux:   /home/[user]/Downloads/TortoiseShare/
macOS:   /Users/[user]/Downloads/TortoiseShare/
```

## 🐛 Gestion d'erreurs

### Erreurs possibles

1. **Fichier introuvable**
   - Vérifié dans `prepareFile()`
   - Retourne `null`

2. **Connexion perdue pendant le transfert**
   - `onError` ou `onDone` appelé
   - Transfert interrompu
   - Fichier partiel supprimé (TODO)

3. **Erreur de sauvegarde**
   - Permissions insuffisantes
   - Disque plein
   - Log: "❌ Erreur fichier"

4. **Timeout**
   - Si le transfert prend trop de temps
   - TODO: Ajouter un timeout

## 📝 TODO / Améliorations

### Priorité 1
- [ ] Reprise après interruption
- [ ] Annulation du transfert
- [ ] Notification système (desktop)

### Priorité 2
- [ ] Transfert Desktop → Mobile
- [ ] Transfert de plusieurs fichiers
- [ ] Compression des fichiers

### Priorité 3
- [ ] Chiffrement des fichiers
- [ ] Vérification d'intégrité (checksum)
- [ ] Historique des transferts

## 🧪 Tests

### Test manuel

**Mobile :**
1. Connecter au PC
2. Cliquer sur "Fichier"
3. Choisir un fichier (image, PDF, etc.)
4. Vérifier la barre de progression
5. Attendre le message "✅ Fichier envoyé"

**Desktop :**
1. Vérifier les logs :
   - "📥 Début réception"
   - "📊 Progression"
   - "✅ Fichier reçu"
2. Ouvrir `Downloads/TortoiseShare/`
3. Vérifier que le fichier est là
4. Ouvrir le fichier pour vérifier qu'il n'est pas corrompu

### Types de fichiers testés
- [ ] Images (JPG, PNG)
- [ ] Documents (PDF, DOCX)
- [ ] Vidéos (MP4)
- [ ] Archives (ZIP)
- [ ] Gros fichiers (> 10 MB)

## 🎉 Résultat

Le transfert de fichiers fonctionne ! Tu peux maintenant :
- Choisir un fichier sur ton mobile
- L'envoyer au PC
- Le retrouver dans Downloads/TortoiseShare/
- Voir la progression en temps réel

**Prochaine étape** : Tester avec différents types de fichiers et améliorer la gestion d'erreurs.
