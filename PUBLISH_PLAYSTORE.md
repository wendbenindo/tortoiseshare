# Publication sur Google Play Store

## Étape 1: Créer une clé de signature (Keystore)

### 1.1 Générer le keystore
```bash
keytool -genkey -v -keystore C:\Users\%USERNAME%\upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Questions à répondre**:
- Mot de passe du keystore: (choisis un mot de passe fort, note-le!)
- Nom et prénom: Ton nom
- Unité organisationnelle: TortoiseShare
- Organisation: Ton nom/entreprise
- Ville: Ta ville
- État: Ton état/province
- Code pays: CD (ou ton pays)

**IMPORTANT**: Note bien:
- Le chemin du keystore: `C:\Users\[TON_NOM]\upload-keystore.jks`
- Le mot de passe du keystore
- L'alias: `upload`

### 1.2 Créer le fichier key.properties

Crée le fichier `android/key.properties`:
```properties
storePassword=TON_MOT_DE_PASSE_KEYSTORE
keyPassword=TON_MOT_DE_PASSE_KEYSTORE
keyAlias=upload
storeFile=C:\\Users\\TON_NOM\\upload-keystore.jks
```

**ATTENTION**: Remplace `TON_MOT_DE_PASSE_KEYSTORE` et `TON_NOM` par tes vraies valeurs!

---

## Étape 2: Configurer le build Android

### 2.1 Modifier android/app/build.gradle.kts

Ajoute AVANT `android {`:
```kotlin
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

Dans `android { ... }`, ajoute AVANT `buildTypes`:
```kotlin
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties['keyAlias']
        keyPassword = keystoreProperties['keyPassword']
        storeFile = keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword = keystoreProperties['storePassword']
    }
}
```

Dans `buildTypes { release { ... } }`, ajoute:
```kotlin
signingConfig = signingConfigs.getByName("release")
```

---

## Étape 3: Préparer les informations de l'app

### 3.1 Vérifier pubspec.yaml
```yaml
name: tortoiseshare
version: 1.0.0+1
```

### 3.2 Modifier android/app/build.gradle.kts

Vérifie:
```kotlin
defaultConfig {
    applicationId = "com.tortoiseshare.app"  // Change si nécessaire
    minSdk = 21
    targetSdk = 34
    versionCode = 1
    versionName = "1.0.0"
}
```

---

## Étape 4: Build l'APK/AAB signé

### 4.1 Build AAB (recommandé pour Play Store)
```bash
flutter build appbundle --release
```

Le fichier sera dans: `build/app/outputs/bundle/release/app-release.aab`

### 4.2 Build APK signé (pour tests)
```bash
flutter build apk --release
```

Le fichier sera dans: `build/app/outputs/flutter-apk/app-release.apk`

---

## Étape 5: Créer le compte Play Console

1. Va sur: https://play.google.com/console
2. Crée un compte développeur (25$ unique)
3. Remplis les informations de ton compte

---

## Étape 6: Créer l'application sur Play Console

### 6.1 Créer l'app
1. Clique sur "Créer une application"
2. Nom: **TortoiseShare**
3. Langue par défaut: Français
4. Type: Application
5. Gratuite ou payante: Gratuite

### 6.2 Remplir les informations obligatoires

**Fiche du Play Store**:
- Titre: TortoiseShare
- Description courte: Partage de fichiers et écran entre mobile et PC
- Description complète: (voir ci-dessous)
- Icône: 512x512 (utilise ton logo)
- Captures d'écran: Au moins 2 screenshots

**Description complète suggérée**:
```
TortoiseShare - Partage simple et rapide

Partagez facilement des fichiers et votre écran entre votre téléphone Android et votre PC Windows.

Fonctionnalités:
✓ Transfert de fichiers rapide via WiFi
✓ Explorateur de fichiers mobile depuis le PC
✓ Partage d'écran mobile vers PC
✓ Envoi de liens et messages
✓ Connexion automatique
✓ Interface simple et intuitive

Aucune connexion Internet requise - fonctionne sur votre réseau local.
```

**Catégorie**: Outils ou Productivité

**Coordonnées**:
- Email de contact
- Site web (optionnel)
- Politique de confidentialité (obligatoire - voir ci-dessous)

---

## Étape 7: Tests fermés (Internal Testing)

### 7.1 Créer une version de test
1. Va dans "Tests" > "Tests internes"
2. Clique sur "Créer une version"
3. Upload le fichier AAB: `app-release.aab`
4. Nom de la version: 1.0.0 (1)
5. Notes de version: "Version initiale"

### 7.2 Ajouter des testeurs
1. Crée une liste de testeurs
2. Ajoute les emails des testeurs
3. Publie la version de test

### 7.3 Partager le lien de test
Les testeurs recevront un lien pour télécharger l'app.

---

## Étape 8: Politique de confidentialité (obligatoire)

Crée un fichier `privacy_policy.html` ou utilise un service gratuit comme:
- https://www.privacypolicygenerator.info/
- https://app-privacy-policy-generator.firebaseapp.com/

**Points à inclure**:
- Aucune donnée personnelle collectée
- Aucune connexion Internet (sauf réseau local)
- Permissions utilisées (stockage, réseau)

---

## Checklist avant publication

- [ ] Keystore créé et sauvegardé
- [ ] key.properties configuré
- [ ] build.gradle.kts modifié
- [ ] AAB généré avec succès
- [ ] Compte Play Console créé
- [ ] Application créée sur Play Console
- [ ] Fiche du Play Store remplie
- [ ] Icône et screenshots ajoutés
- [ ] Politique de confidentialité créée
- [ ] Version de test interne créée
- [ ] Testeurs ajoutés

---

## Commandes utiles

**Vérifier la signature de l'APK**:
```bash
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk
```

**Vérifier la taille de l'AAB**:
```bash
dir build\app\outputs\bundle\release\app-release.aab
```

---

## Prochaines étapes après tests fermés

1. Tests internes (quelques testeurs)
2. Tests fermés (plus de testeurs)
3. Tests ouverts (optionnel)
4. Production (publication publique)

---

## Support

Si tu as des erreurs, note-les et je t'aiderai à les résoudre!
