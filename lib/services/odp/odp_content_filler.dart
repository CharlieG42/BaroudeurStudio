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
  /// Hauteur minimum de l'image en centimètres.
  final double minHeightCm;

  /// Largeur minimum de l'image en centimètres.
  final double minWidthCm;

  /// Largeur maximum de l'image en centimètres (pour ne pas déborder de la page).
  final double maxWidthCm;

  /// Hauteur maximum de l'image en centimètres.
  final double maxHeightCm;

  const OdpImageSettings({
    this.minHeightCm = 8.0,
    this.minWidthCm = 13.0,
    this.maxWidthCm = 18.0,
    this.maxHeightCm = 20.0,
  });

  /// Valeurs par défaut.
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

  /// Ratio largeur/hauteur de l'image.
  double get aspectRatio => height > 0 ? width / height : 1.0;

  /// Indique si l'image est en mode paysage (largeur > hauteur).
  bool get isLandscape => width > height;
}

/// Remplacement des placeholders du template ODP `content.xml`.
///
/// Le template (`assets/templates/template_baroudeurstudio.odp`) contient 3 pages:
///  - page 1 (couverture) avec le placeholder `{{TREK_TITLE}}`
///  - page 2 (modele de page "jour") avec les placeholders `{{JOUR_DEPART}}`,
///    `{{JOUR_RESUME}}` et `{{JOUR_IMAGE_1}}`
///  - page 3 (page de fin) avec une image
///
/// Cette classe se charge de:
///  - remplir la couverture,
///  - dupliquer la page "jour" pour chaque `JourTrek`,
///  - préserver les sauts de ligne dans les textes (convertis en
///    `<text:line-break/>`),
///  - injecter une image par jour dans le frame `{{JOUR_IMAGE_1}}` en
///    respectant le ratio d'origine et les dimensions minimum configurées,
///  - renuméroter les pages / `draw:name`.
///
/// Les méthodes sont pures (sans IO) afin d'être testables unitairement.
class OdpContentFiller {
  /// Nom du placeholder pour le titre du trek.
  static const String trekTitlePh = '{{TREK_TITLE}}';

  /// Nom du placeholder pour le départ du jour.
  static const String jourDepartPh = '{{JOUR_DEPART}}';

  /// Nom du placeholder pour le résumé du jour.
  static const String jourResumePh = '{{JOUR_RESUME}}';

  /// Nom du placeholder pour l'image du jour.
  static const String jourImagePh = '{{JOUR_IMAGE_1}}';

  /// Préfixe de balise ouvrante d'une page ODP.
  static const String _pageOpenTag = '<draw:page';

  /// Indique si la position [idx] de [s] correspond bien à une balise
  /// `<draw:page ...>` (et non à `<draw:page-thumbnail ...>`).
  static bool _isRealPageOpen(String s, int idx) {
    final afterPos = idx + _pageOpenTag.length;
    if (afterPos >= s.length) return true;
    final ch = s[afterPos];
    return ch == ' ' || ch == '>' || ch == '\t' || ch == '\n' || ch == '/';
  }

  /// Recherche la prochaine vraie balise `<draw:page ...>` à partir de [from].
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
  /// [contentXml] est le contenu brut du `content.xml` du template.
  /// [jourImagePaths] contient, pour chaque jour (dans le même ordre que
  /// [jours]), le chemin de l'image à insérer dans le frame
  /// `{{JOUR_IMAGE_1}}` (ex: `Pictures/jour_0.jpg`). Une valeur `null`
  /// signifie qu'il n'y a pas d'image pour ce jour (le placeholder est alors
  /// simplement supprimé).
  /// [jourImageDimensions] contient, pour chaque jour, les dimensions en
  /// pixels de l'image (pour calculer le ratio et les dimensions d'affichage).
  /// Si `null` ou manquant, les dimensions du template sont utilisées.
  /// [imageSettings] contrôle les dimensions minimum/maximum des images.
  ///
  /// Retourne le nouveau `content.xml` avec toutes les pages.
  static String fill(
    String contentXml,
    Trek trek,
    List<JourTrek> jours,
    List<String?> jourImagePaths, {
    List<ImageDimensions?>? jourImageDimensions,
    OdpImageSettings imageSettings = OdpImageSettings.defaults,
  }) {
    if (jours.length != jourImagePaths.length) {
      throw ArgumentError(
        'jours et jourImagePaths doivent avoir la même longueur',
      );
    }

    // 1. Remplir la couverture (page 1).
    final titre = escapeXml(trek.titre);
    contentXml = contentXml.replaceAll(trekTitlePh, titre);

    // 2. Extraire la page "jour" (page 2) qui sert de modèle.
    final dayPages = extractTopLevelPages(contentXml);
    if (dayPages.length < 3) {
      throw StateError(
        'Le template ODP doit contenir au moins 3 pages (couverture, jour, fin)',
      );
    }
    final coverPage = dayPages[0];
    final dayPageTemplate = dayPages[1];
    final endPage = dayPages[2];

    // 3. Générer une page remplie pour chaque jour.
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr');
    final filledDayPages = <String>[];
    for (int i = 0; i < jours.length; i++) {
      final jour = jours[i];
      final imagePath = jourImagePaths[i];
      final imgDims = jourImageDimensions != null && i < jourImageDimensions.length
          ? jourImageDimensions[i]
          : null;
      final jourDate = DateTime.tryParse(jour.date);
      final dateStr = jourDate != null ? dateFormat.format(jourDate) : jour.date;
      final departStr = jour.lieuDepart.isNotEmpty
          ? '${jour.lieuDepart} -> ${jour.lieuArrivee}'
          : dateStr;
      final resume = jour.resume.isNotEmpty
          ? jour.resume
          : (jour.texteGenereIA ?? '');

      String page = dayPageTemplate;
      page = page.replaceAll(jourDepartPh, escapeXml(departStr));
      page = page.replaceAll(jourResumePh, escapeXml(resume));
      page = injectImage(page, jourImagePh, imagePath, imgDims, imageSettings);
      // Renommer la page pour éviter les collisions de `draw:name`.
      page = renamePage(page, 'jour_${i + 1}');
      page = updatePageThumbnailNumber(page, i + 2);
      filledDayPages.add(page);
    }

    // 4. Reconstruire le document: couverture + pages de jour + page de fin.
    final presentationOpen = '<office:presentation>';
    final presentationClose = '</office:presentation>';
    final preStart = contentXml.indexOf(presentationOpen);
    final postEnd = contentXml.indexOf(presentationClose);
    if (preStart < 0 || postEnd < 0) {
      throw StateError('content.xml du template mal formé: balise presentation absente');
    }
    final head = contentXml.substring(0, preStart + presentationOpen.length);
    final tail = contentXml.substring(postEnd);

    final pages = <String>[coverPage];
    if (filledDayPages.isEmpty) {
      // Aucun jour: on garde la page modèle vide (placeholders supprimés).
      pages.add(removeAllPlaceholders(dayPageTemplate));
    } else {
      pages.addAll(filledDayPages);
    }
    pages.add(endPage);

    final rebuilt = head + pages.join('\n') + tail;
    return rebuilt;
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
  ///
  /// Règle: la hauteur doit être au minimum [settings.minHeightCm] OU la
  /// largeur au minimum [settings.minWidthCm], tout en respectant le ratio
  /// et sans dépasser les maximums.
  static ({double widthCm, double heightCm}) computeImageDimensions(
    ImageDimensions? dims,
    OdpImageSettings settings,
  ) {
    // Sans dimensions connues, on utilise les valeurs minimum comme carré.
    if (dims == null || dims.width <= 0 || dims.height <= 0) {
      return (widthCm: settings.minWidthCm, heightCm: settings.minHeightCm);
    }

    final ratio = dims.aspectRatio; // width / height

    // Calculer les dimensions qui satisfont les deux contraintes minimum.
    // - Si on fixe la hauteur à minHeightCm, la largeur = minHeightCm * ratio.
    // - Si on fixe la largeur à minWidthCm, la hauteur = minWidthCm / ratio.

    // On choisit la dimension qui satisfait le mieux les deux minimums.
    double widthCm;
    double heightCm;

    if (dims.isLandscape) {
      // Image paysage: la largeur est le facteur limitant.
      // On veut largeur >= minWidthCm.
      widthCm = settings.minWidthCm;
      heightCm = widthCm / ratio;
      // Mais s'assurer aussi que la hauteur >= minHeightCm.
      if (heightCm < settings.minHeightCm) {
        heightCm = settings.minHeightCm;
        widthCm = heightCm * ratio;
      }
    } else {
      // Image portrait ou carrée: la hauteur est le facteur limitant.
      // On veut hauteur >= minHeightCm.
      heightCm = settings.minHeightCm;
      widthCm = heightCm * ratio;
      // Mais s'assurer aussi que la largeur >= minWidthCm.
      if (widthCm < settings.minWidthCm) {
        widthCm = settings.minWidthCm;
        heightCm = widthCm / ratio;
      }
    }

    // Appliquer les maximums (en préservant le ratio).
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
  /// Le frame englobant (balise `draw:frame` contenant le placeholder) est
  /// remplacé par un frame contenant une `draw:image` pointant vers
  /// [imagePath]. Les dimensions du frame sont calculées à partir du ratio
  /// de l'image ([dims]) et des [settings], en conservant la position (x, y)
  /// du frame original du template.
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

    // Extraire la position (x, y) du frame original pour conserver la mise
    // en page définie dans le template.
    final x = _attr(originalFrame, 'svg:x');
    final y = _attr(originalFrame, 'svg:y');
    final styleName = _attr(originalFrame, 'draw:style-name');
    final textStyle = _attr(originalFrame, 'draw:text-style-name');

    // Calculer les dimensions optimales en respectant le ratio.
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

  /// Renomme l'attribut `draw:name` de la première balise `draw:page`.
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

  /// Met à jour l'attribut `draw:page-number` d'un `draw:page-thumbnail`.
  static String updatePageThumbnailNumber(String page, int number) {
    return page.replaceAll(
      RegExp(r'draw:page-number="\d+"'),
      'draw:page-number="$number"',
    );
  }

  /// Supprime tous les placeholders `{{...}}` restants.
  static String removeAllPlaceholders(String s) {
    return s.replaceAll(RegExp(r'\{\{[^}]*\}\}'), '');
  }

  /// Extrait la valeur d'un attribut `name="value"` depuis [tag].
  static String? _attr(String tag, String name) {
    final m = RegExp('$name="([^"]*)"').firstMatch(tag);
    return m?.group(1);
  }

  /// Formate une valeur en centimètres avec 3 décimales (format ODP).
  static String _formatCm(double cm) {
    return cm.toStringAsFixed(3);
  }

  /// Échappe les caractères spéciaux XML et convertit les sauts de ligne
  /// (`\n`, `\r\n`) en éléments `<text:line-break/>` pour préserver la mise
  /// en forme du texte dans le document ODP.
  ///
  /// En ODF, un saut de ligne simple (soft break) au sein d'un paragraphe
  /// est représenté par `<text:line-break/>`. Cette méthode préserve donc les
  /// sauts de ligne saisis par l'utilisateur dans les champs de texte
  /// (résumé, émotions, découvertes, etc.).
  static String escapeXml(String text) {
    // D'abord échapper les caractères spéciaux.
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    // Ensuite convertir les sauts de ligne en <text:line-break/>.
    // On normalise \r\n et \r en \n d'abord.
    return escaped
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '<text:line-break/>');
  }

  /// Encode une chaîne en UTF-8 bytes.
  static Uint8List toUtf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
}
