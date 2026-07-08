/// Builder pour le fichier manifest.xml des documents ODP
class ManifestXmlBuilder {
  /// Génère le contenu XML du manifest.xml
  /// Include les entrées pour toutes les images
  static String build(List<String> imagePaths) {
    final StringBuffer xml = StringBuffer();
    
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">');
    xml.writeln('  <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="mimetype" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="META-INF/manifest.xml" manifest:media-type="text/xml"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>');
    xml.writeln('  <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>');
    
    // Ajouter les entrées pour les images
    for (final imagePath in imagePaths) {
      xml.writeln('  <manifest:file-entry manifest:full-path="$imagePath" manifest:media-type="image/jpeg"/>');
    }
    
    xml.writeln('</manifest:manifest>');
    
    return xml.toString();
  }
}