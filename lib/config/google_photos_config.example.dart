/// Configuration OAuth pour l'accès à Google Photos (Picker API).
///
/// ⚠️ NE JAMAIS committer de vraies valeurs de secret dans ce fichier.
/// Ce fichier (`google_photos_config.dart`) doit être ignoré par Git
/// (voir .gitignore) et copié manuellement depuis
/// `google_photos_config.example.dart` sur chaque machine de
/// développement, en remplaçant les valeurs par les tiennes issues de
/// Google Cloud Console.
class GooglePhotosConfig {
  // Client OAuth de type "Android". Pas de secret pour ce type de client :
  // l'authentification repose sur le nom de package + l'empreinte SHA-1
  // déclarés dans la console Google Cloud.
  static const String androidClientId =
      '436961855144-ohvkv5f6oekd4fisi1fnepsnpldgnikl.apps.googleusercontent.com';

  // Client OAuth de type "Web application". Contre-intuitif mais requis
  // par google_sign_in sur Android : même en se connectant depuis le
  // téléphone, l'API exige un "serverClientId" qui doit être le Client ID
  // d'un client de type Web (pas le Client ID Android). Sans lui,
  // l'erreur "serverClientId must be provided on Android" apparaît.
  static const String webServerClientId =
      '436961855144-s9b9de41rijth9icvftrssonginvnnaf.apps.googleusercontent.com';

  // Scope nécessaire pour utiliser la Picker API (lecture des médias
  // sélectionnés par l'utilisateur via le sélecteur Google Photos).
  static const String scope =
      'https://www.googleapis.com/auth/photospicker.mediaitems.readonly';

  // --- Client Desktop (Windows/macOS/Linux) : mis en pause pour l'instant ---
  // Le flux OAuth desktop nécessite un serveur loopback local et soulève
  // une vraie question de sécurité (le client_secret ne peut pas être
  // gardé secret dans un binaire desktop distribué). À reprendre plus
  // tard si besoin, une fois la version Android stabilisée.
  //
  // static const String desktopClientId = 'COLLE_TON_CLIENT_ID_DESKTOP_ICI';
  // static const String desktopClientSecret = 'COLLE_TON_CLIENT_SECRET_DESKTOP_ICI';
}
