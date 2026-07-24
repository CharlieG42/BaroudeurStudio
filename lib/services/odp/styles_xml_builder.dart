/// Builder pour le fichier styles.xml des documents ODP
/// 
/// IMPORTANT: Tous les documents ODP générés sont systématiquement en orientation PORTRAIT
/// Dimensions: 21cm (largeur) x 28cm (hauteur)
/// Cela garantit une cohérence totale entre tous les exports
class StylesXmlBuilder {
  /// Couleurs principales pour le style
  static const String primaryColor = '#f5a665';
  static const String secondaryColor = '#d7b895';
  static const String accentColor = '#A67352';
  static const String textColor = '#000000';
  static const String lightTextColor = '#666666';

  /// Dimensions de la page - TOUJOURS en portrait
  /// Largeur: 21cm, Hauteur: 28cm
  static const String pageWidth = '21cm';
  static const String pageHeight = '28cm';
  static const String printOrientation = 'portrait';

  /// Génère le contenu XML du styles.xml
  /// 
  /// Ce fichier définit:
  /// - La mise en page des pages (AL1 et PM1) en portrait obligatoire
  /// - Les styles de paragraphe (P1-P5)
  /// - Le style graphique pour les images
  /// - La page maître par défaut
  static String build() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                        xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
                        xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
                        xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
                        xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0">
  <office:styles>
    <!-- Mise en page des pages - ORIENTATION PORTRAIT OBLIGATOIRE -->
    <draw:page-layout draw:name="AL1">
      <draw:page-layout-properties draw:page-width="$pageWidth" draw:page-height="$pageHeight" draw:print-orientation="$printOrientation"/>
    </draw:page-layout>
    <style:page-layout style:name="PM1">
      <style:page-layout-properties fo:page-width="$pageWidth" fo:page-height="$pageHeight" style:print-orientation="$printOrientation"/>
    </style:page-layout>
    
    <!-- Style de la page de dessin -->
    <style:style style:name="DP1" style:family="drawing-page">
      <style:drawing-page-properties draw:page-layout-name="AL1" draw:background-color="$secondaryColor"/>
    </style:style>
    
    <!-- Styles de paragraphe -->
    <style:style style:name="P1" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="24pt" fo:font-weight="bold" style:color="$primaryColor"/>
    </style:style>
    <style:style style:name="P2" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="18pt" fo:font-weight="bold" style:color="$accentColor"/>
    </style:style>
    <style:style style:name="P3" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="16pt" style:font-style="italic" style:color="$lightTextColor"/>
    </style:style>
    <style:style style:name="P4" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="14pt" style:color="$textColor"/>
    </style:style>
    <style:style style:name="P5" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="12pt" style:color="$lightTextColor"/>
    </style:style>
    
    <!-- Style pour les images -->
    <style:style style:name="graphic" style:family="graphic">
      <style:graphic-properties svg:stroke-color="#000000" draw:fill="solid" draw:fill-color="#ffffff" fo:wrap-option="wrap" draw:textarea-horizontal-align="center" draw:textarea-vertical-align="center"/>
    </style:style>
  </office:styles>
  <office:automatic-styles>
  </office:automatic-styles>
  <office:master-styles>
    <!-- Page maître par défaut utilisant la mise en page PM1 (portrait) -->
    <style:master-page style:name="Default" style:page-layout-name="PM1">
      <draw:page draw:name="Default" draw:style-name="DP1">
      </draw:page>
    </style:master-page>
  </office:master-styles>
</office:document-styles>''';
  }
}
