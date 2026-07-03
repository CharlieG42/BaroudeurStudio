import 'package:flutter/foundation.dart';

/// Utilitaires pour la gestion des noms de fichiers
class FilenameUtils {
  /// Nettoie une chaine de caracteres pour etre utilisee comme nom de fichier
  /// Remplace les caracteres speciaux par des underscores
  static String sanitizeFilename(String input) {
    return input
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001f]'), '_')
        .replaceAll(' ', '_');
  }

  /// Génère un nom de fichier unique pour l'export
  static String generateExportFilename(String title, String format) {
    final sanitizedTitle = sanitizeFilename(title);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'Baroudeurs_' + sanitizedTitle + '_' + timestamp.toString() + '.' + format;
  }
}