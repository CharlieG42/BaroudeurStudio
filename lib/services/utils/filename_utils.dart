/// Utilitaires pour la gestion des noms de fichiers
/// Nettoie les chaînes pour éviter les caractères interdits sous Windows
class FilenameUtils {
  /// Génère un nom de fichier valide pour l'export
  /// Remplace tous les caractères non alphanumériques par des underscores
  static String generateExportFilename(String title, String extension) {
    // Remplacer tous les caractères non alphanumériques, espaces, tirets
    // par des underscores
    String sanitized = title.replaceAll(RegExp('[^\w\s-]'), '_');
    
    // Remplacer les espaces par des underscores
    sanitized = sanitized.replaceAll(RegExp('\s+'), '_');
    
    // Supprimer les underscores en début et fin
    sanitized = sanitized.trim().replaceAll(RegExp('^_+|_+$'), '');
    
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
    String sanitized = input.replaceAll(RegExp('[^\w\s-]'), '_');
    sanitized = sanitized.replaceAll(RegExp('\s+'), '_');
    sanitized = sanitized.trim().replaceAll(RegExp('^_+|_+$'), '');
    
    if (sanitized.isEmpty) {
      sanitized = 'fichier';
    }
    
    return sanitized;
  }
}