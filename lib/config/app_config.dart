/// Configuration de l'application Baroudeur Studio
/// Contient les paramètres configurables par l'utilisateur
class AppConfig {
  /// Qualité de compression des images pour l'export ODP
  /// Valeur entre 0 et 100 (0 = très compressé, 100 = qualité maximale)
  /// Par défaut: 70 (bon compromis qualité/taille)
  static int imageCompressionQuality = 70;

  /// Format d'export par défaut
  /// 'pdf_text' pour PDF texte seulement
  /// 'odp' pour OpenDocument Presentation (LibreOffice)
  static String defaultExportFormat = 'pdf_text';

  /// Définir la qualité de compression (0-100)
  static void setCompressionQuality(int value) {
    if (value < 0) value = 0;
    if (value > 100) value = 100;
    imageCompressionQuality = value;
  }

  /// Réinitialiser aux valeurs par défaut
  static void resetToDefaults() {
    imageCompressionQuality = 70;
    defaultExportFormat = 'pdf_text';
  }
}