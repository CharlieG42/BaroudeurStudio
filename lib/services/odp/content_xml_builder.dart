import 'package:intl/intl.dart';
import '../../models/trek.dart';
import '../../models/jour_trek.dart';
import '../../models/media.dart';

/// Builder pour le fichier content.xml des documents ODP
/// 
/// IMPORTANT: Tous les documents générés utilisent la page maître "Default" 
/// qui est configurée en orientation PORTRAIT (21cm x 28cm) dans styles.xml
/// Chaque page (draw:page) référence draw:master-page-name="Default"
/// 
/// Ce builder gère correctement le pageIndex pour éviter les problèmes de scoping
class ContentXmlBuilder {
  /// Génère le contenu XML du content.xml
  /// 
  /// Structure du document:
  /// - Page de couverture (page 0)
  /// - Page de titre avec les informations du trek (page 1)
  /// - Une page par jour de trek avec ses médias (pages 2+)
  /// - Page de fin (dernière page)
  /// 
  /// Toutes les pages utilisent la mise en page portrait définie dans styles.xml
  static String build(Trek trek, List<JourTrek> jours, Map<int, List<Media>> mediasByJour) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateDebut = DateTime.parse(trek.dateDebut);
    final dateFin = DateTime.parse(trek.dateFin);
    final duree = trek.dureeJours;
    
    final StringBuffer xml = StringBuffer();
    
    // En-tête XML
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"');
    xml.writeln('                         xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"');
    xml.writeln('                         xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"');
    xml.writeln('                         xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"');
    xml.writeln('                         xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"');
    xml.writeln('                         xmlns:xlink="http://www.w3.org/1999/xlink"');
    xml.writeln('                         xmlns:dc="http://purl.org/dc/elements/1.1/"');
    xml.writeln('                         xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"');
    xml.writeln('                         xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0">');
    xml.writeln('  <office:scripts/>');
    xml.writeln('  <office:font-face-decls>');
    xml.writeln('    <style:font-face style:name="Liberation Sans" svg:font-family="Liberation Sans"/>');
    xml.writeln('  </office:font-face-decls>');
    xml.writeln('  <office:automatic-styles>');
    xml.writeln('    <style:style style:name="P1" style:family="paragraph" style:parent-style-name="Standard">');
    xml.writeln('      <style:text-properties style:font-name="Liberation Sans" style:font-size="24pt" fo:font-weight="bold" style:color="#f5a665"/>');
    xml.writeln('    </style:style>');
    xml.writeln('    <style:style style:name="P2" style:family="paragraph" style:parent-style-name="Standard">');
    xml.writeln('      <style:text-properties style:font-name="Liberation Sans" style:font-size="18pt" fo:font-weight="bold" style:color="#A67352"/>');
    xml.writeln('    </style:style>');
    xml.writeln('    <style:style style:name="P3" style:family="paragraph" style:parent-style-name="Standard">');
    xml.writeln('      <style:text-properties style:font-name="Liberation Sans" style:font-size="16pt" style:font-style="italic" style:color="#666666"/>');
    xml.writeln('    </style:style>');
    xml.writeln('    <style:style style:name="P4" style:family="paragraph" style:parent-style-name="Standard">');
    xml.writeln('      <style:text-properties style:font-name="Liberation Sans" style:font-size="14pt" style:color="#000000"/>');
    xml.writeln('    </style:style>');
    xml.writeln('    <style:style style:name="P5" style:family="paragraph" style:parent-style-name="Standard">');
    xml.writeln('      <style:text-properties style:font-name="Liberation Sans" style:font-size="12pt" style:color="#666666"/>');
    xml.writeln('    </style:style>');
    xml.writeln('    <style:style style:name="DP1" style:family="drawing-page">');
    xml.writeln('      <style:drawing-page-properties draw:page-layout-name="AL1" style:background-color="#d7b895"/>');
    xml.writeln('    </style:style>');
    xml.writeln('    <style:style style:name="graphic" style:family="graphic">');
    xml.writeln('      <style:graphic-properties svg:stroke-color="#000000" draw:fill="solid" draw:fill-color="#ffffff" fo:wrap-option="wrap" draw:textarea-horizontal-align="center" draw:textarea-vertical-align="center"/>');
    xml.writeln('    </style:style>');
    xml.writeln('  </office:automatic-styles>');
    xml.writeln('  <office:body>');
    xml.writeln('    <office:presentation>');

    // Génération des pages - toutes utilisent master-page-name="Default" (portrait)
    int pageIndex = 0;
    _addCoverPage(xml, trek, pageIndex);
    pageIndex++;
    _addTitlePage(xml, trek, dateFormat, dateDebut, dateFin, duree, pageIndex);
    pageIndex++;
    for (final jour in jours) {
      final medias = mediasByJour[jour.id] ?? [];
      _addJourPage(xml, jour, medias, pageIndex);
      pageIndex++;
    }
    _addEndPage(xml, trek, pageIndex);
    xml.writeln('    </office:presentation>');
    xml.writeln('  </office:body>');
    xml.writeln('</office:document-content>');
    return xml.toString();
  }

  /// Ajoute la page de couverture
  /// Utilise la page maître "Default" configurée en portrait dans styles.xml
  static void _addCoverPage(StringBuffer xml, Trek trek, int pageIndex) {
    final title = _escapeXml(trek.titre);
    final region = _escapeXml(trek.region);
    final country = _escapeXml(trek.pays);
    
    // draw:master-page-name="Default" garantit l'utilisation de la mise en page portrait
    xml.writeln('      <draw:page draw:name="page_$pageIndex" draw:style-name="DP1" draw:master-page-name="Default">');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="4cm" svg:width="26cm" svg:height="2cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P1">Les Baroudeurs</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="7cm" svg:width="26cm" svg:height="1cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P2">$title</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="9cm" svg:width="26cm" svg:height="1cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P3">$region, $country</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="11cm" svg:width="26cm" svg:height="1cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P3">Un recit de voyage</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('      </draw:page>');
  }

  /// Ajoute la page de titre avec les informations du trek
  /// Utilise la page maître "Default" configurée en portrait dans styles.xml
  static void _addTitlePage(StringBuffer xml, Trek trek, DateFormat dateFormat, DateTime dateDebut, DateTime dateFin, int duree, int pageIndex) {
    final title = _escapeXml(trek.titre);
    final companions = _escapeXml(trek.compagnons.isNotEmpty ? trek.compagnons : 'Seul(e)');
    final startDate = dateFormat.format(dateDebut);
    final endDate = dateFormat.format(dateFin);
    
    // draw:master-page-name="Default" garantit l'utilisation de la mise en page portrait
    xml.writeln('      <draw:page draw:name="page_$pageIndex" draw:style-name="DP1" draw:master-page-name="Default">');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="2cm" svg:width="26cm" svg:height="1cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P2">$title</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="4cm" svg:width="26cm" svg:height="10cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P4">Du: $startDate</text:p>');
    xml.writeln('            <text:p text:style-name="P4">Au: $endDate</text:p>');
    xml.writeln('            <text:p text:style-name="P4">Duree: $duree jour(s)</text:p>');
    if (trek.distanceKm != null) {
      xml.writeln('            <text:p text:style-name="P4">Distance: ${trek.distanceKm!.toStringAsFixed(1)} km</text:p>');
    }
    if (trek.denivelePositifM != null) {
      xml.writeln('            <text:p text:style-name="P4">Denivele: ${trek.denivelePositifM} m</text:p>');
    }
    xml.writeln('            <text:p text:style-name="P4">Compagnons: $companions</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('      </draw:page>');
  }

  /// Ajoute une page pour un jour de trek avec ses médias
  /// Utilise la page maître "Default" configurée en portrait dans styles.xml
  /// 
  /// Mise en page:
  /// - En-tête avec la date et le lieu (y=1cm)
  /// - Images disposées verticalement (à partir de y=3cm)
  /// - Contenu textuel en dessous des images
  static void _addJourPage(StringBuffer xml, JourTrek jour, List<Media> medias, int pageIndex) {
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr');
    final jourDate = DateTime.parse(jour.date);
    final dateStr = dateFormat.format(jourDate);
    final depart = _escapeXml(jour.lieuDepart);
    final arrivee = _escapeXml(jour.lieuArrivee);
    final resume = _escapeXml(jour.resume);
    final meteo = _escapeXml(jour.meteo);
    final emotions = _escapeXml(jour.emotions);
    final difficultes = _escapeXml(jour.difficultes);
    final decouvertes = _escapeXml(jour.decouvertes);
    final distance = jour.distanceKm?.toStringAsFixed(1) ?? 'N/A';
    
    // draw:master-page-name="Default" garantit l'utilisation de la mise en page portrait
    xml.writeln('      <draw:page draw:name="page_$pageIndex" draw:style-name="DP1" draw:master-page-name="Default">');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="1cm" svg:width="26cm" svg:height="1cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P2">$dateStr</text:p>');
    if (jour.lieuDepart.isNotEmpty || jour.lieuArrivee.isNotEmpty) {
      xml.writeln('            <text:p text:style-name="P3">$depart -> $arrivee</text:p>');
    }
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    
    // Ajout des images
    for (int mediaIndex = 0; mediaIndex < medias.length; mediaIndex++) {
      final imagePath = 'Pictures/image_$pageIndex-$mediaIndex.jpg';
      final yPosition = 3 + mediaIndex * 8;
      xml.writeln('        <draw:frame draw:name="image_$pageIndex-$mediaIndex" draw:style-name="graphic" svg:x="2cm" svg:y="${yPosition}cm" svg:width="10cm" svg:height="7cm">');
      xml.writeln('          <draw:image xlink:href="$imagePath" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/>');
      xml.writeln('        </draw:frame>');
    }
    
    // Contenu textuel sous les images
    final contentY = 3 + medias.length * 8 + 1;
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="${contentY}cm" svg:width="26cm" svg:height="10cm">');
    xml.writeln('          <draw:text-box>');
    if (jour.resume.isNotEmpty) {
      xml.writeln('            <text:p text:style-name="P4">Recit du jour: $resume</text:p>');
    }
    xml.writeln('            <text:p text:style-name="P4">Distance: $distance km</text:p>');
    xml.writeln('            <text:p text:style-name="P4">Meteo: $meteo</text:p>');
    xml.writeln('            <text:p text:style-name="P4">Emotions: $emotions</text:p>');
    xml.writeln('            <text:p text:style-name="P4">Difficultes: $difficultes</text:p>');
    xml.writeln('            <text:p text:style-name="P4">Decouvertes: $decouvertes</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('      </draw:page>');
  }

  /// Ajoute la page de fin
  /// Utilise la page maître "Default" configurée en portrait dans styles.xml
  static void _addEndPage(StringBuffer xml, Trek trek, int pageIndex) {
    final title = _escapeXml(trek.titre);
    final year = DateTime.now().year;
    final thankYouMessage = _escapeXml("Merci d\'avoir vecu cette aventure !");
    
    // draw:master-page-name="Default" garantit l'utilisation de la mise en page portrait
    xml.writeln('      <draw:page draw:name="page_$pageIndex" draw:style-name="DP1" draw:master-page-name="Default">');
    xml.writeln('        <draw:frame svg:x="1cm" svg:y="8cm" svg:width="26cm" svg:height="4cm">');
    xml.writeln('          <draw:text-box>');
    xml.writeln('            <text:p text:style-name="P1">Fin du recit</text:p>');
    xml.writeln('            <text:p text:style-name="P2">$title</text:p>');
    xml.writeln('            <text:p text:style-name="P3">$thankYouMessage</text:p>');
    xml.writeln('            <text:p text:style-name="P5">Les Baroudeurs - $year</text:p>');
    xml.writeln('          </draw:text-box>');
    xml.writeln('        </draw:frame>');
    xml.writeln('      </draw:page>');
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
