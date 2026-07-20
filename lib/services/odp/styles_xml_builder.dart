/// Builder pour le fichier styles.xml des documents ODP
class StylesXmlBuilder {
  /// Couleurs principales pour le style
  static const String primaryColor = '#f5a665';
  static const String secondaryColor = '#d7b895';
  static const String accentColor = '#A67352';
  static const String textColor = '#000000';
  static const String lightTextColor = '#666666';

  /// Génère le contenu XML du styles.xml
  static String build() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                        xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
                        xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
                        xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
                        xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0">
  <office:styles>
    <draw:page-layout draw:name="AL1">
      <draw:page-layout-properties draw:page-width="28cm" draw:page-height="21cm" draw:print-orientation="landscape"/>
    </draw:page-layout>
    <style:page-layout style:name="PM1">
      <style:page-layout-properties fo:page-width="28cm" fo:page-height="21cm" style:print-orientation="landscape"/>
    </style:page-layout>
    <style:style style:name="DP1" style:family="drawing-page">
      <style:drawing-page-properties draw:page-layout-name="AL1" draw:background-color="''' + secondaryColor + '''" />
    </style:style>
    <style:style style:name="P1" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="24pt" fo:font-weight="bold" style:color="''' + primaryColor + '''" />
    </style:style>
    <style:style style:name="P2" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="18pt" fo:font-weight="bold" style:color="''' + accentColor + '''" />
    </style:style>
    <style:style style:name="P3" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="16pt" style:font-style="italic" style:color="''' + lightTextColor + '''" />
    </style:style>
    <style:style style:name="P4" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="14pt" style:color="''' + textColor + '''" />
    </style:style>
    <style:style style:name="P5" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties style:font-name="Liberation Sans" style:font-size="12pt" style:color="''' + lightTextColor + '''" />
    </style:style>
    <style:style style:name="graphic" style:family="graphic">
      <style:graphic-properties svg:stroke-color="#000000" draw:fill="solid" draw:fill-color="#ffffff" fo:wrap-option="wrap" draw:textarea-horizontal-align="center" draw:textarea-vertical-align="center" />
    </style:style>
  </office:styles>
  <office:automatic-styles />
  <office:master-styles>
    <style:master-page style:name="Default" style:page-layout-name="PM1">
      <draw:page draw:name="Default" draw:style-name="DP1" draw:master-page-name="" />
    </style:master-page>
  </office:master-styles>
</office:document-styles>''';
  }
}