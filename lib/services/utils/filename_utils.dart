/// Utilitaires pour la gestion des noms de fichiers
/// Nettoie les chaînes pour éviter les caractères interdits sous Windows
class FilenameUtils {
  /// Génère un nom de fichier valide pour l'export
  /// Remplace tous les caractères non autorisés par des underscores
  /// Caractères autorisés: a-z, A-Z, 0-9, espace, tiret, underscore
  static String generateExportFilename(String title, String extension) {
    // Garder seulement: lettres, chiffres, espaces, tirets, underscores
    // Tout le reste est remplacé par _
    String sanitized = title.replaceAll(RegExp('[^a-zA-Z0-9 _-]'), '_');
    
    // Remplacer les espaces multiples par un seul underscore
    sanitized = sanitized.replaceAll(RegExp(' +'), '_');
    
    // Supprimer les underscores en début et fin (sans utiliser $)
    // Méthode manuelle pour éviter les problèmes avec $ sous Windows
    while (sanitized.startsWith('_')) {
      sanitized = sanitized.substring(1);
    }
    while (sanitized.endsWith('_')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    
    // Si vide après nettoyage, utiliser un nom par défaut
    if (sanitized.isEmpty) {
      sanitized = 'export';
    }
    
    // Limiter la longueur (Windows: 255 chars max, moins l'extension)
    final maxLength = 200;
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }
    
    // Ajouter l'extension
    return sanitized + '.' + extension;
  }

  /// Nettoie une chaîne pour être utilisée comme nom de fichier
  static String sanitizeFilename(String input) {
    String sanitized = input.replaceAll(RegExp('[^a-zA-Z0-9 _-]'), '_');
    sanitized = sanitized.replaceAll(RegExp(' +'), '_');
    
    // Supprimer les underscores en début et fin (sans utiliser $)
    while (sanitized.startsWith('_')) {
      sanitized = sanitized.substring(1);
    }
    while (sanitized.endsWith('_')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    
    if (sanitized.isEmpty) {
      sanitized = 'fichier';
    }
    
    return sanitized;
  }
}