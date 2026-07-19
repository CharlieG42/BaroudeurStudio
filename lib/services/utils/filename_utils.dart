/// Utilitaires pour la gestion des noms de fichiers
/// Nettoie les chaînes pour éviter les caractères interdits sous Windows
class FilenameUtils {
  /// Caractères interdits sous Windows: <>:"/|?* et caractères de contrôle (0-31)
  static const _forbiddenChars = ['<', '>', ':', '"', '/', '\', '|', '?', '*'];
  static final _forbiddenCharRegex = RegExp('[<>:"\/|?*\x00-\x1f]');

  /// Génère un nom de fichier valide pour l'export
  /// Remplace les caractères interdits par des underscores
  static String generateExportFilename(String title, String extension) {
    // Remplacer les caractères interdits
    String sanitized = title.replaceAll(_forbiddenCharRegex, '_');
    
    // Remplacer les espaces multiples par un seul underscore
    sanitized = sanitized.replaceAll(RegExp('\s+'), '_');
    
    // Supprimer les underscores en début et fin
    sanitized = sanitized.trim().replaceAll(RegExp('^_+|_+$'), '');
    
    // Si vide après nettoyage, utiliser un nom par défaut
    if (sanitized.isEmpty) {
      sanitized = 'export';
    }
    
    // Limiter la longueur (Windows: 255 chars max, moins l'extension)
    final maxLength = 200; // Laisse de la marge pour le chemin complet
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }
    
    // Ajouter l'extension
    return sanitized + '.' + extension;
  }

  /// Nettoie une chaîne pour être utilisée comme nom de fichier
  static String sanitizeFilename(String input) {
    String sanitized = input.replaceAll(_forbiddenCharRegex, '_');
    sanitized = sanitized.replaceAll(RegExp('\s+'), '_');
    sanitized = sanitized.trim().replaceAll(RegExp('^_+|_+$'), '');
    
    if (sanitized.isEmpty) {
      sanitized = 'fichier';
    }
    
    return sanitized;
  }
}