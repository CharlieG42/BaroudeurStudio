import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../models/trek.dart';
import '../../models/jour_trek.dart';

/// Paramètres de dimensionnement des images dans l'export ODP.
///
/// Par défaut, on respecte le ratio d'origine de l'image tout en garantissant
/// une hauteur minimum de 8cm OU une largeur minimum de 13cm. L'utilisateur
/// peut ajuster ces valeurs via le menu Paramétrage.
class OdpImageSettings {
  final double minHeightCm;
  final double minWidthCm;
  final double maxWidthCm;
  final double maxHeightCm;

  const OdpImageSettings({
    this.minHeightCm = 8.0,
    this.minWidthCm = 13.0,
    this.maxWidthCm = 18.0,
    this.maxHeightCm = 20.0,
  });

  static const OdpImageSettings defaults = OdpImageSettings();

  OdpImageSettings copyWith({
    double? minHeightCm,
    double? minWidthCm,
    double? maxWidthCm,
    double? maxHeightCm,
  }) {
    return OdpImageSettings(
      minHeightCm: minHeightCm ?? this.minHeightCm,
      minWidthCm: minWidthCm ?? this.minWidthCm,
      maxWidthCm: maxWidthCm ?? this.maxWidthCm,
      maxHeightCm: maxHeightCm ?? this.maxHeightCm,
    );
  }
}

/// Informations de dimension d'une image (en pixels).
class ImageDimensions {
  final int width;
  final int height;

  const ImageDimensions(this.width, this.height);

  double get aspectRatio => height > 0 ? width / height : 1.0;
  bool get isLandscape => width > height;
}

/// Une entrée média (image + texte associé) pour une page du document ODP.
///
/// Chaque jour peut avoir plusieurs entrées. Chaque entrée génère une page
/// dédiée avec l'image et son texte lié (légende ou résumé du jour).
class MediaEntry {
  /// Chemin de l'image dans l'archive ODP (ex: Pictures/jour_0_img_0.jpg).
  /// `null` si aucune image n'est associée à cette entrée.
  final String? imagePath;

  /// Dimensions en pixels de l'image (pour calculer le ratio).
  final ImageDimensions? dimensions;

  /// Texte associé à l'image (légende de la photo, ou résumé du jour
  /// si aucune légende n'est définie).
  final String text;

  const MediaEntry({
    this.imagePath,
    this.dimensions,
    required this.text,
  });
}

/// Données d'un jour pour la génération du document ODP.
///
/// Chaque jour devient un "chapitre" : une page de titre (avec la date et
/// le trajet) suivie d'une page par entrée média (image + texte lié).
class JourChapterData {
  final JourTrek jour;
  final List<MediaEntry> entries;

  const JourChapterData({required this.jour, required this.entries});
}

/// Remplacement des placeholders du template ODP `content.xml`.
///
/// Le template (`assets/templates/template_baroudeurstudio.odp`) contient 3 pages:
///  - page 1 (couverture) avec le placeholder `{{TREK_TITLE}}`
///  - page 2 (modèle de page "jour") avec les placeholders `{{JOUR_DEPART}}`,
///    `{{JOUR_RESUME}}` et `{{JOUR_IMAGE_1}}`
///  - page 3 (page de fin) avec une image
///
/// Cette classe génère un document structuré en chapitres:
///  - Page de couverture (titre du trek)
///  - Pour chaque jour (chapitre):
///    - Une page de titre (date + trajet)
///    - Une page par entrée média (image + texte lié)
///  - Page de fin
///
/// Les méthodes sont pures (sans IO) afin d'être testables unitairement.
class OdpContentFiller {
  static const String trekTitlePh = '{{TREK_TITLE}}';
  static const String jourDepartPh = '{{JOUR_DEPART}}';
  static const String jourResumePh = '{{JOUR_RESUME}}';
  static const String jourImagePh = '{{JOUR_IMAGE_1}}';

  static const String _pageOpenTag = '<draw:page';

  static bool _isRealPageOpen(String s, int idx) {
    final afterPos = idx + _pageOpenTag.length;
    if (afterPos >= s.length) return true;
    final ch = s[afterPos];
    return ch == ' ' || ch == '>' || ch == '\t' || ch == '\n' || ch == '/';
  }

  static int _findPageOpen(String s, int from) {
    var pos = from;
    while (true) {
      final idx = s.indexOf(_pageOpenTag, pos);
      if (idx < 0) return -1;
      if (_isRealPageOpen(s, idx)) return idx;
      pos = idx + 1;
    }
  }

  /// Remplit le `content.xml` du template avec les données du trek.
  ///
  /// [chapters] contient les données de chaque jour (chapitre), avec pour
  /// chacun la liste des entrées média (image + texte lié).
  ///
  /// Structure générée:
  /// - Couverture (titre du trek)
  /// - Pour chaque chapitre: page de titre + page(s) image+texte
  /// - Page de fin
  static String fill(
    String contentXml,
    Trek trek,
    List<JourChapterData> chapters, {
    OdpImageSettings imageSettings = OdpImageSettings.defaults,
  }) {
    // 1. Remplir la couverture (page 1).
    final titre = escapeXml(trek.titre);
    contentXml = contentXml.replaceAll(trekTitlePh, titre);

    // 2. Extraire les pages du template.
    final dayPages = extractTopLevelPages(contentXml);
    if (dayPages.length < 3) {
      throw StateError(
        'Le template ODP doit contenir au moins 3 pages (couverture, jour, fin)',
      );
    }
    final coverPage = dayPages[0];
    final dayPageTemplate = dayPages[1];
    final endPage = dayPages[2];

    // 3. Générer les pages pour chaque chapitre.
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr');
    final allPages = <String>[coverPage];
    int pageNumber = 2;

    for (int ci = 0; ci < chapters.length; ci++) {
      final chapter = chapters[ci];
      final jour = chapter.jour;
      final jourDate = DateTime.tryParse(jour.date);
      final dateStr = jourDate != null ? dateFormat.format(jourDate) : jour.date;
      final departStr = jour.lieuDepart.isNotEmpty
          ? '${jour.lieuDepart} -> ${jour.lieuArrivee}'
          : dateStr;

      // Page de titre du chapitre (Jour X - date + trajet)
      String titlePage = dayPageTemplate;
      titlePage = titlePage.replaceAll(
          jourDepartPh, escapeXml('Jour ${jour.numeroJour} - $departStr'));
      titlePage = titlePage.replaceAll(jourResumePh, escapeXml(dateStr));
      titlePage = titlePage.replaceAll(jourImagePh, '');
      titlePage = renamePage(titlePage, 'chapitre_${ci + 1}');
      titlePage = updatePageThumbnailNumber(titlePage, pageNumber);
      allPages.add(titlePage);
      pageNumber++;

      // Pages image + texte pour chaque entrée média
      for (int ei = 0; ei < chapter.entries.length; ei++) {
        final entry = chapter.entries[ei];
        String page = dayPageTemplate;
        // Titre: "Jour X - Photo Y" ou "Jour X - Texte" si pas d'image
        final pageTitle = entry.imagePath != null
            ? 'Jour ${jour.numeroJour} - Photo ${ei + 1}'
            : 'Jour ${jour.numeroJour} - Texte ${ei + 1}';
        page = page.replaceAll(jourDepartPh, escapeXml(pageTitle));
        page = page.replaceAll(jourResumePh, escapeXml(entry.text));
        page = injectImage(page, jourImagePh, entry.imagePath,
            entry.dimensions, imageSettings);
        page = renamePage(page, 'jour_${ci + 1}_img_${ei + 1}');
        page = updatePageThumbnailNumber(page, pageNumber);
        allPages.add(page);
        pageNumber++;
      }

      // Si le jour n'a aucune entrée média, on garde quand même une page
      // avec le résumé du jour (sans image).
      if (chapter.entries.isEmpty) {
        final resume = jour.resume.isNotEmpty
            ? jour.resume
            : (jour.texteGenereIA ?? '');
        String page = dayPageTemplate;
        page = page.replaceAll(jourDepartPh, escapeXml('Jour ${jour.numeroJour} - $departStr'));
        page = page.replaceAll(jourResumePh, escapeXml(resume));
        page = page.replaceAll(jourImagePh, '');
        page = renamePage(page, 'jour_${ci + 1}');
        page = updatePageThumbnailNumber(page, pageNumber);
        allPages.add(page);
        pageNumber++;
      }
    }

    allPages.add(endPage);

    // 4. Reconstruire le document.
    final presentationOpen = '<office:presentation>';
    final presentationClose = '</office:presentation>';
    final preStart = contentXml.indexOf(presentationOpen);
    final postEnd = contentXml.indexOf(presentationClose);
    if (preStart < 0 || postEnd < 0) {
      throw StateError('content.xml du template mal formé: balise presentation absente');
    }
    final head = contentXml.substring(0, preStart + presentationOpen.length);
    final tail = contentXml.substring(postEnd);
    return head + allPages.join('\n') + tail;
  }

  /// Extrait les éléments `<draw:page ...>...</draw:page>` de premier niveau.
  static List<String> extractTopLevelPages(String contentXml) {
    final pages = <String>[];
    int i = 0;
    while (true) {
      final start = _findPageOpen(contentXml, i);
      if (start < 0) break;
      final tagEnd = contentXml.indexOf('>', start);
      if (tagEnd < 0) break;
      final openTag = contentXml.substring(start, tagEnd + 1);
      final isSelfClosed = openTag.endsWith('/>');
      if (isSelfClosed) {
        pages.add(openTag);
        i = tagEnd + 1;
        continue;
      }
      var depth = 1;
      var j = tagEnd + 1;
      var found = false;
      while (depth > 0 && j < contentXml.length) {
        final nextOpen = _findPageOpen(contentXml, j);
        final nextClose = contentXml.indexOf('</draw:page>', j);
        if (nextClose < 0) break;
        if (nextOpen >= 0 && nextOpen < nextClose) {
          depth++;
          j = contentXml.indexOf('>', nextOpen) + 1;
        } else {
          depth--;
          if (depth == 0) {
            final page = contentXml.substring(
              start,
              nextClose + '</draw:page>'.length,
            );
            pages.add(page);
            i = nextClose + '</draw:page>'.length;
            found = true;
          } else {
            j = nextClose + '</draw:page>'.length;
          }
        }
      }
      if (!found) break;
    }
    return pages;
  }

  /// Calcule les dimensions d'affichage (largeur, hauteur) en centimètres
  /// pour une image donnée, en respectant son ratio d'origine et les
  /// contraintes minimum/maximum.
  static ({double widthCm, double heightCm}) computeImageDimensions(
    ImageDimensions? dims,
    OdpImageSettings settings,
  ) {
    if (dims == null || dims.width <= 0 || dims.height <= 0) {
      return (widthCm: settings.minWidthCm, heightCm: settings.minHeightCm);
    }

    final ratio = dims.aspectRatio;
    double widthCm;
    double heightCm;

    if (dims.isLandscape) {
      widthCm = settings.minWidthCm;
      heightCm = widthCm / ratio;
      if (heightCm < settings.minHeightCm) {
        heightCm = settings.minHeightCm;
        widthCm = heightCm * ratio;
      }
    } else {
      heightCm = settings.minHeightCm;
      widthCm = heightCm * ratio;
      if (widthCm < settings.minWidthCm) {
        widthCm = settings.minWidthCm;
        heightCm = widthCm / ratio;
      }
    }

    if (widthCm > settings.maxWidthCm) {
      widthCm = settings.maxWidthCm;
      heightCm = widthCm / ratio;
    }
    if (heightCm > settings.maxHeightCm) {
      heightCm = settings.maxHeightCm;
      widthCm = heightCm * ratio;
    }

    return (widthCm: widthCm, heightCm: heightCm);
  }

  /// Injecte une image dans le frame qui contient [placeholder].
  ///
  /// Le frame englobant est remplacé par un frame contenant une `draw:image`
  /// avec les dimensions calculées à partir du ratio de l'image.
  /// Si [imagePath] est null, le placeholder est simplement supprimé.
  static String injectImage(
    String page,
    String placeholder,
    String? imagePath,
    ImageDimensions? dims,
    OdpImageSettings settings,
  ) {
    if (imagePath == null || imagePath.isEmpty) {
      return page.replaceAll(placeholder, '');
    }
    final phIndex = page.indexOf(placeholder);
    if (phIndex < 0) return page;
    final frameStart = page.lastIndexOf('<draw:frame', phIndex);
    if (frameStart < 0) {
      return page.replaceAll(
        placeholder,
        '<draw:image xlink:href="$imagePath" xlink:type="simple" '
            'xlink:show="embed" xlink:actuate="onLoad" '
            'draw:mime-type="image/jpeg"/>',
      );
    }
    final frameEnd = page.indexOf('</draw:frame>', phIndex);
    if (frameEnd < 0) return page.replaceAll(placeholder, '');
    final frameEndPos = frameEnd + '</draw:frame>'.length;
    final originalFrame = page.substring(frameStart, frameEndPos);

    final x = _attr(originalFrame, 'svg:x');
    final y = _attr(originalFrame, 'svg:y');
    final styleName = _attr(originalFrame, 'draw:style-name');
    final textStyle = _attr(originalFrame, 'draw:text-style-name');

    final computed = computeImageDimensions(dims, settings);
    final widthStr = '${_formatCm(computed.widthCm)}cm';
    final heightStr = '${_formatCm(computed.heightCm)}cm';

    final dimsBuffer = StringBuffer();
    if (styleName != null) dimsBuffer.write(' draw:style-name="$styleName"');
    if (textStyle != null) dimsBuffer.write(' draw:text-style-name="$textStyle"');
    dimsBuffer.write(' svg:width="$widthStr"');
    dimsBuffer.write(' svg:height="$heightStr"');
    if (x != null) dimsBuffer.write(' svg:x="$x"');
    if (y != null) dimsBuffer.write(' svg:y="$y"');

    final imageFrame =
        '<draw:frame$dimsBuffer draw:layer="layout">'
        '<draw:image xlink:href="$imagePath" xlink:type="simple" '
        'xlink:show="embed" xlink:actuate="onLoad" '
        'draw:mime-type="image/jpeg"><text:p/></draw:image>'
        '</draw:frame>';

    return page.substring(0, frameStart) + imageFrame + page.substring(frameEndPos);
  }

  static String renamePage(String page, String newName) {
    final openTagEnd = page.indexOf('>', page.indexOf('<draw:page'));
    final openTag = page.substring(0, openTagEnd + 1);
    if (openTag.contains('draw:name=')) {
      final renamed = openTag.replaceFirst(
        RegExp(r'draw:name="[^"]*"'),
        'draw:name="$newName"',
      );
      return renamed + page.substring(openTagEnd + 1);
    }
    return openTag.replaceAll('>', ' draw:name="$newName">') +
        page.substring(openTagEnd + 1);
  }

  static String updatePageThumbnailNumber(String page, int number) {
    return page.replaceAll(
      RegExp(r'draw:page-number="\d+"'),
      'draw:page-number="$number"',
    );
  }

  static String removeAllPlaceholders(String s) {
    return s.replaceAll(RegExp(r'\{\{[^}]*\}\}'), '');
  }

  static String? _attr(String tag, String name) {
    final m = RegExp('$name="([^"]*)"').firstMatch(tag);
    return m?.group(1);
  }

  static String _formatCm(double cm) => cm.toStringAsFixed(3);

  /// Échappe les caractères spéciaux XML et convertit les sauts de ligne
  /// (`\n`, `\r\n`) en éléments `<text:line-break/>`.
  static String escapeXml(String text) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    return escaped
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '<text:line-break/>');
  }

  static Uint8List toUtf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
}
