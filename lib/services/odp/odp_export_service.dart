import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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
/// A la difference de l'ancienne implementation qui reconstruisait tout le
/// document ODP a la main, ce service se base sur le template
/// `assets/templates/template_baroudeurstudio.odp` (realise sous LibreOffice).
/// Le template apporte sa propre mise en page (styles, master-pages, polices,
/// couleurs, orientation, image de couverture...). Le service se contente de:
///
/// - charger le template depuis les assets,
/// - decompresser l'archive ODP,
/// - remplir les placeholders de content.xml (`{{TREK_TITLE}}`,
///   `{{JOUR_DEPART}}`, `{{JOUR_RESUME}}`, `{{JOUR_IMAGE_1}}`),
/// - dupliquer la page "jour" pour chaque `JourTrek`,
/// - ajouter les images des jours dans `Pictures/`,
/// - mettre a jour `META-INF/manifest.xml` avec les nouvelles images,
/// - re-encoder le ZIP avec mimetype en premier et non compresse
///   (obligatoire pour la conformite ODP).
class OdpExportService {
  /// Chemin du template ODP dans les assets Flutter.
  static const String templateAssetPath =
      'assets/templates/template_baroudeurstudio.odp';

  /// Type MIME ODP.
  static const String odpMimeType =
      'application/vnd.oasis.opendocument.presentation';

  /// Genere un fichier ODP a partir d'un trek, en se basant sur le template.
  Future<File> exportTrekToOdp(Trek trek) async {
    // 1. Charger les donnees du trek.
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

    // 3. Lire content.xml et le remplir.
    final contentFile = archive.findFile('content.xml');
    if (contentFile == null) {
      throw StateError('Le template ODP ne contient pas de content.xml');
    }
    final contentXml =
        utf8.decode(contentFile.content as List<int>, allowMalformed: true);

    // 4. Determiner le chemin d'image de chaque jour (dans l'archive).
    final jourImagePaths = <String?>[];
    final jourPhotoMedias = <Media?>[];
    for (int i = 0; i < jours.length; i++) {
      final medias = mediasByJour[jours[i].id] ?? [];
      // Pour le moment une image par jour (la premiere photo disponible).
      Media? firstPhoto;
      for (final m in medias) {
        if (m.type == MediaType.photo) {
          firstPhoto = m;
          break;
        }
      }
      firstPhoto ??= medias.isNotEmpty ? medias.first : null;
      jourPhotoMedias.add(firstPhoto);
      if (firstPhoto != null) {
        jourImagePaths.add('Pictures/jour_$i.jpg');
      } else {
        jourImagePaths.add(null);
      }
    }

    final filledContent =
        OdpContentFiller.fill(contentXml, trek, jours, jourImagePaths);

    // 5. Ajouter les images des jours dans l'archive.
    for (int i = 0; i < jours.length; i++) {
      final imagePath = jourImagePaths[i];
      final firstPhoto = jourPhotoMedias[i];
      if (imagePath == null || firstPhoto == null) continue;
      try {
        final file = File(firstPhoto.cheminFichier);
        final imageBytes = await file.readAsBytes();
        final optimizedBytes = await compute(
          _optimizeImageInIsolate,
          (imageBytes, AppConfig.imageCompressionQuality),
        );
        archive.addFile(
          ArchiveFile(imagePath, optimizedBytes.length, optimizedBytes),
        );
      } catch (e) {
        debugPrint('Erreur lors du chargement de l\'image: $e');
      }
    }

    // 6. Mettre a jour content.xml dans l'archive.
    final contentBytes = Uint8List.fromList(utf8.encode(filledContent));
    _replaceFileInArchive(archive, 'content.xml', contentBytes);

    // 7. Mettre a jour META-INF/manifest.xml avec les nouvelles images.
    final manifestFile = archive.findFile('META-INF/manifest.xml');
    if (manifestFile != null) {
      final manifestXml =
          utf8.decode(manifestFile.content as List<int>, allowMalformed: true);
      final updatedManifest =
          _addImagesToManifest(manifestXml, jourImagePaths);
      _replaceFileInArchive(
        archive,
        'META-INF/manifest.xml',
        Uint8List.fromList(utf8.encode(updatedManifest)),
      );
    }

    // 8. Mettre a jour meta.xml avec le titre et la date.
    final metaFile = archive.findFile('meta.xml');
    if (metaFile != null) {
      final metaXml =
          utf8.decode(metaFile.content as List<int>, allowMalformed: true);
      final updatedMeta = _updateMetaXml(metaXml, trek);
      _replaceFileInArchive(
        archive,
        'meta.xml',
        Uint8List.fromList(utf8.encode(updatedMeta)),
      );
    }

    // 9. Re-encoder l'archive: mimetype en premier et non compresse.
    //
    // On reconstruit une nouvelle archive pour controler l'ordre des entrees
    // (le mimetype doit etre le premier fichier, stocke sans compression,
    // c'est une obligation du format ODP/ODF).
    final newArchive = Archive();

    // mimetype en premier, non compresse.
    final mimetypeFile = archive.findFile('mimetype');
    if (mimetypeFile != null) {
      final mtContent = mimetypeFile.content as List<int>;
      final mt = ArchiveFile(
        'mimetype',
        mtContent.length,
        Uint8List.fromList(mtContent),
      );
      mt.compress = false;
      newArchive.addFile(mt);
    }

    // Ajouter le reste des fichiers (fichiers et repertoires) du template.
    for (final file in archive) {
      if (file.name == 'mimetype') continue;
      if (!file.isFile) {
        // Entree de repertoire (ex: Configurations2/).
        newArchive.addFile(file);
        continue;
      }
      // Fichier regulier: copier le contenu et forcer la compression.
      final data = file.content as List<int>;
      final copy = ArchiveFile(file.name, data.length, Uint8List.fromList(data));
      copy.compress = true;
      newArchive.addFile(copy);
    }

    final zipData = ZipEncoder().encode(newArchive);
    if (zipData == null) {
      throw StateError('Echec de l\'encodage de l\'archive ODP');
    }

    // 10. Ecrire le fichier final.
    final directory = await getApplicationDocumentsDirectory();
    final filename = FilenameUtils.generateExportFilename(trek.titre, 'odp');
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(zipData);
    return file;
  }

  /// Remplace (ou ajoute) un fichier dans l'archive.
  void _replaceFileInArchive(
    Archive archive,
    String name,
    Uint8List bytes,
  ) {
    final existing = archive.findFile(name);
    if (existing != null) {
      archive.removeFile(existing);
    }
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  /// Ajoute les entrees manifest pour les images de jour qui ne sont pas
  /// deja presentes.
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

  /// Met a jour le titre et la date dans meta.xml.
  String _updateMetaXml(String metaXml, Trek trek) {
    final now = DateTime.now().toUtc().toIso8601String();
    var result = metaXml;
    // Remplacer/dc:title ou l'ajouter.
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
    // Mettre a jour la date de modification.
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
