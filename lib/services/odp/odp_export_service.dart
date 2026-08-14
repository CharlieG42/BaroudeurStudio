import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../models/trek.dart';
import '../../models/media.dart';
import '../../db/database_helper.dart';
import '../../config/app_config.dart';
import '../utils/image_optimizer.dart';
import '../utils/filename_utils.dart';
import 'odp_content_filler.dart';

/// Service d'export ODP (OpenDocument Presentation) pour les treks.
///
/// Ce service se base sur le template
/// `assets/templates/template_baroudeurstudio.odp` (réalisé sous LibreOffice).
/// Le template apporte sa propre mise en page (styles, master-pages, polices,
/// couleurs, orientation, image de couverture...). Le service se contente de:
///
/// - charger le template depuis les assets,
/// - décompresser l'archive ODP,
/// - remplir les placeholders de content.xml (`{{TREK_TITLE}}`,
///   `{{JOUR_DEPART}}`, `{{JOUR_RESUME}}`, `{{JOUR_IMAGE_1}}`), en préservant
///   les sauts de ligne du texte,
/// - dupliquer la page "jour" pour chaque `JourTrek`,
/// - ajouter les images des jours dans `Pictures/` en respectant le ratio
///   d'origine et les dimensions minimum configurées,
/// - mettre à jour `META-INF/manifest.xml` avec les nouvelles images,
/// - ré-encoder le ZIP avec mimetype en premier et non compressé
///   (obligatoire pour la conformité ODP).
///
/// IMPORTANT: le package `archive` 3.x a un bug dans `removeFile()` qui
/// corrompt les `_fileMap` après suppression d'un fichier (les index ne sont
/// pas recalculés). On évite donc `removeFile` en construisant une nouvelle
/// archive à partir des contenus lus immédiatement après le décodage.
class OdpExportService {
  /// Chemin du template ODP dans les assets Flutter.
  static const String templateAssetPath =
      'assets/templates/template_baroudeurstudio.odp';

  /// Type MIME ODP.
  static const String odpMimeType =
      'application/vnd.oasis.opendocument.presentation';

  /// Paramètres de dimensionnement des images (modifiables via le menu
  /// Paramétrage). Valeurs par défaut: hauteur min 8cm, largeur min 13cm.
  OdpImageSettings imageSettings = OdpImageSettings.defaults;

  /// Génère un fichier ODP à partir d'un trek, en se basant sur le template.
  Future<File> exportTrekToOdp(Trek trek) async {
    // 1. Charger les données du trek.
    final jours = await DatabaseHelper.instance.getJoursForTrek(trek.id!);
    final mediasByJour = <int, List<Media>>{};
    for (final jour in jours) {
      mediasByJour[jour.id!] =
          await DatabaseHelper.instance.getMediasForJour(jour.id!);
    }

    // 2. Charger le template depuis les assets.
    final templateBytes = await rootBundle.load(templateAssetPath);
    final archive =
        ZipDecoder().decodeBytes(templateBytes.buffer.asUint8List());

    // 3. Lire IMMÉDIATEMENT le contenu de tous les fichiers du template dans
    //    des variables locales. C'est nécessaire car le package `archive` 3.x
    //    a un bug: après removeFile(), les index internes (_fileMap) ne sont
    //    pas recalculés et findFile() renvoie des contenus corrompus.
    final fileContents = <String, Uint8List>{};
    for (final file in archive) {
      if (file.isFile) {
        final data = file.content as List<int>;
        fileContents[file.name] = Uint8List.fromList(data);
      }
    }

    // 4. Déterminer le chemin d'image de chaque jour (dans l'archive) et
    //    charger/optimiser les images pour extraire leurs dimensions.
    final jourImagePaths = <String?>[];
    final jourImageDimensions = <ImageDimensions?>[];
    for (int i = 0; i < jours.length; i++) {
      final medias = mediasByJour[jours[i].id] ?? [];
      // Pour le moment une image par jour (la première photo disponible).
      Media? firstPhoto;
      for (final m in medias) {
        if (m.type == MediaType.photo) {
          firstPhoto = m;
          break;
        }
      }
      firstPhoto ??= medias.isNotEmpty ? medias.first : null;

      if (firstPhoto != null) {
        final imagePath = 'Pictures/jour_$i.jpg';
        jourImagePaths.add(imagePath);
        // Charger et optimiser l'image, puis extraire ses dimensions.
        try {
          final file = File(firstPhoto.cheminFichier);
          final imageBytes = await file.readAsBytes();
          final optimizedBytes = await compute(
            _optimizeImageInIsolate,
            (imageBytes, AppConfig.imageCompressionQuality),
          );
          fileContents[imagePath] = optimizedBytes;
          // Extraire les dimensions de l'image optimisée.
          final dims = _readImageDimensions(optimizedBytes);
          jourImageDimensions.add(dims);
        } catch (e) {
          debugPrint('Erreur lors du chargement de l\'image: $e');
          jourImagePaths.last = null;
          jourImageDimensions.add(null);
        }
      } else {
        jourImagePaths.add(null);
        jourImageDimensions.add(null);
      }
    }

    // 5. Remplir content.xml avec les placeholders (en préservant les sauts
    //    de ligne et en calculant les dimensions des images selon le ratio).
    final contentXml = utf8.decode(fileContents['content.xml']!, allowMalformed: true);
    final filledContent = OdpContentFiller.fill(
      contentXml,
      trek,
      jours,
      jourImagePaths,
      jourImageDimensions: jourImageDimensions,
      imageSettings: imageSettings,
    );
    fileContents['content.xml'] = Uint8List.fromList(utf8.encode(filledContent));

    // 6. Mettre à jour META-INF/manifest.xml avec les nouvelles images.
    final manifestXml = utf8.decode(
      fileContents['META-INF/manifest.xml']!,
      allowMalformed: true,
    );
    final updatedManifest = _addImagesToManifest(manifestXml, jourImagePaths);
    fileContents['META-INF/manifest.xml'] =
        Uint8List.fromList(utf8.encode(updatedManifest));

    // 7. Mettre à jour meta.xml avec le titre et la date.
    final metaXml = utf8.decode(fileContents['meta.xml']!, allowMalformed: true);
    final updatedMeta = _updateMetaXml(metaXml, trek);
    fileContents['meta.xml'] = Uint8List.fromList(utf8.encode(updatedMeta));

    // 8. Ré-encoder l'archive: mimetype en premier et non compressé.
    final newArchive = Archive();

    // mimetype en premier, non compressé.
    final mimetypeData = fileContents['mimetype']!;
    final mt = ArchiveFile('mimetype', mimetypeData.length, mimetypeData);
    mt.compress = false;
    newArchive.addFile(mt);
    fileContents.remove('mimetype');

    // Ajouter le reste des fichiers dans l'ordre original du template.
    for (final file in archive) {
      if (file.name == 'mimetype') continue;
      if (!file.isFile) {
        newArchive.addFile(file);
        continue;
      }
      final data = fileContents[file.name];
      if (data == null) continue;
      final copy = ArchiveFile(file.name, data.length, data);
      copy.compress = true;
      newArchive.addFile(copy);
      fileContents.remove(file.name);
    }

    // Ajouter les nouvelles images (jour_x.jpg) qui ne sont pas dans le template.
    for (final entry in fileContents.entries) {
      if (entry.key.startsWith('Pictures/jour_')) {
        final copy = ArchiveFile(
          entry.key,
          entry.value.length,
          entry.value,
        );
        copy.compress = true;
        newArchive.addFile(copy);
      }
    }

    final zipData = ZipEncoder().encode(newArchive);
    if (zipData == null) {
      throw StateError('Échec de l\'encodage de l\'archive ODP');
    }

    // 9. Écrire le fichier final.
    final directory = await getApplicationDocumentsDirectory();
    final filename = FilenameUtils.generateExportFilename(trek.titre, 'odp');
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(zipData);
    return file;
  }

  /// Lit les dimensions (largeur, hauteur en pixels) d'une image JPEG.
  ///
  /// Utilise le package `image` pour décoder l'en-tête de l'image sans
  /// charger toute l'image en mémoire.
  ImageDimensions? _readImageDimensions(Uint8List imageBytes) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;
      return ImageDimensions(decoded.width, decoded.height);
    } catch (e) {
      debugPrint('Erreur lors de la lecture des dimensions de l\'image: $e');
      return null;
    }
  }

  /// Ajoute les entrées manifest pour les images de jour qui ne sont pas
  /// déjà présentes.
  String _addImagesToManifest(String manifestXml, List<String?> imagePaths) {
    final toAdd = <String>[];
    for (final path in imagePaths) {
      if (path == null || path.isEmpty) continue;
      if (!manifestXml.contains('manifest:full-path="$path"')) {
        toAdd.add(
          '  <manifest:file-entry manifest:full-path="$path" '
          'manifest:media-type="image/jpeg"/>',
        );
      }
    }
    if (toAdd.isEmpty) return manifestXml;
    final insertBefore = manifestXml.indexOf('</manifest:manifest>');
    if (insertBefore < 0) return manifestXml;
    return '${manifestXml.substring(0, insertBefore)}'
        '${toAdd.join('\n')}\n'
        '${manifestXml.substring(insertBefore)}';
  }

  /// Met à jour le titre et la date dans meta.xml.
  String _updateMetaXml(String metaXml, Trek trek) {
    final now = DateTime.now().toUtc().toIso8601String();
    var result = metaXml;
    final escaped = _escapeXml(trek.titre);
    if (result.contains('<dc:title>')) {
      result = result.replaceFirst(
        RegExp(r'<dc:title>[^<]*</dc:title>'),
        '<dc:title>$escaped</dc:title>',
      );
    } else {
      result = result.replaceFirst(
        '<office:meta>',
        '<office:meta>\n    <dc:title>$escaped</dc:title>',
      );
    }
    if (result.contains('<dc:date>')) {
      result = result.replaceFirst(
        RegExp(r'<dc:date>[^<]*</dc:date>'),
        '<dc:date>$now</dc:date>',
      );
    }
    return result;
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Fonction pour optimiser une image dans un isolate.
  static Uint8List _optimizeImageInIsolate((Uint8List, int) params) {
    final (imageBytes, quality) = params;
    return ImageOptimizer.optimizeImage(imageBytes, quality: quality);
  }
}
