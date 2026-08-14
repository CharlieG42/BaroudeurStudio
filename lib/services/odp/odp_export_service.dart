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
/// Le document généré est structuré en chapitres: chaque jour devient un
/// chapitre avec une page de titre (date + trajet) suivie d'une page par
/// photo (image + texte/légende lié). Le ratio d'origine des images est
/// respecté, avec une hauteur minimum de 8cm ou une largeur minimum de 13cm.
///
/// IMPORTANT: le package `archive` 3.x a un bug dans `removeFile()` qui
/// corrompt les `_fileMap` après suppression d'un fichier. On évite donc
/// `removeFile` en construisant une nouvelle archive à partir des contenus
/// lus immédiatement après le décodage.
class OdpExportService {
  static const String templateAssetPath =
      'assets/templates/template_baroudeurstudio.odp';

  static const String odpMimeType =
      'application/vnd.oasis.opendocument.presentation';

  /// Paramètres de dimensionnement des images (modifiables via le menu
  /// Paramétrage).
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

    // 3. Lire IMMÉDIATEMENT le contenu de tous les fichiers du template.
    final fileContents = <String, Uint8List>{};
    for (final file in archive) {
      if (file.isFile) {
        final data = file.content as List<int>;
        fileContents[file.name] = Uint8List.fromList(data);
      }
    }

    // 4. Collecter les photos de chaque jour, les optimiser et construire
    //    les données de chapitrage (JourChapterData).
    final chapters = <JourChapterData>[];
    final allImagePaths = <String>[];

    for (int ji = 0; ji < jours.length; ji++) {
      final jour = jours[ji];
      final medias = mediasByJour[jour.id] ?? [];
      final photos = medias.where((m) => m.type == MediaType.photo).toList();

      final entries = <MediaEntry>[];

      if (photos.isEmpty) {
        // Aucune photo: une entrée texte seule avec le résumé du jour.
        final resume = jour.resume.isNotEmpty
            ? jour.resume
            : (jour.texteGenereIA ?? '');
        entries.add(MediaEntry(text: resume));
      } else {
        // Une entrée par photo, avec sa légende (ou le résumé du jour
        // si la légende est vide et qu'il s'agit de la première photo).
        for (int pi = 0; pi < photos.length; pi++) {
          final photo = photos[pi];
          final imagePath = 'Pictures/jour_${ji}_img_$pi.jpg';

          // Texte associé: la légende de la photo, ou le résumé du jour
          // pour la première photo si aucune légende n'est définie.
          String text;
          if (photo.legende != null && photo.legende!.isNotEmpty) {
            text = photo.legende!;
          } else if (pi == 0) {
            text = jour.resume.isNotEmpty
                ? jour.resume
                : (jour.texteGenereIA ?? '');
          } else {
            text = '';
          }

          // Charger et optimiser l'image.
          ImageDimensions? dims;
          try {
            final file = File(photo.cheminFichier);
            final imageBytes = await file.readAsBytes();
            final optimizedBytes = await compute(
              _optimizeImageInIsolate,
              (imageBytes, AppConfig.imageCompressionQuality),
            );
            fileContents[imagePath] = optimizedBytes;
            dims = _readImageDimensions(optimizedBytes);
          } catch (e) {
            debugPrint('Erreur lors du chargement de l\'image: $e');
          }

          entries.add(MediaEntry(
            imagePath: fileContents.containsKey(imagePath) ? imagePath : null,
            dimensions: dims,
            text: text,
          ));
          if (fileContents.containsKey(imagePath)) {
            allImagePaths.add(imagePath);
          }
        }
      }

      chapters.add(JourChapterData(jour: jour, entries: entries));
    }

    // 5. Remplir content.xml avec le chapitrage.
    final contentXml = utf8.decode(fileContents['content.xml']!, allowMalformed: true);
    final filledContent = OdpContentFiller.fill(
      contentXml,
      trek,
      chapters,
      imageSettings: imageSettings,
    );
    fileContents['content.xml'] = Uint8List.fromList(utf8.encode(filledContent));

    // 6. Mettre à jour META-INF/manifest.xml avec les nouvelles images.
    final manifestXml = utf8.decode(
      fileContents['META-INF/manifest.xml']!,
      allowMalformed: true,
    );
    final updatedManifest = _addImagesToManifest(manifestXml, allImagePaths);
    fileContents['META-INF/manifest.xml'] =
        Uint8List.fromList(utf8.encode(updatedManifest));

    // 7. Mettre à jour meta.xml avec le titre et la date.
    final metaXml = utf8.decode(fileContents['meta.xml']!, allowMalformed: true);
    final updatedMeta = _updateMetaXml(metaXml, trek);
    fileContents['meta.xml'] = Uint8List.fromList(utf8.encode(updatedMeta));

    // 8. Ré-encoder l'archive: mimetype en premier et non compressé.
    final newArchive = Archive();

    final mimetypeData = fileContents['mimetype']!;
    final mt = ArchiveFile('mimetype', mimetypeData.length, mimetypeData);
    mt.compress = false;
    newArchive.addFile(mt);
    fileContents.remove('mimetype');

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

    // Ajouter les nouvelles images qui ne sont pas dans le template.
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

  /// Lit les dimensions (largeur, hauteur en pixels) d'une image.
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

  String _addImagesToManifest(String manifestXml, List<String> imagePaths) {
    final toAdd = <String>[];
    for (final path in imagePaths) {
      if (path.isEmpty) continue;
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

  static Uint8List _optimizeImageInIsolate((Uint8List, int) params) {
    final (imageBytes, quality) = params;
    return ImageOptimizer.optimizeImage(imageBytes, quality: quality);
  }
}
