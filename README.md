# Les Baroudeurs — MVP v0.5

Treks + journal quotidien + photos (appareil ou Google Photos sur Android,
taille originale/compressée) + import de trace GPX (calcul automatique
distance/dénivelé, modifiable) + notes vocales avec transcription
automatique. Stockage SQLite + fichiers locaux. Toujours sans IA de
rédaction, sans illustrations Ghibli, sans export pour le moment.

> **Important si tu as déjà testé la v0.1** : la base de données passe en
> version 2 (ajout de la table des photos). La migration est automatique au
> premier lancement — tes treks et jours existants sont conservés, rien à
> faire de ton côté.

---

## 0. Prérequis communs

1. Installer Flutter (si pas déjà fait) :
   https://docs.flutter.dev/get-started/install

2. Vérifier l'installation :
   ```bash
   flutter doctor
   ```
   Corrige les éventuels soucis signalés (Xcode, Android SDK, etc.) avant de continuer.

3. Récupérer les dépendances du projet — à faire **une fois**, depuis le dossier `les_baroudeurs/` :
   ```bash
   cd les_baroudeurs
   flutter pub get
   ```

---

## 1. Tester sur macOS (desktop)

1. Activer le support desktop macOS (une seule fois sur ta machine) :
   ```bash
   flutter config --enable-macos-desktop
   ```

2. Lancer l'app :
   ```bash
   flutter run -d macos
   ```

   Si Xcode n'est pas installé, installe-le depuis l'App Store (nécessaire
   pour compiler les apps macOS/iOS).

3. La base de données SQLite sera créée automatiquement dans le dossier
   "Documents" de l'app (géré par `path_provider`), aucune config
   supplémentaire nécessaire.

---

## 2. Tester sur Windows (desktop)

1. Activer le support desktop Windows (une seule fois) :
   ```bash
   flutter config --enable-windows-desktop
   ```

2. Prérequis : Visual Studio (pas seulement VS Code) avec le composant
   **"Desktop development with C++"** installé. C'est nécessaire pour
   compiler le runner Windows de Flutter.

3. Lancer l'app :
   ```bash
   flutter run -d windows
   ```

4. Comme pour macOS, `sqflite_common_ffi` gère la base SQLite via le moteur
   natif `sqlite3` — rien à configurer manuellement.

> **Note sur la compression d'image** : le package `flutter_image_compress`
> peut nécessiter une étape `flutter pub get` supplémentaire après ajout au
> projet pour bien enregistrer son plugin Windows. Si tu obtiens une erreur
> du type "Plugin flutter_image_compress not found" au build, relance
> `flutter clean` puis `flutter pub get` avant de rebuilder.

---

## 3. Tester sur Android

### Option A — Émulateur Android
1. Ouvrir Android Studio → Device Manager → créer un émulateur (ex: Pixel 6,
   API 33+).
2. Lancer l'émulateur.
3. Vérifier qu'il est détecté :
   ```bash
   flutter devices
   ```
4. Lancer l'app :
   ```bash
   flutter run -d emulator-5554
   ```
   (remplace `emulator-5554` par l'ID retourné par `flutter devices`)

### Option B — Téléphone Android physique
1. Activer le mode développeur sur le téléphone :
   Paramètres → À propos du téléphone → appuyer 7 fois sur "Numéro de build"
2. Activer le débogage USB :
   Paramètres → Options pour les développeurs → Débogage USB
3. Brancher le téléphone en USB, autoriser l'ordinateur si demandé.
4. Vérifier qu'il est détecté :
   ```bash
   flutter devices
   ```
5. Lancer l'app :
   ```bash
   flutter run -d <id_du_telephone>
   ```

Sur Android, `sqflite` utilise le moteur SQLite natif du système — aucune
configuration supplémentaire nécessaire.

### Configuration requise pour l'import depuis Google Photos

1. Crée le fichier `lib/config/google_photos_config.dart` en copiant
   `lib/config/google_photos_config.example.dart` (ce premier fichier est
   ignoré par Git, donc jamais committé).
2. Renseigne `androidClientId` avec le Client ID OAuth de type "Android"
   créé dans Google Cloud Console (déjà fait pour ce projet — la valeur
   est dans le fichier exemple).
3. Renseigne aussi `webServerClientId` avec le Client ID OAuth de type
   **"Web application"** (pas Android !). C'est une exigence un peu
   contre-intuitive de `google_sign_in` sur Android : même en se
   connectant depuis le téléphone, l'API attend un `serverClientId` qui
   doit être un Client ID de type Web. Sans lui, l'erreur
   `serverClientId must be provided on Android` apparaît.
4. Vérifie que dans Google Cloud Console :
   - Le nom de package du client Android correspond bien à
     `com.baroudeurs.studio`
   - L'empreinte SHA-1 de ta clé de signature (debug, et plus tard
     release) est bien renseignée
   - L'API "Google Photos Picker API" est activée (APIs & Services >
     Enabled APIs)
5. Comme l'app reste en mode "Test" dans la console (usage personnel),
   un écran "App non vérifiée" peut apparaître à la première connexion —
   c'est normal, clique sur "Continuer" / "Avancé > Accéder à l'app".

**Note** : l'import Google Photos n'est implémenté que pour Android dans
cette version. Le client Desktop a été créé dans Google Cloud Console
mais l'intégration Windows est mise en pause (le flux OAuth desktop pose
des questions de sécurité spécifiques liées au stockage du secret client
dans un binaire distribué — à reprendre plus tard si besoin).

### Configuration requise pour les notes vocales (transcription)

Le package `speech_to_text` nécessite des permissions et déclarations
Android spécifiques. Ouvre `android/app/src/main/AndroidManifest.xml` et
ajoute, **avant** la balise `<application>` :

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />

<queries>
    <intent>
        <action android:name="android.speech.RecognitionService" />
    </intent>
</queries>
```

Sans le bloc `<queries>`, Android peut empêcher l'app de détecter les
moteurs de reconnaissance vocale installés sur le téléphone (changement
de comportement introduit par Android 11+).

**Note sur la qualité de transcription** : ce service utilise le moteur
de reconnaissance vocale du téléphone (Google, généralement), qui
nécessite le plus souvent une connexion internet active pour de bons
résultats. Un mode hors-ligne existe sur certains appareils Android mais
dépend de packs de langue téléchargés séparément dans les paramètres
système (Paramètres > Système > Langues > Reconnaissance vocale hors
ligne).

---

## 4. Build "release" (optionnel, pour partager une version installable)

### macOS
```bash
flutter build macos
```
→ produit `build/macos/Build/Products/Release/les_baroudeurs.app`

### Windows
```bash
flutter build windows
```
→ produit `build/windows/x64/runner/Release/` (dossier avec le .exe et ses DLLs)

### Android (APK)
```bash
flutter build apk --release
```
→ produit `build/app/outputs/flutter-apk/app-release.apk`
   Tu peux transférer cet APK sur un téléphone Android et l'installer
   directement (active "Sources inconnues" dans les paramètres si demandé).

---

## 5. Ce qui est testable dans ce MVP

- Créer un trek (titre, dates, région, pays, distance, dénivelé, mode de
  voyage, compagnons)
- Voir la liste des treks
- Ouvrir un trek → voir/modifier ses infos, le supprimer
- Ajouter un jour (lieu départ/arrivée, distance, météo, résumé, émotions,
  difficultés, découvertes)
- Modifier / supprimer un jour
- **Ajouter des photos à un jour** (une fois le jour enregistré une première
  fois), via le bouton "Ajouter" qui propose deux sources :
  - **Depuis l'appareil** : explorateur de fichiers classique
  - **Depuis Google Photos** (Android uniquement) : ouvre le sélecteur
    Google Photos dans le navigateur/l'app, tu choisis tes photos
    là-bas, puis l'import continue automatiquement dans Les Baroudeurs
  - Dans les deux cas : **choix entre taille originale et compressée**
    dans une boîte de dialogue, copie automatique dans le dossier de
    l'app, affichage en galerie, suppression
- Appui long sur une photo : ajouter/modifier une légende
- Appui simple sur une photo : vue plein écran
- Les données et fichiers persistent entre les lancements de l'app

### Détails sur les photos

- Bouton "Enregistrer" dans l'écran d'un jour : sauvegarde sans fermer
  l'écran, ce qui permet ensuite d'ajouter des photos
- Bouton "Fermer" (en haut à droite) : referme l'écran et revient au détail
  du trek
- Les photos sont **copiées** (pas seulement référencées) dans :
  `Documents/media/jour_<id>/<uuid>.<ext>`, qu'elles viennent de
  l'appareil ou de Google Photos
- Supprimer une photo dans l'app supprime aussi le fichier copié
- **Compression** (si choisie) : redimensionnement à 1920px sur le plus
  grand côté, qualité JPEG 80%, sans métadonnées EXIF — réduction typique
  de 80 à 90% du poids du fichier, largement suffisant pour l'impression
  et pour servir de base à la génération d'illustrations IA
- Les formats HEIC ne sont pas compressés (copiés en taille originale,
  quel que soit le choix) en raison d'un support inégal selon plateforme
- **Import Google Photos** : la première utilisation demande une
  connexion à ton compte Google ; les suivantes seront plus rapides
  (le token est réutilisé tant qu'il est valide). La sélection dans
  Google Photos a un délai limité (quelques minutes) — si tu mets trop
  de temps à choisir, il faudra relancer l'import.

## 6. Ce qui n'est PAS encore dans ce MVP

- Vidéos / notes vocales / GPS
- Détection automatique de lieux, sommets, animaux, etc.
- Appel à l'IA pour générer le brouillon du livre
- Génération d'illustrations
- Export PDF/PPTX/EPUB

---

## 7. Dépannage rapide

- **Erreur liée à `sqflite_common_ffi` sur desktop** : vérifie que
  `flutter pub get` a bien tourné après modification du `pubspec.yaml`.
- **`flutter devices` ne montre rien** : relance `flutter doctor` pour voir
  ce qui manque (SDK Android, licences, etc.)
- **Build Windows échoue** : assure-toi que Visual Studio (pas seulement
  VS Code) est installé avec le workload C++.
