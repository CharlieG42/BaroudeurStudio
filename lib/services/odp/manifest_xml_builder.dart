/// Builder pour le fichier manifest.xml des documents ODP
class ManifestXmlBuilder {
  /// Génère le contenu XML du manifest.xml
  /// Include les entrées pour toutes les images avec leurs MIME types respectifs
  /// 
  /// [imagePathsWithMime] : Map où la clé est le chemin de l'image et la valeur est le MIME type
  static String build(Map<String, String> imagePathsWithMime) {
    final StringBuffer xml = StringBuffer();
    
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">');
    xml.writeln('  <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="mimetype" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="META-INF/manifest.xml" manifest:media-type="text/xml"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>');
    
    // Ajouter les entrées pour les images avec leurs MIME types
    for (final entry in imagePathsWithMime.entries) {
      final imagePath = entry.key;
      final mimeType = entry.value;
      xml.writeln('  <manifest:file-entry manifest:full-path="$imagePath" manifest:media-type="$mimeType"/>');
    }
    
    xml.writeln('</manifest:manifest>');
    
    return xml.toString();
  }
  
  /// Méthode de compatibilité pour les appels existants
  /// Utilise image/jpeg comme MIME type par défaut
  static String buildWithDefaultMime(List<String> imagePaths) {
    final imagePathsWithMime = <String, String>{};
    for (final imagePath in imagePaths) {
      imagePathsWithMime[imagePath] = 'image/jpeg';
    }
    return build(imagePathsWithMime);
  }
}
