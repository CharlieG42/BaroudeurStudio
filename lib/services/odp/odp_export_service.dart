import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../../models/trek.dart';
import '../../models/jour_trek.dart';
import '../../models/media.dart';
import '../../db/database_helper.dart';
import '../../config/app_config.dart';
import '../utils/image_optimizer.dart';
import '../utils/filename_utils.dart';
import 'manifest_xml_builder.dart';
import 'styles_xml_builder.dart';
import 'meta_xml_builder.dart';
import 'content_xml_builder.dart';

/// Service d'export ODP (OpenDocument Presentation) pour les treks
/// 
/// Utilise le package archive pour créer des fichiers ZIP conformes au standard ODP
/// 
/// IMPORTANT:
/// - Tous les documents générés sont systématiquement en orientation PORTRAIT (21cm x 28cm)
/// - Le chargement des images se fait de manière asynchrone pour éviter les problèmes de mémoire
/// - Les images sont optimisées avant d'être ajoutées à l'archive
class OdpExportService {
  /// Génère un fichier ODP à partir d'un trek
  /// 
  /// Le document généré a les caractéristiques suivantes:
  /// - Orientation: PORTRAIT (21cm x 28cm) - garantie par styles.xml et content.xml
  /// - Format: OpenDocument Presentation (compatible LibreOffice/OpenOffice)
  /// - Contenu: Toutes les informations du trek + images des médias
  /// 
  /// Retourne le fichier ODP généré
  Future<File> exportTrekToOdp(Trek trek) async {
    // Récupérer les jours du trek
    final jours = await DatabaseHelper.instance.getJoursForTrek(trek.id!);
    
    // Récupérer les médias par jour de manière asynchrone et parallèle
    final mediasByJour = <int, List<Media>>{};
    
    // Créer une liste de futures pour tous les appels getMediasForJour
    final mediaFutures = <Future<void>>[];
    for (final jour in jours) {
      final future = DatabaseHelper.instance.getMediasForJour(jour.id!).then((medias) {
        mediasByJour[jour.id!] = medias;
      });
      mediaFutures.add(future);
    }
    
    // Attendre que tous les appels soient terminés
    await Future.wait(mediaFutures);
    
    // Collecter tous les chemins d'images (doit correspondre à la logique de content_xml_builder)
    final allImagePaths = <String>[];
    int pageIndex = 0;
    for (final jour in jours) {
      final medias = mediasByJour[jour.id] ?? [];
      for (int mediaIndex = 0; mediaIndex < medias.length; mediaIndex++) {
        final imagePath = 'Pictures/image_' + pageIndex.toString() + '_' + mediaIndex.toString() + '.jpg';
        allImagePaths.add(imagePath);
      }
      pageIndex++;
    }
    
    // Créer l'archive ZIP
    final archive = Archive();
    
    // IMPORTANT: mimetype DOIT être le premier fichier dans l'archive
    // Pour ODP, mimetype ne doit pas être compressé et doit être le premier
    final mimetypeContent = 'application/vnd.oasis.opendocument.presentation';
    final mimetypeBytes = Uint8List.fromList(mimetypeContent.codeUnits);
    
    // Le fichier mimetype DOIT être stocké sans compression (obligatoire pour le format ODP)
    final mimetypeFile = ArchiveFile('mimetype', mimetypeBytes.length, mimetypeBytes);
    mimetypeFile.compress = false;
    archive.addFile(mimetypeFile);
    
    // Ajouter META-INF/manifest.xml avec toutes les entrées y compris les images
    final manifestXml = ManifestXmlBuilder.build(allImagePaths);
    final manifestBytes = Uint8List.fromList(manifestXml.codeUnits);
    archive.addFile(ArchiveFile('META-INF/manifest.xml', manifestBytes.length, manifestBytes));
    
    // Ajouter content.xml
    final contentXml = ContentXmlBuilder.build(trek, jours, mediasByJour);
    final contentBytes = Uint8List.fromList(contentXml.codeUnits);
    archive.addFile(ArchiveFile('content.xml', contentBytes.length, contentBytes));
    
    // Ajouter styles.xml
    final stylesXml = StylesXmlBuilder.build();
    final stylesBytes = Uint8List.fromList(stylesXml.codeUnits);
    archive.addFile(ArchiveFile('styles.xml', stylesBytes.length, stylesBytes));
    
    // Ajouter meta.xml
    final metaXml = MetaXmlBuilder.build(trek);
    final metaBytes = Uint8List.fromList(metaXml.codeUnits);
    archive.addFile(ArchiveFile('meta.xml', metaBytes.length, metaBytes));
    
    // Ajouter les images à l'archive de manière asynchrone
    pageIndex = 0;
    for (final jour in jours) {
      final medias = mediasByJour[jour.id] ?? [];
      
      // Traiter chaque média de manière asynchrone
      for (int mediaIndex = 0; mediaIndex < medias.length; mediaIndex++) {
        final media = medias[mediaIndex];
        final imagePath = 'Pictures/image_' + pageIndex.toString() + '_' + mediaIndex.toString() + '.jpg';
        
        try {
          // Charger l'image de manière asynchrone
          final file = File(media.cheminFichier);
          final imageBytes = await file.readAsBytes();
          
          // Optimiser l'image dans un isolate pour éviter de bloquer l'UI
          final optimizedBytes = await compute(
            _optimizeImageInIsolate,
            (imageBytes, AppConfig.imageCompressionQuality),
          );
          
          archive.addFile(ArchiveFile(imagePath, optimizedBytes.length, optimizedBytes));
        } catch (e) {
          // Ignorer si l'image ne peut pas être lue
          debugPrint('Erreur lors du chargement de l\'image ${media.cheminFichier}: $e');
        }
      }
      pageIndex++;
    }
    
    // Générer le fichier ODP
    final directory = await getApplicationDocumentsDirectory();
    final filename = FilenameUtils.generateExportFilename(trek.titre, 'odp');
    final filePath = directory.path + '/' + filename;
    final file = File(filePath);
    
    // Encoder et écrire l'archive
    final zipData = ZipEncoder().encode(archive);
    if (zipData != null) {
      await file.writeAsBytes(zipData);
    }
    
    return file;
  }
  
  /// Fonction pour optimiser une image dans un isolate
  /// Cette fonction est conçue pour être appelée via compute()
  static Uint8List _optimizeImageInIsolate((Uint8List, int) params) {
    final (imageBytes, quality) = params;
    return ImageOptimizer.optimizeImage(imageBytes, quality: quality);
  }
}
