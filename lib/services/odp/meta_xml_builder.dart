import 'package:intl/intl.dart';
import '../../models/trek.dart';

/// Builder pour le fichier meta.xml des documents ODP
class MetaXmlBuilder {
  /// Génère le contenu XML du meta.xml
  static String build(Trek trek) {
    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-ddTHH:mm:ssZ');
    final creationDate = dateFormat.format(now);
    final title = _escapeXml(trek.titre);
    
    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                      xmlns:xlink="http://www.w3.org/1999/xlink"
                      xmlns:dc="http://purl.org/dc/elements/1.1/"
                      xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0">
  <office:meta>
    <meta:initial-creator>Baroudeur Studio</meta:initial-creator>
    <dc:creator>Les Baroudeurs</dc:creator>
    <meta:creation-date>''' + creationDate + '''</meta:creation-date>
    <dc:date>''' + creationDate + '''</dc:date>
    <dc:title>''' + title + '''</dc:title>
    <dc:subject>Recit de voyage - Les Baroudeurs</dc:subject>
    <dc:description>Carnets de trek illustres pour la collection Les Baroudeurs</dc:description>
  </office:meta>
</office:document-meta>''';
  }

  /// Échappe les caractères spéciaux pour le XML
  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}