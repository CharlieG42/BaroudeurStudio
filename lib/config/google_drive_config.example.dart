/// Configuration OAuth pour la sauvegarde Google Drive.
///
/// ⚠️ NE JAMAIS committer de vraies valeurs de secret dans ce fichier.
/// Ce fichier (`google_drive_config.dart`) doit être ignoré par Git
/// (voir .gitignore) et copié manuellement depuis
/// `google_drive_config.example.dart` sur chaque machine de
/// développement, en remplaçant les valeurs par les tiennes issues de
/// Google Cloud Console.
///
/// On réutilise les mêmes Client IDs que Google Photos (même projet
/// Google Cloud, même application Android) : la Drive API doit juste
/// être activée dans ce projet, et le scope `drive.file` ajouté.
class GoogleDriveConfig {
  // Client OAuth de type "Android" (identique à Google Photos).
  static const String androidClientId =
      '436961855144-ohvkv5f6oekd4fisi1fnepsnpldgnikl.apps.googleusercontent.com';

  // Client OAuth de type "Web application" : requis par google_sign_in
  // sur Android comme serverClientId (même principe que Google Photos).
  static const String webServerClientId =
      '436961855144-s9b9de41rijth9icvftrssonginvnnaf.apps.googleusercontent.com';

  // Scope Drive : accès limité aux fichiers créés par l'application
  // (les sauvegardes .bwzt uniquement). Scope non sensible : pas de
  // revue de conformité OAuth requise par Google.
  static const String driveScope =
      'https://www.googleapis.com/auth/drive.file';
}
