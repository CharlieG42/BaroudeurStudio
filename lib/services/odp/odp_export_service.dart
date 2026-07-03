import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

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
/// Utilise le package archive pour créer des fichiers ZIP conformes au standard ODP
class OdpExportService {
  /// Génère un fichier ODP à partir d'un trek
  Future<File> exportTrekToOdp(Trek trek) async {
    // Récupérer les jours du trek
    final jours = await DatabaseHelper.instance.getJoursForTrek(trek.id!);
    
    // Récupérer les médias par jour
    final mediasByJour = <int, List<Media>>{};
    for (final jour in jours) {
      final medias = await DatabaseHelper.instance.getMediasForJour(jour.id!);
      mediasByJour[jour.id!] = medias;
    }
    
    // Créer l'archive ZIP
    final archive = Archive();
    
    // Ajouter le fichier mimetype (doit être le premier fichier dans l'archive)
    archive.addFile(ArchiveFile(
      'mimetype',
      48,
      'application/vnd.oasis.opendocument.presentation'.codeUnits
    ));
    
    // Ajouter META-INF/manifest.xml
    final manifestXml = ManifestXmlBuilder.build();
    archive.addFile(ArchiveFile('META-INF/manifest.xml', manifestXml.length, manifestXml.codeUnits));
    
    // Ajouter content.xml
    final contentXml = ContentXmlBuilder.build(trek, jours, mediasByJour);
    archive.addFile(ArchiveFile('content.xml', contentXml.length, contentXml.codeUnits));
    
    // Ajouter styles.xml
    final stylesXml = StylesXmlBuilder.build();
    archive.addFile(ArchiveFile('styles.xml', stylesXml.length, stylesXml.codeUnits));
    
    // Ajouter meta.xml
    final metaXml = MetaXmlBuilder.build(trek);
    archive.addFile(ArchiveFile('meta.xml', metaXml.length, metaXml.codeUnits));
    
    // Ajouter les images à l'archive
    int pageIndex = 0;
    for (final jour in jours) {
      final medias = mediasByJour[jour.id] ?? [];
      for (int mediaIndex = 0; mediaIndex < medias.length; mediaIndex++) {
        final media = medias[mediaIndex];
        try {
          final file = File(media.cheminFichier);
          final imageBytes = file.readAsBytesSync();
          final optimizedBytes = ImageOptimizer.optimizeImage(
            imageBytes, 
            quality: AppConfig.imageCompressionQuality
          );
          
          final imagePath = 'Pictures/image_' + pageIndex.toString() + '_' + mediaIndex.toString() + '.jpg';
          archive.addFile(ArchiveFile(imagePath, optimizedBytes.length, optimizedBytes));
          
        } catch (e) {
          // Ignorer si l'image ne peut pas être lue
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
}