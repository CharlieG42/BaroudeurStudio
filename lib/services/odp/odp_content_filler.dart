import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../models/trek.dart';
import '../../models/jour_trek.dart';

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
///  - injecter une image par jour dans le frame `{{JOUR_IMAGE_1}}`,
///  - renumeroter les pages / `draw:name`.
///
/// Les methodes sont pures (sans IO) afin d'etre testables unitairement.
class OdpContentFiller {
  /// Nom du placeholder pour le titre du trek.
  static const String trekTitlePh = '{{TREK_TITLE}}';

  /// Nom du placeholder pour le depart du jour.
  static const String jourDepartPh = '{{JOUR_DEPART}}';

  /// Nom du placeholder pour le resume du jour.
  static const String jourResumePh = '{{JOUR_RESUME}}';

  /// Nom du placeholder pour l'image du jour.
  static const String jourImagePh = '{{JOUR_IMAGE_1}}';

  /// Prefixe de balise ouvrante d'une page ODP.
  static const String _pageOpenTag = '<draw:page';

  /// Indique si la position [idx] de [s] correspond bien a une balise
  /// `<draw:page ...>` (et non a `<draw:page-thumbnail ...>`).
  ///
  /// `<draw:page` est un prefixe commun aux deux; on verifie le caractere qui
  /// suit: un separateur (espace, `>`, tab, newline, `/`) designe une vraie
  /// page, tandis qu'un `-` designe `draw:page-thumbnail`.
  static bool _isRealPageOpen(String s, int idx) {
    final afterPos = idx + _pageOpenTag.length;
    if (afterPos >= s.length) return true;
    final ch = s[afterPos];
    return ch == ' ' || ch == '>' || ch == '\t' || ch == '\n' || ch == '/';
  }

  /// Recherche la prochaine vraie balise `<draw:page ...>` a partir de [from].
  static int _findPageOpen(String s, int from) {
    var pos = from;
    while (true) {
      final idx = s.indexOf(_pageOpenTag, pos);
      if (idx < 0) return -1;
      if (_isRealPageOpen(s, idx)) return idx;
      pos = idx + 1;
    }
  }

  /// Remplit le `content.xml` du template avec les donnees du trek.
  ///
  /// [contentXml] est le contenu brut du `content.xml` du template.
  /// [jourImagePaths] contient, pour chaque jour (dans le meme ordre que
  /// [jours]), le chemin de l'image a inserer dans le frame
  /// `{{JOUR_IMAGE_1}}` (ex: `Pictures/jour_0.jpg`). Une valeur `null`
  /// signifie qu'il n'y a pas d'image pour ce jour (le placeholder est alors
  /// simplement supprime).
  ///
  /// Retourne le nouveau `content.xml` avec toutes les pages.
  static String fill(
    String contentXml,
    Trek trek,
    List<JourTrek> jours,
    List<String?> jourImagePaths,
  ) {
    if (jours.length != jourImagePaths.length) {
      throw ArgumentError(
        'jours et jourImagePaths doivent avoir la meme longueur',
      );
    }

    // 1. Remplir la couverture (page 1).
    final titre = escapeXml(trek.titre);
    contentXml = contentXml.replaceAll(trekTitlePh, titre);

    // 2. Extraire la page "jour" (page 2) qui sert de modele.
    final dayPages = extractTopLevelPages(contentXml);
    if (dayPages.length < 3) {
      throw StateError(
        'Le template ODP doit contenir au moins 3 pages (couverture, jour, fin)',
      );
    }
    final coverPage = dayPages[0];
    final dayPageTemplate = dayPages[1];
    final endPage = dayPages[2];

    // 3. Generer une page remplie pour chaque jour.
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr');
    final filledDayPages = <String>[];
    for (int i = 0; i < jours.length; i++) {
      final jour = jours[i];
      final imagePath = jourImagePaths[i];
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
      page = injectImage(page, jourImagePh, imagePath);
      // Renommer la page pour eviter les collisions de `draw:name`.
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
      throw StateError('content.xml du template mal forme: balise presentation absente');
    }
    final head = contentXml.substring(0, preStart + presentationOpen.length);
    final tail = contentXml.substring(postEnd);

    final pages = <String>[coverPage];
    if (filledDayPages.isEmpty) {
      // Aucun jour: on garde la page modele vide (placeholders supprimes).
      pages.add(removeAllPlaceholders(dayPageTemplate));
    } else {
      pages.addAll(filledDayPages);
    }
    pages.add(endPage);

    final rebuilt = head + pages.join('\n') + tail;
    return rebuilt;
  }

  /// Extrait les elements `<draw:page ...>...</draw:page>` de premier niveau.
  ///
  /// On ne peut pas juste spliter sur `</draw:page>` car une page contient des
  /// `presentation:notes` qui peuvent elles-memes contenir des sous-elements
  /// (notamment des `<draw:page-thumbnail>` dont le nom commence par
  /// `<draw:page`). On fait donc une analyse parenthesee robuste qui distingue
  /// `<draw:page` (page) de `<draw:page-thumbnail`.
  static List<String> extractTopLevelPages(String contentXml) {
    final pages = <String>[];
    int i = 0;
    while (true) {
      final start = _findPageOpen(contentXml, i);
      if (start < 0) break;
      // Trouver la fin de la balise ouvrante.
      final tagEnd = contentXml.indexOf('>', start);
      if (tagEnd < 0) break;
      final openTag = contentXml.substring(start, tagEnd + 1);
      final isSelfClosed = openTag.endsWith('/>');
      if (isSelfClosed) {
        pages.add(openTag);
        i = tagEnd + 1;
        continue;
      }
      // Recherche de la balise fermante correspondante en gerant
      // l'imbrication (au cas ou une page contiendrait un draw:page imbrique).
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

  /// Injecte une image dans le frame qui contient [placeholder].
  ///
  /// Le frame englobant (balise `draw:frame` contenant le placeholder) est
  /// remplace par un frame contenant une `draw:image` pointant vers
  /// [imagePath]. Si [imagePath] est null, le placeholder est simplement
  /// supprime.
  static String injectImage(
    String page,
    String placeholder,
    String? imagePath,
  ) {
    if (imagePath == null || imagePath.isEmpty) {
      return page.replaceAll(placeholder, '');
    }
    // Trouver le draw:frame qui contient le placeholder et le remplacer
    // en entier par un frame d'image reutilisant les memes dimensions.
    final phIndex = page.indexOf(placeholder);
    if (phIndex < 0) return page;
    final frameStart = page.lastIndexOf('<draw:frame', phIndex);
    if (frameStart < 0) {
      // Pas de frame englobant: on remplace juste le placeholder par une image.
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

    // Extraire largeur/hauteur/x/y du frame original pour conserver la mise
    // en page definie dans le template.
    final width = _attr(originalFrame, 'svg:width');
    final height = _attr(originalFrame, 'svg:height');
    final x = _attr(originalFrame, 'svg:x');
    final y = _attr(originalFrame, 'svg:y');
    final styleName = _attr(originalFrame, 'draw:style-name');
    final textStyle = _attr(originalFrame, 'draw:text-style-name');

    final dims = StringBuffer();
    if (styleName != null) dims.write(' draw:style-name="$styleName"');
    if (textStyle != null) dims.write(' draw:text-style-name="$textStyle"');
    if (width != null) dims.write(' svg:width="$width"');
    if (height != null) dims.write(' svg:height="$height"');
    if (x != null) dims.write(' svg:x="$x"');
    if (y != null) dims.write(' svg:y="$y"');

    final imageFrame =
        '<draw:frame$dims draw:layer="layout">'
        '<draw:image xlink:href="$imagePath" xlink:type="simple" '
        'xlink:show="embed" xlink:actuate="onLoad" '
        'draw:mime-type="image/jpeg"/>'
        '</draw:frame>';

    return page.substring(0, frameStart) + imageFrame + page.substring(frameEndPos);
  }

  /// Renomme l'attribut `draw:name` de la premiere balise `draw:page`.
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
    // Ajouter draw:name avant le > fermant.
    return openTag.replaceAll('>', ' draw:name="$newName">') +
        page.substring(openTagEnd + 1);
  }

  /// Met a jour l'attribut `draw:page-number` d'un `draw:page-thumbnail`.
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

  /// Echappe les caracteres speciaux XML.
  static String escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Encode une chaine en UTF-8 bytes.
  static Uint8List toUtf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
}
