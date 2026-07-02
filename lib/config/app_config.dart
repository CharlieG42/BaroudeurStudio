/// Configuration de l'application Baroudeur Studio
/// Contient les paramètres configurables par l'utilisateur

class AppConfig {
  /// Qualité de compression des images pour l'export PDF/PPTX
  /// Valeur entre 0 et 100 (0 = très compressé, 100 = qualité maximale)
  /// Par défaut: 70 (bon compromis qualité/taille)
  static int imageCompressionQuality = 70;

  /// Format d'export par défaut
  /// 'pdf' pour PDF texte seulement
  /// 'pdf_images' pour PDF avec images
  /// 'pptx' pour PowerPoint
  static String defaultExportFormat = 'pdf';

  /// Obtenir la qualité de compression (0.0 - 1.0 pour les bibliothèques qui l'utilisent)
  static double get compressionQuality => imageCompressionQuality / 100.0;

  /// Définir la qualité de compression (0-100)
  static set compressionQuality(int value) {
    if (value < 0) value = 0;
    if (value > 100) value = 100;
    imageCompressionQuality = value;
  }

  /// Réinitialiser aux valeurs par défaut
  static void resetToDefaults() {
    imageCompressionQuality = 70;
    defaultExportFormat = 'pdf';
  }
}
